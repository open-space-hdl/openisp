# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configuration of isp_pkg_tb (verification plan, section 3): the table of the output dimensions of a window
filter and of a bin that test_dimensions compares with the functions of the package. The expected values come from
the reference model (tools/isp_model.py): the window generator Window (its number of reference pixels along an axis)
and bin_count, the definition of a bin of isp_bin."""

import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "tools"))

from isp_model import Window, bin_count, write_parity  # noqa: E402

SIZES = list(range(1, 41)) + [255, 256, 257, 4095, 4096, 4097, 65535, 65536]
BORDERS = ("valid", "zero", "replicate", "mirror")


def window_count(n, win, stride, border):
    """Reference pixels along an axis of n pixels; the border mode valid has none when the window is larger."""
    if border == "valid" and n < win:
        return 0
    return Window(n, 1, 1, win, 1, 0, 0, stride, 1, border).wo


def configure(lib, out_dir):
    path = Path(out_dir) / "isp_pkg" / "dimensions.txt"
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = []
    for n in SIZES:
        for win in range(1, 17):
            for stride in range(1, 17):
                for border in BORDERS:
                    lines.append(f"W {n} {win} {stride} {border} {window_count(n, win, stride, border)}")
        for factor in range(1, 17):
            for border in BORDERS[:3]:
                lines.append(f"B {n} {factor} {border} {bin_count(n, factor, border)}")
    path.write_text("\n".join(lines) + "\n", encoding="ascii", newline="\n")
    lib.test_bench("isp_pkg_tb").test("test_dimensions").add_config(
        name="sweep", generics={"DimFile_g": path.as_posix()})

    # PKG-08: the parity bit after a write, for every pattern of byte strobes, register widths from 0 to 32 bits (in
    # one byte, at the byte boundaries, the widths of the registers of the modules) and random values; rows
    # "bits old data parity strobes expected" with the words and the strobes in binary
    rng = random.Random(8)
    rows = []
    for bits in (0, 1, 2, 7, 8, 9, 15, 16, 17, 18, 23, 24, 25, 31, 32):
        for ena in range(16):
            values = [(0, 0), (0xFFFFFFFF, 0), (0, 0xFFFFFFFF)] + \
                     [(rng.getrandbits(32), rng.getrandbits(32)) for _ in range(5)]
            for old, data in values:
                for par in (0, 1):
                    exp = write_parity(old, data, par, ena, bits)
                    rows.append(f"{bits} {old:032b} {data:032b} {par} {ena:04b} {exp}")
    ppath = Path(out_dir) / "isp_pkg" / "write_parity.txt"
    ppath.write_text("\n".join(rows) + "\n", encoding="ascii", newline="\n")
    lib.test_bench("isp_pkg_tb").test("test_write_parity").add_config(
        name="table", generics={"ParFile_g": ppath.as_posix()})
