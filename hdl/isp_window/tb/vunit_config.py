# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of isp_window_tb (verification plan, sections 2 and 3).

For every configuration and test, the stimulus and the injection script are built here, the reference model
(tools/isp_model.py) computes the expected windows, the pulse counts and the input beat that completes every window,
and the files are written to the vector directory.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "tools"))

from isp_model import SEQ_LAST, Window, ecc_codeword_width, ecc_data_positions, window  # noqa: E402
from isp_tbgen import (image_beats, malformed_streams, packets, random_image, raw_packet, rng_for,  # noqa: E402
                       seed_for, status, watchdog_us, write_test)

MODULE = "isp_window"
MAIN = ["test_static", "test_input_stream", "test_handshake", "test_reset"]


def cfg(name, w, h, bits, wx, wy, ax=None, ay=None, sx=1, sy=1, border="replicate", resource="AUTO", ecc=1,
        gap=20, stall=20, tests=None):
    ax = (wx - 1) // 2 if ax is None else ax
    ay = (wy - 1) // 2 if ay is None else ay
    return dict(name=name, w=w, h=h, bits=bits, wx=wx, wy=wy, ax=ax, ay=ay, sx=sx, sy=sy, border=border,
                resource=resource, ecc=ecc, gap=gap, stall=stall, tests=tests or ["test_static"])


CONFIGS = [
    cfg("rep3", 10, 7, 12, 3, 3, tests=MAIN),
    cfg("zero3", 10, 7, 12, 3, 3, border="zero", gap=30, stall=40, tests=MAIN),
    cfg("mirror5", 12, 9, 16, 5, 5, border="mirror", tests=MAIN),
    cfg("valid3", 10, 7, 12, 3, 3, border="valid", tests=MAIN),
    cfg("bin2_valid", 11, 7, 12, 2, 2, 0, 0, 2, 2, "valid", tests=MAIN),
    cfg("bin2_zero", 11, 7, 12, 2, 2, 0, 0, 2, 2, "zero", tests=MAIN),
    cfg("bin4_rep", 10, 9, 14, 4, 4, 0, 0, 4, 4, "replicate", ecc=0, tests=MAIN),
    cfg("row9", 20, 4, 12, 9, 1, 4, 0, border="mirror", tests=MAIN),
    cfg("col5", 4, 12, 12, 1, 5, 0, 4, border="zero", resource="SRL", ecc=0, tests=MAIN),
    cfg("max", 18, 17, 32, 16, 16, 7, 7, border="zero", resource="BRAM", gap=10, stall=10,
        tests=["test_static", "test_ecc"]),
    cfg("image_equals_window", 3, 3, 8, 3, 3, resource="SRL", tests=MAIN),
    cfg("image_equals_window_valid", 3, 3, 8, 3, 3, border="valid", resource="SRL", ecc=0, tests=MAIN),
    cfg("ecc_srl_0", 8, 6, 12, 3, 3, resource="SRL", ecc=0, gap=0, stall=0, tests=["test_ecc"]),
    cfg("ecc_srl_1", 8, 6, 12, 3, 3, resource="SRL", ecc=1, gap=0, stall=0, tests=["test_ecc"]),
    cfg("ecc_bram_0", 8, 6, 12, 3, 3, resource="BRAM", ecc=0, gap=0, stall=0, tests=["test_ecc"]),
    cfg("ecc_bram_1", 8, 6, 12, 3, 3, resource="BRAM", ecc=1, gap=0, stall=0, tests=["test_ecc"]),
    cfg("ecc_bram_min", 4, 6, 12, 3, 3, border="mirror", resource="BRAM", ecc=1, gap=0, stall=0,
        tests=["test_ecc"]),
    cfg("w65536", 65536, 3, 12, 3, 3, gap=10, stall=10),
    cfg("h65536", 3, 65536, 12, 3, 3, border="mirror", resource="SRL", gap=10, stall=10),
    cfg("bits1", 7, 5, 1, 3, 3),
    cfg("rate_rep", 16, 6, 12, 3, 3, gap=0, stall=0, tests=["test_rate"]),
    cfg("rate_valid", 16, 6, 12, 3, 3, border="valid", gap=0, stall=0, tests=["test_rate"]),
    cfg("rate_bin", 16, 6, 12, 2, 2, 0, 0, 2, 2, "valid", gap=0, stall=0, tests=["test_rate"]),
    cfg("rate_right", 16, 6, 12, 16, 2, 0, 0, border="zero", gap=0, stall=0, tests=["test_rate"]),
]
# Sweeps (test_static): every window size, every odd mirror size, every anchor of 4 x 3, every stride, pixel widths
CONFIGS += [cfg("size_{}x{}".format(n, 17 - n), n + 3, 20 - n, 6, n, 17 - n) for n in range(1, 17)]
CONFIGS += [cfg("mirror_{}x{}".format(n, 16 - n), n + 4, 20 - n, 6, n, 16 - n, border="mirror")
            for n in range(1, 16, 2)]
CONFIGS += [cfg("anchor_{}_{}_{}".format(ax, ay, b), 10, 7, 8, 4, 3, ax, ay, border=b)
            for b in ("zero", "replicate") for ax in range(4) for ay in range(3)]
CONFIGS += [cfg("stride_{}x{}".format(n, 17 - n), 20, 20, 8, 3, 3, sx=n, sy=17 - n,
                border="valid" if n % 2 else "zero") for n in range(1, 17)]
CONFIGS += [cfg("bits_{}".format(b), 7, 5, b, 3, 3) for b in (2, 12, 31, 32)]


def model_of(c):
    return lambda it: window(it, c["w"], c["h"], c["bits"], c["wx"], c["wy"], c["ax"], c["ay"], c["sx"], c["sy"],
                             c["border"])


def big(c):
    return c["w"] * c["h"] > 4096


def drain(c):
    """Cycles until the module has processed every pixel sent, also the virtual lines of an image."""
    rr, rb = c["wx"] - 1 - c["ax"], c["wy"] - 1 - c["ay"]
    return rb * (c["w"] + rr) + rr + 20


def img(rng, c, mode="lines"):
    return image_beats(rng, c["w"], c["h"], c["bits"], mode)


def build_static(rng, c):
    modes = ["lines", "random"] if big(c) else ["lines", "one", "random", "wplus1", "line_end"]
    items = []
    for k, mode in enumerate(modes):
        items += img(rng, c, mode)
        if k == 2:
            items += [("G", 25)]
    return items + status()


def build_input_stream(rng, c):
    return malformed_streams(rng, c["w"], c["h"], c["bits"], packets_count=40)


def build_handshake(rng, c):
    w, h = c["w"], c["h"]
    n = w * h
    items = img(rng, c, "lines")
    pix = random_image(rng, w, h, c["bits"])
    # The sink held during the virtual columns of a line and during a pause of the source
    items += packets(pix[:w], [w], last=h == 1) + [("H", 1), ("T", 30), ("H", 0), ("G", 10)]
    if h > 1:
        items += packets(pix[w:], [w] * (h - 1), first=False)
    # The sink held from the last pixel of an image on, during the windows of the right and the lower border (no input
    # pending, so that the source never waits on a beat while the sink is held)
    items += img(rng, c, "lines") + [("H", 1), ("T", drain(c) + 30), ("H", 0)]
    # From an idle module, the sink held while the first two pixels of the next image arrive (they fit into the input
    # stage of the frame sync whatever the windows they complete)
    nxt = random_image(rng, w, h, c["bits"])
    items += [("W",), ("H", 1)] + packets(nxt[:2], [2], last=n == 2) + [("T", 20), ("H", 0)]
    if n > 2:
        items += packets(nxt[2:], [n - 2], first=False)
    # A cut image (two pixels), the sink held and the source pausing, then an image start that completes it (E1)
    items += img(rng, c, "lines")[:min(n - 1, 2)] + [("H", 1), ("G", 20), ("H", 0)]
    items += img(rng, c, "random")
    return items + status()


def build_ecc(rng, c):
    """Single and double errors per delay and bit class (verification plan, TC-WIN-04)."""
    w, h, wy, bits = c["w"], c["h"], c["wy"], c["bits"]
    cw = ecc_codeword_width(bits)
    pos = ecc_data_positions(bits)
    hamming = [1 << k for k in range(cw.bit_length()) if 0 < (1 << k) < cw]
    delays = list(range(1, max(wy, 2)))
    if len(delays) > 3:
        delays = [1, len(delays) // 2, len(delays)]
    marker = [100]
    items = []

    def inject(pattern, line, col):
        """An image whose pixel (col, line) is preceded by the injection (the pattern applies to its event)."""
        nonlocal items
        pix = random_image(rng, w, h, bits)
        k = line * w + col
        items += packets(pix[:k], [k], last=False) if k else []
        items += [("T", drain(c)), ("J", marker[0], pattern)]
        marker[0] += 1
        items += packets(pix[k:], [w * h - k], first=k == 0)

    for t in delays:
        shift = (t - 1) * cw
        d1, d2 = rng.sample(pos, 2)
        line = min(t, h - 1)
        for pattern in (1 << d1, hamming[rng.randrange(len(hamming))], 1, (1 << d1) | (1 << d2), (1 << d1) | 1):
            inject(pattern << shift, line, rng.randrange(w))
    if wy >= 3:
        # Errors in two delays in one event; a single and a double error in one event
        d1, d2 = rng.sample(pos, 2)
        inject((1 << d1) | (1 << (cw + d2)), h - 1, rng.randrange(w))
        inject((1 << d1) | (((1 << d1) | (1 << d2)) << cw), h - 1, rng.randrange(w))
    # An injection in the last line of an image: read in the virtual lines or in the next image
    inject(((1 << pos[0]) | (1 << pos[1])) << ((delays[0] - 1) * cw), h - 1, w - 1)
    items += img(rng, c, "lines") + img(rng, c, "random")
    return items + status()


def build_reset(rng, c):
    w, h, bits = c["w"], c["h"], c["bits"]
    n = w * h
    items = img(rng, c, "lines")
    # Reset with the module idle (two cycles)
    items += [("W",), ("T", drain(c)), ("R", 0, 0, 2)] + img(rng, c, "random")
    # Held resets during the pixels of a line and at the end of an image (every window delivered), of one cycle
    for k in sorted({n // 2, n - 1, n} - {0}):
        pix = random_image(rng, w, h, bits)
        items += packets(pix[:k], [k], last=k == n) + [("T", drain(c)), ("R", 0, 0, 1)]
        if k < n:
            items += raw_packet(pix[k:], SEQ_LAST)
        items += img(rng, c, "lines")
    # Running resets of two cycles: during a line and while the windows of the borders are output; at most the
    # windows of the image before are dropped
    geo = Window(w, h, bits, c["wx"], c["wy"], c["ax"], c["ay"], c["sx"], c["sy"], c["border"])
    for k, drop in ((max(n // 2, 1), min(2, geo.wo * geo.ho)), (n, min(3, geo.wo * geo.ho))):
        pix = random_image(rng, w, h, bits)
        items += packets(pix[:k], [k], last=k == n) + [("R", drop, 1, 2)]
        if k < n:
            items += raw_packet(pix[k:], SEQ_LAST)
        items += img(rng, c, "lines")
    return items + status()


def build_rate(rng, c):
    items = [("M", 1)]
    for mode in ("lines", "random", "one", "lines"):
        items += img(rng, c, mode)
    items += [("W",), ("M", 2)]
    return items + status()


BUILDERS = {
    "test_static": build_static,
    "test_input_stream": build_input_stream,
    "test_handshake": build_handshake,
    "test_ecc": build_ecc,
    "test_reset": build_reset,
    "test_rate": build_rate,
}


def configure(lib, out_dir):
    tb = lib.test_bench("isp_window_tb")
    for c in CONFIGS:
        geo = Window(c["w"], c["h"], c["bits"], c["wx"], c["wy"], c["ax"], c["ay"], c["sx"], c["sy"], c["border"])
        for test in c["tests"]:
            rng = rng_for(MODULE, c["name"], test)
            items = BUILDERS[test](rng, c)
            folder = Path(out_dir) / MODULE / c["name"]
            files = {ext: folder / (test + "." + ext) for ext in ("stim", "exp", "inj", "tim")}
            res = write_test(files["stim"], files["exp"], items, model_of(c), c["bits"], inj_path=files["inj"],
                             tim_path=files["tim"])
            tb.test(test).add_config(name=c["name"], generics={
                "ImageWidth_g": c["w"], "ImageHeight_g": c["h"], "PixelBits_g": c["bits"], "WinX_g": c["wx"],
                "WinY_g": c["wy"], "AnchorX_g": c["ax"], "AnchorY_g": c["ay"], "StrideX_g": c["sx"],
                "StrideY_g": c["sy"], "BorderMode_g": c["border"], "EccPipeline_g": c["ecc"],
                "Resource_g": c["resource"], "OutWidth_g": geo.wo, "OutHeight_g": geo.ho,
                "StimFile_g": files["stim"].as_posix(), "ExpFile_g": files["exp"].as_posix(),
                "InjFile_g": files["inj"].as_posix(), "TimFile_g": files["tim"].as_posix(),
                "GapPct_g": c["gap"], "StallPct_g": c["stall"], "Seed_g": seed_for(MODULE, c["name"], test),
                "ExpFraming_g": res["errors"], "ExpSec_g": res["sec"], "ExpDed_g": res["ded"],
                "WatchdogUs_g": watchdog_us(files["stim"], files["exp"])})
