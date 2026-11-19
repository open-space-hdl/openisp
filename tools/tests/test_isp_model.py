# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""Directed tests of the reference models against results worked out by hand from the specifications."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from isp_model import (CRP_INJECT, CRP_ROI_POS, CRP_STATUS, PNT_CTRL, PNT_GAIN, PNT_INJECT,  # noqa: E402
                       PNT_OFFSET_HI, PNT_OFFSET_LO, PNT_SHIFT, crop, ecc_codeword_width, ecc_data_positions,
                       ecc_decode, frame_sync, point, point_op, window)
from isp_tbgen import packets  # noqa: E402


def beats(model_out):
    return [o for o in model_out if o[0] == "B"]


def test_user_guide_example():
    # Image of 4 x 3 pixels in packets of 7 and 5 pixels (user guide, section 2.2)
    pix = list(range(1, 13))
    out, err, _ = frame_sync(packets(pix, [7, 5]), 4, 3)
    assert err == 0
    assert [o[1] for o in out] == pix
    assert [o[2] for o in out] == [0, 0, 0, 1] * 3
    assert [o[3] for o in out] == [1] * 4 + [0] * 4 + [2] * 4
    assert [(o[4], o[5]) for o in out][:5] == [(0, 0), (1, 0), (2, 0), (3, 0), (0, 1)]


def test_one_line_and_one_pixel():
    out, err, _ = frame_sync(packets([5, 6, 7], [3]), 3, 1)
    assert err == 0 and [o[3] for o in out] == [3, 3, 3] and [o[2] for o in out] == [0, 0, 1]
    out, err, _ = frame_sync(packets([9], [1]), 1, 1)
    assert err == 0 and out == [("B", 9, 1, 3, 0, 0)]


def test_e1_short_image():
    # 2 x 2 image cut after 3 pixels, then a complete image
    items = packets([1, 2, 3], [3], last=False) + packets([5, 6, 7, 8], [4])
    out, err, annot = frame_sync(items, 2, 2)
    assert err == 1
    assert [o[1] for o in out] == [1, 2, 3, 0, 5, 6, 7, 8]
    assert [(o[4], o[5]) for o in out][3] == (1, 1)
    assert annot[-1] == (8, False)


def test_e2_runs():
    # Pixels before the first image start: one run; after the image: two runs separated by an image
    items = [("B", 1, 0, 0), ("B", 2, 1, 0)] + packets([3], [1]) + [("B", 4, 1, 2)] + packets([5], [1]) \
        + [("B", 6, 0, 0), ("B", 7, 1, 0)]
    out, err, _ = frame_sync(items, 1, 1)
    assert [o[1] for o in out] == [3, 5]
    assert err == 3


def test_e3_e4():
    # E3: the last pixel in a "00" packet; the rest of the packet is a run of E2
    items = [("B", 1, 0, 1), ("B", 2, 0, 1), ("B", 3, 1, 1)]
    out, err, _ = frame_sync(items, 2, 1)
    assert [o[1] for o in out] == [1, 2] and err == 2          # E3 and one E2
    # E4: a "10" packet that ends at pixel 0 of a 2 x 1 image; the image continues
    items = [("B", 1, 1, 3), ("B", 2, 1, 2)]
    out, err, _ = frame_sync(items, 2, 1)
    assert [o[1] for o in out] == [1, 2] and err == 1


def test_reset_drops_beats():
    items = packets([1, 2, 3], [3], last=False) + [("R", 1, 0, 2)] + [("B", 4, 1, 2)] + packets([5, 6, 7, 8], [4])
    out, err, annot = frame_sync(items, 2, 2)
    assert [o[1] if o[0] == "B" else "R" for o in out] == [1, 2, "R", 5, 6, 7, 8]
    assert err == 1                                             # the remainder after the reset is a run of E2
    assert annot[3] == (2, False)


def crop_pixels(out):
    return [o[1] for o in out if o[0] == "B"]


def test_crop_static():
    # 4 x 3 image, region (1, 1) of 2 x 2: pixels 6, 7 and 10, 11
    pix = list(range(1, 13))
    out, ferr, _, ex = crop(packets(pix, [12]), 4, 3, 1, 1, 2, 2, False)
    cerr = ex["config"]
    assert ferr == 0 and cerr == 0
    assert crop_pixels(out) == [6, 7, 10, 11]
    assert [o[2] for o in out] == [0, 1, 0, 1]                  # Last at the last column of the region
    assert [o[3] for o in out] == [1, 1, 2, 2]                  # first line "01", last line "10"


def test_crop_runtime_position_and_invalid():
    pix = list(range(1, 13))
    img = packets(pix, [4, 4, 4])
    items = img + [("A", 100, [("W", CRP_ROI_POS, (0 << 16) | 2, 0xF)])] + img \
        + [("A", 101, [("W", CRP_ROI_POS, (2 << 16) | 3, 0xF), ("C", CRP_ROI_POS, None, 0xF)])] + img
    out, _, _, ex = crop(items, 4, 3, 1, 1, 2, 2, True)
    cerr, regs = ex["config"], ex["regs"]
    # Generics, then (2, 0), then (3, 2) is invalid (3 + 2 > 4): generics again with one Err_Config
    assert crop_pixels(out) == [6, 7, 10, 11, 3, 4, 7, 8, 6, 7, 10, 11]
    assert cerr == 1
    assert regs[1][1][1] == ("C", CRP_ROI_POS, (2 << 16) | 3, 0xF)   # the register keeps the written value


def test_crop_parity_and_strobes():
    pix = list(range(1, 13))
    img = packets(pix, [12])
    items = [("A", 100, [("W", CRP_ROI_POS, 0x00000002, 0x1)]), ]   # only byte 0: X = 2, Y stays 1
    items += img + [("A", 101, [("W", CRP_INJECT, 1, 0xF)])] + img + img
    items += [("A", 102, [("W", CRP_INJECT, 1, 0xF)])] + img        # a second injection restores the parity
    items += [("A", 103, [("C", CRP_STATUS, None, 0xF)])]
    out, _, _, ex = crop(items, 4, 3, 1, 1, 2, 2, True)
    cerr, regs = ex["config"], ex["regs"]
    assert crop_pixels(out) == [7, 8, 11, 12, 6, 7, 10, 11, 6, 7, 10, 11, 7, 8, 11, 12]
    assert cerr == 2
    assert regs[-1][1][0][2] == 0x200                              # STATUS.ERR_CONFIG, image closed


def test_crop_reset_restores_generics():
    pix = list(range(1, 13))
    img = packets(pix, [12])
    items = [("A", 100, [("W", CRP_ROI_POS, 0x2, 0xF)])] + img + [("R", 0, 0, 2)] + img
    out, _, _, _ = crop(items, 4, 3, 1, 1, 2, 2, True)
    assert crop_pixels([o for o in out]) == [3, 4, 7, 8, 6, 7, 10, 11]


def test_crop_timing():
    # 4 x 3, region (1, 1) of 2 x 2: the output pixels come from the input beats 5, 6, 9 and 10
    out, _, _, ex = crop(packets(list(range(1, 13)), [4, 4, 4]), 4, 3, 1, 1, 2, 2, False)
    assert ex["timing"] == [5, 6, 9, 10]


def test_point_op():
    # Dark level 100, gain 1229 / 1024
    assert point_op(200, -100, 1229, 10, 0, 4095) == 120          # 122900 / 1024 = 120.02
    assert point_op(50, -100, 1229, 10, 0, 4095) == 0             # floor(-60.01) = -61, clamped to 0
    assert point_op(50, -100, 1229, 10, -1000, 4095) == -61       # the arithmetic shift rounds toward minus infinity
    assert point_op(4095, 0, 7, 0, 0, 4095) == 4095               # upper clamp
    assert point_op(10, 0, 1, 0, 200, 100) == 100                 # Low above High: first Low, then High


def run_point(items, **kw):
    args = dict(width=2, height=1, in_bits=12, out_bits=12, gain_bits=16, max_shift=28, offset_g=0, gain_g=1,
                shift_g=0, low_g=0, high_g=-1, runtime=True)
    args.update(kw)
    return point(items, **args)


def test_point_hold_and_parity():
    img = packets([10, 20], [2])
    items = [("A", 100, [("W", PNT_GAIN, 2, 0xF)])] + img                       # gain 2
    items += [("A", 101, [("W", PNT_CTRL, 1, 0xF), ("W", PNT_GAIN, 3, 0xF)])] + img   # held: still 2
    items += [("A", 102, [("W", PNT_CTRL, 0, 0xF)])] + img                    # gain 3
    items += [("A", 103, [("W", PNT_INJECT, 4, 0xF)])] + img + img            # parity of GAIN: generics twice
    items += [("A", 104, [("W", PNT_CTRL, 1, 0xF), ("W", PNT_INJECT, 4, 0xF)])] + img   # held: no check
    items += [("A", 105, [("W", PNT_INJECT, 4, 0xF), ("W", PNT_CTRL, 0, 0xF)])] + img   # bad again, taken: error
    items += [("A", 106, [("W", PNT_GAIN, 5, 0xF)])] + img                    # written: gain 5
    out, _, _, ex = run_point(items)
    cerr = ex["config"]
    assert [o[1] for o in out] == [20, 40, 20, 40, 30, 60, 10, 20, 10, 20, 10, 20, 10, 20, 50, 100]
    assert cerr == 3


def test_point_ctrl_parity():
    img = packets([10, 20], [2])
    items = [("A", 100, [("W", PNT_CTRL, 1, 0xF), ("W", PNT_GAIN, 3, 0xF)])] + img      # held: gain 1
    items += [("A", 101, [("W", PNT_INJECT, 1 << 6, 0xF)])] + img + img                # CTRL bad: gain 3, 2 errors
    items += [("A", 102, [("W", PNT_CTRL, 1, 0xF), ("W", PNT_GAIN, 5, 0xF)])] + img    # restored, held: gain 3
    items += [("A", 103, [("W", PNT_CTRL, 1, 0xF), ("W", PNT_INJECT, (1 << 6) | (1 << 2), 0xF)])] + img
    # CTRL and GAIN bad at the same image start: the generics, one Err_Config
    out, _, _, ex = run_point(items)
    assert [o[1] for o in out] == [10, 20, 30, 60, 30, 60, 30, 60, 10, 20]
    assert ex["config"] == 3


def test_point_readback():
    items = [("A", 100, [("W", PNT_OFFSET_LO, 0xFFFFFFF0, 0xF), ("C", PNT_OFFSET_LO, None, 0xF),
                         ("C", PNT_OFFSET_HI, None, 0xF),
                         ("W", PNT_OFFSET_LO, 0x00001FFF, 0xF), ("C", PNT_OFFSET_LO, None, 0xF),
                         ("W", PNT_SHIFT, 0x7F, 0xF), ("C", PNT_SHIFT, None, 0xF),
                         ("W", PNT_GAIN, 0xFFFFFFFF, 0x1), ("C", PNT_GAIN, None, 0xF)])]
    regs = run_point(items)[3]["regs"]
    reads = [e[2] for e in regs[0][1] if e[0] == "C"]
    # 13-bit offset: -16 sign-extended; 0x1FFF is -1; SHIFT keeps 7 bits; GAIN: only byte 0 written
    assert reads == [0xFFFFFFF0, 0xFFFFFFFF, 0xFFFFFFFF, 0x7F, 0xFF]


def test_point_shift_limited():
    img = packets([1024, 0], [2])
    items = [("A", 100, [("W", PNT_SHIFT, 127, 0xF)])] + img
    out = run_point(items, max_shift=8)[0]
    assert [o[1] for o in out] == [4, 0]                                       # 1024 >> 8


def elements(data, count, bits):
    """Elements of a window, element k first."""
    return [data >> (k * bits) & ((1 << bits) - 1) for k in range(count)]


def image(w, h):
    """Pixel value 10 x (y + 1) + x + 1: p(x, y) can be read from the value."""
    return [10 * (y + 1) + x + 1 for y in range(h) for x in range(w)]


def test_ecc_code():
    # 12 data bits: 5 Hamming parity bits, 18 bits; data bit 0 at position 3, bit 1 at 5, bit 11 at 17
    assert ecc_codeword_width(12) == 18
    pos = ecc_data_positions(12)
    assert pos[:4] == [3, 5, 6, 7] and pos[-1] == 17 and len(pos) == 12
    assert ecc_decode(1 << 3, 12) == (0, True, False)              # data bit: corrected
    assert ecc_decode(1 << 0, 12) == (0, True, False)              # overall parity bit
    assert ecc_decode(1 << 4, 12) == (0, True, False)              # Hamming parity bit
    assert ecc_decode((1 << 3) | (1 << 5), 12) == (3, False, True)  # two data bits: data as read
    assert ecc_decode((1 << 3) | (1 << 0), 12) == (1, False, True)  # data and overall parity bit
    assert ecc_decode((1 << 1) | (1 << 2), 12) == (0, False, True)  # two parity bits
    assert ecc_codeword_width(1) == 4 and ecc_codeword_width(32) == 39


def test_window_replicate_and_mirror_corner():
    pix = image(3, 3)                                               # p(x, y) = 10 (y + 1) + x + 1
    out = window(packets(pix, [9]), 3, 3, 8, 3, 3, border="replicate")[0]
    assert len(out) == 9 and [o[2] for o in out] == [0, 0, 1] * 3
    assert [o[3] for o in out] == [1, 1, 1, 0, 0, 0, 2, 2, 2]
    # Window of (0, 0): rows of the lines 0, 0, 1 and columns 0, 0, 1
    assert elements(out[0][1], 9, 8) == [11, 11, 12, 11, 11, 12, 21, 21, 22]
    # Window of (2, 2): rows 1, 2, 2 and columns 1, 2, 2
    assert elements(out[8][1], 9, 8) == [22, 23, 23, 32, 33, 33, 32, 33, 33]
    out = window(packets(pix, [9]), 3, 3, 8, 3, 3, border="mirror")[0]
    # Mirror: line -1 is line 1, column -1 is column 1
    assert elements(out[0][1], 9, 8) == [22, 21, 22, 12, 11, 12, 22, 21, 22]
    assert elements(out[8][1], 9, 8) == [22, 23, 22, 32, 33, 32, 22, 23, 22]


def test_window_valid_and_zero():
    pix = image(4, 3)
    out = window(packets(pix, [12]), 4, 3, 8, 3, 3, border="valid")[0]
    assert [(o[4], o[5], o[2], o[3]) for o in out] == [(1, 1, 0, 3), (2, 1, 1, 3)]   # one line: flags "11"
    assert elements(out[1][1], 9, 8) == [12, 13, 14, 22, 23, 24, 32, 33, 34]
    out = window(packets(pix, [12]), 4, 3, 8, 3, 3, border="zero")[0]
    assert elements(out[0][1], 9, 8) == [0, 0, 0, 0, 11, 12, 0, 21, 22]
    assert elements(out[11][1], 9, 8) == [23, 24, 0, 33, 34, 0, 0, 0, 0]


def test_window_binning():
    pix = image(5, 3)
    out = window(packets(pix, [15]), 5, 3, 8, 2, 2, 0, 0, 2, 2, border="valid")[0]
    assert [(o[4], o[5]) for o in out] == [(0, 0), (2, 0)]          # the incomplete windows are dropped
    assert elements(out[1][1], 4, 8) == [13, 14, 23, 24]
    out = window(packets(pix, [15]), 5, 3, 8, 2, 2, 0, 0, 2, 2, border="zero")[0]
    assert [(o[4], o[5], o[2], o[3]) for o in out] == [(0, 0, 0, 1), (2, 0, 0, 1), (4, 0, 1, 1),
                                                        (0, 2, 0, 2), (2, 2, 0, 2), (4, 2, 1, 2)]
    assert elements(out[5][1], 4, 8) == [35, 0, 0, 0]


def test_window_timing_and_count():
    # 3 x 3 replicate on 4 x 3: the window of (x, y) is completed by p(x + 1, y + 1)
    pix = image(4, 3)
    items = packets(pix, [4, 4, 4])
    out, _, annot, ex = window(items, 4, 3, 8, 3, 3, border="replicate")
    # Pixel index 5 = p(1, 1) completes the window (0, 0); index 7 = p(3, 1) completes (2, 0), then HCOL (3, 0)
    assert ex["timing"][:4] == [5, 6, 7, -1]
    assert annot[4][0] == 0 and annot[5][0] == 1 and annot[7][0] == 4
    assert annot[11][0] == 12 and ex["timing"][4:8] == [9, 10, 11, -1] and ex["timing"][8:] == [-1] * 4


def test_window_ecc():
    # 1 x 3 window (one column, two delays) on a 3 x 4 image of 12-bit pixels, replicate
    pix = image(3, 4)
    cw = ecc_codeword_width(12)
    pos = ecc_data_positions(12)
    double = (1 << pos[0]) | (1 << pos[1])                          # data bits 0 and 1: mask 3
    # Inject into delay 1 before p(1, 1): the codeword of p(1, 1) in delay 1 carries the double error
    items = packets(pix[:4], [4], last=False) + [("J", 100, double)] + packets(pix[4:], [8], first=False)
    out, _, _, ex = window(items, 3, 4, 12, 1, 3, border="replicate")
    assert ex["ded"] == 1 and ex["sec"] == 0
    vals = [elements(o[1], 3, 12) for o in out]
    # Window of (x, y) = rows y - 1, y, y + 1 of column x; p(1, 1) = 22 changes to 22 ^ 3 = 21 from delay 1 on:
    # in the window of (1, 1) (row 1, read from delay 1) and of (1, 2) (row 0, from delay 2)
    assert vals[4] == [12, 21, 32] and vals[7] == [21, 32, 42]
    assert vals[10] == [32, 42, 42]                                 # (1, 3): unchanged
    # The same into delay 2: the codeword that delay 2 writes in that event is p(1, 0); visible in (1, 1) only
    items = packets(pix[:4], [4], last=False) + [("J", 100, double << cw)] + packets(pix[4:], [8], first=False)
    out, _, _, ex = window(items, 3, 4, 12, 1, 3, border="replicate")
    vals = [elements(o[1], 3, 12) for o in out]
    assert ex["ded"] == 1 and vals[4] == [12 ^ 3, 22, 32] and vals[1] == [12, 12, 22]
    # Single errors in both delays in one event: corrected, one pulse
    items = packets(pix[:4], [4], last=False) + [("J", 100, (1 << pos[3]) | (1 << (cw + 0)))] \
        + packets(pix[4:], [8], first=False)
    out, _, _, ex = window(items, 3, 4, 12, 1, 3, border="replicate")
    assert ex["sec"] == 1 and ex["ded"] == 0
    assert [elements(o[1], 3, 12) for o in out] == [elements(o[1], 3, 12) for o in window(
        packets(pix, [12]), 3, 4, 12, 1, 3, border="replicate")[0]]

