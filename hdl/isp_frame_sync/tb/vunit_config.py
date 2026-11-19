# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of isp_frame_sync_tb (verification plan, sections 2 and 3).

For every configuration and test, the stimulus is built here, the reference model (tools/isp_model.py) computes the
expected output and the number of Err_Framing pulses, and both files are written to the vector directory.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "tools"))

from isp_model import SEQ_CONT, SEQ_FIRST, SEQ_LAST, SEQ_ONLY, frame_sync  # noqa: E402
from isp_tbgen import (image_beats, packets, random_image, raw_packet, rng_for, seed_for, split,  # noqa: E402
                       write_test)

MODULE = "isp_frame_sync"
ALL = ["test_images", "test_short_images", "test_excess_pixels", "test_end_flags", "test_reset", "test_status",
       "test_rate", "test_random_streams"]
NO_RATE = [t for t in ALL if t != "test_rate"]
BIG = ["test_images", "test_short_images"]

# (name, W, H, PixelBits, gap %, stall %, tests)
CONFIGS = [
    ("w5_h4_p12", 5, 4, 12, 0, 0, ALL),
    ("w5_h4_p12_bp", 5, 4, 12, 30, 40, NO_RATE),
    ("w1_h1_p1", 1, 1, 1, 30, 40, NO_RATE),
    ("w1_h6_p8", 1, 6, 8, 30, 40, NO_RATE),
    ("w7_h1_p16", 7, 1, 16, 0, 0, ALL),
    ("w2_h2_p64", 2, 2, 64, 30, 40, NO_RATE),
    ("w33_h9_p13", 33, 9, 13, 20, 20, NO_RATE),
    ("w64_h32_p32", 64, 32, 32, 0, 0, ALL),
    ("w65536_h1_p12", 65536, 1, 12, 10, 10, BIG),
    ("w1_h65536_p12", 1, 65536, 12, 10, 10, BIG),
] + [("w3_h2_p{}".format(n), 3, 2, n, 20, 20, ["test_images"]) for n in (1, 2, 7, 8, 12, 13, 16, 31, 32, 33, 63, 64)]


def status():
    """Wait for the sink, give the module time for discards, probe Stat_ImageOpen."""
    return [("W",), ("T", 8), ("P",)]


def short_image(rng, w, h, bits, k):
    """The first k pixels of an image, without the last flags (the image is cut)."""
    pix = random_image(rng, w, h, bits)[:k]
    return packets(pix, split(rng, k, w, "random"), last=False)


def single_start_image(rng, w, h, bits):
    """A complete image in one packet with the flags "11"."""
    return image_beats(rng, w, h, bits, "one")


def build_images(rng, w, h, bits):
    modes = ["lines", "one", "pixel", "wplus1", "random", "line_end", "random", "lines"]
    if w * h > 4096:
        modes = ["lines", "random"]
    items = []
    for mode in modes:
        items += image_beats(rng, w, h, bits, mode)
    return items + status()


def build_short_images(rng, w, h, bits):
    n = w * h
    items = []
    if n == 1:
        # No image can be cut: complete images only
        return build_images(rng, w, h, bits)
    cuts = sorted({1, n - 1, w if n > w else 1, (n // 2) if n > 2 else 1})
    for i, k in enumerate(cuts):
        items += short_image(rng, w, h, bits, k)
        # The next image starts in a "01" packet or in a "11" packet
        items += image_beats(rng, w, h, bits, "random" if i % 2 == 0 else "one")
    # Two short images in a row, then a complete one
    items += short_image(rng, w, h, bits, 1) + short_image(rng, w, h, bits, n - 1)
    items += image_beats(rng, w, h, bits, "lines")
    return items + status()


def build_excess_pixels(rng, w, h, bits):
    n = w * h
    items = []
    # After the reset: a "00" and a "10" packet without an image start (one run)
    items += raw_packet([rng.getrandbits(bits) for _ in range(3)], SEQ_CONT)
    items += raw_packet([rng.getrandbits(bits) for _ in range(2)], SEQ_LAST)
    items += image_beats(rng, w, h, bits, "lines")
    # After a complete image: a "00" packet (a run), an image, a "10" packet (a run)
    items += raw_packet([rng.getrandbits(bits) for _ in range(4)], SEQ_CONT)
    items += image_beats(rng, w, h, bits, "random")
    items += raw_packet([rng.getrandbits(bits) for _ in range(1)], SEQ_LAST)
    items += image_beats(rng, w, h, bits, "one")
    # A last packet longer than the image: E3, then a run of E2
    pix = random_image(rng, w, h, bits) + [rng.getrandbits(bits) for _ in range(3)]
    lengths = split(rng, n, w, "random")
    lengths[-1] += 3
    items += packets(pix, lengths)
    items += image_beats(rng, w, h, bits, "lines")
    return items + status()


def build_end_flags(rng, w, h, bits):
    n = w * h
    items = []

    def rnd(k):
        return [rng.getrandbits(bits) for _ in range(k)]

    if n >= 2:
        # The last pixel with Last in a "00" packet
        items += raw_packet(rnd(n - 1), SEQ_FIRST) + raw_packet(rnd(1), SEQ_CONT)
    # An image in one "01" packet: the last pixel in a "01" packet
    items += raw_packet(rnd(n), SEQ_FIRST)
    items += image_beats(rng, w, h, bits, "random")
    # The last pixel without Last: the packet continues for one more pixel (E3, then E2)
    if n >= 2:
        items += raw_packet(rnd(n - 1), SEQ_FIRST) + raw_packet(rnd(2), SEQ_LAST)
    else:
        items += raw_packet(rnd(2), SEQ_ONLY)
    items += image_beats(rng, w, h, bits, "lines")
    if n >= 3:
        # A "10" packet that ends before the last pixel (E4); the image completed by a further packet
        k = rng.randint(1, n - 2)
        items += raw_packet(rnd(1), SEQ_FIRST) + raw_packet(rnd(k), SEQ_LAST) + raw_packet(rnd(n - 1 - k), SEQ_LAST)
    if n >= 2:
        # A "11" packet that ends at the first pixel (E4), the rest in a "10" packet
        items += raw_packet(rnd(1), SEQ_ONLY) + raw_packet(rnd(n - 1), SEQ_LAST)
        # E4 followed by an early image start (E1)
        items += raw_packet(rnd(1), SEQ_ONLY)
        items += image_beats(rng, w, h, bits, "random")
    items += image_beats(rng, w, h, bits, "one")
    return items + status()


def build_reset(rng, w, h, bits):
    n = w * h
    items = image_beats(rng, w, h, bits, "lines")
    # Reset with the module idle (two cycles)
    items += [("W",), ("T", 4), ("R", 0, 0, 2)]
    items += image_beats(rng, w, h, bits, "random")
    if n >= 5:
        for mode, cycles in ((0, 1), (1, 2)):
            # In the middle of an image: held and running
            pix = random_image(rng, w, h, bits)
            k = rng.randint(4, n - 1)
            items += packets(pix[:k], [k], last=False)
            items += [("R", 2, mode, cycles)]
            # The rest of the interrupted image: a run of E2
            items += raw_packet(pix[k:], SEQ_LAST)
            items += image_beats(rng, w, h, bits, "lines")
    if n >= 3:
        for mode, cycles in ((0, 2), (1, 1)):
            # While missing pixels are generated: the cut image, the next image start and one more pixel
            k = 1
            m = n - k
            items += short_image(rng, w, h, bits, k) + [("W",)]
            pix = random_image(rng, w, h, bits)
            items += packets(pix[:2], [2], last=False)
            drop = (m - m // 2) + 2
            items += [("R", drop, mode, cycles)]
            items += raw_packet(pix[2:], SEQ_LAST)
            items += image_beats(rng, w, h, bits, "random")
    return items + status()


def build_status(rng, w, h, bits):
    n = w * h
    items = status()                                     # 0 after the reset
    if n >= 2:
        pix = random_image(rng, w, h, bits)
        k = n // 2 if n > 2 else 1
        items += packets(pix[:k], [k], last=False) + status()          # 1 after an image start
        items += [("G", 40)] + status()                                # 1 during a pause of the source
        items += raw_packet(pix[k:], SEQ_LAST) + status()              # 0 after the last pixel
        # 1 while missing pixels are generated with the output held
        items += short_image(rng, w, h, bits, 1) + [("W",), ("H", 1)]
        pix = random_image(rng, w, h, bits)
        items += packets(pix[:1], [1], last=False) + [("T", 10), ("P",), ("H", 0)]
        items += raw_packet(pix[1:], SEQ_LAST) + status()
        # 0 after an image ended by E3 (the last pixel in a "01" packet)
        items += raw_packet([rng.getrandbits(bits) for _ in range(n)], SEQ_FIRST) + status()
    items += image_beats(rng, w, h, bits, "lines") + status()
    return items


def build_rate(rng, w, h, bits):
    n = w * h
    # Phase 1: images back to back, without gaps
    items = [("M", 1)]
    for mode in ("lines", "random", "one"):
        items += image_beats(rng, w, h, bits, mode)
    items += [("W",), ("M", 2)]
    # Phase 2: short images followed at once by an image start
    if n >= 2:
        for m in sorted({1, w, n - 1} & set(range(1, n))):
            items += short_image(rng, w, h, bits, n - m) + [("W",), ("M", 1000 + m)]
            items += image_beats(rng, w, h, bits, "lines") + [("W",), ("M", 2)]
    # Phase 3: with the output held, 3W + 5 pixels without an image start
    items += image_beats(rng, w, h, bits, "lines") + [("W",), ("M", 4), ("H", 1)]
    items += raw_packet([rng.getrandbits(bits) for _ in range(3 * w + 5)], SEQ_CONT)
    items += [("T", 5), ("H", 0), ("M", 5)]
    return items + status()


def build_random_streams(rng, w, h, bits):
    n = w * h
    items = []
    for _ in range(400):
        if rng.random() < 0.15:
            items += image_beats(rng, w, h, bits, rng.choice(["lines", "one", "random", "pixel"]))
            continue
        length = rng.randint(1, 2 * n)
        pix = [rng.getrandbits(bits) for _ in range(length)]
        if rng.random() < 0.2:
            # Flags that change within the packet
            items += [("B", p, 1 if j == length - 1 else 0, rng.randint(0, 3)) for j, p in enumerate(pix)]
        else:
            items += raw_packet(pix, rng.randint(0, 3))
    items += image_beats(rng, w, h, bits, "random") + image_beats(rng, w, h, bits, "lines")
    return items + status()


BUILDERS = {
    "test_images": build_images,
    "test_short_images": build_short_images,
    "test_excess_pixels": build_excess_pixels,
    "test_end_flags": build_end_flags,
    "test_reset": build_reset,
    "test_status": build_status,
    "test_rate": build_rate,
    "test_random_streams": build_random_streams,
}


def configure(lib, out_dir):
    tb = lib.test_bench("isp_frame_sync_tb")
    for name, w, h, bits, gap, stall, tests in CONFIGS:
        xw = max((w - 1).bit_length(), 1)
        for test in tests:
            rng = rng_for(MODULE, name, test)
            items = BUILDERS[test](rng, w, h, bits)
            folder = Path(out_dir) / MODULE / name
            stim = folder / (test + ".stim")
            exp = folder / (test + ".exp")
            errors = write_test(stim, exp, items, lambda it: frame_sync(it, w, h), bits,
                                side=lambda o: format((o[5] << xw) | o[4], "x"))["errors"]
            tb.test(test).add_config(name=name, generics={
                "ImageWidth_g": w, "ImageHeight_g": h, "PixelBits_g": bits,
                "StimFile_g": stim.as_posix(), "ExpFile_g": exp.as_posix(),
                "GapPct_g": gap, "StallPct_g": stall, "Seed_g": seed_for(MODULE, name, test),
                "ExpFraming_g": errors})
