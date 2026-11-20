# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""Reference models of the OpenISP modules, written from their specifications, not from the RTL.

Every model takes a list of input items and the generics of the module and returns the expected output items, the
number of error pulses and an annotation per input item:

- ('B', pixel, last, user): one input beat; user is the integer value of the sequence flags (bit 1 = User(1))
- ('R', drop, mode, cycles): a reset of the module; the last `drop` output beats before it are lost
- ('A', marker, entries): register accesses at a marker of the stimulus; entries are (op, address, data, strobes)
  with op 'W' (write) or 'C' (read and compare; the model sets the expected data)
- ('J', marker, pattern): error injection at a marker: the flip pattern of the ECC codewords, latched for the next
  pixel event
- any other item ('G', 'T', 'H', 'M', 'K', 'W', 'P') passes through without effect on the model

Output items: ('B', pixel, last, user, x, y) and ('R', mode). The annotation of an input item is the state after it:
(number of output beats so far, image open). Models with further results return them as a fourth element, a dict:
"config" (Err_Config pulses), "regs" (resolved register entries per marker), "sec" and "ded" (ECC status pulses),
"timing" (per output beat the index of the input beat that completes it, or -1).
"""

from collections import deque

SEQ_CONT, SEQ_FIRST, SEQ_LAST, SEQ_ONLY = 0, 1, 2, 3


def line_flags(y, height):
    """Sequence flags of output line y of an image of `height` lines (one packet per line)."""
    if height == 1:
        return SEQ_ONLY
    if y == 0:
        return SEQ_FIRST
    if y == height - 1:
        return SEQ_LAST
    return SEQ_CONT


class FrameSync:
    """isp_frame_sync (specification, section 3): the pixel count from the image start decides the end of an image.

    E1: an image start while an image is open completes it with pixels of value 0 (one error).
    E2: pixels while no image is open, other than an image start, are discarded (one error per run).
    E3: pixel W x H - 1 not on the last beat of a packet with the flags "10" or "11" ends the image (one error).
    E4: the last beat of a packet with the flags "10" or "11" before pixel W x H - 1 does not end it (one error).
    """

    def __init__(self, width, height):
        self.width, self.height = width, height
        self.total = width * height
        self.errors = 0
        self.reset()

    def reset(self):
        self.open = False
        self.n = 0
        self.first = True
        self.run = False

    def _emit(self, out, pixel, n):
        x, y = n % self.width, n // self.width
        out.append(("B", pixel, 1 if x == self.width - 1 else 0, line_flags(y, self.height), x, y))

    def feed(self, pixel, last, user):
        """One input beat; returns the output beats it causes."""
        out = []
        start = self.first and (user & 1) == 1
        end_flags = last == 1 and (user & 2) == 2
        if self.open and start:
            self.errors += 1                                    # E1
            for n in range(self.n, self.total):
                self._emit(out, 0, n)
            self.open = False
            self.run = False
        if self.open:
            n = self.n
            self._emit(out, pixel, n)
            if n == self.total - 1:
                if not end_flags:
                    self.errors += 1                            # E3
                self.open = False
                self.run = False
            else:
                if end_flags:
                    self.errors += 1                            # E4
                self.n = n + 1
        elif start:
            self.run = False
            self._emit(out, pixel, 0)
            if self.total == 1:
                if not end_flags:
                    self.errors += 1                            # E3
            else:
                if end_flags:
                    self.errors += 1                            # E4
                self.open = True
                self.n = 1
        elif not self.run:
            self.errors += 1                                    # E2, once per run
            self.run = True
        self.first = last == 1
        return out


def _drop(out, drop):
    """Removes the last `drop` output beats (lost by a reset)."""
    for _ in range(drop):
        assert out and out[-1][0] == "B", "reset drops beats of an earlier reset"
        out.pop()


def frame_sync(items, width, height):
    """Model of isp_frame_sync over a list of input items; returns (out, errors, annot)."""
    fs = FrameSync(width, height)
    out, annot = [], []
    count = 0
    for it in items:
        if it[0] == "B":
            beats = fs.feed(it[1], it[2], it[3])
            out += beats
            count += len(beats)
        elif it[0] == "R":
            _, drop, mode, _cycles = it
            assert drop <= count, "reset drops more beats than were produced"
            _drop(out, drop)
            count -= drop
            out.append(("R", mode))
            fs.reset()
        annot.append((count, fs.open))
    return out, fs.errors, annot


# Register map of isp_crop (specification, section 7)
CRP_ID, CRP_IMAGE, CRP_ROI_SIZE, CRP_ROI_POS, CRP_STATUS, CRP_INJECT = 0x00, 0x04, 0x08, 0x0C, 0x10, 0x14


def crop(items, width, height, roi_x, roi_y, roi_w, roi_h, runtime):
    """isp_crop: the region of interest of every image of the frame sync. With `runtime`, the position is ROI_POS at
    the image start when it lies inside the image and its parity bit matches; otherwise the generics apply and
    Err_Config pulses. Returns (out, framing errors, annot, {"config", "regs", "timing"})."""
    fs = FrameSync(width, height)
    reg = (roi_y << 16) | roi_x                  # ROI_POS, reset value from the generics
    parity_ok = True
    status_framing = status_config = False
    config_errors = 0
    pos = (roi_x, roi_y)
    out, annot, regs, timing = [], [], [], []
    count = beat = 0

    def select(beats, src):
        nonlocal pos, config_errors, status_config, count
        for n, b in enumerate(beats):
            _, pixel, _last, _user, x, y = b
            if x == 0 and y == 0:
                # Image start: the limits of this image
                pos = (roi_x, roi_y)
                if runtime:
                    rx, ry = reg & 0xFFFF, reg >> 16
                    if parity_ok and rx + roi_w <= width and ry + roi_h <= height:
                        pos = (rx, ry)
                    else:
                        config_errors += 1
                        status_config = True
            x0, y0 = pos
            if x0 <= x < x0 + roi_w and y0 <= y < y0 + roi_h:
                out.append(("B", pixel, 1 if x == x0 + roi_w - 1 else 0, line_flags(y - y0, roi_h), x, y))
                # The pixel of the input beat is the last of the beats it causes; the others are padding
                timing.append(src if n == len(beats) - 1 else -1)
                count += 1

    def read(addr):
        if addr == CRP_ID:
            return 0x43525001
        if addr == CRP_IMAGE:
            return ((height - 1) << 16) | (width - 1)
        if addr == CRP_ROI_SIZE:
            return ((roi_h - 1) << 16) | (roi_w - 1)
        if addr == CRP_ROI_POS:
            return reg if runtime else (roi_y << 16) | roi_x
        if addr == CRP_STATUS:
            return (1 if fs.open else 0) | (0x100 if status_framing else 0) | (0x200 if status_config else 0)
        return 0

    for it in items:
        if it[0] == "B":
            before = fs.errors
            select(fs.feed(it[1], it[2], it[3]), beat)
            beat += 1
            if fs.errors > before:
                status_framing = True
        elif it[0] == "R":
            _, drop, mode, _cycles = it
            assert drop <= count, "reset drops more beats than were produced"
            _drop(out, drop)
            del timing[len(timing) - drop:]
            count -= drop
            out.append(("R", mode))
            fs.reset()
            reg, parity_ok = (roi_y << 16) | roi_x, True
            status_framing = status_config = False
        elif it[0] == "A":
            _, marker, entries = it
            resolved = []
            for op, addr, data, strobes in entries:
                if op == "W":
                    if addr == CRP_ROI_POS and runtime:
                        for byte in range(4):
                            if strobes & (1 << byte):
                                mask = 0xFF << (8 * byte)
                                reg = (reg & ~mask) | (data & mask)
                        parity_ok = True
                    elif addr == CRP_STATUS and strobes & 0x2:
                        if data & 0x100:
                            status_framing = False
                        if data & 0x200:
                            status_config = False
                    elif addr == CRP_INJECT and runtime and strobes & 0x1 and data & 1:
                        parity_ok = not parity_ok
                    resolved.append(("W", addr, data, strobes))
                else:
                    resolved.append(("C", addr, read(addr), 0xF))
            regs.append((marker, resolved))
        annot.append((count, fs.open))
    return out, fs.errors, annot, {"config": config_errors, "regs": regs, "timing": timing}


def _strobe(old, data, strobes):
    """A 32-bit register value after a write of `data` with the byte strobes."""
    for byte in range(4):
        if strobes & (1 << byte):
            mask = 0xFF << (8 * byte)
            old = (old & ~mask) | (data & mask)
    return old


# Register map of isp_point (specification, section 7)
PNT_ID, PNT_IMAGE, PNT_PARAM, PNT_CTRL, PNT_STATUS, PNT_INJECT = 0x00, 0x04, 0x08, 0x0C, 0x10, 0x14
PNT_OFFSET_LO, PNT_OFFSET_HI, PNT_GAIN, PNT_SHIFT, PNT_LOW, PNT_HIGH = 0x18, 0x1C, 0x20, 0x24, 0x28, 0x2C
PNT_PARAMS = [PNT_OFFSET_LO, PNT_OFFSET_HI, PNT_GAIN, PNT_SHIFT, PNT_LOW, PNT_HIGH]


def point_op(pixel, offset, gain, shift, low, high):
    """The operation of isp_point in unbounded integers: q = min(max(floor((p + offset) x gain / 2^shift), low),
    high); the lower threshold first, then the upper one."""
    v = ((pixel + offset) * gain) >> shift
    return min(max(v, low), high)


def point(items, width, height, in_bits, out_bits, gain_bits, max_shift, offset_g, gain_g, shift_g, low_g, high_g,
          runtime):
    """isp_point. Returns (out, framing errors, annot, {"config", "regs", "timing"})."""
    fs = FrameSync(width, height)
    ow = min(in_bits + 1, 64)                         # bits of the offset
    full = (1 << out_bits) - 1
    gen = (offset_g, gain_g, shift_g, low_g, full if high_g == -1 else high_g)

    def to_signed(value, bits):
        value &= (1 << bits) - 1
        return value - (1 << bits) if value >> (bits - 1) else value

    # Stored register bits (reset values from the generics) and their parity flags
    st = {}

    def reset_regs():
        st["off"] = gen[0] & ((1 << ow) - 1)
        st["gain"], st["shift"], st["low"], st["high"] = gen[1], gen[2], gen[3], gen[4]
        st["parity"] = [True] * 7                    # OFFSET_LO, OFFSET_HI, GAIN, SHIFT, LOW, HIGH, CTRL
        st["hold"] = False

    reset_regs()
    work = gen                                        # the parameter set in use, from the reset the generics
    status_framing = status_config = False
    config_errors = 0
    out, annot, regs, timing = [], [], [], []
    count = beat = 0

    def reg_set():
        return (to_signed(st["off"], ow), st["gain"], min(st["shift"], max_shift), st["low"], st["high"])

    def read(addr):
        off64 = to_signed(st["off"], ow) & ((1 << 64) - 1)
        if not runtime and addr in PNT_PARAMS:
            off64 = gen[0] & ((1 << 64) - 1)
            values = {PNT_GAIN: gen[1], PNT_SHIFT: gen[2], PNT_LOW: gen[3], PNT_HIGH: gen[4]}
        else:
            values = {PNT_GAIN: st["gain"], PNT_SHIFT: st["shift"], PNT_LOW: st["low"], PNT_HIGH: st["high"]}
        values[PNT_OFFSET_LO] = off64 & 0xFFFFFFFF
        values[PNT_OFFSET_HI] = off64 >> 32
        values[PNT_ID] = 0x504E5401
        values[PNT_IMAGE] = ((height - 1) << 16) | (width - 1)
        values[PNT_PARAM] = (max_shift << 24) | (gain_bits << 16) | (out_bits << 8) | in_bits
        values[PNT_CTRL] = 1 if st["hold"] else 0
        values[PNT_STATUS] = (1 if fs.open else 0) | (0x100 if status_framing else 0) | \
            (0x200 if status_config else 0)
        return values.get(addr, 0)

    def write(addr, data, strobes):
        nonlocal status_framing, status_config
        if addr == PNT_STATUS and strobes & 0x2:
            if data & 0x100:
                status_framing = False
            if data & 0x200:
                status_config = False
        if addr == PNT_CTRL and strobes & 0x1:
            st["hold"] = bool(data & 1)
            st["parity"][6] = True
        if not runtime:
            return
        off64 = to_signed(st["off"], ow) & ((1 << 64) - 1)
        if addr == PNT_OFFSET_LO:
            off64 = (off64 & ~0xFFFFFFFF) | _strobe(off64 & 0xFFFFFFFF, data, strobes)
            st["off"] = off64 & ((1 << ow) - 1)
            st["parity"][0] = True
        elif addr == PNT_OFFSET_HI:
            off64 = (off64 & 0xFFFFFFFF) | (_strobe(off64 >> 32, data, strobes) << 32)
            st["off"] = off64 & ((1 << ow) - 1)
            st["parity"][1] = True
        elif addr == PNT_GAIN:
            st["gain"] = _strobe(st["gain"], data, strobes) & ((1 << gain_bits) - 1)
            st["parity"][2] = True
        elif addr == PNT_SHIFT:
            st["shift"] = _strobe(st["shift"], data, strobes) & 0x7F
            st["parity"][3] = True
        elif addr == PNT_LOW:
            st["low"] = _strobe(st["low"], data, strobes) & full
            st["parity"][4] = True
        elif addr == PNT_HIGH:
            st["high"] = _strobe(st["high"], data, strobes) & full
            st["parity"][5] = True
        elif addr == PNT_INJECT and strobes & 0x1:
            for n in range(7):
                if data & (1 << n):
                    st["parity"][n] = not st["parity"][n]

    for it in items:
        if it[0] == "B":
            before = fs.errors
            beats = fs.feed(it[1], it[2], it[3])
            for n, b in enumerate(beats):
                _, pixel, last, user, x, y = b
                if x == 0 and y == 0 and runtime:
                    # A CTRL with a wrong parity bit counts as HOLD 0 and is reported; one Err_Config per image start
                    ctrl_bad = not st["parity"][6]
                    error = ctrl_bad
                    if not st["hold"] or ctrl_bad:
                        if all(st["parity"][:6]):
                            work = reg_set()
                        else:
                            work = gen
                            error = True
                    if error:
                        config_errors += 1
                        status_config = True
                out.append(("B", point_op(pixel, *work), last, user, x, y))
                # The pixel of the input beat is the last of the beats it causes; the others are padding
                timing.append(beat if n == len(beats) - 1 else -1)
                count += 1
            beat += 1
            if fs.errors > before:
                status_framing = True
        elif it[0] == "R":
            _, drop, mode, _cycles = it
            assert drop <= count, "reset drops more beats than were produced"
            _drop(out, drop)
            del timing[len(timing) - drop:]
            count -= drop
            out.append(("R", mode))
            fs.reset()
            reset_regs()
            work = gen
            status_framing = status_config = False
        elif it[0] == "A":
            _, marker, entries = it
            resolved = []
            for op, addr, data, strobes in entries:
                if op == "W":
                    write(addr, data, strobes)
                    resolved.append(("W", addr, data, strobes))
                else:
                    resolved.append(("C", addr, read(addr), 0xF))
            regs.append((marker, resolved))
        annot.append((count, fs.open))
    return out, fs.errors, annot, {"config": config_errors, "regs": regs, "timing": timing}


# ECC of Open Logic (olo_ft_pkg_ecc): bit 0 the overall parity, bits 1 to n the Hamming codeword with the parity bits
# at the powers of two and the data bits at the other positions, in order.

def ecc_parity_bits(bits):
    """Hamming parity bits of a codeword for `bits` data bits (eccParityBits)."""
    p = 1
    while 2 ** p < bits + p + 1:
        p += 1
    return p


def ecc_codeword_width(bits):
    """Width of the codeword (eccCodewordWidth)."""
    return bits + ecc_parity_bits(bits) + 1


def ecc_data_positions(bits):
    """Codeword bit of every data bit: data bit k is codeword bit ecc_data_positions(bits)[k]."""
    length = bits + ecc_parity_bits(bits)
    return [i for i in range(1, length + 1) if i & (i - 1) != 0]


def ecc_decode(pattern, bits):
    """Effect of the flip pattern `pattern` on a codeword as the decoder of Open Logic sees it: returns (data mask,
    sec, ded). The code is linear, so the syndrome of the received word is the syndrome of the pattern."""
    length = bits + ecc_parity_bits(bits)
    syndrome = 0
    for i in range(1, length + 1):
        if pattern >> i & 1:
            syndrome ^= i
    odd = bin(pattern).count("1") % 2 == 1
    corrected = pattern
    if odd and 0 < syndrome <= length:
        corrected ^= 1 << syndrome
    mask = 0
    for k, pos in enumerate(ecc_data_positions(bits)):
        if corrected >> pos & 1:
            mask |= 1 << k
    return mask, odd, syndrome != 0 and not odd


class Window:
    """isp_window over the images of the frame sync (specification, sections 1.1 and 6).

    The events follow the architecture (section 5): a PIX event per pixel, Rr HCOL events after every line and Rb
    virtual lines of W VPIX events after every image, except in the border mode valid. In the event of line ye the
    pixel of line ye - d comes from delay d (WIN-FT-01); the delays are modelled as queues of W codewords, so that an
    injected pattern is read W pixel events after it was written and a double error travels on through the chain.
    """

    def __init__(self, width, height, bits, win_x, win_y, anchor_x, anchor_y, stride_x, stride_y, border):
        assert border in ("valid", "zero", "replicate", "mirror")
        self.w, self.h, self.bits = width, height, bits
        self.wx, self.wy, self.ax, self.ay = win_x, win_y, anchor_x, anchor_y
        self.sx, self.sy, self.border = stride_x, stride_y, border
        self.rr, self.rb = win_x - 1 - anchor_x, win_y - 1 - anchor_y
        if border == "valid":
            self.x0, self.y0 = anchor_x, anchor_y
            self.wo = (width - win_x) // stride_x + 1
            self.ho = (height - win_y) // stride_y + 1
        else:
            self.x0, self.y0 = 0, 0
            self.wo = -(-width // stride_x)
            self.ho = -(-height // stride_y)
        self.xl = self.x0 + (self.wo - 1) * stride_x
        self.yl = self.y0 + (self.ho - 1) * stride_y
        self.cw = ecc_codeword_width(bits)
        self.sec = self.ded = 0
        self.reset()

    def reset(self):
        self.delays = [deque([(0, 0)] * self.w) for _ in range(self.wy - 1)]
        self.pending = 0
        self.cols = {}

    def inject(self, pattern):
        self.pending = pattern

    def _map(self, c, n):
        """Coordinate c of the extended image mapped into 0 to n - 1, or None for the value 0."""
        if 0 <= c < n:
            return c
        if self.border == "zero" or self.border == "valid":
            return None
        if self.border == "replicate":
            return min(max(c, 0), n - 1)
        r = -c if c < 0 else 2 * (n - 1) - c
        assert 0 <= r < n, "mirror leaves the image"
        return r

    def _shift(self, pixel, xe, ye):
        """Pixel event (PIX or VPIX) at (xe, ye): shifts the delays and stores the column of xe."""
        pattern, self.pending = self.pending, 0
        lines = [pixel]
        sec = ded = False
        value = pixel
        # The delays that the row selection of line ye uses (the border rule replaces the others, WIN-FT-02)
        used = set()
        for j in range(self.wy):
            line = self._map(ye - (self.wy - 1) + j, self.h)
            if line is not None and 0 <= ye - line < self.wy:
                used.add(ye - line)
        for t in range(self.wy - 1):
            queue = self.delays[t]
            stored, flips = queue.popleft()
            mask, s, d = ecc_decode(flips, self.bits)
            read = stored ^ mask
            if t + 1 in used:
                sec, ded = sec or s, ded or d
            queue.append((value, pattern >> (t * self.cw) & ((1 << self.cw) - 1)))
            lines.append(read)
            value = read
        self.sec += sec
        self.ded += ded
        self.cols[xe] = lines

    def _window(self, xe, ye, src, out):
        """Window completed by the event at (xe, ye), if its pixel is a reference pixel."""
        x, y = xe - self.rr, ye - self.rb
        if not (self.x0 <= x <= self.xl and (x - self.x0) % self.sx == 0):
            return
        if not (self.y0 <= y <= self.yl and (y - self.y0) % self.sy == 0):
            return
        # Row j is line ye - (WinY - 1) + j, mapped by the border mode, from delay ye - line of the column
        delay = []
        for j in range(self.wy):
            line = self._map(ye - (self.wy - 1) + j, self.h)
            if line is not None:
                assert 0 <= ye - line < self.wy, "a row outside the column"
            delay.append(None if line is None else ye - line)
        data = 0
        for j in range(self.wy):
            for i in range(self.wx):
                col = self._map(x - self.ax + i, self.w)
                value = 0 if col is None or delay[j] is None else self.cols[col][delay[j]]
                data |= value << ((j * self.wx + i) * self.bits)
        m = (y - self.y0) // self.sy
        out.append(("B", data, 1 if x == self.xl else 0, line_flags(m, self.ho), x, y, src))

    def pixel(self, pixel, xe, ye, src):
        """Events of one pixel of the frame sync; `src` is the index of the input beat or -1. Returns the windows."""
        out = []
        self._shift(pixel, xe, ye)
        self._window(xe, ye, src, out)
        if xe == self.w - 1 and self.border != "valid":
            for xh in range(self.w, self.w + self.rr):
                self._window(xh, ye, -1, out)
            if ye == self.h - 1:
                for yv in range(self.h, self.h + self.rb):
                    for xv in range(self.w):
                        self._shift(0, xv, yv)
                        self._window(xv, yv, -1, out)
                    for xh in range(self.w, self.w + self.rr):
                        self._window(xh, yv, -1, out)
        return out


def window(items, width, height, bits, win_x, win_y, anchor_x=None, anchor_y=None, stride_x=1, stride_y=1,
           border="replicate"):
    """isp_window. Returns (out, framing errors, annot, {"sec", "ded", "timing"}); the data of an output beat is the
    window, element k = j x WinX + i in bits (k + 1) x bits - 1 downto k x bits."""
    anchor_x = (win_x - 1) // 2 if anchor_x is None else anchor_x
    anchor_y = (win_y - 1) // 2 if anchor_y is None else anchor_y
    fs = FrameSync(width, height)
    win = Window(width, height, bits, win_x, win_y, anchor_x, anchor_y, stride_x, stride_y, border)
    out, annot, timing = [], [], []
    count = 0
    beat = 0
    for it in items:
        if it[0] == "B":
            beats = fs.feed(it[1], it[2], it[3])
            for k, b in enumerate(beats):
                # The pixel of this input beat is the last of the beats it causes; the others are padding
                src = beat if k == len(beats) - 1 else -1
                for o in win.pixel(b[1], b[4], b[5], src):
                    out.append(o[:6])
                    timing.append(o[6])
                    count += 1
            beat += 1
        elif it[0] == "R":
            _, drop, mode, _cycles = it
            assert drop <= count, "reset drops more beats than were produced"
            _drop(out, drop)
            del timing[len(timing) - drop:]
            count -= drop
            out.append(("R", mode))
            fs.reset()
            win.reset()
        elif it[0] == "J":
            win.inject(it[2])
        annot.append((count, fs.open))
    return out, fs.errors, annot, {"sec": win.sec, "ded": win.ded, "timing": timing}


def log2ceil(n):
    """Smallest b with 2^b >= n."""
    return (n - 1).bit_length()


# Register map of isp_conv (specification, section 7)
CNV_ID, CNV_PARAM, CNV_CTRL, CNV_STATUS, CNV_INJECT, CNV_COEF = 0x000, 0x004, 0x008, 0x00C, 0x010, 0x100


def conv_full_bits(pixel_bits, coef_bits, taps):
    """F of the specification: every sum that is not negative fits."""
    return pixel_bits + coef_bits - 1 + log2ceil(taps)


class ConvKernel:
    """isp_conv: the kernel of one window and its registers (specification, sections 1.1 and 7)."""

    def __init__(self, pixel_bits, win_x, win_y, coef_bits, coef, runtime, out_bits):
        self.pb, self.wx, self.wy, self.cb = pixel_bits, win_x, win_y, coef_bits
        self.taps = win_x * win_y
        assert len(coef) == self.taps
        self.coef, self.runtime = list(coef), runtime
        full = conv_full_bits(pixel_bits, coef_bits, self.taps)
        self.out_b = full if out_bits == 0 else out_bits
        self.cmask = (1 << coef_bits) - 1
        self.config_errors = 0
        self.reset()

    def _signed(self, value):
        value &= self.cmask
        return value - (1 << self.cb) if value >> (self.cb - 1) else value

    def reset(self):
        self.regs = [c & self.cmask for c in self.coef]
        self.parity = [True] * self.taps
        self.hold = False
        self.ctrl_parity = True
        self.work = list(self.coef)
        self.status_config = False
        self.first = True

    def feed(self, data, last, user):
        """One window; returns the output pixel."""
        if self.first and user in (SEQ_FIRST, SEQ_ONLY) and self.runtime:
            # A CTRL with a wrong parity bit counts as HOLD 0 and is reported; one Err_Config per image start
            error = not self.ctrl_parity
            if not self.hold or not self.ctrl_parity:
                if all(self.parity):
                    self.work = [self._signed(c) for c in self.regs]
                else:
                    self.work = list(self.coef)
                    error = True
            if error:
                self.config_errors += 1
                self.status_config = True
        self.first = last == 1
        pmask = (1 << self.pb) - 1
        s = sum(self.work[k] * (data >> (k * self.pb) & pmask) for k in range(self.taps))
        return 0 if s < 0 else min(s, (1 << self.out_b) - 1)

    def read(self, addr):
        if addr == CNV_ID:
            return 0x434E5601
        if addr == CNV_PARAM:
            return (self.pb << 24) | (self.cb << 16) | (self.wy << 8) | self.wx
        if addr == CNV_CTRL:
            return 1 if self.hold else 0
        if addr == CNV_STATUS:
            return 0x200 if self.status_config else 0
        if CNV_COEF <= addr < CNV_COEF + 4 * self.taps and addr % 4 == 0:
            k = (addr - CNV_COEF) // 4
            value = self._signed(self.regs[k]) if self.runtime else self.coef[k]
            return value & 0xFFFFFFFF
        return 0

    def write(self, addr, data, strobes):
        if addr == CNV_CTRL and strobes & 0x1:
            self.hold = bool(data & 1)
            self.ctrl_parity = True
        elif addr == CNV_STATUS and strobes & 0x2 and data & 0x200:
            self.status_config = False
        elif addr == CNV_INJECT and self.runtime and strobes & 0x1:
            k = (data >> 8) & 0xFF if strobes & 0x2 else 0
            if data & 1 and k < self.taps:
                self.parity[k] = not self.parity[k]
            if data & 2:
                self.ctrl_parity = not self.ctrl_parity
        elif self.runtime and CNV_COEF <= addr < CNV_COEF + 4 * self.taps and addr % 4 == 0:
            k = (addr - CNV_COEF) // 4
            self.regs[k] = _strobe(self._signed(self.regs[k]) & 0xFFFFFFFF, data, strobes) & self.cmask
            self.parity[k] = True

    def accesses(self, entries):
        """Register accesses of one marker; returns them with the expected read data."""
        resolved = []
        for op, addr, data, strobes in entries:
            if op == "W":
                self.write(addr, data, strobes)
                resolved.append(("W", addr, data, strobes))
            else:
                resolved.append(("C", addr, self.read(addr), 0xF))
        return resolved


def conv(items, pixel_bits, win_x, win_y, coef_bits, coef, runtime, out_bits):
    """isp_conv: every beat is a window; q = 0 for a negative sum, otherwise min(S, 2^B - 1). The image start is the
    first beat of a packet with the flags "01" or "11". Returns (out, 0, annot, {"config", "regs", "timing"}); the
    output pixel of a window comes from the input beat of that window."""
    k = ConvKernel(pixel_bits, win_x, win_y, coef_bits, coef, runtime, out_bits)
    out, annot, regs, timing = [], [], [], []
    count = beat = 0
    for it in items:
        if it[0] == "B":
            out.append(("B", k.feed(it[1], it[2], it[3]), it[2], it[3], 0, 0))
            timing.append(beat)
            count += 1
            beat += 1
        elif it[0] == "R":
            _, drop, mode, _cycles = it
            assert drop <= count, "reset drops more beats than were produced"
            _drop(out, drop)
            del timing[len(timing) - drop:]
            count -= drop
            out.append(("R", mode))
            k.reset()
        elif it[0] == "A":
            regs.append((it[1], k.accesses(it[2])))
        annot.append((count, False))
    return out, 0, annot, {"config": k.config_errors, "regs": regs, "timing": timing}


def filter2d(items, width, height, pixel_bits, win_x, win_y, anchor_x=None, anchor_y=None, stride_x=1, stride_y=1,
             border="replicate", coef_bits=16, coef=None, runtime=False, out_bits=0):
    """isp_filter2d: the windows of the model window are the input of the kernel of the model conv. Returns (out,
    framing errors, annot, {"sec", "ded", "config", "regs", "timing"})."""
    anchor_x = (win_x - 1) // 2 if anchor_x is None else anchor_x
    anchor_y = (win_y - 1) // 2 if anchor_y is None else anchor_y
    fs = FrameSync(width, height)
    win = Window(width, height, pixel_bits, win_x, win_y, anchor_x, anchor_y, stride_x, stride_y, border)
    k = ConvKernel(pixel_bits, win_x, win_y, coef_bits, coef, runtime, out_bits)
    out, annot, regs, timing = [], [], [], []
    count = beat = 0
    for it in items:
        if it[0] == "B":
            beats = fs.feed(it[1], it[2], it[3])
            for n, b in enumerate(beats):
                src = beat if n == len(beats) - 1 else -1
                for o in win.pixel(b[1], b[4], b[5], src):
                    out.append(("B", k.feed(o[1], o[2], o[3]), o[2], o[3], o[4], o[5]))
                    timing.append(o[6])
                    count += 1
            beat += 1
        elif it[0] == "R":
            _, drop, mode, _cycles = it
            assert drop <= count, "reset drops more beats than were produced"
            _drop(out, drop)
            del timing[len(timing) - drop:]
            count -= drop
            out.append(("R", mode))
            fs.reset()
            win.reset()
            k.reset()
        elif it[0] == "J":
            win.inject(it[2])
        elif it[0] == "A":
            regs.append((it[1], k.accesses(it[2])))
        annot.append((count, fs.open))
    return out, fs.errors, annot, {"sec": win.sec, "ded": win.ded, "config": k.config_errors, "regs": regs,
                                   "timing": timing}


def bin_sum(items, width, height, pixel_bits, bin_x, bin_y, border):
    """isp_bin from the definition of a bin (specification, section 1.1): the sum of the pixels p' of every bin, for
    the Wo x Ho bins of the border mode. Returns (out, framing errors, annot)."""
    assert border in ("valid", "zero", "replicate")
    if border == "valid":
        wo, ho = width // bin_x, height // bin_y
    else:
        wo, ho = -(-width // bin_x), -(-height // bin_y)
    fs = FrameSync(width, height)
    out, annot = [], []
    count = 0
    img = {}

    def ext(x, y):
        if 0 <= x < width and 0 <= y < height:
            return img[(x, y)]
        if border == "zero":
            return 0
        return img[(min(max(x, 0), width - 1), min(max(y, 0), height - 1))]

    def emit(n, m):
        nonlocal count
        s = sum(ext(n * bin_x + i, m * bin_y + j) for i in range(bin_x) for j in range(bin_y))
        out.append(("B", s, 1 if n == wo - 1 else 0, line_flags(m, ho), n, m))
        count += 1

    for it in items:
        if it[0] == "B":
            for b in fs.feed(it[1], it[2], it[3]):
                _, pixel, _last, _user, x, y = b
                img[(x, y)] = pixel
                # A bin is complete with its last pixel in the image: the last column and the last line of the bin
                # that lie in the image
                n, m = x // bin_x, y // bin_y
                if n < wo and m < ho and x == min(n * bin_x + bin_x - 1, width - 1) and                         y == min(m * bin_y + bin_y - 1, height - 1):
                    emit(n, m)
        elif it[0] == "R":
            _, drop, mode, _cycles = it
            assert drop <= count, "reset drops more beats than were produced"
            _drop(out, drop)
            count -= drop
            out.append(("R", mode))
            fs.reset()
        annot.append((count, fs.open))
    return out, fs.errors, annot


class SumFilter:
    """One filter of isp_bin: isp_filter2d with a window of `win_x` x `win_y` ones, anchor 0 and a stride of the window
    size (frame sync, window and kernel of the models above)."""

    def __init__(self, width, height, pixel_bits, win_x, win_y, border, out_bits):
        self.fs = FrameSync(width, height)
        self.win = Window(width, height, pixel_bits, win_x, win_y, 0, 0, win_x, win_y, border)
        self.k = ConvKernel(pixel_bits, win_x, win_y, 2, [1] * (win_x * win_y), False, out_bits)

    def reset(self):
        self.fs.reset()
        self.win.reset()
        self.k.reset()

    def feed(self, pixel, last, user, src):
        """One input beat with the index `src` of the input beat of the module (-1 for none); returns the output beats
        (value, last, user, src), src the input beat that completed the window or -1."""
        res = []
        beats = self.fs.feed(pixel, last, user)
        for n, b in enumerate(beats):
            s = src if n == len(beats) - 1 else -1
            for o in self.win.pixel(b[1], b[4], b[5], s):
                res.append((self.k.feed(o[1], o[2], o[3]), o[2], o[3], o[6]))
        return res


def bin_filters(items, width, height, pixel_bits, bin_x, bin_y, border):
    """isp_bin as the architecture builds it: the horizontal sum (BinX x 1, present for bin_x > 1) and the vertical sum
    (1 x BinY on the narrowed image, present for bin_y > 1) in series, the frame sync alone for 1 x 1. Items
    ('J', marker, pattern) inject into the line buffers of the vertical sum (no effect without it). Returns (out, framing errors, annot,
    {"sec", "ded", "timing"}); annot carries the OR of the open flags of the frame syncs (Stat_ImageOpen), timing the
    input beat that completed the bin of every output pixel (-1 for a bin completed by a virtual pixel)."""
    assert border in ("valid", "zero", "replicate")
    ph, q = pixel_bits + log2ceil(bin_x), pixel_bits + log2ceil(bin_x * bin_y)
    wo_h = width // bin_x if border == "valid" else -(-width // bin_x)
    hor = SumFilter(width, height, pixel_bits, bin_x, 1, border, ph) if bin_x > 1 else None
    ver = SumFilter(wo_h, height, ph, 1, bin_y, border, q) if bin_y > 1 else None
    fs = FrameSync(width, height) if hor is None and ver is None else None
    first_fs = hor.fs if hor else ver.fs if ver else fs
    out, annot, timing = [], [], []
    count = beat = 0
    for it in items:
        if it[0] == "B":
            if hor:
                mid = hor.feed(it[1], it[2], it[3], beat)
            elif ver:
                mid = [(it[1], it[2], it[3], beat)]
            else:
                beats = fs.feed(it[1], it[2], it[3])
                mid = [(b[1], b[2], b[3], beat if n == len(beats) - 1 else -1) for n, b in enumerate(beats)]
            res = [o for m in mid for o in ver.feed(*m)] if ver else mid
            for value, last, user, src in res:
                out.append(("B", value, last, user))
                timing.append(src)
                count += 1
            beat += 1
        elif it[0] == "R":
            _, drop, mode, _cycles = it
            assert drop <= count, "reset drops more beats than were produced"
            _drop(out, drop)
            del timing[len(timing) - drop:]
            count -= drop
            out.append(("R", mode))
            for part in (hor, ver, fs):
                if part:
                    part.reset()
        elif it[0] == "J" and ver:
            # Without the vertical sum the injection ports are not connected: no effect
            ver.win.inject(it[2])
        opened = any(part.open for part in (hor and hor.fs, ver and ver.fs, fs) if part)
        annot.append((count, opened))
    # The horizontal sum delivers complete images only: the frame sync of the vertical sum never reports
    assert not (hor and ver and ver.fs.errors), "the vertical sum saw a malformed stream"
    return out, first_fs.errors, annot, {"sec": ver.win.sec if ver else 0, "ded": ver.win.ded if ver else 0,
                                          "timing": timing}


def bin_model(items, width, height, pixel_bits, bin_x, bin_y, border):
    """The reference model of isp_bin: the output pixels from the definition of a bin (bin_sum); the composition of
    the two filters (bin_filters) gives the pulse counts, Stat_ImageOpen and the timing, and the output pixels of a
    test with an injection (whose double errors change the sums). Without an injection the two must agree."""
    comp = bin_filters(items, width, height, pixel_bits, bin_x, bin_y, border)
    if any(it[0] == "J" for it in items):
        return comp
    ref, errors, _annot = bin_sum(items, width, height, pixel_bits, bin_x, bin_y, border)
    assert [o[:4] for o in ref] == [o[:4] for o in comp[0]], "bin_filters differs from the definition of a bin"
    assert errors == comp[1]
    return ref, errors, comp[2], comp[3]


# Register map of isp_replace (specification, section 7)
RPL_ID, RPL_IMAGE, RPL_PARAM, RPL_MAP_LINE, RPL_MAP_WORDS = 0x00, 0x04, 0x08, 0x0C, 0x10
RPL_CTRL, RPL_STATUS, RPL_MAP_ADDR, RPL_MAP_DATA = 0x14, 0x18, 0x1C, 0x20


def replace_pixel(line, flags, x, gap):
    """Replacement of pixel x of a line (specification, section 1.1): returns (q, unreplaced). `flags` is true for
    an operational pixel; a place outside the line is not operational."""
    if flags[x]:
        return line[x], False
    width = len(line)
    dl = next((d for d in range(1, gap + 1) if x - d >= 0 and flags[x - d]), None)
    dr = next((d for d in range(1, gap + 1) if x + d < width and flags[x + d]), None)
    if dl is not None and dr is not None:
        d = dl + dr
        return (line[x - dl] * dr + line[x + dr] * dl + d // 2) // d, False
    if dl is not None:
        return line[x - dl], False
    if dr is not None:
        return line[x + dr], False
    return line[x], True


def replace(items, width, height, pixel_bits, gap):
    """isp_replace. The defect map is read as the architecture reads it (section 5): words 0 to 2 with pixel (0, 0),
    word k + 2 when word k comes in use, never across the image start; a word keeps the value it had when it was
    read. Map words carry injected error patterns, decoded with the code of olo_ft_pkg_ecc; the errors of a word are
    reported when the word comes in use, so a word read ahead and dropped by a reset reports nothing (RPL-IF-04).
    Items ('A', ...) are register accesses, ('J', marker, pattern) an injection into the next write of the map. The
    scrubber is not modelled (the tests that count pulses run with Scrub_Enable 0); ('S', marker, 1) marks the words
    with a single error as corrected. Returns (out, framing errors, annot, {"unreplaced", "sec", "ded", "regs",
    "timing"}); timing holds for every output pixel q(x, y) the input beat of p(x + G, y), or -1 where that pixel is
    outside the image or was generated by the frame sync. An unreplaced pixel counts when it is delivered; one that a
    reset drops counts not."""
    wl = -(-width // 32)
    words = height * wl
    fs = FrameSync(width, height)
    st = {"map": [0] * words, "err": [0] * words, "addr": 0, "pending": 0, "framing": False, "unrepl": False,
          "sec": False, "ded": False, "busy": False}
    cnt = {"sec": 0, "ded": 0}
    out, annot, regs, timing = [], [], [], []
    unrepl_beats = []                            # per output beat: unreplaced (counted when the beat is delivered)
    count = beat = 0
    cache = {}                                   # words of the image in progress, as read: (value, sec, ded)
    line = {"pix": [], "flags": [], "src": []}
    use = {"word": None}

    def read_word(k):
        if k in cache or k >= words:
            return
        mask, s, d = ecc_decode(st["err"][k], 32)
        cache[k] = (st["map"][k] ^ mask, s, d)

    def come_in_use(k):
        _, s, d = cache[k]
        use["word"] = k
        cnt["sec"] += s
        cnt["ded"] += d
        st["sec"] = st["sec"] or s
        st["ded"] = st["ded"] or d

    def read(addr):
        values = {RPL_ID: 0x52504C01, RPL_IMAGE: ((height - 1) << 16) | (width - 1),
                  RPL_PARAM: (pixel_bits << 8) | gap, RPL_MAP_LINE: wl, RPL_MAP_WORDS: words,
                  RPL_MAP_ADDR: st["addr"],
                  RPL_STATUS: (1 if fs.open else 0) | (2 if st["busy"] else 0) | (0x100 if st["framing"] else 0) |
                  (0x400 if st["unrepl"] else 0) | (0x10000 if st["sec"] else 0) | (0x20000 if st["ded"] else 0)}
        return values.get(addr, 0)

    def write(addr, data, strobes):
        if addr == RPL_MAP_ADDR:
            st["addr"] = _strobe(st["addr"], data, strobes)
        elif addr == RPL_MAP_DATA:
            if st["addr"] < words and not st["busy"]:
                st["map"][st["addr"]] = data
                st["err"][st["addr"]] = st["pending"]
                st["pending"] = 0
                st["addr"] += 1
        elif addr == RPL_CTRL and strobes & 0x1 and data & 1 and not st["busy"]:
            # The clear runs during the rest of the accesses of its marker (MAP_DATA and a second CTRL.CLEAR without
            # effect, STATUS.BUSY high); the tests pause for the whole clear before the next marker
            st["busy"] = True
            st["map"] = [0] * words
            st["err"] = [st["pending"]] + [0] * (words - 1) if st["pending"] else [0] * words
            st["pending"] = 0
        elif addr == RPL_STATUS:
            if strobes & 0x2 and data & 0x100:
                st["framing"] = False
            if strobes & 0x2 and data & 0x400:
                st["unrepl"] = False
            if strobes & 0x4 and data & 0x10000:
                st["sec"] = False
            if strobes & 0x4 and data & 0x20000:
                st["ded"] = False

    for it in items:
        if it[0] == "B":
            before = fs.errors
            beats = fs.feed(it[1], it[2], it[3])
            for n, b in enumerate(beats):
                _, pixel, _last, _user, x, y = b
                src = beat if n == len(beats) - 1 else -1
                k = y * wl + x // 32
                if x == 0 and y == 0:
                    cache.clear()
                    for j in range(3):
                        read_word(j)
                    come_in_use(0)
                elif x % 32 == 0:
                    come_in_use(k)
                if x % 32 == 0:
                    read_word(k + 2)
                mark = cache[k][0] >> (x % 32) & 1
                line["pix"].append(pixel)
                line["flags"].append(mark == 0)
                line["src"].append(src)
                # q(x - G) needs the pixels up to x; the last G pixels of a line follow at its end
                done = range(x - gap, x - gap + 1) if x < width - 1 else range(max(x - gap, 0), width)
                for xo in done:
                    if xo < 0:
                        continue
                    # The window of q(xo) reaches xo + G <= x, a place that has arrived (or the line end)
                    q, unrepl = replace_pixel(line["pix"], line["flags"], xo, gap)
                    if unrepl:
                        st["unrepl"] = True
                    unrepl_beats.append(unrepl)
                    out.append(("B", q, 1 if xo == width - 1 else 0, line_flags(y, height), xo, y))
                    timing.append(line["src"][xo + gap] if xo + gap < width else -1)
                    count += 1
                if x == width - 1:
                    line = {"pix": [], "flags": [], "src": []}
            if fs.errors > before:
                st["framing"] = True
            beat += 1
        elif it[0] == "R":
            _, drop, mode, _cycles = it
            assert drop <= count, "reset drops more beats than were produced"
            _drop(out, drop)
            del timing[len(timing) - drop:]
            del unrepl_beats[len(unrepl_beats) - drop:]
            count -= drop
            out.append(("R", mode))
            fs.reset()
            cache.clear()
            line = {"pix": [], "flags": [], "src": []}
            st.update({"addr": 0, "pending": 0, "framing": False, "unrepl": False, "sec": False, "ded": False})
        elif it[0] == "J":
            st["pending"] = it[2]
        elif it[0] == "S" and it[2] == 1:
            # The scrubber, enabled for several passes without images, corrects the single errors and reports both
            if any(bin(e).count("1") == 1 for e in st["err"]):
                st["sec"] = True
            if any(bin(e).count("1") == 2 for e in st["err"]):
                st["ded"] = True
            st["err"] = [e if bin(e).count("1") != 1 else 0 for e in st["err"]]
        elif it[0] == "A":
            resolved = []
            for op, addr, data, strobes in it[2]:
                if op == "W":
                    write(addr, data, strobes)
                    resolved.append(("W", addr, data, strobes))
                else:
                    # An expected value given by the test (STATUS.BUSY during a clear) passes through
                    resolved.append(("C", addr, read(addr) if data is None else data, 0xF))
            regs.append((it[1], resolved))
            st["busy"] = False
        annot.append((count, fs.open))
    return out, fs.errors, annot, {"unreplaced": sum(unrepl_beats), "sec": cnt["sec"], "ded": cnt["ded"],
                                   "regs": regs, "timing": timing}

