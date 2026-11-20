# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of isp_point_tb (verification plan, sections 2 and 3).

For every configuration and test, the stimulus and the register script are built here, the reference model
(tools/isp_model.py) computes the expected output, the pulse counts and the expected register reads, and the files
are written to the vector directory.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "tools"))

from isp_model import (PNT_CTRL, PNT_GAIN, PNT_HIGH, PNT_ID, PNT_IMAGE, PNT_INJECT, PNT_LOW,  # noqa: E402
                       PNT_OFFSET_HI, PNT_OFFSET_LO, PNT_PARAM, PNT_SHIFT, PNT_STATUS, SEQ_CONT, point)
from isp_tbgen import (RegScript, check, image_beats, malformed_streams, packets, random_image,  # noqa: E402
                       raw_packet, rng_for, seed_for, split, status, watchdog_us, write, write_test)

MODULE = "isp_point"
SWEEP_STEPS = 12
PARAMS = [PNT_OFFSET_LO, PNT_OFFSET_HI, PNT_GAIN, PNT_SHIFT, PNT_LOW, PNT_HIGH]

STATIC = ["test_static", "test_input_stream", "test_parity", "test_registers", "test_reset"]
RUNTIME = ["test_static", "test_input_stream", "test_runtime", "test_hold", "test_parity", "test_registers",
           "test_reset"]
DEFAULTS = (0, 1, 0, 0, -1)

# (name, W, H, in bits, out bits, gain bits, MaxShift_g, MultStages_g, runtime, (offset, gain, shift, low, high),
#  gap %, stall %, tests)
CONFIGS = [
    ("shift", 6, 4, 16, 12, 16, 32, 2, False, (0, 1, 4, 0, -1), 20, 20, STATIC),
    ("dark_gain", 6, 4, 12, 12, 16, 28, 2, False, (-100, 1229, 10, 0, -1), 30, 40, STATIC),
    ("clamp", 6, 4, 12, 8, 16, 28, 3, False, (7, 3, 2, 20, 200), 0, 0, STATIC),
    ("neutral", 6, 4, 8, 8, 1, 9, 1, False, DEFAULTS, 20, 20, STATIC),
    ("runtime", 6, 4, 12, 12, 16, 28, 2, True, DEFAULTS, 30, 40, RUNTIME),
    ("runtime_rate", 6, 4, 12, 12, 16, 28, 2, True, DEFAULTS, 0, 0, ["test_rate", "test_flag_coincidence"]),
    ("exhaustive", 16, 1, 4, 4, 3, 6, 4, True, DEFAULTS, 0, 0, ["test_exhaustive"]),
    ("shift_limit", 6, 4, 12, 12, 16, 8, 2, True, DEFAULTS, 20, 20, ["test_runtime"]),
    ("wide", 4, 3, 64, 32, 18, 83, 4, True, DEFAULTS, 20, 20,
     ["test_static", "test_runtime", "test_parity", "test_registers"]),
    ("narrow", 3, 2, 1, 1, 1, 0, 1, True, DEFAULTS, 20, 20,
     ["test_static", "test_runtime", "test_parity", "test_registers"]),
] + [("stages_{}".format(n), 6, 4, 12, 12, 16, 28, n, True, DEFAULTS, 0, 0, ["test_static", "test_rate"])
     for n in range(1, 5)] + [
    ("w65536_h1", 65536, 1, 12, 12, 16, 28, 2, False, (-100, 1229, 10, 0, -1), 10, 10, ["test_static"]),
    ("w1_h65536", 1, 65536, 12, 12, 16, 28, 2, False, (-100, 1229, 10, 0, -1), 10, 10, ["test_static"]),
    # The low bound of the width in a small image (the pull-request CI runs it; w1_h65536 runs in the full tier)
    ("w1_h4", 1, 4, 12, 12, 16, 28, 2, False, (-100, 1229, 10, 0, -1), 10, 10, ["test_static"]),
    ("generic_bounds", 4, 3, 32, 32, 18, 50, 2, False, (-2 ** 31, 2 ** 18 - 1, 50, 2 ** 31 - 1, -1), 0, 0,
     ["test_static", "test_registers"]),
    # The module at the defaults of its entity (DutDefaults_g): the model and the bench take the defaults of the
    # specification, GainBits_g 16 and MaxShift_g InBits_g + GainBits_g (PARAM.MAX_SHIFT)
    ("defaults", 6, 4, 12, 12, 16, 12 + 16, 2, False, DEFAULTS, 20, 20, ["test_static", "test_registers"]),
]
DUT_DEFAULTS = ("defaults",)


class Cfg:
    """Generics of a configuration and the register script of a test."""

    def __init__(self, w, h, inb, outb, gainb, maxs, ms, runtime, gen):
        self.w, self.h, self.inb, self.outb, self.gainb, self.maxs, self.ms = w, h, inb, outb, gainb, maxs, ms
        self.runtime = runtime
        self.gen = gen
        self.ow = min(inb + 1, 64)
        self.regs = RegScript()

    def image(self, rng, mode="lines"):
        """An image with random pixels over the full range, among them 0 and the largest value."""
        n = self.w * self.h
        pix = random_image(rng, self.w, self.h, self.inb)
        if n >= 2:
            a, b = rng.sample(range(n), 2)
            pix[a], pix[b] = 0, (1 << self.inb) - 1
        return packets(pix, split(rng, n, self.w, mode))

    def big(self):
        return self.w * self.h > 4096

    def random_set(self, rng):
        """A random parameter set: offset, gain, shift, low <= high."""
        off = rng.randint(-(1 << (self.ow - 1)), (1 << (self.ow - 1)) - 1)
        gain = rng.randint(0, (1 << self.gainb) - 1)
        shift = rng.randint(0, self.maxs)
        a, b = sorted(rng.randint(0, (1 << self.outb) - 1) for _ in range(2))
        return (off, gain, shift, a, b)

    def set_writes(self, s):
        """Writes of a parameter set (offset, gain, shift, low, high)."""
        off, gain, shift, low, high = s
        return [write(PNT_OFFSET_LO, off & 0xFFFFFFFF), write(PNT_OFFSET_HI, (off >> 32) & 0xFFFFFFFF),
                write(PNT_GAIN, gain), write(PNT_SHIFT, shift), write(PNT_LOW, low), write(PNT_HIGH, high)]


def build_static(rng, c):
    modes = ["lines", "random"] if c.big() else ["lines", "one", "pixel", "random", "wplus1", "line_end"]
    items = []
    for mode in modes:
        items += c.image(rng, mode)
    return items + status()


def build_input_stream(rng, c):
    return malformed_streams(rng, c.w, c.h, c.inb)


def build_runtime(rng, c):
    full = (1 << c.outb) - 1
    lo, hi = -(1 << (c.ow - 1)), (1 << (c.ow - 1)) - 1
    gmax = (1 << c.gainb) - 1
    base = c.random_set(rng)
    sets = [c.random_set(rng) for _ in range(3)]
    sets += [(base[0], 0, base[2], base[3], base[4]), (base[0], 1, base[2], base[3], base[4]),
             (base[0], gmax, base[2], base[3], base[4])]
    # The shifts 0, MaxShift_g, MaxShift_g + 1 and 127 (both taken as MaxShift_g) on a product that the shift makes
    # visible: offset 0, gain 2^min(MaxShift_g, GainBits_g - 1), no clamp
    g = 1 << min(c.maxs, c.gainb - 1)
    sets += [(0, g, s, 0, full) for s in sorted({0, c.maxs, min(c.maxs + 1, 127), 127})]
    sets += [(lo, base[1], base[2], 0, full), (hi, base[1], base[2], 0, full)]
    sets += [(base[0], base[1], base[2], full, 0), (base[0], base[1], base[2], full // 2, full // 2)]
    items = []
    for s in sets:
        items += c.regs.access(*c.set_writes(s), *[check(a) for a in PARAMS])
        items += c.image(rng, "random")
    # A set written during an image takes effect with the next image
    n = c.w * c.h
    if n >= 2:
        pix = random_image(rng, c.w, c.h, c.inb)
        k = n // 2
        items += packets(pix[:k], [k], last=False)
        items += c.regs.access(*c.set_writes(c.random_set(rng)))
        items += packets(pix[k:], [n - k], first=False)
        items += c.image(rng, "lines")
    return items + status()


def build_hold(rng, c):
    a, b, d = c.random_set(rng), c.random_set(rng), c.random_set(rng)
    items = c.regs.access(*c.set_writes(a)) + c.image(rng, "lines")
    # HOLD 1: set b written over two images, which keep a
    items += c.regs.access(write(PNT_CTRL, 1), *c.set_writes(b)[:3])
    items += c.image(rng, "random")
    items += c.regs.access(*c.set_writes(b)[3:], check(PNT_CTRL))
    items += c.image(rng, "lines")
    # HOLD 0: the next image takes b as a whole
    items += c.regs.access(write(PNT_CTRL, 0)) + c.image(rng, "random")
    # HOLD 1 with a register of bad parity: no set taken, no report
    items += c.regs.access(write(PNT_CTRL, 1), write(PNT_INJECT, 1 << 2)) + c.image(rng, "lines")
    items += c.regs.access(check(PNT_STATUS))
    # HOLD 0: the bad parity is found, the generics apply
    items += c.regs.access(write(PNT_CTRL, 0)) + c.image(rng, "random")
    # Written again: the registers apply
    items += c.regs.access(*c.set_writes(d)) + c.image(rng, "lines")
    return items + status()


def build_parity(rng, c):
    s = c.random_set(rng)
    writes = c.set_writes(s)
    items = c.regs.access(*writes) + c.image(rng, "lines")
    for n in range(6):
        # The injection: the generics for every image until the register is written
        items += c.regs.access(write(PNT_INJECT, 1 << n)) + c.image(rng, "random") + c.image(rng, "lines")
        items += c.regs.access(writes[n]) + c.image(rng, "random")
    # Two registers at once, then a second injection that restores both
    items += c.regs.access(write(PNT_INJECT, 0b100100)) + c.image(rng, "lines")
    items += c.regs.access(write(PNT_INJECT, 0b100100), check(PNT_INJECT)) + c.image(rng, "random")
    # CTRL (PNT-ER-04): with HOLD 1, an injection makes HOLD count as 0: the held set is taken, with Err_Config, at
    # every image start until CTRL is written; a write of CTRL restores the parity
    held, later = c.random_set(rng), c.random_set(rng)
    items += c.regs.access(write(PNT_CTRL, 1), *c.set_writes(held)) + c.image(rng, "random")
    items += c.regs.access(write(PNT_INJECT, 1 << 6)) + c.image(rng, "lines") + c.image(rng, "random")
    items += c.regs.access(write(PNT_CTRL, 1), *c.set_writes(later)) + c.image(rng, "lines")
    items += c.regs.access(write(PNT_CTRL, 0)) + c.image(rng, "random")
    # Without the strobe of byte 0 the injection has no effect
    items += c.regs.access(write(PNT_INJECT, 0x7F, 0xE)) + c.image(rng, "lines")
    items += c.regs.access(check(PNT_STATUS))
    return items + status()


def build_registers(rng, c):
    n = c.w * c.h
    items = c.regs.access(*[check(a) for a in (PNT_ID, PNT_IMAGE, PNT_PARAM, PNT_CTRL, PNT_STATUS, PNT_INJECT)],
                          *[check(a) for a in PARAMS])
    # Writes to read-only registers have no effect
    items += c.regs.access(write(PNT_ID, 0xFFFFFFFF), write(PNT_IMAGE, 0xFFFFFFFF), write(PNT_PARAM, 0xFFFFFFFF),
                           check(PNT_ID), check(PNT_IMAGE), check(PNT_PARAM))
    # Every single byte strobe on every parameter register (read only with Runtime_g false)
    for addr in PARAMS:
        for b in range(4):
            items += c.regs.access(write(addr, rng.getrandbits(32), 1 << b), check(addr))
    items += c.image(rng, "lines")
    items += c.regs.access(write(PNT_CTRL, 1), check(PNT_CTRL), write(PNT_CTRL, 0), check(PNT_CTRL))
    # Unused addresses read 0
    items += c.regs.access(*[check(a) for a in (0x30, 0x34, 0x40, 0x80, 0xFC)], write(0x30, 0xFFFFFFFF), check(0x30))
    # STATUS.IMAGE_OPEN during an image
    if n >= 2:
        pix = random_image(rng, c.w, c.h, c.inb)
        items += packets(pix[:1], [1], last=False) + c.regs.access(check(PNT_STATUS))
        items += packets(pix[1:], [n - 1], first=False) + c.regs.access(check(PNT_STATUS))
    # STATUS.ERR_FRAMING: set by a discarded pixel, kept by a write of 0 and without the strobe of byte 1, cleared
    items += raw_packet([rng.getrandbits(c.inb)], SEQ_CONT)
    items += c.regs.access(check(PNT_STATUS), write(PNT_STATUS, 0), check(PNT_STATUS), write(PNT_STATUS, 0x100, 0xD),
                           check(PNT_STATUS), write(PNT_STATUS, 0x100), check(PNT_STATUS))
    items += c.image(rng, "lines")
    if c.runtime:
        # STATUS.ERR_CONFIG in the same way
        items += c.regs.access(write(PNT_INJECT, 1 << 3)) + c.image(rng, "lines")
        items += c.regs.access(check(PNT_STATUS), write(PNT_STATUS, 0), check(PNT_STATUS), write(PNT_STATUS, 0x200),
                               check(PNT_STATUS), write(PNT_INJECT, 1 << 3))
        items += c.image(rng, "random")
    return items + status()


def build_exhaustive(rng, c):
    # Every offset, gain and shift of the configuration as a run-time set, over an image of all pixel values; the
    # shifts above MaxShift_g and 127 are taken as MaxShift_g, which lies below the width of the product
    thresholds = [(0, (1 << c.outb) - 1), (2, 13), (9, 5)]
    shifts = list(range(c.maxs + 3)) + [127]
    items = []
    k = 0
    for off in range(-(1 << (c.ow - 1)), 1 << (c.ow - 1)):
        for gain in range(1 << c.gainb):
            for shift in shifts:
                low, high = thresholds[k % len(thresholds)]
                k += 1
                writes = []
                if gain == 0 and shift == 0:
                    writes += [write(PNT_OFFSET_LO, off & 0xFFFFFFFF), write(PNT_OFFSET_HI, (off >> 32) & 0xFFFFFFFF)]
                if shift == 0:
                    writes.append(write(PNT_GAIN, gain))
                writes += [write(PNT_SHIFT, shift), write(PNT_LOW, low), write(PNT_HIGH, high)]
                items += c.regs.access(*writes)
                pix = list(range(1 << c.inb))
                rng.shuffle(pix)
                items += packets(pix, [len(pix)])
    return items + status()


def build_reset(rng, c):
    n = c.w * c.h
    other = c.random_set(rng)
    items = []
    if c.runtime:
        items += c.regs.access(*c.set_writes(other))
    items += c.image(rng, "lines")
    # Reset with the module idle (two cycles); the registers hold the generics again
    items += [("W",), ("T", 4), ("R", 0, 0, 2)]
    items += c.regs.access(*[check(a) for a in PARAMS], check(PNT_CTRL), check(PNT_STATUS))
    items += c.image(rng, "random")
    if n >= 4:
        for drop, mode, cycles in ((2, 0, 1), (3, 1, 2), (0, 0, 1)):
            if c.runtime:
                items += c.regs.access(*c.set_writes(other))
            pix = random_image(rng, c.w, c.h, c.inb)
            k = rng.randint(max(drop, 1) + 1, n - 1)
            items += packets(pix[:k], [k], last=False)
            items += [("R", drop, mode, cycles)]
            items += raw_packet(pix[k:], 2)
            items += c.image(rng, "lines")
    return items + status()


def build_rate(rng, c):
    items = [("M", 1)]
    for mode in ("lines", "random", "one"):
        items += c.image(rng, mode)
    items += [("W",), ("M", 2)]
    return items + status()


def build_flag_coincidence(rng, c):
    # A parity error of GAIN: every image start pulses Err_Config (ispRegsRun ends before the sweeps)
    items = [("A", 100, [write(PNT_INJECT, 1 << 2)])]
    for d in range(SWEEP_STEPS):
        # An image ends the run of discarded pixels, so that the pixel of the step pulses Err_Framing; the pause
        # after the acknowledge places the pulse inside the range of the clears of the sweep
        items += c.image(rng, "lines") + [("W",), ("T", 4), ("M", 300 + d), ("K", 300 + d), ("T", 4)]
        items += raw_packet([rng.getrandbits(c.inb)], SEQ_CONT) + [("T", 40)]
    for d in range(SWEEP_STEPS):
        items += [("W",), ("T", 4), ("M", 400 + d), ("K", 400 + d), ("T", 4)] + c.image(rng, "lines") + [("T", 40)]
    return items + status()


BUILDERS = {
    "test_static": build_static,
    "test_input_stream": build_input_stream,
    "test_runtime": build_runtime,
    "test_hold": build_hold,
    "test_parity": build_parity,
    "test_registers": build_registers,
    "test_exhaustive": build_exhaustive,
    "test_reset": build_reset,
    "test_rate": build_rate,
    "test_flag_coincidence": build_flag_coincidence,
}


def configure(lib, out_dir):
    tb = lib.test_bench("isp_point_tb")
    for name, w, h, inb, outb, gainb, maxs, ms, runtime, gen, gap, stall, tests in CONFIGS:
        for test in tests:
            rng = rng_for(MODULE, name, test)
            c = Cfg(w, h, inb, outb, gainb, maxs, ms, runtime, gen)
            items = BUILDERS[test](rng, c)
            folder = Path(out_dir) / MODULE / name
            files = {ext: folder / (test + "." + ext) for ext in ("stim", "exp", "regs", "tim")}
            res = write_test(files["stim"], files["exp"], items,
                             lambda it: point(it, w, h, inb, outb, gainb, maxs, *gen, runtime), outb,
                             regs_path=files["regs"], tim_path=files["tim"])
            tb.test(test).add_config(name=name, generics={
                "ImageWidth_g": w, "ImageHeight_g": h, "InBits_g": inb, "OutBits_g": outb, "GainBits_g": gainb,
                "MaxShift_g": maxs, "MultStages_g": ms, "Runtime_g": runtime,
                "Offset_g": gen[0], "Gain_g": gen[1], "Shift_g": gen[2], "Low_g": gen[3], "High_g": gen[4],
                "StimFile_g": files["stim"].as_posix(), "ExpFile_g": files["exp"].as_posix(),
                "RegsFile_g": files["regs"].as_posix(), "TimFile_g": files["tim"].as_posix(),
                "GapPct_g": gap, "StallPct_g": stall, "Seed_g": seed_for(MODULE, name, test),
                "ExpFraming_g": res["errors"], "ExpConfig_g": res["config"], "SweepSteps_g": SWEEP_STEPS,
                "DutDefaults_g": name in DUT_DEFAULTS, "WatchdogUs_g": watchdog_us(files["stim"], files["exp"])})
