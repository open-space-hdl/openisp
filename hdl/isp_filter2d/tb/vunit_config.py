# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of isp_filter2d_tb (verification plan, sections 2 and 3).

For every configuration and test, the pixel stream, the register script and the injection script are built here,
the reference model (tools/isp_model.py, model filter2d: the windows of the model window into the kernel of the model
conv) computes the expected output pixels, the pulse counts, the expected register reads and the input beat that
completes the window of every output pixel, and the files are written to the vector directory. The configuration
`separable` runs two filters in series; its model is the composition of two models filter2d.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "tools"))

from isp_model import (CNV_COEF, CNV_CTRL, CNV_INJECT, CNV_STATUS, SEQ_LAST, Window, conv_full_bits,  # noqa: E402
                       ecc_codeword_width, ecc_data_positions, filter2d)
from isp_tbgen import (RegScript, check, image_beats, malformed_streams, packets, random_image, raw_packet,  # noqa
                       rng_for, seed_for, status, watchdog_us, write, write_test)

MODULE = "isp_filter2d"
SEP2 = [-2, 5, 7, 1, -1]       # second kernel of the configuration separable (asymmetric)


def mtf3():
    return [-1, -2, -1, -2, 28, -2, -1, -2, -1]


def mtf5():
    k = [[0, -1, -1, -1, 0], [-1, -2, -4, -2, -1], [-1, -4, 44, -4, -1], [-1, -2, -4, -2, -1], [0, -1, -1, -1, 0]]
    return [v for row in k for v in row]


def rand_coef(seed, n, cb):
    rng = rng_for(MODULE, "coef", seed)
    return [rng.randint(-(1 << (cb - 1)), (1 << (cb - 1)) - 1) for _ in range(n)]


def cfg(name, w, h, pb, cb, ob, wx, wy, coef, runtime, ax=None, ay=None, sx=1, sy=1, border="replicate", gap=20,
        stall=20, tests=None, separable=False):
    ax = (wx - 1) // 2 if ax is None else ax
    ay = (wy - 1) // 2 if ay is None else ay
    return dict(name=name, w=w, h=h, pb=pb, cb=cb, ob=ob, wx=wx, wy=wy, ax=ax, ay=ay, sx=sx, sy=sy, border=border,
                coef=coef, runtime=runtime, gap=gap, stall=stall, tests=tests or ["test_static"],
                separable=separable)


CONFIGS = [
    cfg("mtf3", 12, 8, 12, 16, 0, 3, 3, mtf3(), True,
        tests=["test_static", "test_input_stream", "test_runtime", "test_errors", "test_reset"]),
    cfg("mtf5_mirror", 14, 10, 12, 16, 0, 5, 5, mtf5(), True, border="mirror", gap=30, stall=40,
        tests=["test_static", "test_runtime", "test_reset"]),
    cfg("mtf5_const", 14, 10, 16, 12, 16, 5, 5, mtf5(), False, border="zero",
        tests=["test_static", "test_input_stream"]),
    cfg("valid", 12, 8, 12, 16, 0, 3, 3, rand_coef("valid", 9, 16), False, border="valid",
        tests=["test_static", "test_input_stream", "test_reset"]),
    cfg("strided", 13, 9, 12, 16, 0, 4, 2, rand_coef("strided", 8, 16), True, ax=1, ay=0, sx=3, sy=2,
        tests=["test_static", "test_runtime", "test_reset"]),
    cfg("bin_h", 13, 9, 12, 2, 14, 4, 1, [1] * 4, False, ax=0, ay=0, sx=4, border="zero"),
    cfg("bin_v", 13, 9, 12, 2, 14, 1, 4, [1] * 4, False, ax=0, ay=0, sy=4, border="zero"),
    cfg("separable", 12, 8, 12, 16, 0, 1, 5, [1, -3, 9, 4, -2], False, separable=True),
    cfg("max", 18, 17, 32, 18, 0, 16, 16, rand_coef("max", 256, 18), True, border="zero", gap=10, stall=10,
        tests=["test_static", "test_runtime"]),
    cfg("ecc", 10, 7, 12, 16, 0, 3, 3, mtf3(), True, gap=0, stall=0, tests=["test_static", "test_errors"]),
    cfg("rate_3", 16, 6, 12, 16, 0, 3, 3, mtf3(), True, gap=0, stall=0, tests=["test_static", "test_rate"]),
    cfg("rate_5", 16, 6, 12, 16, 0, 5, 5, mtf5(), True, gap=0, stall=0, tests=["test_static", "test_rate"]),
]


def geometry(c):
    return Window(c["w"], c["h"], c["pb"], c["wx"], c["wy"], c["ax"], c["ay"], c["sx"], c["sy"], c["border"])


def model_of(c):
    def single(items, out_bits=None):
        return filter2d(items, c["w"], c["h"], c["pb"], c["wx"], c["wy"], c["ax"], c["ay"], c["sx"], c["sy"],
                        c["border"], c["cb"], c["coef"], c["runtime"], c["ob"] if out_bits is None else out_bits)

    if not c["separable"]:
        return single

    def composed(items):
        # The first filter at full precision; its output stream is the input of the second (Win2 = 5 x 1)
        out1, err1, annot1, ex1 = single(items, 0)
        assert all(o[0] == "B" for o in out1), "the composition of separable has no resets"
        geo = geometry(c)
        mid_bits = conv_full_bits(c["pb"], c["cb"], c["wx"] * c["wy"])
        mid = [("B", o[1], o[2], o[3]) for o in out1]
        out2, err2, annot2, ex2 = filter2d(mid, geo.wo, geo.ho, mid_bits, len(SEP2), 1, None, None, 1, 1,
                                           c["border"], c["cb"], SEP2, False, c["ob"])
        # Outputs of the second filter after every item of the test: from the outputs of the first so far
        mids, annot = 0, []
        for count1, opened in annot1:
            mids = count1
            annot.append((annot2[mids - 1][0] if mids else 0, opened))
        extra = {k: ex1[k] + ex2[k] for k in ("sec", "ded", "config")}
        extra.update({"regs": ex1["regs"], "timing": ex2["timing"]})
        return out2, err1 + err2, annot, extra

    return composed


class Ctx:
    def __init__(self, c):
        self.c = c
        self.t = c["wx"] * c["wy"]
        self.regs = RegScript()
        self.heavy = self.t > 64

    def image(self, rng, mode="lines"):
        return image_beats(rng, self.c["w"], self.c["h"], self.c["pb"], mode)

    def const_image(self, value):
        c = self.c
        return packets([value] * (c["w"] * c["h"]), [c["w"]] * c["h"])

    def marker(self, kind, value):
        return [("W",), ("T", 8), (kind, next(self.regs.markers), value)]

    def rand_set(self, rng):
        cb = self.c["cb"]
        return [rng.randint(-(1 << (cb - 1)), (1 << (cb - 1)) - 1) for _ in range(self.t)]

    def set_writes(self, s):
        return [write(CNV_COEF + 4 * k, v & 0xFFFFFFFF) for k, v in enumerate(s)]

    def reads(self, rng):
        ks = range(self.t) if not self.heavy else sorted({0, self.t - 1} | set(rng.sample(range(1, self.t - 1), 6)))
        return [check(CNV_COEF + 4 * k) for k in ks]

    def drain(self):
        """Cycles until the window has made every window of the pixels sent, also those of the virtual lines."""
        c = self.c
        rr, rb = c["wx"] - 1 - c["ax"], c["wy"] - 1 - c["ay"]
        return rb * (c["w"] + rr) + rr + 20


def build_static(rng, x):
    modes = ["lines", "random"] if x.heavy else ["lines", "one", "random", "wplus1", "line_end"]
    items = []
    for k, mode in enumerate(modes):
        items += x.image(rng, mode)
        if k == 1:
            items += [("G", 25)]
    # The largest pixels everywhere (the largest sums, saturation where B is short) and an image of zeros
    items += x.const_image((1 << x.c["pb"]) - 1)
    if not x.heavy:
        items += x.const_image(0)
    return items + status()


def build_input_stream(rng, x):
    return malformed_streams(rng, x.c["w"], x.c["h"], x.c["pb"], packets_count=30)


def build_runtime(rng, x):
    cb = x.c["cb"]
    lo, hi = -(1 << (cb - 1)), (1 << (cb - 1)) - 1
    items = []
    sets = [x.rand_set(rng)] if x.heavy else [x.rand_set(rng), x.rand_set(rng), [lo] * x.t, [hi] * x.t]
    for st in sets:
        items += x.regs.access(*x.set_writes(st), *x.reads(rng)) + x.image(rng)
    # CTRL.HOLD 1: the set written meanwhile waits; HOLD 0: the next image start takes it
    a, b = x.rand_set(rng), x.rand_set(rng)
    items += x.regs.access(*x.set_writes(a)) + x.image(rng)
    items += x.regs.access(write(CNV_CTRL, 1), *x.set_writes(b), check(CNV_CTRL)) + x.image(rng, "random")
    items += x.regs.access(write(CNV_CTRL, 0)) + x.image(rng)
    # A set written during an image takes effect with the next image start of the window stream
    img = x.image(rng)
    half = len(img) // 2
    items += img[:half] + x.regs.access(*x.set_writes(x.rand_set(rng))) + img[half:] + x.image(rng)
    return items + status()


def build_errors(rng, x):
    """Single and double errors in the line buffers of the window, a parity error of a coefficient, all pulses at
    the ports of the filter (TC-FLT-04)."""
    c = x.c
    w, h, wy, pb = c["w"], c["h"], c["wy"], c["pb"]
    cw = ecc_codeword_width(pb)
    pos = ecc_data_positions(pb)
    items = []

    def inject(pattern, line, col):
        """An image whose pixel (col, line) is preceded by the injection (the pattern applies to its event)."""
        nonlocal items
        pix = random_image(rng, w, h, pb)
        k = line * w + col
        items += packets(pix[:k], [k], last=False) if k else []
        items += [("T", x.drain())] + x.marker("J", pattern)
        items += packets(pix[k:], [w * h - k], first=k == 0)

    for t in range(1, wy):
        shift = (t - 1) * cw
        d1, d2 = rng.sample(pos, 2)
        line = min(t, h - 1)
        # A single error in a data bit (corrected: the output unchanged), a double error (the windows that contain
        # the pixel and their output pixels change)
        inject((1 << d1) << shift, line, rng.randrange(w))
        inject(((1 << d1) | (1 << d2)) << shift, line, rng.randrange(1, w - 1))
    # A parity error of a coefficient: the next image uses the coefficients of the generic and pulses Err_Config;
    # the write of the coefficient restores the parity
    s = x.rand_set(rng)
    writes = x.set_writes(s)
    k = rng.randrange(x.t)
    items += x.regs.access(*writes) + x.image(rng)
    items += x.regs.access(write(CNV_INJECT, (k << 8) | 1)) + x.image(rng) + x.image(rng, "random")
    items += x.regs.access(writes[k], check(CNV_STATUS), write(CNV_STATUS, 0x200), check(CNV_STATUS))
    items += x.image(rng)
    return items + status()


def build_reset(rng, x):
    c = x.c
    w, h, pb = c["w"], c["h"], c["pb"]
    n = w * h
    geo = geometry(c)
    other = x.rand_set(rng)
    items = x.regs.access(*x.set_writes(other)) if c["runtime"] else []
    items += x.image(rng)
    # Reset with the module idle (two cycles); the registers return to their reset values
    items += [("W",), ("T", x.drain()), ("R", 0, 0, 2)]
    if c["runtime"]:
        items += x.regs.access(*x.reads(rng), check(CNV_CTRL), check(CNV_STATUS))
    items += x.image(rng, "random")
    # Held resets of one cycle during the pixels of a line and during the windows of the lower border
    for k in sorted({n // 2, n} - {0}):
        pix = random_image(rng, w, h, pb)
        items += packets(pix[:k], [k], last=k == n) + [("T", 3), ("R", 0, 0, 1)]
        if k < n:
            items += raw_packet(pix[k:], SEQ_LAST)
        items += x.image(rng)
    # A held reset while the kernel holds windows: the sink stops, four more pixels enter, the reset drops the
    # windows that were not delivered
    pix = random_image(rng, w, h, pb)
    k = n // 2
    items += packets(pix[:k], [k], last=False) + [("W",), ("H", 1)] + packets(pix[k:k + 4], [4], first=False,
                                                                               last=False)
    items += [("T", 30), ("RD",)]
    items += [("H", 0)] + raw_packet(pix[k + 4:], SEQ_LAST) + x.image(rng)
    # Running resets of two cycles: during a line and during the windows of the borders
    for k, drop in ((max(n // 2, 1), min(2, geo.wo * geo.ho)), (n, min(3, geo.wo * geo.ho))):
        pix = random_image(rng, w, h, pb)
        items += packets(pix[:k], [k], last=k == n) + [("R", drop, 1, 2)]
        if k < n:
            items += raw_packet(pix[k:], SEQ_LAST)
        items += x.image(rng)
    return items + status()


def build_rate(rng, x):
    items = [("M", 1)]
    for mode in ("lines", "random", "one", "lines"):
        items += x.image(rng, mode)
    items += [("W",), ("M", 2)]
    return items + status()


BUILDERS = {
    "test_static": build_static,
    "test_input_stream": build_input_stream,
    "test_runtime": build_runtime,
    "test_errors": build_errors,
    "test_reset": build_reset,
    "test_rate": build_rate,
}


def resolve_held_drop(items, model):
    """("RD",) is a held reset that drops every output the model made after the last ("W",): the sink holds them."""
    out = []
    for it in items:
        if it[0] != "RD":
            out.append(it)
            continue
        annot = model(out)[2]
        last_w = max(j for j, e in enumerate(out) if e[0] == "W")
        # The outputs the sink had at the ("W",) and those the model made up to the reset
        before_w, before_r = annot[last_w][0], annot[-1][0]
        out.append(("R", before_r - before_w, 0, 1))
    return out


def configure(lib, out_dir):
    tb = lib.test_bench("isp_filter2d_tb")
    for c in CONFIGS:
        model = model_of(c)
        geo = geometry(c)
        if c["separable"]:
            g2 = Window(geo.wo, geo.ho, 1, len(SEP2), 1, (len(SEP2) - 1) // 2, 0, 1, 1, c["border"])
            out_w, out_h = g2.wo, g2.ho
        else:
            out_w, out_h = geo.wo, geo.ho
        for test in c["tests"]:
            rng = rng_for(MODULE, c["name"], test)
            x = Ctx(c)
            items = resolve_held_drop(BUILDERS[test](rng, x), model)
            folder = Path(out_dir) / MODULE / c["name"]
            files = {ext: folder / (test + "." + ext) for ext in ("stim", "exp", "regs", "inj", "tim")}
            res = write_test(files["stim"], files["exp"], items, model, c["pb"], regs_path=files["regs"],
                             inj_path=files["inj"], tim_path=files["tim"])
            generics = {
                "ImageWidth_g": c["w"], "ImageHeight_g": c["h"], "PixelBits_g": c["pb"], "WinX_g": c["wx"],
                "WinY_g": c["wy"], "AnchorX_g": c["ax"], "AnchorY_g": c["ay"], "StrideX_g": c["sx"],
                "StrideY_g": c["sy"], "BorderMode_g": c["border"], "CoefBits_g": c["cb"],
                "CoefStr_g": ",".join(str(v) for v in c["coef"]), "RuntimeCoef_g": c["runtime"], "OutBits_g": c["ob"],
                "Separable_g": c["separable"], "OutWidth_g": out_w, "OutHeight_g": out_h,
                "StimFile_g": files["stim"].as_posix(), "ExpFile_g": files["exp"].as_posix(),
                "RegsFile_g": files["regs"].as_posix(), "InjFile_g": files["inj"].as_posix(),
                "TimFile_g": files["tim"].as_posix(), "GapPct_g": c["gap"], "StallPct_g": c["stall"],
                "Seed_g": seed_for(MODULE, c["name"], test), "ExpFraming_g": res["errors"], "ExpSec_g": res["sec"],
                "ExpDed_g": res["ded"], "ExpConfig_g": res["config"],
                "WatchdogUs_g": watchdog_us(files["stim"], files["exp"])}
            if c["separable"]:
                generics.update({"Win2X_g": len(SEP2), "Win2Y_g": 1, "Coef2Str_g": ",".join(str(v) for v in SEP2)})
            tb.test(test).add_config(name=c["name"], generics=generics)
