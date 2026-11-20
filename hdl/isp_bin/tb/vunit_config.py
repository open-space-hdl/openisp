# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of isp_bin_tb (verification plan, sections 2 and 3).

For every configuration and test, the pixel stream and the injection script are built here, the reference model
(tools/isp_model.py, model bin_model: the output pixels from the definition of a bin, the pulse counts, the open flag
and the timing from the two filters in series) computes the expected output pixels, the pulse counts and the input
beat that completes the bin of every output pixel, and the files are written to the vector directory.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "tools"))

from isp_model import SEQ_LAST, bin_model, ecc_codeword_width, ecc_data_positions, log2ceil  # noqa: E402
from isp_tbgen import (RegScript, image_beats, malformed_streams, packets, random_image, raw_packet,  # noqa: E402
                       rng_for, seed_for, status, watchdog_us, write_test)

MODULE = "isp_bin"
MAIN = ["test_static", "test_input_stream", "test_reset"]


def cfg(name, w, h, pb, bx, by, border, ecc=1, resource="AUTO", gap=20, stall=20, tests=None):
    return dict(name=name, w=w, h=h, pb=pb, bx=bx, by=by, border=border, ecc=ecc, resource=resource, gap=gap,
                stall=stall, tests=tests or ["test_static"])


CONFIGS = [
    cfg("bin2_valid", 13, 9, 12, 2, 2, "valid", tests=MAIN),
    cfg("bin2_zero", 13, 9, 12, 2, 2, "zero", gap=30, stall=40, tests=MAIN),
    cfg("bin3x5_rep", 14, 12, 12, 3, 5, "replicate", tests=MAIN),
    cfg("bin4", 16, 16, 16, 4, 4, "valid", ecc=0, resource="SRL", tests=["test_static", "test_reset"]),
    cfg("bin_x_only", 12, 5, 12, 4, 1, "zero", tests=MAIN),
    cfg("bin_y_only", 5, 12, 12, 1, 4, "replicate", tests=MAIN),
    cfg("bin_none", 6, 4, 12, 1, 1, "valid", tests=MAIN),
    # Wo = 4 = 3 + EccPipeline_g, the bound of the block RAM
    cfg("max", 64, 34, 28, 16, 16, "replicate", resource="BRAM", gap=10, stall=10),
    cfg("bits1", 8, 6, 1, 2, 3, "zero", ecc=0, tests=["test_static", "test_ecc"]),
    cfg("image_equals_bin", 4, 4, 12, 4, 4, "valid", resource="SRL", tests=["test_static", "test_input_stream"]),
    # The low bounds of the image size and the pixel width: a 1 x 1 image of 1-bit pixels (the frame sync alone)
    cfg("min", 1, 1, 1, 1, 1, "valid", tests=["test_static", "test_input_stream"]),
    cfg("w65536", 65536, 2, 12, 2, 2, "valid", resource="BRAM", gap=10, stall=10),
    cfg("ecc", 12, 8, 12, 2, 3, "zero", resource="SRL", gap=0, stall=0, tests=["test_static", "test_ecc"]),
    # test_rate (verification plan, section 5): both filters in the modes valid and replicate, the vertical filter
    # waiting longer than the buffers of the horizontal one take (rate_tall), and every shape with one filter or none
    cfg("rate_valid", 16, 8, 12, 4, 2, "valid", gap=0, stall=0, tests=["test_static", "test_rate"]),
    cfg("rate_rep", 16, 8, 12, 4, 2, "replicate", gap=0, stall=0, tests=["test_static", "test_rate"]),
    cfg("rate_tall", 16, 16, 12, 2, 8, "replicate", gap=0, stall=0, tests=["test_static", "test_rate"]),
    cfg("rate_x_only", 16, 8, 12, 4, 1, "replicate", gap=0, stall=0, tests=["test_static", "test_rate"]),
    cfg("rate_y_only", 16, 8, 12, 1, 4, "replicate", gap=0, stall=0, tests=["test_static", "test_rate"]),
    cfg("rate_none", 16, 8, 12, 1, 1, "replicate", gap=0, stall=0, tests=["test_static", "test_rate"]),
]
# The sweep of the factors: bin n x (17 - n), image (n + 3) x (20 - n), the border modes in turn; with BinY_g 1 the
# injection has no effect (test_ecc)
for _n in range(1, 17):
    CONFIGS.append(cfg(f"sweep_{_n:02d}", _n + 3, 20 - _n, 8, _n, 17 - _n, ("valid", "zero", "replicate")[_n % 3],
                       tests=["test_static", "test_ecc"] if _n == 16 else None))

BIG = ("w65536",)


def narrow_width(c):
    return c["w"] // c["bx"] if c["border"] == "valid" else -(-c["w"] // c["bx"])


def out_size(c):
    if c["border"] == "valid":
        return c["w"] // c["bx"], c["h"] // c["by"]
    return -(-c["w"] // c["bx"]), -(-c["h"] // c["by"])


def model_of(c):
    def model(items):
        return bin_model(items, c["w"], c["h"], c["pb"], c["bx"], c["by"], c["border"])
    return model


class Ctx:
    def __init__(self, c):
        self.c = c
        self.markers = RegScript().markers
        self.lat = 16 + log2ceil(c["bx"]) + log2ceil(c["by"])

    def image(self, rng, mode="lines"):
        return image_beats(rng, self.c["w"], self.c["h"], self.c["pb"], mode)

    def const_image(self, value):
        c = self.c
        return packets([value] * (c["w"] * c["h"]), [c["w"]] * c["h"])

    def drain(self):
        """Cycles until both filters have made every bin of the pixels sent, also those of the virtual pixels."""
        c = self.c
        vpix = (c["by"] - 1) * narrow_width(c) if c["border"] != "valid" else 0
        return vpix + c["bx"] + 2 * self.lat + 20

    def close_wait(self):
        """The wait of a probe after complete images: the vertical filter closes an image 7 + log2ceil(BinX_g)
        cycles after the acceptance of its last pixel, the frame sync of the input 1 cycle after it (verification
        plan, section 5); plus the 8 cycles of the shared probe, so that the probe reads 7 cycles after the fall."""
        return 7 + log2ceil(self.c["bx"]) + 8

    def inject(self, pattern):
        """The injection waits until every bin of the pixels sent is in the vertical filter."""
        return [("W",), ("T", 2 * self.lat + 8), ("J", next(self.markers), pattern)]


def build_static(rng, x):
    modes = ["lines", "random"] if x.c["name"] in BIG else ["lines", "one", "random", "wplus1", "line_end"]
    items = []
    for k, mode in enumerate(modes):
        items += x.image(rng, mode)
        if k == 1:
            items += [("G", 25)]
    # The largest pixels everywhere (the largest sums, the top of the output width) and an image of zeros
    items += x.const_image((1 << x.c["pb"]) - 1)
    if x.c["name"] not in BIG:
        items += x.const_image(0)
    return items + status()


def build_input_stream(rng, x):
    c = x.c
    # An image cut after its first pixel, probed: only the frame sync of the input is open (with BinX_g > 1 the
    # horizontal filter has no bin yet); the malformed streams then begin with an image start that completes it
    items = []
    if c["w"] * c["h"] > 1:
        items += packets([rng.getrandbits(c["pb"])], [1], last=False) + [("W",), ("T", 8), ("P",)]
    return items + malformed_streams(rng, c["w"], c["h"], c["pb"], packets_count=30)


def build_ecc(rng, x):
    """Single and double errors in every line buffer of the vertical filter, read by the window of a bin; one more
    single error, so that the counts of Stat_EccSec and Stat_EccDed differ (TC-BIN-03)."""
    c = x.c
    w, h, bx, by, pb = c["w"], c["h"], c["bx"], c["by"], c["pb"]
    ph = pb + log2ceil(bx)
    cw = ecc_codeword_width(ph)
    pos = ecc_data_positions(ph)
    wo = narrow_width(c)
    items = []

    def inject(pattern, line, n):
        """An image whose bin (n, line) of the horizontal filter follows the injection: its event in the vertical
        filter writes the pattern."""
        nonlocal items
        pix = random_image(rng, w, h, pb)
        k = line * w + n * bx
        items += packets(pix[:k], [k], last=False) if k else []
        items += x.inject(pattern)
        items += packets(pix[k:], [w * h - k], first=k == 0)

    if by == 1:
        # No vertical filter: the injection ports are not connected
        inject(1 << pos[0], 0, 0)
        inject(3, 0, 0)
        return items + status()
    for t in range(1, by):
        shift = (t - 1) * cw
        # The narrowed line by - 2, written into delay t - 1 and read as row distance t by the window of line by - 1,
        # the last line of bin row 0: the double error reaches the output pixel of the bin
        line = by - 2
        d1 = rng.choice(pos)
        others = [p for p in pos if p != d1]
        inject((1 << d1) << shift, line, rng.randrange(wo))
        inject(((1 << d1) | (1 << rng.choice(others))) << shift, line, rng.randrange(wo))
    inject(1 << rng.choice(pos), by - 2, rng.randrange(wo))
    return items + status()


def build_reset(rng, x):
    c = x.c
    w, h, pb = c["w"], c["h"], c["pb"]
    n = w * h
    wo, ho = out_size(c)
    items = x.image(rng)
    # Reset with the module idle (two cycles)
    items += [("W",), ("T", x.drain()), ("R", 0, 0, 2)] + x.image(rng, "random")
    # Held resets of one cycle during the pixels of a line and during the virtual pixels after the last line
    for k in sorted({n // 2, n} - {0}):
        pix = random_image(rng, w, h, pb)
        items += packets(pix[:k], [k], last=k == n) + [("T", 3), ("R", 0, 0, 1)]
        if k < n:
            items += raw_packet(pix[k:], SEQ_LAST)
        items += x.image(rng)
    # A held reset while the filters hold bins: the sink stops, more pixels enter, the reset drops the bins that
    # were not delivered. With the sink stopped the module takes at least BinX_g + 3 pixels (the rest of the bin in
    # progress, which goes to the output register, the next bin, which waits in the window register, and the two
    # registers of the frame sync); the frame sync alone takes 2
    pix = random_image(rng, w, h, pb)
    k = n // 2
    more = min(2 if c["bx"] == 1 and c["by"] == 1 else c["bx"] + 3, n - k - 1)
    if more > 0:
        items += packets(pix[:k], [k], last=False) + [("W",), ("H", 1)]
        items += packets(pix[k:k + more], [more], first=False, last=False)
        items += [("T", 30), ("RD",)] + [("H", 0)] + raw_packet(pix[k + more:], SEQ_LAST) + x.image(rng)
    # Running resets of two cycles: during a line and after the last pixel
    for k, drop in ((max(n // 2, 1), min(2, wo * ho)), (n, min(3, wo * ho))):
        pix = random_image(rng, w, h, pb)
        items += packets(pix[:k], [k], last=k == n) + [("R", drop, 1, 2)]
        if k < n:
            items += raw_packet(pix[k:], SEQ_LAST)
        items += x.image(rng)
    return items + status()


def build_rate(rng, x):
    c = x.c
    items = [("M", 1)]
    for mode in ("lines", "random", "one", "lines"):
        items += x.image(rng, mode)
    if c["bx"] > 1 and c["by"] > 1:
        # Read 4 cycles after the acceptance of the last pixel (after edge e0 + 3): the frame sync of the horizontal
        # filter closed the image at e0 + 1, the vertical filter closes it at e0 + 7 + log2ceil(BinX_g) (verification
        # plan, section 5): Stat_ImageOpen is 1 from the vertical filter alone
        items += [("T", 4), ("P", 1)]
    items += [("W",), ("M", 2)]
    return items + status()


BUILDERS = {
    "test_static": build_static,
    "test_input_stream": build_input_stream,
    "test_ecc": build_ecc,
    "test_reset": build_reset,
    "test_rate": build_rate,
}


def settle(items, wait):
    """The probes after a wait for the sink (the shared ("W",), ("T", 8), ("P",)) wait `wait` cycles (Ctx.close_wait):
    in the border mode valid no output need follow the last pixel of an image (lines and columns that no bin uses), so
    the wait for the sink can end with the last pixel, before the vertical filter closes the image."""
    out = list(items)
    for i in range(len(out) - 2):
        if out[i] == ("W",) and out[i + 1] == ("T", 8) and out[i + 2] == ("P",):
            out[i + 1] = ("T", wait)
    return out


def resolve_held_drop(items, model):
    """("RD",) is a held reset that drops every output the model made after the last ("W",): the sink holds them."""
    out = []
    for it in items:
        if it[0] != "RD":
            out.append(it)
            continue
        annot = model(out)[2]
        last_w = max(j for j, e in enumerate(out) if e[0] == "W")
        before_w, before_r = annot[last_w][0], annot[-1][0]
        out.append(("R", before_r - before_w, 0, 1))
    return out


def configure(lib, out_dir):
    tb = lib.test_bench("isp_bin_tb")
    for c in CONFIGS:
        model = model_of(c)
        out_w, out_h = out_size(c)
        for test in c["tests"]:
            rng = rng_for(MODULE, c["name"], test)
            x = Ctx(c)
            items = resolve_held_drop(settle(BUILDERS[test](rng, x), x.close_wait()), model)
            folder = Path(out_dir) / MODULE / c["name"]
            files = {ext: folder / (test + "." + ext) for ext in ("stim", "exp", "inj", "tim")}
            res = write_test(files["stim"], files["exp"], items, model, c["pb"], inj_path=files["inj"],
                             tim_path=files["tim"])
            generics = {
                "ImageWidth_g": c["w"], "ImageHeight_g": c["h"], "PixelBits_g": c["pb"], "BinX_g": c["bx"],
                "BinY_g": c["by"], "BorderMode_g": c["border"], "EccPipeline_g": c["ecc"],
                "Resource_g": c["resource"], "OutWidth_g": out_w, "OutHeight_g": out_h,
                "StimFile_g": files["stim"].as_posix(), "ExpFile_g": files["exp"].as_posix(),
                "InjFile_g": files["inj"].as_posix(), "TimFile_g": files["tim"].as_posix(), "GapPct_g": c["gap"],
                "StallPct_g": c["stall"], "Seed_g": seed_for(MODULE, c["name"], test), "ExpFraming_g": res["errors"],
                "ExpSec_g": res["sec"], "ExpDed_g": res["ded"],
                "WatchdogUs_g": watchdog_us(files["stim"], files["exp"])}
            tb.test(test).add_config(name=c["name"], generics=generics)
