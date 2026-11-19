# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""Directed tests of the reference models against results worked out by hand from the specifications."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from isp_model import CRP_INJECT, CRP_ROI_POS, CRP_STATUS, crop, frame_sync  # noqa: E402
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
    out, ferr, _, cerr, _ = crop(packets(pix, [12]), 4, 3, 1, 1, 2, 2, False)
    assert ferr == 0 and cerr == 0
    assert crop_pixels(out) == [6, 7, 10, 11]
    assert [o[2] for o in out] == [0, 1, 0, 1]                  # Last at the last column of the region
    assert [o[3] for o in out] == [1, 1, 2, 2]                  # first line "01", last line "10"


def test_crop_runtime_position_and_invalid():
    pix = list(range(1, 13))
    img = packets(pix, [4, 4, 4])
    items = img + [("A", 100, [("W", CRP_ROI_POS, (0 << 16) | 2, 0xF)])] + img \
        + [("A", 101, [("W", CRP_ROI_POS, (2 << 16) | 3, 0xF), ("C", CRP_ROI_POS, None, 0xF)])] + img
    out, _, _, cerr, regs = crop(items, 4, 3, 1, 1, 2, 2, True)
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
    out, _, _, cerr, regs = crop(items, 4, 3, 1, 1, 2, 2, True)
    assert crop_pixels(out) == [7, 8, 11, 12, 6, 7, 10, 11, 6, 7, 10, 11, 7, 8, 11, 12]
    assert cerr == 2
    assert regs[-1][1][0][2] == 0x200                              # STATUS.ERR_CONFIG, image closed


def test_crop_reset_restores_generics():
    pix = list(range(1, 13))
    img = packets(pix, [12])
    items = [("A", 100, [("W", CRP_ROI_POS, 0x2, 0xF)])] + img + [("R", 0, 0, 2)] + img
    out, _, _, _, _ = crop(items, 4, 3, 1, 1, 2, 2, True)
    assert crop_pixels([o for o in out]) == [3, 4, 7, 8, 6, 7, 10, 11]

