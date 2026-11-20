# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of isp_conv_tb (verification plan, sections 2 and 3).

For every configuration and test, the window stream and the register script are built here, the reference model
(tools/isp_model.py) computes the expected output pixels, the Err_Config pulses and the expected register reads,
and the files are written to the vector directory. The coefficient set of the generic is passed as a string.
"""

import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "tools"))

from isp_model import (CNV_COEF, CNV_CTRL, CNV_ID, CNV_INJECT, CNV_PARAM, CNV_STATUS, SEQ_CONT,  # noqa: E402
                       SEQ_FIRST, conv, conv_full_bits)
from isp_tbgen import RegScript, check, packets, raw_packet, rng_for, seed_for, status, watchdog_us, write, \
    write_test  # noqa: E402

MODULE = "isp_conv"
SWEEP_STEPS = 12
REGS = ["test_static", "test_runtime", "test_hold", "test_parity", "test_registers", "test_packets", "test_reset"]
CONST = ["test_static", "test_parity", "test_registers", "test_packets", "test_reset"]


def mtf3():
    return [-1, -2, -1, -2, 28, -2, -1, -2, -1]


def mtf5():
    k = [[0, -1, -1, -1, 0], [-1, -2, -4, -2, -1], [-1, -4, 44, -4, -1], [-1, -2, -4, -2, -1], [0, -1, -1, -1, 0]]
    return [v for row in k for v in row]


def rand_coef(seed, n, cb):
    rng = random.Random(seed)
    return [rng.randint(-(1 << (cb - 1)), (1 << (cb - 1)) - 1) for _ in range(n)]


def bounds_coef(n, cb):
    lo, hi = -(1 << (cb - 1)), (1 << (cb - 1)) - 1
    return [lo if k % 2 == 0 else hi for k in range(n)]


def cfg(name, pb, wx, wy, cb, coef, runtime, ob, w, h, gap=20, stall=20, tests=None):
    return dict(name=name, pb=pb, wx=wx, wy=wy, cb=cb, coef=coef, runtime=runtime, ob=ob, w=w, h=h, gap=gap,
                stall=stall, tests=tests or ["test_static"])


CONFIGS = [
    cfg("mtf3", 12, 3, 3, 16, mtf3(), True, 0, 8, 6, tests=REGS),
    cfg("mtf5_const", 12, 5, 5, 16, mtf5(), False, 12, 8, 6, 30, 40, tests=CONST),
    cfg("ones4", 12, 1, 4, 2, [1] * 4, False, 0, 6, 4, tests=CONST),
    cfg("exhaustive", 3, 1, 2, 3, [1, 1], True, 0, 8, 8, 0, 0, tests=["test_exhaustive"]),
    cfg("exhaustive_sat", 3, 1, 2, 3, [1, 1], True, 3, 8, 8, 0, 0, tests=["test_exhaustive"]),
    cfg("min", 1, 1, 1, 2, [1], True, 1, 5, 3, tests=REGS),
    cfg("max", 32, 16, 16, 18, rand_coef(16, 256, 18), True, 64, 4, 3, 10, 10, tests=REGS),
    cfg("wide", 32, 3, 3, 18, bounds_coef(9, 18), True, 0, 6, 4, tests=REGS),
    cfg("rate_3", 12, 3, 3, 16, rand_coef(3, 9, 16), True, 0, 16, 6, 0, 0, tests=["test_rate", "test_flag_coincidence"]),
    cfg("rate_5", 12, 5, 5, 16, rand_coef(5, 25, 16), True, 0, 16, 6, 0, 0, tests=["test_rate"]),
    cfg("rate_256", 12, 16, 16, 16, rand_coef(256, 256, 16), True, 0, 16, 6, 0, 0, tests=["test_rate"]),
]
# Sweeps: every window size (run time), every depth of the adder tree (constant), the bounds of the widths
CONFIGS += [cfg("size_{}x{}".format(n, 17 - n), 8, n, 17 - n, 8, rand_coef(n, n * (17 - n), 8), True, 0, 4, 3,
                tests=["test_static", "test_parity"]) for n in range(1, 17)]
TAPS = [(1, 1), (1, 2), (1, 3), (2, 2), (1, 5), (2, 4), (3, 11), (2, 16), (5, 13), (4, 16), (10, 13), (8, 16),
        (15, 16), (16, 16)]
CONFIGS += [cfg("taps_{}".format(x * y), 6, x, y, 6, rand_coef(x * y, x * y, 6), False, 0, 4, 3,
                tests=["test_static", "test_parity"]) for x, y in TAPS]
WIDTHS = [(1, 2, 1), (3, 3, 0), (16, 17, 12), (31, 18, conv_full_bits(31, 18, 9)), (32, 18, 64), (32, 2, 0)]
CONFIGS += [cfg("widths_{}_{}_{}".format(p, c, o), p, 3, 3, c, rand_coef(p + c, 9, c), True, o, 6, 4,
                tests=["test_static", "test_runtime", "test_parity"]) for p, c, o in WIDTHS]


class Ctx:
    def __init__(self, c):
        self.c = c
        self.t = c["wx"] * c["wy"]
        self.regs = RegScript()

    def window(self, elems):
        return sum(e << (k * self.c["pb"]) for k, e in enumerate(elems))

    def rand_window(self, rng):
        return self.window([rng.getrandbits(self.c["pb"]) for _ in range(self.t)])

    def special(self):
        """Windows of the coefficients of the generic: of largest elements, of zero elements, of the largest and of
        the most negative sum, and with nonzero elements a sum of exactly 0 where the set has both signs."""
        top = (1 << self.c["pb"]) - 1
        coef = self.c["coef"]
        wins = [self.window([top] * self.t), 0, self.window([top if co > 0 else 0 for co in coef]),
                self.window([top if co < 0 else 0 for co in coef])]
        pos = [k for k, co in enumerate(coef) if co > 0]
        neg = [k for k, co in enumerate(coef) if co < 0]
        if pos and neg:
            # c(p) x |c(n)| + c(n) x c(p) = 0 with the smallest such pair that fits the pixel width
            p, n = min(((p, n) for p in pos for n in neg), key=lambda pn: max(coef[pn[0]], -coef[pn[1]]))
            if max(coef[p], -coef[n]) <= top:
                elems = [0] * self.t
                elems[p], elems[n] = -coef[n], coef[p]
                wins.append(self.window(elems))
        return wins

    def image(self, rng, extremes=True, mode="lines"):
        """An image of W x H random windows; with extremes, the special windows of the generic at random places."""
        c = self.c
        n = c["w"] * c["h"]
        wins = [self.rand_window(rng) for _ in range(n)]
        if extremes:
            spec = self.special()
            for k, s in zip(rng.sample(range(n), min(n, len(spec))), spec):
                wins[k] = s
        lengths = [c["w"]] * c["h"] if mode == "lines" else [n]
        return packets(wins, lengths)

    def rand_set(self, rng):
        cb = self.c["cb"]
        return [rng.randint(-(1 << (cb - 1)), (1 << (cb - 1)) - 1) for _ in range(self.t)]

    def set_writes(self, s):
        return [write(CNV_COEF + 4 * k, v & 0xFFFFFFFF) for k, v in enumerate(s)]

    def reads(self):
        return [check(CNV_COEF + 4 * k) for k in range(self.t)]


def build_static(rng, x):
    # Window streams as isp_window delivers them (one packet per line); other packet shapes in test_packets
    items = []
    for _ in range(4):
        items += x.image(rng)
    items += [("G", 20)] + x.image(rng)
    return items + status()


def build_runtime(rng, x):
    cb = x.c["cb"]
    lo, hi = -(1 << (cb - 1)), (1 << (cb - 1)) - 1
    sets = [x.rand_set(rng) for _ in range(2)] + [[lo] * x.t, [hi] * x.t]
    s = x.rand_set(rng)
    sets += [s, [-v if lo < -v <= hi else v for v in s]]
    items = []
    for st in sets:
        items += x.regs.access(*x.set_writes(st), *x.reads()) + x.image(rng)
    # A set written during an image takes effect with the next image
    img = x.image(rng)
    half = len(img) // 2
    items += img[:half] + x.regs.access(*x.set_writes(x.rand_set(rng))) + img[half:] + x.image(rng)
    return items + status()


def build_hold(rng, x):
    a, b, d = x.rand_set(rng), x.rand_set(rng), x.rand_set(rng)
    wb = x.set_writes(b)
    items = x.regs.access(*x.set_writes(a)) + x.image(rng)
    items += x.regs.access(write(CNV_CTRL, 1), *wb[:len(wb) // 2]) + x.image(rng)
    items += x.regs.access(*wb[len(wb) // 2:], check(CNV_CTRL)) + x.image(rng)
    items += x.regs.access(write(CNV_CTRL, 0)) + x.image(rng)
    # HOLD 1 with a coefficient of bad parity: no set taken, no report
    items += x.regs.access(write(CNV_CTRL, 1), write(CNV_INJECT, 1)) + x.image(rng) + x.regs.access(check(CNV_STATUS))
    items += x.regs.access(write(CNV_CTRL, 0)) + x.image(rng)
    items += x.regs.access(*x.set_writes(d)) + x.image(rng)
    return items + status()


def build_parity(rng, x):
    t = x.t
    s = x.rand_set(rng)
    writes = x.set_writes(s)
    items = x.regs.access(*writes) + x.image(rng)
    # Every coefficient for T up to 16; above, the first, the last and eight more (one generate loop of the RTL)
    ks = list(range(t)) if t <= 16 else sorted({0, t - 1} | set(rng.sample(range(1, t - 1), 8)))
    for k in ks:
        items += x.regs.access(write(CNV_INJECT, (k << 8) | 1)) + x.image(rng) + x.image(rng)
        items += x.regs.access(writes[k]) + x.image(rng)
    if t >= 2:
        # Two injections in one set, then a second injection of each that restores the parity
        a, b = (0, t - 1)
        items += x.regs.access(write(CNV_INJECT, (a << 8) | 1), write(CNV_INJECT, (b << 8) | 1)) + x.image(rng)
        items += x.regs.access(write(CNV_INJECT, (a << 8) | 1), write(CNV_INJECT, (b << 8) | 1)) + x.image(rng)
    items += build_partial_writes(rng, x, writes)
    # An index of T or above has no effect; without the strobe of byte 0 no injection
    items += x.regs.access(write(CNV_INJECT, (min(t, 255) << 8) | 1)) + x.image(rng)
    items += x.regs.access(write(CNV_INJECT, 3, 0xE)) + x.image(rng)
    # CTRL (CNV-ER-02): with HOLD 1, the held set is taken at every image start until CTRL is written
    held, later = x.rand_set(rng), x.rand_set(rng)
    items += x.regs.access(write(CNV_CTRL, 1), *x.set_writes(held)) + x.image(rng)
    items += x.regs.access(write(CNV_INJECT, 2)) + x.image(rng) + x.image(rng)
    items += x.regs.access(write(CNV_CTRL, 1), *x.set_writes(later)) + x.image(rng)
    items += x.regs.access(write(CNV_CTRL, 0), check(CNV_INJECT), check(CNV_STATUS)) + x.image(rng)
    return items + status()


def build_partial_writes(rng, x, writes):
    """CNV-RG-03, PKG-08: a mismatch (the injection gives the syndrome of an upset) survives a write that keeps a byte
    with bits of the register and a write of only bytes without bits; a write of every byte with bits clears it; a
    partial write of a register without a mismatch sets the parity for the resulting value. The model decides the
    expected images and pulses."""
    cb = x.c["cb"]
    with_bits = (1 << ((cb + 7) // 8)) - 1           # the strobes of the bytes with bits of a coefficient
    k = rng.randrange(x.t)
    addr = CNV_COEF + 4 * k
    items = []
    keeps = []
    if with_bits != 0x1:
        keeps.append(with_bits & ~0x1)               # a write that keeps byte 0
    if with_bits != 0xF:
        keeps.append(0xF & ~with_bits)               # a write of only bytes without bits
    for strobes in keeps:
        items += x.regs.access(write(CNV_INJECT, (k << 8) | 1),
                               write(addr, rng.getrandbits(32), strobes)) + x.image(rng) + x.image(rng)
        items += x.regs.access(write(addr, rng.getrandbits(32), 0xF)) + x.image(rng)
    # No mismatch: a partial write of byte 0 alone, then the set is used without an error
    items += x.regs.access(write(addr, rng.getrandbits(32), 0x1)) + x.image(rng)
    items += x.regs.access(writes[k]) + x.image(rng)
    return items


def build_registers(rng, x):
    t = x.t
    items = x.regs.access(*[check(a) for a in (CNV_ID, CNV_PARAM, CNV_CTRL, CNV_STATUS, CNV_INJECT)], *x.reads())
    items += x.regs.access(write(CNV_ID, 0xFFFFFFFF), write(CNV_PARAM, 0xFFFFFFFF), check(CNV_ID), check(CNV_PARAM))
    # Every single byte strobe on a few coefficients (read only with RuntimeCoef_g false)
    for k in sorted({0, t - 1, t // 2}):
        for b in range(4):
            items += x.regs.access(write(CNV_COEF + 4 * k, rng.getrandbits(32), 1 << b), check(CNV_COEF + 4 * k))
    items += x.image(rng)
    items += x.regs.access(write(CNV_CTRL, 1), check(CNV_CTRL), write(CNV_CTRL, 0), check(CNV_CTRL))
    # Unused addresses read 0: the gaps, above the last coefficient, the end of the address space
    unused = [0x014, 0x0FC, CNV_COEF + 4 * t, 0xFFC]
    items += x.regs.access(*[check(a) for a in unused if a < 0x1000], write(0x014, 0xFFFFFFFF), check(0x014))
    if x.c["runtime"]:
        # STATUS.ERR_CONFIG: set, kept by a write of 0 and without the strobe of byte 1, cleared by a write of 1
        items += x.regs.access(write(CNV_INJECT, 1)) + x.image(rng)
        items += x.regs.access(check(CNV_STATUS), write(CNV_STATUS, 0), check(CNV_STATUS),
                               write(CNV_STATUS, 0x200, 0xD), check(CNV_STATUS), write(CNV_STATUS, 0x200),
                               check(CNV_STATUS), write(CNV_INJECT, 1))
        items += x.image(rng)
    return items + status()


def build_exhaustive(rng, x):
    # Every coefficient pair of the 3-bit coefficients over an image of every pair of 3-bit elements
    vals = range(-4, 4)
    wins = [x.window([e0, e1]) for e1 in range(8) for e0 in range(8)]
    items = []
    for c0 in vals:
        for c1 in vals:
            items += x.regs.access(write(CNV_COEF, c0 & 0xFFFFFFFF), write(CNV_COEF + 4, c1 & 0xFFFFFFFF))
            order = list(wins)
            rng.shuffle(order)
            items += packets(order, [8] * 8)
    return items + status()


def build_packets(rng, x):
    # Streams that define the image start by their packets only (contract checker off)
    items = x.regs.access(*x.set_writes(x.rand_set(rng))) if x.c["runtime"] else []
    items += raw_packet([x.rand_window(rng) for _ in range(3)], SEQ_CONT)      # no image start
    items += raw_packet([x.rand_window(rng) for _ in range(2)], SEQ_FIRST)     # an image start
    items += x.regs.access(*x.set_writes(x.rand_set(rng))) if x.c["runtime"] else []
    items += raw_packet([x.rand_window(rng) for _ in range(4)], SEQ_CONT)      # the set stays
    # Last on every beat, other flags on the later beats of a packet
    items += [("B", x.rand_window(rng), 1, rng.randint(0, 3)) for _ in range(8)]
    items += [("B", x.rand_window(rng), 0, 1), ("B", x.rand_window(rng), 0, 0), ("B", x.rand_window(rng), 1, 2)]
    for _ in range(20):
        length = rng.randint(1, 6)
        items += raw_packet([x.rand_window(rng) for _ in range(length)], rng.randint(0, 3))
        if x.c["runtime"] and rng.random() < 0.3:
            items += x.regs.access(*x.set_writes(x.rand_set(rng)))
    items += x.image(rng) + x.image(rng)
    return items + status()


def build_reset(rng, x):
    other = x.rand_set(rng)
    items = []
    if x.c["runtime"]:
        items += x.regs.access(*x.set_writes(other))
    items += x.image(rng)
    items += [("W",), ("T", 4), ("R", 0, 0, 2)]
    items += x.regs.access(*x.reads(), check(CNV_CTRL), check(CNV_STATUS)) + x.image(rng)
    n = x.c["w"] * x.c["h"]
    # Held and running resets during an image, of one and two cycles; the last two between the image start and the
    # first output pixel (the first window in the pipeline)
    for drop, mode, cycles, k in ((2, 0, 1, None), (3, 1, 2, None), (0, 0, 1, None), (1, 0, 1, 1), (1, 1, 2, 1)):
        if x.c["runtime"]:
            items += x.regs.access(*x.set_writes(other))
        # The window stream stops at the reset, as isp_window does when it is reset with the module, and the next
        # image follows
        img = x.image(rng)
        k = rng.randint(max(drop, 1) + 1, n - 1) if k is None else k
        items += img[:k] + [("R", drop, mode, cycles)]
        items += x.image(rng)
    return items + status()


def build_rate(rng, x):
    items = [("M", 1)]
    for _ in range(3):
        items += x.image(rng)
    items += [("W",), ("M", 2)]
    return items + status()


def build_flag_coincidence(rng, x):
    # A parity error of COEF[0]: every image start pulses Err_Config (ispRegsRun ends before the sweep)
    items = [("A", 100, [write(CNV_INJECT, 1)])]
    for d in range(SWEEP_STEPS):
        items += [("W",), ("T", 4), ("M", 400 + d), ("K", 400 + d), ("T", 4)] + x.image(rng) + [("T", 40)]
    return items + status()


BUILDERS = {
    "test_static": build_static,
    "test_runtime": build_runtime,
    "test_hold": build_hold,
    "test_parity": build_parity,
    "test_registers": build_registers,
    "test_exhaustive": build_exhaustive,
    "test_packets": build_packets,
    "test_reset": build_reset,
    "test_rate": build_rate,
    "test_flag_coincidence": build_flag_coincidence,
}


def configure(lib, out_dir):
    tb = lib.test_bench("isp_conv_tb")
    for c in CONFIGS:
        for test in c["tests"]:
            rng = rng_for(MODULE, c["name"], test)
            x = Ctx(c)
            items = BUILDERS[test](rng, x)
            folder = Path(out_dir) / MODULE / c["name"]
            files = {ext: folder / (test + "." + ext) for ext in ("stim", "exp", "regs", "tim")}
            res = write_test(files["stim"], files["exp"], items,
                             lambda it: conv(it, c["pb"], c["wx"], c["wy"], c["cb"], c["coef"], c["runtime"], c["ob"]),
                             c["pb"], regs_path=files["regs"], tim_path=files["tim"])
            tb.test(test).add_config(name=c["name"], generics={
                "PixelBits_g": c["pb"], "WinX_g": c["wx"], "WinY_g": c["wy"], "CoefBits_g": c["cb"],
                "CoefStr_g": ",".join(str(v) for v in c["coef"]), "RuntimeCoef_g": c["runtime"],
                "OutBits_g": c["ob"], "ImageWidth_g": c["w"], "ImageHeight_g": c["h"],
                "Contract_g": test != "test_packets",
                "StimFile_g": files["stim"].as_posix(), "ExpFile_g": files["exp"].as_posix(),
                "RegsFile_g": files["regs"].as_posix(), "TimFile_g": files["tim"].as_posix(),
                "GapPct_g": c["gap"], "StallPct_g": c["stall"], "Seed_g": seed_for(MODULE, c["name"], test),
                "ExpConfig_g": res["config"], "SweepSteps_g": SWEEP_STEPS,
                "WatchdogUs_g": watchdog_us(files["stim"], files["exp"])})
