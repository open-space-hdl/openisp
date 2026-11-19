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
