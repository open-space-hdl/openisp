# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""Tests of the check of the pull-request test list (tools/ci_subset.py) on made-up test names."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from ci_subset import check, read_patterns  # noqa: E402

TESTS = [
    "openisp.isp_pkg_tb.test_package",
    "openisp.isp_a_tb.small.test_static",
    "openisp.isp_a_tb.small.test_reset",
    "openisp.isp_a_tb.w65536.test_static",
    "openisp.isp_b_tb.exhaustive.test_exhaustive",
    "openisp.isp_b_tb.exhaustive_p6.test_exhaustive",
]


def test_complete_subset_passes():
    selected, failures = check(TESTS, ["openisp.isp_pkg_tb.*", "openisp.isp_a_tb.small.*",
                                       "openisp.isp_b_tb.exhaustive.*"])
    assert failures == []
    assert selected == [TESTS[0], TESTS[1], TESTS[2], TESTS[4]]


def test_pattern_without_match_fails():
    _, failures = check(TESTS, ["openisp.isp_*", "openisp.isp_a_tb.renamed.*"])
    assert "pattern matches no test: openisp.isp_a_tb.renamed.*" in failures


def test_test_in_no_configuration_fails():
    _, failures = check(TESTS, ["openisp.isp_pkg_tb.*", "openisp.isp_a_tb.small.test_static",
                                "openisp.isp_b_tb.exhaustive.*"])
    assert failures == ["test in no configuration of the subset: isp_a_tb.test_reset"]


def test_full_tier_configuration_fails():
    _, failures = check(TESTS, ["openisp.isp_pkg_tb.*", "openisp.isp_a_tb.*", "openisp.isp_b_tb.*"])
    assert failures == ["configuration of the full tier in the subset: openisp.isp_a_tb.w65536.test_static",
                        "configuration of the full tier in the subset: openisp.isp_b_tb.exhaustive_p6.test_exhaustive"]


def test_comments_and_blank_lines(tmp_path):
    f = tmp_path / "list.txt"
    f.write_text("# comment\n\nopenisp.isp_a_tb.small.*  # trailing\n  openisp.isp_pkg_tb.*\n", encoding="utf-8")
    assert read_patterns(f) == ["openisp.isp_a_tb.small.*", "openisp.isp_pkg_tb.*"]
