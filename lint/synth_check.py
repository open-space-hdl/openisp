# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""Synthesis check of OpenISP with GHDL: elaborates and synthesises the top-level entities of the modules in their
default configurations and at the bounds of every numeric generic, and checks that every configuration outside the
declared ranges stops the elaboration with its message.

Usage: python lint/synth_check.py [name ...]
Uses the libraries compiled by the regression runner (run `python run.py --compile` first). Names select
configurations; without names all run. Exit code 0 when every configuration synthesises without error and without
inferred latch, and every configuration outside the ranges stops with its expected message.
GHDL 6.0.0 cannot override real or vector generics with -g: such an entity is synthesised through a wrapper
lint/<entity>_synth.vhd that takes integer generics and converts them; the wrappers are analysed into the library
before the synthesis.
This is a technology-independent check of synthesizability; resources and timing need the FPGA tools.
"""

import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LIBS = ROOT / "vunit_out" / "ghdl" / "libraries"

# Configurations that must synthesise: (name, top, generics)
CONFIGS = [
    # isp_frame_sync (TC-FSY-09); isp_pkg is synthesised with it (TC-PKG-02)
    ("fsy_w1_h1_p1", "isp_frame_sync", {"ImageWidth_g": "1", "ImageHeight_g": "1", "PixelBits_g": "1"}),
    ("fsy_w4096_h4096_p12", "isp_frame_sync", {"ImageWidth_g": "4096", "ImageHeight_g": "4096", "PixelBits_g": "12"}),
    ("fsy_w1_h65536_p32", "isp_frame_sync", {"ImageWidth_g": "1", "ImageHeight_g": "65536", "PixelBits_g": "32"}),
    ("fsy_w65536_h1_p8", "isp_frame_sync", {"ImageWidth_g": "65536", "ImageHeight_g": "1", "PixelBits_g": "8"}),
    ("fsy_w65536_h65536_p64", "isp_frame_sync",
     {"ImageWidth_g": "65536", "ImageHeight_g": "65536", "PixelBits_g": "64"}),
]


def crp(w, h, bits, x, y, rw, rh, runtime):
    """Generics of isp_crop."""
    return {"ImageWidth_g": str(w), "ImageHeight_g": str(h), "PixelBits_g": str(bits), "RoiX_g": str(x),
            "RoiY_g": str(y), "RoiWidth_g": str(rw), "RoiHeight_g": str(rh), "RuntimeRoi_g": str(runtime).lower()}


# isp_crop (TC-CRP-10): the bounds of every generic with both values of RuntimeRoi_g
CONFIGS += [
    ("crp_w1_h1_p1", "isp_crop", crp(1, 1, 1, 0, 0, 1, 1, False)),
    ("crp_w1_h1_p1_rt", "isp_crop", crp(1, 1, 1, 0, 0, 1, 1, True)),
    ("crp_w4096_h4096_p12_rt", "isp_crop", crp(4096, 4096, 12, 512, 512, 1024, 1024, True)),
    ("crp_w4096_h4096_p12", "isp_crop", crp(4096, 4096, 12, 512, 512, 1024, 1024, False)),
    ("crp_w65536_h65536_p64_whole", "isp_crop", crp(65536, 65536, 64, 0, 0, 65536, 65536, False)),
    ("crp_w65536_h65536_p64_whole_rt", "isp_crop", crp(65536, 65536, 64, 0, 0, 65536, 65536, True)),
    ("crp_w65536_h65536_p64_corner_rt", "isp_crop", crp(65536, 65536, 64, 65535, 65535, 1, 1, True)),
    ("crp_w65536_h1_p12_line_rt", "isp_crop", crp(65536, 1, 12, 0, 0, 65536, 1, True)),
    ("crp_w1_h65536_p12_column_rt", "isp_crop", crp(1, 65536, 12, 0, 0, 1, 65536, True)),
]


def pnt(w, h, inb, outb, gainb, maxs, ms, runtime, offset=0, gain=1, shift=0, low=0, high=-1):
    """Generics of isp_point."""
    return {"ImageWidth_g": str(w), "ImageHeight_g": str(h), "InBits_g": str(inb), "OutBits_g": str(outb),
            "GainBits_g": str(gainb), "MaxShift_g": str(maxs), "MultStages_g": str(ms),
            "Runtime_g": str(runtime).lower(), "Offset_g": str(offset), "Gain_g": str(gain), "Shift_g": str(shift),
            "Low_g": str(low), "High_g": str(high)}


# isp_point (TC-PNT-11): the bounds of every width, every MultStages_g, both values of Runtime_g and the bounds of the
# parameters of the generics
CONFIGS += [
    ("pnt_default_rt", "isp_point", pnt(4096, 4096, 16, 12, 16, 32, 2, True)),
    ("pnt_min", "isp_point", pnt(1, 1, 1, 1, 1, 0, 1, False)),
    # Every generic but the dimensions and the pixel bits at the default of the entity (MaxShift_g InBits_g +
    # GainBits_g), also with 64-bit input pixels
    ("pnt_defaults", "isp_point", {"ImageWidth_g": "4096", "ImageHeight_g": "4096", "InBits_g": "12",
                                   "OutBits_g": "12"}),
    ("pnt_defaults_64", "isp_point", {"ImageWidth_g": "16", "ImageHeight_g": "16", "InBits_g": "64",
                                      "OutBits_g": "32"}),
    ("pnt_min_rt", "isp_point", pnt(1, 1, 1, 1, 1, 3, 1, True)),
    ("pnt_max_rt", "isp_point", pnt(65536, 65536, 64, 32, 18, 83, 4, True)),
    ("pnt_max", "isp_point", pnt(65536, 65536, 64, 32, 18, 83, 3, False, -2 ** 31, 2 ** 18 - 1, 83, 2 ** 31 - 1)),
    ("pnt_params", "isp_point", pnt(64, 64, 32, 32, 18, 50, 2, False, -2 ** 31, 2 ** 18 - 1, 50, 2 ** 31 - 1, -1)),
    ("pnt_params_rt", "isp_point", pnt(64, 64, 32, 32, 18, 50, 2, True, 2 ** 31 - 1, 0, 0, 0, 0)),
]


def win(w, h, bits, wx, wy, border, ax=None, ay=None, sx=1, sy=1, ecc=1, resource="AUTO"):
    """Generics of isp_window (the anchors default to the middle)."""
    g = {"ImageWidth_g": str(w), "ImageHeight_g": str(h), "PixelBits_g": str(bits), "WinX_g": str(wx),
         "WinY_g": str(wy), "StrideX_g": str(sx), "StrideY_g": str(sy), "BorderMode_g": border,
         "EccPipeline_g": str(ecc), "Resource_g": resource}
    if ax is not None:
        g["AnchorX_g"] = str(ax)
    if ay is not None:
        g["AnchorY_g"] = str(ay)
    return g


# isp_window (TC-WIN-08): the bounds of every numeric generic, every border mode and every resource
CONFIGS += [
    ("win_default", "isp_window", win(4096, 4096, 12, 3, 3, "replicate")),
    ("win_min", "isp_window", win(1, 1, 1, 1, 1, "valid", sx=1, sy=1)),
    ("win_max", "isp_window", win(65536, 16, 32, 16, 16, "zero", 0, 15, 16, 16, 0, "BRAM")),
    ("win_tall", "isp_window", win(16, 65536, 32, 16, 16, "valid", 15, 0, 1, 1, 1, "SRL")),
    ("win_mirror", "isp_window", win(4096, 64, 16, 5, 5, "mirror", ecc=0, resource="BRAM")),
    ("win_zero", "isp_window", win(64, 64, 8, 4, 2, "zero", 1, 0, 3, 2)),
    ("win_row", "isp_window", win(64, 8, 12, 9, 1, "replicate")),
    ("win_bram_min", "isp_window", win(4, 8, 12, 3, 3, "replicate", ecc=1, resource="BRAM")),
]


def cnv(bits, wx, wy, cb, runtime, out_bits, coef_set=0, count=0, offset=0):
    """Generics of the wrapper isp_conv_synth (lint/isp_conv_synth.vhd)."""
    return {"PixelBits_g": str(bits), "WinX_g": str(wx), "WinY_g": str(wy), "CoefBits_g": str(cb),
            "RuntimeCoef_g": str(runtime).lower(), "OutBits_g": str(out_bits), "CoefSet_g": str(coef_set),
            "CoefCount_g": str(count), "CoefOffset_g": str(offset)}


# isp_conv (TC-CNV-11): the bounds of every numeric generic with both values of RuntimeCoef_g, coefficients at their
# bounds
CONFIGS += [
    ("cnv_default_rt", "isp_conv_synth", cnv(12, 3, 3, 16, True, 0)),
    ("cnv_default", "isp_conv_synth", cnv(12, 3, 3, 16, False, 0)),
    ("cnv_min_rt", "isp_conv_synth", cnv(1, 1, 1, 2, True, 1)),
    ("cnv_min", "isp_conv_synth", cnv(1, 1, 1, 2, False, 0)),
    ("cnv_max_rt", "isp_conv_synth", cnv(32, 16, 16, 18, True, 64)),
    ("cnv_max", "isp_conv_synth", cnv(32, 16, 16, 18, False, 0)),
    ("cnv_ones", "isp_conv_synth", cnv(12, 1, 4, 2, False, 0, coef_set=1)),
    ("cnv_mtf5_rt", "isp_conv_synth", cnv(12, 5, 5, 16, True, 12)),
]


def flt(wx, wy, border, cb, runtime, out_bits, ax=None, ay=None, sx=1, sy=1, bits=12, coef_set=0, count=0):
    """Generics of the wrapper isp_filter2d_synth (lint/isp_filter2d_synth.vhd), images of 1024 x 1024."""
    ax = (wx - 1) // 2 if ax is None else ax
    ay = (wy - 1) // 2 if ay is None else ay
    return {"ImageWidth_g": "1024", "ImageHeight_g": "1024", "PixelBits_g": str(bits), "WinX_g": str(wx),
            "WinY_g": str(wy), "AnchorX_g": str(ax), "AnchorY_g": str(ay), "StrideX_g": str(sx), "StrideY_g": str(sy),
            "BorderMode_g": border, "CoefBits_g": str(cb), "RuntimeCoef_g": str(runtime).lower(),
            "OutBits_g": str(out_bits), "CoefSet_g": str(coef_set), "CoefCount_g": str(count)}


# isp_filter2d (TC-FLT-07): the MTF filters, the mode valid, a stride, the horizontal filter of isp_bin and the 3 x 3
# filter with constant coefficients
CONFIGS += [
    ("flt_mtf3", "isp_filter2d_synth", flt(3, 3, "replicate", 16, True, 0)),
    ("flt_mtf5_mirror", "isp_filter2d_synth", flt(5, 5, "mirror", 16, True, 0)),
    ("flt_valid", "isp_filter2d_synth", flt(3, 3, "valid", 16, False, 0)),
    ("flt_strided", "isp_filter2d_synth", flt(4, 2, "replicate", 16, True, 0, ax=1, ay=0, sx=3, sy=2)),
    ("flt_bin_h", "isp_filter2d_synth", flt(4, 1, "zero", 2, False, 14, ax=0, ay=0, sx=4, coef_set=1)),
    ("flt_mtf3_const", "isp_filter2d_synth", flt(3, 3, "replicate", 16, False, 0)),
]



def bin_(w, h, bits, bx, by, border, ecc=1, resource="AUTO"):
    """Generics of isp_bin."""
    return {"ImageWidth_g": str(w), "ImageHeight_g": str(h), "PixelBits_g": str(bits), "BinX_g": str(bx),
            "BinY_g": str(by), "BorderMode_g": border, "EccPipeline_g": str(ecc), "Resource_g": resource}


# isp_bin (TC-BIN-07): the default (2 x 2 valid on lines of 4096 pixels), every border mode, the bounds of the image
# size (the bin, 65536), of the pixel width (1, 28) and of the factors (1, 16, each without the other filter and
# both 1: the frame sync alone), every line buffer resource and both values of EccPipeline_g
CONFIGS += [
    ("bin_default", "isp_bin", bin_(4096, 1024, 12, 2, 2, "valid")),
    ("bin_4x4_rep", "isp_bin", bin_(4096, 1024, 12, 4, 4, "replicate")),
    ("bin_3x5_zero", "isp_bin", bin_(1024, 1024, 12, 3, 5, "zero", ecc=0)),
    ("bin_image_equals_bin", "isp_bin", bin_(2, 2, 1, 2, 2, "valid", ecc=0, resource="SRL")),
    ("bin_1x1", "isp_bin", bin_(1, 1, 1, 1, 1, "valid")),
    ("bin_16x1", "isp_bin", bin_(65536, 1, 28, 16, 1, "zero")),
    ("bin_1x16", "isp_bin", bin_(1, 65536, 28, 1, 16, "replicate", resource="SRL")),
    ("bin_max", "isp_bin", bin_(65536, 65536, 28, 16, 16, "replicate", resource="BRAM")),
]

def rpl(w, h, bits, g, lat=1, ecc=0, period_ms=0):
    """Generics of the wrapper isp_replace_synth (lint/isp_replace_synth.vhd)."""
    return {"ImageWidth_g": str(w), "ImageHeight_g": str(h), "PixelBits_g": str(bits), "MaxGap_g": str(g),
            "RamRdLatency_g": str(lat), "EccPipeline_g": str(ecc), "ClkFreqHz_g": "150000000",
            "ScrubPeriodMs_g": str(period_ms)}


# isp_replace (TC-RPL-12): the bounds of every numeric generic, the scrubber free running and paced (1 ms), the
# bounds of the scrub period (1 ms, 2^30 - 1 ms) and of the clock of a paced scrubber (1 kHz, 2.14748e11 Hz)
CONFIGS += [
    # The default of the module: EccPipeline_g 1
    ("rpl_default", "isp_replace_synth", rpl(2048, 1024, 12, 2, ecc=1)),
    ("rpl_period_max", "isp_replace_synth", dict(rpl(40, 6, 12, 2), ScrubPeriodMs_g="1073741823")),
    ("rpl_clk_min", "isp_replace_synth", dict(rpl(40, 6, 12, 2, period_ms=1), ClkFreqHz_g="1000")),
    ("rpl_clk_max", "isp_replace_synth", dict(rpl(40, 6, 12, 2, period_ms=1), ClkFreqKHz_g="214748000")),
    ("rpl_min", "isp_replace_synth", rpl(3, 1, 1, 1)),
    ("rpl_max", "isp_replace_synth", rpl(65536, 1, 24, 7, 3, 2, 1)),
    ("rpl_h_max", "isp_replace_synth", rpl(15, 65536, 12, 7, 2, 1)),
]

# Configurations outside the declared ranges and the message their elaboration stops with
FSY_OK = {"ImageWidth_g": "8", "ImageHeight_g": "4", "PixelBits_g": "12"}
NEGATIVE = [
    ("fsy_width_0", "isp_frame_sync", dict(FSY_OK, ImageWidth_g="0"), 'generic "ImageWidth_g" is out of bounds'),
    ("fsy_width_65537", "isp_frame_sync", dict(FSY_OK, ImageWidth_g="65537"),
     "isp_frame_sync: ImageWidth_g must be 1 to 65536"),
    ("fsy_height_0", "isp_frame_sync", dict(FSY_OK, ImageHeight_g="0"), 'generic "ImageHeight_g" is out of bounds'),
    ("fsy_height_65537", "isp_frame_sync", dict(FSY_OK, ImageHeight_g="65537"),
     "isp_frame_sync: ImageHeight_g must be 1 to 65536"),
    ("fsy_bits_0", "isp_frame_sync", dict(FSY_OK, PixelBits_g="0"), 'generic "PixelBits_g" is out of bounds'),
    ("fsy_bits_65", "isp_frame_sync", dict(FSY_OK, PixelBits_g="65"), "isp_frame_sync: PixelBits_g must be 1 to 64"),
]

CRP_OK = crp(8, 6, 12, 2, 1, 4, 3, True)
NEGATIVE += [
    ("crp_width_65537", "isp_crop", dict(CRP_OK, ImageWidth_g="65537"), "ImageWidth_g must be 1 to 65536"),
    ("crp_height_65537", "isp_crop", dict(CRP_OK, ImageHeight_g="65537"), "ImageHeight_g must be 1 to 65536"),
    ("crp_bits_65", "isp_crop", dict(CRP_OK, PixelBits_g="65"), "PixelBits_g must be 1 to 64"),
    ("crp_roi_width_0", "isp_crop", dict(CRP_OK, RoiWidth_g="0"), 'generic "RoiWidth_g" is out of bounds'),
    ("crp_roi_height_0", "isp_crop", dict(CRP_OK, RoiHeight_g="0"), 'generic "RoiHeight_g" is out of bounds'),
    ("crp_roi_x_8", "isp_crop", dict(CRP_OK, RoiX_g="8", RoiWidth_g="1"), "isp_crop: RoiX_g must be 0 to"),
    ("crp_roi_y_6", "isp_crop", dict(CRP_OK, RoiY_g="6", RoiHeight_g="1"), "isp_crop: RoiY_g must be 0 to"),
    ("crp_roi_width_7", "isp_crop", dict(CRP_OK, RoiWidth_g="7"), "isp_crop: RoiWidth_g must be 1 to"),
    ("crp_roi_height_6", "isp_crop", dict(CRP_OK, RoiHeight_g="6"), "isp_crop: RoiHeight_g must be 1 to"),
]

WIN_OK = win(8, 6, 12, 3, 3, "replicate")
NEGATIVE += [
    ("win_x_17", "isp_window", dict(WIN_OK, WinX_g="17", ImageWidth_g="20"), "isp_window: WinX_g must be 1 to 16"),
    ("win_y_17", "isp_window", dict(WIN_OK, WinY_g="17", ImageHeight_g="20"), "isp_window: WinY_g must be 1 to 16"),
    ("win_width_below", "isp_window", dict(WIN_OK, ImageWidth_g="2"), "isp_window: ImageWidth_g must be WinX_g to"),
    ("win_height_below", "isp_window", dict(WIN_OK, ImageHeight_g="2"), "isp_window: ImageHeight_g must be WinY_g"),
    ("win_width_below_valid", "isp_window", dict(WIN_OK, ImageWidth_g="2", BorderMode_g="valid"),
     "isp_window: ImageWidth_g must be WinX_g to"),
    ("win_width_65537", "isp_window", dict(WIN_OK, ImageWidth_g="65537"), "ImageWidth_g must be"),
    ("win_bits_33", "isp_window", dict(WIN_OK, PixelBits_g="33"), "isp_window: PixelBits_g must be 1 to 32"),
    ("win_anchor_x", "isp_window", dict(WIN_OK, AnchorX_g="3"), "isp_window: AnchorX_g must be 0 to"),
    ("win_anchor_y", "isp_window", dict(WIN_OK, AnchorY_g="3"), "isp_window: AnchorY_g must be 0 to"),
    ("win_stride_x_17", "isp_window", dict(WIN_OK, StrideX_g="17"), "isp_window: StrideX_g must be 1 to 16"),
    ("win_stride_y_17", "isp_window", dict(WIN_OK, StrideY_g="17"), "isp_window: StrideY_g must be 1 to 16"),
    ("win_border", "isp_window", dict(WIN_OK, BorderMode_g="wrap"), "isp_window: BorderMode_g must be"),
    ("win_mirror_even", "isp_window", dict(WIN_OK, BorderMode_g="mirror", WinX_g="4"), "mirror needs an odd WinX_g"),
    ("win_mirror_anchor_x", "isp_window", dict(WIN_OK, BorderMode_g="mirror", AnchorX_g="0"),
     "mirror needs an odd WinX_g"),
    ("win_mirror_anchor_y", "isp_window", dict(WIN_OK, BorderMode_g="mirror", AnchorY_g="2"),
     "mirror needs an odd WinY_g"),
    ("win_ecc_2", "isp_window", dict(WIN_OK, EccPipeline_g="2"), "isp_window: EccPipeline_g must be 0 or 1"),
    ("win_resource", "isp_window", dict(WIN_OK, Resource_g="FIFO"), "isp_window: Resource_g must be AUTO, SRL or BRAM"),
    ("win_bram_narrow_case", "isp_window", dict(WIN_OK, Resource_g="bram", ImageWidth_g="3"),
     "isp_window: ImageWidth_g must be at least 3 + EccPipeline_g"),
    ("win_bram_narrow", "isp_window", dict(WIN_OK, Resource_g="BRAM", ImageWidth_g="3"),
     "isp_window: ImageWidth_g must be at least 3 + EccPipeline_g"),
]

CNV_OK = cnv(12, 3, 3, 16, True, 0)
NEGATIVE += [
    ("cnv_bits_33", "isp_conv_synth", dict(CNV_OK, PixelBits_g="33"), "isp_conv: PixelBits_g must be 1 to 32"),
    ("cnv_x_17", "isp_conv_synth", dict(CNV_OK, WinX_g="17"), "isp_conv: WinX_g must be 1 to 16"),
    ("cnv_y_17", "isp_conv_synth", dict(CNV_OK, WinY_g="17"), "isp_conv: WinY_g must be 1 to 16"),
    ("cnv_coef_bits_1", "isp_conv_synth", dict(CNV_OK, CoefBits_g="1"), "isp_conv: CoefBits_g must be 2 to 18"),
    ("cnv_coef_bits_19", "isp_conv_synth", dict(CNV_OK, CoefBits_g="19"), "isp_conv: CoefBits_g must be 2 to 18"),
    ("cnv_out_bits_65", "isp_conv_synth", dict(CNV_OK, OutBits_g="65"), "isp_conv: OutBits_g must be 0 or 1 to 64"),
    ("cnv_coef_fewer", "isp_conv_synth", dict(CNV_OK, CoefCount_g="-1"), "isp_conv: Coef_g must have"),
    ("cnv_coef_more", "isp_conv_synth", dict(CNV_OK, CoefCount_g="1"), "isp_conv: Coef_g must have"),
    ("cnv_coef_low", "isp_conv_synth", dict(CNV_OK, CoefOffset_g="-1"), "isp_conv: Coef_g values must be"),
    ("cnv_coef_high", "isp_conv_synth", dict(CNV_OK, CoefOffset_g="65536"), "isp_conv: Coef_g values must be"),
]

FLT_OK = flt(3, 3, "replicate", 16, True, 0)
NEGATIVE += [
    ("flt_x_17", "isp_filter2d_synth", dict(FLT_OK, WinX_g="17"), "WinX_g must be 1 to 16"),
    ("flt_coef_bits_19", "isp_filter2d_synth", dict(FLT_OK, CoefBits_g="19"), "isp_conv: CoefBits_g must be 2 to 18"),
    ("flt_border", "isp_filter2d_synth", dict(FLT_OK, BorderMode_g="wrap"), "isp_window: BorderMode_g must be"),
    ("flt_coef_fewer", "isp_filter2d_synth", dict(FLT_OK, CoefCount_g="-1"), "isp_conv: Coef_g must have"),
    ("flt_ecc_2", "isp_filter2d_synth", dict(FLT_OK, EccPipeline_g="2"), "isp_window: EccPipeline_g must be 0 or 1"),
    ("flt_resource", "isp_filter2d_synth", dict(FLT_OK, Resource_g="FIFO"),
     "isp_window: Resource_g must be AUTO, SRL or BRAM"),
]

BIN_OK = bin_(64, 32, 12, 2, 2, "valid")
NEGATIVE += [
    ("bin_x_17", "isp_bin", dict(BIN_OK, BinX_g="17"), "isp_bin: BinX_g must be 1 to 16"),
    ("bin_y_17", "isp_bin", dict(BIN_OK, BinY_g="17"), "isp_bin: BinY_g must be 1 to 16"),
    ("bin_bits_29", "isp_bin", dict(BIN_OK, PixelBits_g="29"), "isp_bin: PixelBits_g must be 1 to 28"),
    ("bin_mirror", "isp_bin", dict(BIN_OK, BorderMode_g="mirror"),
     "isp_bin: BorderMode_g must be valid, zero or replicate"),
    ("bin_width_below", "isp_bin", dict(BIN_OK, ImageWidth_g="1"), "isp_bin: ImageWidth_g must be BinX_g to 65536"),
    ("bin_width_65537", "isp_bin", dict(BIN_OK, ImageWidth_g="65537"),
     "isp_bin: ImageWidth_g must be BinX_g to 65536"),
    ("bin_height_below", "isp_bin", dict(BIN_OK, ImageHeight_g="1"),
     "isp_bin: ImageHeight_g must be BinY_g to 65536"),
    ("bin_ecc_2", "isp_bin", dict(BIN_OK, EccPipeline_g="2"), "isp_window: EccPipeline_g must be 0 or 1"),
    ("bin_resource", "isp_bin", dict(BIN_OK, Resource_g="FIFO"), "isp_window: Resource_g must be AUTO, SRL or BRAM"),
    ("bin_bram_narrow", "isp_bin", dict(BIN_OK, ImageWidth_g="7", Resource_g="BRAM"),
     "isp_bin: ImageWidth_g / BinX_g must be at least 3 + EccPipeline_g with Resource_g BRAM"),
]

RPL_OK = rpl(40, 6, 12, 2)
NEGATIVE += [
    ("rpl_gap_0", "isp_replace_synth", dict(RPL_OK, MaxGap_g="0"), "isp_replace: MaxGap_g must be 1 to 7"),
    ("rpl_gap_8", "isp_replace_synth", dict(RPL_OK, MaxGap_g="8"), "isp_replace: MaxGap_g must be 1 to 7"),
    ("rpl_width_2g", "isp_replace_synth", dict(RPL_OK, ImageWidth_g="4"),
     "isp_replace: ImageWidth_g must be 2 x MaxGap_g + 1 to 65536"),
    ("rpl_width_65537", "isp_replace_synth", dict(RPL_OK, ImageWidth_g="65537"),
     "isp_replace: ImageWidth_g must be 2 x MaxGap_g + 1 to 65536"),
    ("rpl_height_65537", "isp_replace_synth", dict(RPL_OK, ImageHeight_g="65537"),
     "isp_replace: ImageHeight_g must be 1 to 65536"),
    ("rpl_bits_25", "isp_replace_synth", dict(RPL_OK, PixelBits_g="25"), "isp_replace: PixelBits_g must be 1 to 24"),
    ("rpl_lat_4", "isp_replace_synth", dict(RPL_OK, RamRdLatency_g="4"),
     "isp_replace: RamRdLatency_g must be 1 to 3"),
    ("rpl_ecc_3", "isp_replace_synth", dict(RPL_OK, EccPipeline_g="3"), "isp_replace: EccPipeline_g must be 0 to 2"),
    ("rpl_period_negative", "isp_replace_synth", dict(RPL_OK, ScrubPeriodMs_g="-1"),
     "isp_replace: ScrubPeriod_g must be 0.0 or 0.001 to 1073741.823"),
    ("rpl_period_below", "isp_replace_synth", dict(RPL_OK, ScrubPeriodUs_g="500"),
     "isp_replace: ScrubPeriod_g must be 0.0 or 0.001 to 1073741.823"),
    ("rpl_period_above", "isp_replace_synth", dict(RPL_OK, ScrubPeriodMs_g="1073741823", ScrubPeriodUs_g="1000"),
     "isp_replace: ScrubPeriod_g must be 0.0 or 0.001 to 1073741.823"),
    ("rpl_clk_low", "isp_replace_synth", dict(RPL_OK, ClkFreqHz_g="999", ScrubPeriodMs_g="300"),
     "isp_replace: ClkFreqHz_g must be 1000.0 to 2.14748e11"),
    ("rpl_clk_high", "isp_replace_synth", dict(RPL_OK, ClkFreqKHz_g="214748001", ScrubPeriodMs_g="300"),
     "isp_replace: ClkFreqHz_g must be 1000.0 to 2.14748e11"),
]

PNT_OK = pnt(8, 6, 12, 12, 16, 28, 2, True)
NEGATIVE += [
    ("pnt_in_bits_65", "isp_point", dict(PNT_OK, InBits_g="65"), "Bits_g must be 1 to 64"),
    ("pnt_out_bits_33", "isp_point", dict(PNT_OK, OutBits_g="33"), "isp_point: OutBits_g must be 1 to 32"),
    ("pnt_gain_bits_19", "isp_point", dict(PNT_OK, GainBits_g="19"), "isp_point: GainBits_g must be 1 to 18"),
    ("pnt_max_shift_30", "isp_point", dict(PNT_OK, MaxShift_g="30"), "isp_point: MaxShift_g must be 0 to"),
    ("pnt_mult_stages_5", "isp_point", dict(PNT_OK, MultStages_g="5"), "isp_point: MultStages_g must be 1 to 4"),
    ("pnt_mult_stages_0", "isp_point", dict(PNT_OK, MultStages_g="0"), 'generic "MultStages_g" is out of bounds'),
    ("pnt_gain_65536", "isp_point", dict(PNT_OK, Gain_g="65536"), "isp_point: Gain_g must be 0 to"),
    ("pnt_low_4096", "isp_point", dict(PNT_OK, Low_g="4096"), "isp_point: Low_g must be 0 to"),
    ("pnt_high_4096", "isp_point", dict(PNT_OK, High_g="4096"), "isp_point: High_g must be -1 or"),
    ("pnt_high_minus_2", "isp_point", dict(PNT_OK, High_g="-2"), "isp_point: High_g must be -1 or"),
    ("pnt_shift_29", "isp_point", dict(PNT_OK, Shift_g="29"), "isp_point: Shift_g must be 0 to MaxShift_g"),
    ("pnt_offset_4096", "isp_point", dict(PNT_OK, Offset_g="4096"), "isp_point: Offset_g must lie in the range"),
    ("pnt_offset_minus_4097", "isp_point", dict(PNT_OK, Offset_g="-4097"), "isp_point: Offset_g must lie in the range"),
]


def run_synth(top, generics, out_file):
    cmd = ["ghdl", "--synth", "--std=08", "-frelaxed", f"-P{LIBS / 'olo'}", "--work=openisp",
           f"--workdir={LIBS / 'openisp'}"]
    cmd += [f"-g{name}={value}" for name, value in generics.items()]
    cmd.append(top)
    with open(out_file, "w") as netlist:
        res = subprocess.run(cmd, stdout=netlist, stderr=subprocess.PIPE, text=True)
    return res.returncode, res.stderr


def synth(name, top, generics, work):
    code, log = run_synth(top, generics, work / f"{name}.vhd")
    # Inferred latches are reported as "latch" warnings
    latches = [line for line in log.splitlines() if re.search(r"\blatch\b", line, re.IGNORECASE)]
    errors = [line for line in log.splitlines() if "error" in line.lower() or "exception" in line.lower()]
    ok = code == 0 and not latches and not errors
    print(f"{name}: {'OK' if ok else 'FAILED'}", flush=True)
    for line in (errors + latches)[:20]:
        print("  " + line)
    return ok


def outside(name, top, generics, message, work):
    code, log = run_synth(top, generics, work / f"{name}.vhd")
    ok = code != 0 and message in log
    print(f"{name}: {'stopped as expected' if ok else 'FAILED'}", flush=True)
    if not ok:
        for line in log.splitlines()[:20]:
            print("  " + line)
    return ok


def main():
    if not CONFIGS and not NEGATIVE:
        print("no synthesis configurations yet")
        return
    if not LIBS.exists():
        raise SystemExit("compiled libraries not found, run: python run.py --compile")
    names = set(sys.argv[1:])
    # Wrappers of entities whose generics GHDL cannot set on the command line
    for wrapper in sorted((ROOT / "lint").glob("*_synth.vhd")):
        res = subprocess.run(["ghdl", "-a", "--std=08", "-frelaxed", f"-P{LIBS / 'olo'}", "--work=openisp",
                              f"--workdir={LIBS / 'openisp'}", str(wrapper)], capture_output=True, text=True)
        if res.returncode != 0:
            raise SystemExit(f"{wrapper.name}: analysis failed\n{res.stderr}")
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        results = [synth(n, t, g, work) for n, t, g in CONFIGS if not names or n in names]
        results += [outside(n, t, g, m, work) for n, t, g, m in NEGATIVE if not names or n in names]
    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
