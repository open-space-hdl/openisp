# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of isp_crop_tb (verification plan, sections 2 and 3).

For every configuration and test, the stimulus and the register script are built here, the reference model
(tools/isp_model.py) computes the expected output, the pulse counts and the expected register reads, and the files
are written to the vector directory.
"""

import itertools
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "tools"))

from isp_model import (CRP_ID, CRP_IMAGE, CRP_INJECT, CRP_ROI_POS, CRP_ROI_SIZE, CRP_STATUS, SEQ_CONT,  # noqa: E402
                       SEQ_FIRST, SEQ_LAST, SEQ_ONLY, crop)
from isp_tbgen import (image_beats, packets, random_image, raw_packet, rng_for, seed_for, split,  # noqa: E402
                       watchdog_us, write_test)

MODULE = "isp_crop"
SWEEP_STEPS = 12

ALL = ["test_static", "test_input_stream", "test_runtime_position", "test_invalid_position", "test_parity",
       "test_registers", "test_reset"]

# (name, W, H, PixelBits, (X, Y, width, height), runtime, gap %, stall %, tests)
CONFIGS = [
    ("w8_h6_static", 8, 6, 12, (2, 1, 4, 3), False, 0, 0,
     ["test_static", "test_input_stream", "test_registers", "test_reset", "test_rate"]),
    ("w8_h6_static_bp", 8, 6, 12, (2, 1, 4, 3), False, 30, 40,
     ["test_static", "test_input_stream", "test_parity", "test_registers", "test_reset"]),
    ("w8_h6_runtime", 8, 6, 12, (2, 1, 4, 3), True, 30, 40, ALL),
    ("w8_h6_runtime_rate", 8, 6, 12, (2, 1, 4, 3), True, 0, 0, ["test_rate", "test_flag_coincidence"]),
    ("w8_h6_full", 8, 6, 8, (0, 0, 8, 6), True, 20, 20,
     ["test_static", "test_input_stream", "test_runtime_position", "test_invalid_position"]),
    ("w8_h6_corner", 8, 6, 16, (7, 5, 1, 1), True, 20, 20,
     ["test_static", "test_runtime_position", "test_invalid_position", "test_parity"]),
    ("w8_h6_line", 8, 6, 1, (0, 5, 8, 1), False, 20, 20, ["test_static", "test_input_stream"]),
    ("w8_h6_column", 8, 6, 64, (3, 0, 1, 6), False, 20, 20, ["test_static", "test_input_stream"]),
    ("w1_h1", 1, 1, 7, (0, 0, 1, 1), True, 30, 40,
     ["test_static", "test_input_stream", "test_runtime_position", "test_parity", "test_reset"]),
    ("w33_h9", 33, 9, 13, (5, 2, 20, 6), True, 20, 20, ALL),
    ("w33_h9_rate", 33, 9, 13, (5, 2, 20, 6), False, 0, 0, ["test_rate"]),
    ("w65536_h1", 65536, 1, 12, (65535, 0, 1, 1), True, 10, 10,
     ["test_static", "test_runtime_position", "test_invalid_position"]),
    ("w1_h65536", 1, 65536, 12, (0, 0, 1, 65536), False, 10, 10, ["test_static"]),
]


def pos(x, y):
    """Value of ROI_POS."""
    return (y << 16) | x


class Cfg:
    """Generics of a configuration and the markers of its register script."""

    def __init__(self, w, h, bits, roi, runtime):
        self.w, self.h, self.bits = w, h, bits
        self.x, self.y, self.rw, self.rh = roi
        self.runtime = runtime
        self.markers = itertools.count(100)

    def regs(self, *entries):
        """Register accesses after every pixel sent so far has passed the module."""
        return [("W",), ("T", 8), ("A", next(self.markers), list(entries))]

    def image(self, rng, mode="lines"):
        return image_beats(rng, self.w, self.h, self.bits, mode)

    def big(self):
        return self.w * self.h > 4096


def status():
    """Wait for the sink, give the module time for discards, probe Stat_ImageOpen."""
    return [("W",), ("T", 8), ("P",)]


def short_image(rng, c, k):
    """The first k pixels of an image, without the last flags (the image is cut)."""
    pix = random_image(rng, c.w, c.h, c.bits)[:k]
    return packets(pix, split(rng, k, c.w, "random"), last=False)


def write(addr, data, strobes=0xF):
    return ("W", addr, data, strobes)


def check(addr):
    return ("C", addr, None, 0xF)


def build_static(rng, c):
    modes = ["lines", "random"] if c.big() else ["lines", "one", "pixel", "random", "wplus1", "line_end", "random",
                                                  "lines"]
    items = []
    for mode in modes:
        items += c.image(rng, mode)
    return items + status()


def build_input_stream(rng, c):
    n = c.w * c.h
    items = c.image(rng, "random")
    if n >= 2:
        # Short images, the missing pixels inside and outside the region, each followed by an image start
        for k in sorted({1, n // 2, n - 1} - {0}):
            items += short_image(rng, c, k) + c.image(rng, "random") + status()
    # Pixels without an image start ("00" and "10" packets)
    items += raw_packet([rng.getrandbits(c.bits) for _ in range(3)], SEQ_CONT)
    items += raw_packet([rng.getrandbits(c.bits) for _ in range(2)], SEQ_LAST)
    items += c.image(rng, "lines") + status()
    if n >= 2:
        # E3: the last pixel in a "01" packet; E4: a "11" packet that ends at the first pixel
        items += raw_packet([rng.getrandbits(c.bits) for _ in range(n)], SEQ_FIRST)
        items += raw_packet([rng.getrandbits(c.bits)], SEQ_ONLY)
        items += raw_packet([rng.getrandbits(c.bits) for _ in range(n - 1)], SEQ_LAST)
    # Random packets with random flags
    for _ in range(60):
        if rng.random() < 0.2:
            items += c.image(rng, rng.choice(["lines", "one", "random"]))
            continue
        length = rng.randint(1, 2 * n)
        items += raw_packet([rng.getrandbits(c.bits) for _ in range(length)], rng.randint(0, 3))
    items += c.image(rng, "random") + c.image(rng, "lines")
    return items + status()


def valid_positions(rng, c):
    """(0, 0), the largest valid position and random valid ones."""
    mx, my = c.w - c.rw, c.h - c.rh
    out = [(0, 0), (mx, my)]
    out += [(rng.randint(0, mx), rng.randint(0, my)) for _ in range(1 if c.big() else 3)]
    return out


def build_runtime_position(rng, c):
    items = []
    for x, y in valid_positions(rng, c):
        items += c.regs(write(CRP_ROI_POS, pos(x, y)), check(CRP_ROI_POS))
        items += c.image(rng, "random")
    # A write during an image takes effect with the next image
    n = c.w * c.h
    if n >= 2:
        pix = random_image(rng, c.w, c.h, c.bits)
        k = n // 2
        x, y = rng.randint(0, c.w - c.rw), rng.randint(0, c.h - c.rh)
        items += packets(pix[:k], [k], last=False)
        items += c.regs(write(CRP_ROI_POS, pos(x, y)))
        items += packets(pix[k:], [n - k], first=False)
        items += c.image(rng, "lines")
    # Single byte strobes: the bytes that are not selected keep their value
    for strobes in (0x1, 0xC) if c.big() else (0x1, 0x2, 0x4, 0x8, 0x3, 0xC):
        x, y = rng.randint(0, c.w - c.rw), rng.randint(0, c.h - c.rh)
        data = pos(x, y)
        for b in range(4):
            if not strobes & (1 << b):
                data |= rng.getrandbits(8) << (8 * b)
        items += c.regs(write(CRP_ROI_POS, data, strobes), check(CRP_ROI_POS))
        items += c.image(rng, "random")
    return items + status()


def build_invalid_position(rng, c):
    mx, my = c.w - c.rw, c.h - c.rh
    bad = []
    if mx + 1 <= 0xFFFF:
        bad.append((mx + 1, 0))
    if my + 1 <= 0xFFFF:
        bad.append((0, my + 1))
    if mx + 1 <= 0xFFFF and my + 1 <= 0xFFFF:
        bad.append((mx + 1, my + 1))
    bad.append((0xFFFF, 0xFFFF))
    items = []
    for x, y in bad:
        items += c.regs(write(CRP_ROI_POS, pos(x, y)), check(CRP_ROI_POS))
        # Images with the generics and one Err_Config each
        items += c.image(rng, "random") + ([] if c.big() else c.image(rng, "lines"))
        items += c.regs(check(CRP_STATUS), write(CRP_STATUS, 0x200), check(CRP_STATUS))
        # The largest valid position in one direction and a valid write afterwards
        items += c.regs(write(CRP_ROI_POS, pos(mx, 0)))
        items += c.image(rng, "random")
        items += c.regs(write(CRP_ROI_POS, pos(0, my)), check(CRP_STATUS))
        items += c.image(rng, "lines")
    return items + status()


def build_parity(rng, c):
    # A position that differs from the generics, so that the use of the generics is visible
    other = (0, 0) if (c.x, c.y) != (0, 0) else (c.w - c.rw, c.h - c.rh)
    items = c.regs(write(CRP_ROI_POS, pos(*other)))
    items += c.image(rng, "lines")
    # The injection: every image uses the generics until ROI_POS is written
    items += c.regs(write(CRP_INJECT, 1))
    items += c.image(rng, "random") + c.image(rng, "lines")
    # A second injection restores the parity
    items += c.regs(write(CRP_INJECT, 1), check(CRP_INJECT))
    items += c.image(rng, "random")
    # An injection followed by a write: the written position
    items += c.regs(write(CRP_INJECT, 1), write(CRP_ROI_POS, pos(*other)))
    items += c.image(rng, "lines")
    # An injection with the strobe of byte 0 off has no effect
    items += c.regs(write(CRP_INJECT, 1, 0xE))
    items += c.image(rng, "random")
    items += c.regs(check(CRP_STATUS))
    return items + status()


def build_registers(rng, c):
    n = c.w * c.h
    items = c.regs(check(CRP_ID), check(CRP_IMAGE), check(CRP_ROI_SIZE), check(CRP_ROI_POS), check(CRP_STATUS),
                   check(CRP_INJECT))
    # Writes to read-only registers (and to ROI_POS with RuntimeRoi_g false) have no effect
    items += c.regs(write(CRP_ID, 0xFFFFFFFF), write(CRP_IMAGE, 0xFFFFFFFF), write(CRP_ROI_SIZE, 0xFFFFFFFF),
                    check(CRP_ID), check(CRP_IMAGE), check(CRP_ROI_SIZE))
    if not c.runtime:
        items += c.regs(write(CRP_ROI_POS, pos(0, 0)), check(CRP_ROI_POS))
    # Unused addresses read 0
    items += c.regs(*[check(a) for a in (0x18, 0x1C, 0x40, 0x80, 0xFC)], write(0x18, 0xFFFFFFFF), check(0x18))
    # STATUS.IMAGE_OPEN during an image
    if n >= 2:
        pix = random_image(rng, c.w, c.h, c.bits)
        items += packets(pix[:1], [1], last=False) + c.regs(check(CRP_STATUS))
        items += packets(pix[1:], [n - 1], first=False) + c.regs(check(CRP_STATUS))
    # STATUS.ERR_FRAMING: set by a discarded pixel, kept by a write of 0 and by a clear without the strobe of byte 1,
    # cleared by a write of 1
    items += raw_packet([rng.getrandbits(c.bits)], SEQ_CONT)
    items += c.regs(check(CRP_STATUS), write(CRP_STATUS, 0), check(CRP_STATUS), write(CRP_STATUS, 0x100, 0xD),
                    check(CRP_STATUS), write(CRP_STATUS, 0x100), check(CRP_STATUS))
    items += c.image(rng, "lines")
    if c.runtime:
        # STATUS.ERR_CONFIG in the same way
        items += c.regs(write(CRP_ROI_POS, pos(0xFFFF, 0)))
        items += c.image(rng, "lines")
        items += c.regs(check(CRP_STATUS), write(CRP_STATUS, 0), check(CRP_STATUS), write(CRP_STATUS, 0x200),
                        check(CRP_STATUS), write(CRP_ROI_POS, pos(c.x, c.y)))
        items += c.image(rng, "random")
    return items + status()


def build_reset(rng, c):
    n = c.w * c.h
    # A position that differs from the generics, so that the reset value is visible
    other = (0, 0) if (c.x, c.y) != (0, 0) else (c.w - c.rw, c.h - c.rh)
    items = []
    if c.runtime:
        items += c.regs(write(CRP_ROI_POS, pos(*other)))
    items += c.image(rng, "lines")
    # Reset with the module idle (two cycles); ROI_POS holds the generics again
    items += [("W",), ("T", 4), ("R", 0, 0, 2)]
    items += c.regs(check(CRP_ROI_POS), check(CRP_STATUS))
    items += c.image(rng, "random")
    roi = [i for i in range(n) if c.x <= i % c.w < c.x + c.rw and c.y <= i // c.w < c.y + c.rh]
    outside = [i for i in range(n) if i not in set(roi)]
    cases = []
    # In the middle of an image: the last pixel sent inside the region (1 or 2 beats in the module), or outside
    if len(roi) >= 3:
        cases += [(roi[2] + 1, 2, 0, 1), (roi[1] + 1, 1, 1, 2)]
    if len(roi) >= 2:
        cases += [(roi[1] + 1, 1, 0, 2)]
    # The last pixel sent outside the region, after the first pixel of the region
    later = [i for i in outside if i > roi[0]] if roi else []
    if later:
        k = later[0] + 1
        cases += [(k, 0, 0, 1), (k, sum(1 for i in roi if i < k), 1, 1)]
    for k, drop, mode, cycles in cases:
        if c.runtime:
            items += c.regs(write(CRP_ROI_POS, pos(*other)))
        pix = random_image(rng, c.w, c.h, c.bits)
        if mode == 1 and drop == 0:
            continue
        items += packets(pix[:k], [k], last=False)
        items += [("R", drop, mode, cycles)]
        # The rest of the interrupted image is a run of pixels without an image start
        if k < n:
            items += raw_packet(pix[k:], SEQ_LAST)
        items += c.image(rng, "lines")
    return items + status()


def build_rate(rng, c):
    # Phase 1: images back to back, without gaps
    items = [("M", 1)]
    for mode in ("lines", "random", "one"):
        items += c.image(rng, mode)
    items += [("W",), ("M", 2)]
    # Phase 2: the last pixel of the first line of the region held in the output register; the pixels outside the
    # region up to the next pixel of the region are taken in every cycle (marker 4)
    n = c.w * c.h
    last = c.y * c.w + c.x + c.rw - 1
    nxt = last + c.w - c.rw + 1 if c.rh > 1 else n
    if nxt - last > 1:
        pix = random_image(rng, c.w, c.h, c.bits)
        items += packets(pix[:last], [last], last=False) + [("W",), ("H", 1)]
        items += packets(pix[last:last + 1], [1], first=False, last=False) + [("T", 6), ("M", 4)]
        rest = pix[last + 1:nxt]
        items += packets(rest, [len(rest)], first=False, last=nxt == n)
        items += [("T", 3), ("M", 5), ("H", 0)]
        if nxt < n:
            items += packets(pix[nxt:], [n - nxt], first=False)
        items += [("W",), ("M", 6)]
    return items + status()


def build_flag_coincidence(rng, c):
    items = []
    if c.runtime:
        # An invalid position: every image start pulses Err_Config (ispRegsRun ends before the sweeps)
        bad = pos(c.w - c.rw + 1, 0) if c.w - c.rw + 1 <= 0xFFFF else pos(0, c.h - c.rh + 1)
        items += [("A", 100, [write(CRP_ROI_POS, bad)])]
    for d in range(SWEEP_STEPS):
        # An image ends the run of discarded pixels, so that the pixel of the step pulses Err_Framing; the pause
        # after the acknowledge places the pulse inside the range of the clears of the sweep
        items += c.image(rng, "lines") + [("W",), ("T", 4), ("M", 300 + d), ("K", 300 + d), ("T", 4)]
        items += raw_packet([rng.getrandbits(c.bits)], SEQ_CONT) + [("T", 40)]
    if c.runtime:
        for d in range(SWEEP_STEPS):
            items += [("W",), ("T", 4), ("M", 400 + d), ("K", 400 + d), ("T", 4)] + c.image(rng, "lines") + [("T", 40)]
    return items + status()


BUILDERS = {
    "test_static": build_static,
    "test_input_stream": build_input_stream,
    "test_runtime_position": build_runtime_position,
    "test_invalid_position": build_invalid_position,
    "test_parity": build_parity,
    "test_registers": build_registers,
    "test_reset": build_reset,
    "test_rate": build_rate,
    "test_flag_coincidence": build_flag_coincidence,
}


def configure(lib, out_dir):
    tb = lib.test_bench("isp_crop_tb")
    for name, w, h, bits, roi, runtime, gap, stall, tests in CONFIGS:
        for test in tests:
            rng = rng_for(MODULE, name, test)
            c = Cfg(w, h, bits, roi, runtime)
            items = BUILDERS[test](rng, c)
            folder = Path(out_dir) / MODULE / name
            files = {ext: folder / (test + "." + ext) for ext in ("stim", "exp", "regs", "tim")}
            res = write_test(files["stim"], files["exp"], items,
                             lambda it: crop(it, w, h, *roi, runtime), bits,
                             regs_path=files["regs"], tim_path=files["tim"])
            tb.test(test).add_config(name=name, generics={
                "ImageWidth_g": w, "ImageHeight_g": h, "PixelBits_g": bits,
                "RoiX_g": roi[0], "RoiY_g": roi[1], "RoiWidth_g": roi[2], "RoiHeight_g": roi[3],
                "RuntimeRoi_g": runtime,
                "StimFile_g": files["stim"].as_posix(), "ExpFile_g": files["exp"].as_posix(),
                "RegsFile_g": files["regs"].as_posix(), "TimFile_g": files["tim"].as_posix(),
                "GapPct_g": gap, "StallPct_g": stall, "Seed_g": seed_for(MODULE, name, test),
                "ExpFraming_g": res["errors"], "ExpConfig_g": res["config"], "SweepSteps_g": SWEEP_STEPS,
                "WatchdogUs_g": watchdog_us(files["stim"], files["exp"])})
