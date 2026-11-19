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
    Err_Config pulses. Returns (out, framing errors, annot, {"config", "regs"})."""
    fs = FrameSync(width, height)
    reg = (roi_y << 16) | roi_x                  # ROI_POS, reset value from the generics
    parity_ok = True
    status_framing = status_config = False
    config_errors = 0
    pos = (roi_x, roi_y)
    out, annot, regs = [], [], []
    count = 0

    def select(beats):
        nonlocal pos, config_errors, status_config, count
        for b in beats:
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
            select(fs.feed(it[1], it[2], it[3]))
            if fs.errors > before:
                status_framing = True
        elif it[0] == "R":
            _, drop, mode, _cycles = it
            assert drop <= count, "reset drops more beats than were produced"
            _drop(out, drop)
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
    return out, fs.errors, annot, {"config": config_errors, "regs": regs}


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
    """isp_point. Returns (out, framing errors, annot, {"config", "regs"})."""
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
        st["parity"] = [True] * 6
        st["hold"] = False

    reset_regs()
    work = gen                                        # the parameter set in use, from the reset the generics
    status_framing = status_config = False
    config_errors = 0
    out, annot, regs = [], [], []
    count = 0

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
        values[PNT_CTRL] = 1 if (runtime and st["hold"]) else 0
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
        elif addr == PNT_CTRL and strobes & 0x1:
            st["hold"] = bool(data & 1)
        elif addr == PNT_INJECT and strobes & 0x1:
            for n in range(6):
                if data & (1 << n):
                    st["parity"][n] = not st["parity"][n]

    for it in items:
        if it[0] == "B":
            before = fs.errors
            for b in fs.feed(it[1], it[2], it[3]):
                _, pixel, last, user, x, y = b
                if x == 0 and y == 0 and runtime and not st["hold"]:
                    if all(st["parity"]):
                        work = reg_set()
                    else:
                        work = gen
                        config_errors += 1
                        status_config = True
                out.append(("B", point_op(pixel, *work), last, user, x, y))
                count += 1
            if fs.errors > before:
                status_framing = True
        elif it[0] == "R":
            _, drop, mode, _cycles = it
            assert drop <= count, "reset drops more beats than were produced"
            _drop(out, drop)
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
    return out, fs.errors, annot, {"config": config_errors, "regs": regs}


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
        self.delays = [[(0, 0)] * self.w for _ in range(self.wy - 1)]
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
        for t in range(self.wy - 1):
            queue = self.delays[t]
            stored, flips = queue.pop(0)
            mask, s, d = ecc_decode(flips, self.bits)
            read = stored ^ mask
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

