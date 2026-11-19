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
- any other item ('G', 'T', 'H', 'M', 'K', 'W', 'P') passes through without effect on the model

Output items: ('B', pixel, last, user, x, y) and ('R', mode). The annotation of an input item is the state after it:
(number of output beats so far, image open). Models of modules with registers also return the resolved register
entries per marker.
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
    Err_Config pulses. Returns (out, framing errors, annot, config errors, register entries per marker)."""
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
    return out, fs.errors, annot, config_errors, regs


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
    """isp_point. Returns (out, framing errors, annot, config errors, register entries per marker)."""
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
    return out, fs.errors, annot, config_errors, regs

