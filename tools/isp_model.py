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
