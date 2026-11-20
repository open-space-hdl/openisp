# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""Compares the port traces of two trees that ran the same tests with `python run.py --port-trace`.

Usage: python tools/trace_compare.py <tree A> <tree B> [<pattern of test names>]

The test outputs of vunit_out/test_output are matched by test: VUnit names a test output after the test and ends the
name with the SHA-1 of the test name (40 hexadecimal digits); on Windows it shortens the readable part by the length of
the output path, so that the same test can have different directory names in two trees. The tool therefore matches the
outputs by that hash and takes the test names from vunit_out/test_output/test_name_to_path_mapping.txt. For every test
(all of them, or those whose name matches the pattern, for example "openisp.isp_conv_tb.*"), the file ghdl/port.vcd of
tree A is compared with that of tree B, without the header lines ($date, $version, $comment). A test whose trace is
missing in either tree, or has no time step, counts as missing; test outputs of earlier runs count as well, so both
trees start from the same tests (a new vunit_out, or the pattern). The summary gives the identical, different and
missing traces per testbench; the exit code is 0 only when every trace is identical.

A typical use: two worktrees of the commits before and after a change of the RTL, the same tests run in both with
`--port-trace`; identical traces show that the change keeps every cycle at the signals of the testbenches.
"""

import fnmatch
import re
import sys
from collections import defaultdict
from pathlib import Path

HASH = re.compile(r"([0-9a-f]{40})$")


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
    """{hash: (test name, test output directory)} of a tree, for the tests whose name matches the pattern."""
    root = Path(tree) / "vunit_out" / "test_output"
    names = {}
    mapping = root / "test_name_to_path_mapping.txt"
    if mapping.exists():
        for line in mapping.read_text(encoding="utf-8").splitlines():
            if " " in line:
                directory, name = line.split(" ", 1)
                names[directory] = name
    out = {}
    for d in root.iterdir():
        m = HASH.search(d.name)
        if d.is_dir() and m:
            name = names.get(d.name, d.name)
            if fnmatch.fnmatchcase(name, pattern):
                out[m.group(1)] = (name, d)
    return out


def main():
    if len(sys.argv) not in (3, 4):
        sys.exit(__doc__)
    pattern = sys.argv[3] if len(sys.argv) == 4 else "*"
    a, b = outputs(sys.argv[1], pattern), outputs(sys.argv[2], pattern)
    stats = defaultdict(lambda: [0, 0, 0, 0])      # identical, different, missing, time steps
    for key in sorted(set(a) | set(b), key=lambda k: (a.get(k) or b.get(k))[0]):
        name = (a.get(key) or b.get(key))[0]
        bench = name.split(".")[1] if name.count(".") >= 2 else name
        va = a[key][1] / "ghdl" / "port.vcd" if key in a else None
        vb = b[key][1] / "ghdl" / "port.vcd" if key in b else None
        if va is None or vb is None or not va.exists() or not vb.exists():
            stats[bench][2] += 1
            print(f"missing    {name}")
            continue
        x, y = body(va), body(vb)
        if not any(line.startswith("#") for line in x) or not any(line.startswith("#") for line in y):
            stats[bench][2] += 1
            print(f"missing    {name} (a trace without time steps)")
            continue
        if x == y:
            stats[bench][0] += 1
            stats[bench][3] += sum(1 for line in x if line.startswith("#"))
        else:
            stats[bench][1] += 1
            k = next((i for i, (p, q) in enumerate(zip(x, y)) if p != q), min(len(x), len(y)))
            print(f"different  {name}, line {k}: {x[k] if k < len(x) else 'end'} / {y[k] if k < len(y) else 'end'}")
    total = [0, 0, 0, 0]
    for bench in sorted(stats):
        s = stats[bench]
        print(f"{bench}: {s[0]} identical ({s[3]} time steps), {s[1]} different, {s[2]} missing")
        total = [t + v for t, v in zip(total, s)]
    print(f"all: {total[0]} identical ({total[3]} time steps), {total[1]} different, {total[2]} missing")
    sys.exit(0 if total[1] == 0 and total[2] == 0 and total[0] > 0 else 1)


if __name__ == "__main__":
    main()
