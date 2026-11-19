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
GHDL 6.0.0 cannot override real generics with -g: an entity with real generics is synthesised through a wrapper in
lint/ that takes integer generics and converts them.
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
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        results = [synth(n, t, g, work) for n, t, g in CONFIGS if not names or n in names]
        results += [outside(n, t, g, m, work) for n, t, g, m in NEGATIVE if not names or n in names]
    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
