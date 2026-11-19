# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""Checks the test list of the pull-request CI (pr_tests.txt) against the tests of the regression.

The pull-request CI runs the tests that match the VUnit patterns of pr_tests.txt (`python run.py --subset
pr_tests.txt`); the full regression runs on pushes to develop, release/* and main and on pull requests into main.
The check fails when:

- a pattern matches no test (a renamed configuration or test);
- a test of a testbench runs in no configuration of the subset;
- the subset contains a configuration of the full tier only (FULL_TIER).

`python tools/ci_subset.py --check` lists the tests with `python run.py --list` and exits with 1 on a failure.
`python tools/ci_subset.py --list` prints the tests of the subset.
"""

import argparse
import collections
import subprocess
import sys
from fnmatch import fnmatchcase
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SUBSET_FILE = ROOT / "pr_tests.txt"

# Configurations that run in the full tier only: images of 65536 pixels per line or of 65536 lines and the
# exhaustive configurations of more than a minute
FULL_TIER = ("*65536*", "exhaustive_p6")


def read_patterns(path):
    """The VUnit patterns of the file: one per line, '#' starts a comment."""
    patterns = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.split("#", 1)[0].strip()
        if line:
            patterns.append(line)
    return patterns


def list_tests():
    """The names of all tests of the regression, <library>.<testbench>.<configuration>.<test>."""
    out = subprocess.run([sys.executable, str(ROOT / "run.py"), "--list"], cwd=ROOT, capture_output=True,
                         text=True, check=True).stdout
    return [ln.strip() for ln in out.splitlines() if ln.startswith("openisp.")]


def select(tests, patterns):
    """The tests that match a pattern, and the patterns that match none (VUnit matches with fnmatch)."""
    selected = [t for t in tests if any(fnmatchcase(t, p) for p in patterns)]
    unmatched = [p for p in patterns if not any(fnmatchcase(t, p) for t in tests)]
    return selected, unmatched


def check(tests, patterns):
    """The failures of the rules of the module docstring."""
    selected, unmatched = select(tests, patterns)
    failures = [f"pattern matches no test: {p}" for p in unmatched]
    functions = collections.defaultdict(list)
    for t in tests:
        lib, bench, *_, test = t.split(".")
        functions[(bench, test)].append(t)
    chosen = set(selected)
    failures += [f"test in no configuration of the subset: {b}.{t}" for (b, t), names in sorted(functions.items())
                 if not chosen.intersection(names)]
    for t in selected:
        parts = t.split(".")
        if len(parts) == 4 and any(fnmatchcase(parts[2], f) for f in FULL_TIER):
            failures.append(f"configuration of the full tier in the subset: {t}")
    return selected, failures


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="check the subset, exit 1 on a failure")
    parser.add_argument("--list", action="store_true", help="print the tests of the subset")
    parser.add_argument("--file", type=Path, default=SUBSET_FILE, help="pattern file (default pr_tests.txt)")
    args = parser.parse_args()
    tests = list_tests()
    patterns = read_patterns(args.file)
    selected, failures = check(tests, patterns)
    if args.list:
        print("\n".join(selected))
    for f in failures:
        print(f)
    print(f"{args.file.name}: {len(patterns)} patterns, {len(selected)} of {len(tests)} tests")
    if args.check and failures:
        sys.exit(1)


if __name__ == "__main__":
    main()
