# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""Compares the port traces of two trees that ran the same tests with `python run.py --port-trace`.

Usage: python tools/trace_compare.py <tree A> <tree B> [<glob of test outputs>]

For every test output directory of vunit_out/test_output (all of them, or those matching the glob, for example
"openisp.isp_conv_tb.*"), the file ghdl/port.vcd of tree A is compared with that of tree B, without the header lines
($date, $version, $comment). A test whose trace is missing in either tree counts as missing. The summary gives the
identical, different and missing traces per testbench; the exit code is 0 only when every trace is identical.

A typical use: two worktrees of the commits before and after a change of the RTL, the same tests run in both with
`--port-trace`; identical traces show that the change keeps every cycle at the signals of the testbenches.
"""

import sys
from collections import defaultdict
from pathlib import Path


def body(path):
    """The lines of a VCD without the header blocks that differ between runs."""
    out, skip = [], False
    for line in path.read_text().splitlines():
        if line.startswith(("$date", "$version", "$comment")):
            skip = True
        if not skip:
            out.append(line)
        if skip and "$end" in line:
            skip = False
    return out


def outputs(tree, pattern):
    root = Path(tree) / "vunit_out" / "test_output"
    return {d.name: d for d in root.glob(pattern) if d.is_dir()}


def main():
    if len(sys.argv) not in (3, 4):
        sys.exit(__doc__)
    pattern = sys.argv[3] if len(sys.argv) == 4 else "*"
    a, b = outputs(sys.argv[1], pattern), outputs(sys.argv[2], pattern)
    stats = defaultdict(lambda: [0, 0, 0, 0])      # identical, different, missing, time steps
    for name in sorted(set(a) | set(b)):
        bench = name.split(".")[1] if "." in name else name
        va = a[name] / "ghdl" / "port.vcd" if name in a else None
        vb = b[name] / "ghdl" / "port.vcd" if name in b else None
        if va is None or vb is None or not va.exists() or not vb.exists():
            stats[bench][2] += 1
            print(f"missing    {name}")
            continue
        x, y = body(va), body(vb)
        if x == y:
            stats[bench][0] += 1
            stats[bench][3] += sum(1 for line in x if line.startswith("#"))
        else:
            stats[bench][1] += 1
            k = next((i for i, (p, q) in enumerate(zip(x, y)) if p != q), min(len(x), len(y)))
            print(f"different  {name}, line {k}: {x[k] if k < len(x) else 'end'} / {y[k] if k < len(y) else 'end'}")
    total = [0, 0, 0]
    for bench in sorted(stats):
        s = stats[bench]
        print(f"{bench}: {s[0]} identical ({s[3]} time steps), {s[1]} different, {s[2]} missing")
        total = [total[0] + s[0], total[1] + s[1], total[2] + s[2]]
    print(f"all: {total[0]} identical, {total[1]} different, {total[2]} missing")
    sys.exit(0 if total[1] == 0 and total[2] == 0 and total[0] > 0 else 1)


if __name__ == "__main__":
    main()
