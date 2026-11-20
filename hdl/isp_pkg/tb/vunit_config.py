# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configuration of isp_pkg_tb (verification plan, section 3): the table of the output dimensions of a window
filter and of a bin that test_dimensions compares with the functions of the package. The expected values come from
the reference model (tools/isp_model.py): the window generator Window (its number of reference pixels along an axis)
and bin_count, the definition of a bin of isp_bin."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "tools"))

from isp_model import Window, bin_count  # noqa: E402

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
