# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""Compliance matrix of OpenISP.

Usage: python tools/compliance.py [--check]
No ECSS or CCSDS standard covers image signal processing. The reference of OpenISP is its own requirements
specification: the core requirements of docs/requirements.md (IDs ISP-<GROUP>-<NN>), mapped to the owning modules by
the requirement traceability matrix of docs/architecture.md (section 10). Every requirement of a module specification
(hdl/<module>/docs/specification.md) names the core requirements it implements in the last column of its table, or
"none".

The script reads the matrix, the module requirements and the test cases of every verification_plan.md (test and
requirement IDs) and writes docs/compliance.md: for every core requirement of the matrix the module requirements that
trace to it and the test cases that verify them. With --check the file is not written; the exit code is 1 when a core
requirement in the scope of the core has no test case, when a module requirement has no test case, when a module
requirement names a core requirement that the matrix does not contain, when a test case of a plan is not run or when
docs/compliance.md is not current. A module without a verification plan is in development: its requirements are
listed, but not counted as gaps. Before the matrix exists (docs/architecture.md without section 10), the references to
core requirements are not checked.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs" / "compliance.md"
ARCHITECTURE = ROOT / "docs" / "architecture.md"
# Core requirement of docs/requirements.md
CORE_RE = re.compile(r"\bISP-[A-Z]+-\d{2}\b")
# Module requirement of a specification
REQ_RE = re.compile(r"^[A-Z]+(-[A-Z0-9]+)*-\d{2}$")


def table_rows(text):
    """Rows of markdown tables as lists of cells (header and separator rows included)."""
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("|") and line.endswith("|"):
            yield [c.strip() for c in line.strip("|").split("|")]


def expand_ids(cell):
    """Requirement IDs of a test row: 'WIN-IF-01, WIN-FN-01 to 03, WIN-ER-01, 02' -> full list."""
    ids = []
    last = None
    for part in [p.strip() for p in cell.split(",")]:
        m = re.match(r"^([A-Z]+(?:-[A-Z0-9]+)*-)(\d+)(?:\s+to\s+(?:[A-Z]+(?:-[A-Z0-9]+)*-)?(\d+))?", part)
        if m:
            prefix, first = m.group(1), int(m.group(2))
            last_n = int(m.group(3)) if m.group(3) else first
            width = len(m.group(2))
            ids += [f"{prefix}{n:0{width}d}" for n in range(first, last_n + 1)]
            last = (prefix, width)
            continue
        m = re.match(r"^(\d+)(?:\s+to\s+(\d+))?$", part)
        if m and last:
            prefix, width = last
            first = int(m.group(1))
            last_n = int(m.group(2)) if m.group(2) else first
            ids += [f"{prefix}{n:0{width}d}" for n in range(first, last_n + 1)]
    return ids


def load_requirements():
    """Requirements of the module specifications: ID -> (module, core requirement IDs)."""
    reqs = {}
    for spec in sorted(ROOT.glob("hdl/*/docs/specification.md")):
        module = spec.parent.parent.name
        for row in table_rows(spec.read_text(encoding="utf-8")):
            if len(row) >= 3 and REQ_RE.match(row[0]) and not CORE_RE.fullmatch(row[0]):
                reqs[row[0]] = (module, set(CORE_RE.findall(row[-1])))
    return reqs


def load_tests():
    """Test cases of the verification plans: test ID -> requirement IDs. Also returns the test names of the plans
    that no testbench of the repository runs."""
    tests = {}
    names = set()
    for plan in sorted(ROOT.glob("hdl/*/docs/verification_plan.md")):
        for row in table_rows(plan.read_text(encoding="utf-8")):
            if len(row) >= 3 and row[0].startswith("`test_"):
                m = re.search(r"\((TC-[A-Z]+-\d+)\)", row[0])
                tid = m.group(1) if m else row[0]
                tests.setdefault(tid, set()).update(expand_ids(row[-1]))
                names.add(row[0].split("`")[1])
    run_names = set()
    for tb in ROOT.glob("hdl/*/tb/*.vhd"):
        run_names.update(re.findall(r'run\("(test_\w+)"\)', tb.read_text(encoding="utf-8")))
    return tests, sorted(names - run_names)


def load_matrix():
    """Rows of the traceability matrix (architecture section 10): core requirement, title, owner, ..."""
    if not ARCHITECTURE.exists():
        return []
    text = ARCHITECTURE.read_text(encoding="utf-8")
    start = text.find("## 10 Requirement traceability matrix")
    if start < 0:
        return []
    end = text.find("## 11 ", start)
    section = text[start:end if end >= 0 else len(text)]
    rows = []
    for row in table_rows(section):
        if len(row) >= 3 and CORE_RE.fullmatch(row[0]):
            rows.append(row[:3])
    return rows


def test_key(tid):
    parts = tid.split("-")
    return (parts[1] if len(parts) > 1 else tid, int(parts[2]) if len(parts) > 2 and parts[2].isdigit() else 0)


def main():
    reqs = load_requirements()
    tests, not_run = load_tests()
    matrix = load_matrix()
    lines = [
        "# OpenISP: Compliance Matrix",
        "",
        "Generated by `python tools/compliance.py` from the requirement traceability matrix of the architecture",
        "(section 10), the requirements of the module specifications and the test cases of the module verification",
        "plans. `python tools/compliance.py --check` fails when a core requirement or a module requirement has no test",
        "case, or when a test case of a plan is not run by a testbench.",
        "",
        "## 1. Core requirements",
        "",
        "No ECSS or CCSDS standard covers image signal processing; the reference of OpenISP is its own requirements",
        "specification (`docs/requirements.md`). A core requirement is listed with every module requirement that",
        "implements it, and with the test cases that verify these module requirements.",
        "",
        "| Core requirement | Title | Owner | Module requirements | Test cases | Status |",
        "| --- | --- | --- | --- | --- | --- |",
    ]
    missing = []
    counts = {}
    known = {row[0] for row in matrix}
    for core_id, title, owner in matrix:
        req_ids = sorted(r for r, (_, refs) in reqs.items() if core_id in refs)
        test_ids = sorted({t for t, ids in tests.items() if ids & set(req_ids)}, key=test_key)
        if owner.startswith("Planned"):
            status = "Planned"
        elif owner.startswith("User"):
            status = "User obligation"
        elif test_ids:
            status = "Verified"
        else:
            status = "Not traced"
            missing.append(core_id)
        counts[status] = counts.get(status, 0) + 1
        lines.append(f"| {core_id} | {title} | {owner} | {', '.join(req_ids) or '-'} | "
                     f"{', '.join(test_ids) or '-'} | {status} |")
    summary = "; ".join(f"{k.lower()}: {v}" for k, v in sorted(counts.items())) or "none"
    lines += [
        "",
        f"Core requirements: {len(matrix)}; {summary}.",
        "",
        "## 2. Module requirements",
        "",
        "Requirements of the module specifications and the test cases that verify them (requirements without a core",
        "requirement included).",
        "",
        "| Module | Requirements | Verified by a test case | Without a test case |",
        "| --- | --- | --- | --- |",
    ]
    covered = set().union(*tests.values()) if tests else set()
    planned = {p.parent.parent.name for p in ROOT.glob("hdl/*/docs/verification_plan.md")}
    untested = sorted(r for r, (m, _) in reqs.items() if r not in covered and m in planned)
    unknown = sorted({(r, c) for r, (_, refs) in reqs.items() for c in refs if c not in known}) if matrix else []
    for module in sorted({m for m, _ in reqs.values()}):
        ids = [r for r, (m, _) in reqs.items() if m == module]
        if module in planned:
            gaps = [r for r in ids if r not in covered]
            lines.append(f"| `{module}` | {len(ids)} | {len(ids) - len(gaps)} | {', '.join(gaps) or '-'} |")
        else:
            lines.append(f"| `{module}` | {len(ids)} | - | In development: no verification plan yet |")
    lines += [
        "",
        f"Requirements: {len(reqs)}; without a test case: {len(untested)}; test cases of the plans not run by a "
        f"testbench: {len(not_run)}.",
        "",
    ]
    text = "\n".join(lines)
    stale = False
    if "--check" not in sys.argv:
        OUT.write_text(text, encoding="utf-8", newline="\n")
        print(f"written {OUT.relative_to(ROOT)}")
    elif not OUT.exists() or OUT.read_text(encoding="utf-8") != text:
        stale = True
        print(f"{OUT.relative_to(ROOT)} is not current: run python tools/compliance.py")
    for c in missing:
        print(f"core requirement not traced: {c}")
    for r in untested:
        print(f"requirement without a test case: {r}")
    for r, c in unknown:
        print(f"requirement {r} names {c}, which is not in the traceability matrix")
    for n in not_run:
        print(f"test case of a plan not run by a testbench: {n}")
    failed = missing or untested or unknown or not_run or stale
    sys.exit(1 if failed and "--check" in sys.argv else 0)


if __name__ == "__main__":
    main()
