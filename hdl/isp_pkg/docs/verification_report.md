# isp_pkg: Verification Report

## 1. Test results

Run on 2026-11-19 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM (commit 4f1e13b), Open Logic 4.8.0-ft.2:
`python run.py "*isp_pkg*"`. QuestaSim runs with the release regression.

| Test | Passed |
| --- | --- |
| `test_package` (TC-PKG-01) | 1 of 1 |
| TC-PKG-02 (`lint/synth_check.py`): the package synthesised with `isp_frame_sync` in its five configurations | 5 of 5 |

## 2. Summary

The four flag constants equal their literals. `ispPosWidth(n)` equals the number of bits of n - 1, at least 1, for
every n from 1 to 65536. `ispIsImageStart` is true exactly for a first beat with the flags "01" or "11", and false
for every metavalue in the first-beat flag and in each bit of the flags.

## 3. Requirement coverage

| Requirement | Test case | Status |
| --- | --- | --- |
| PKG-01 | TC-PKG-01 | Passed |
| PKG-02 | TC-PKG-01 | Passed |
| PKG-03 | TC-PKG-01 | Passed |
| PKG-04 | TC-PKG-02 | Passed |

## 4. Findings

| Finding | Correction |
| --- | --- |
| `ispIsImageStart` compared only bit 0 of the flags (the flags "01" and "11" are the values with bit 0 set), so the flags "X1" would have started an image, against PKG-03. Found while writing the test of metavalues in each bit, before the first simulation | The function compares both bits with the constants `SeqFirst_c` and `SeqOnly_c`; the test covers a metavalue in each bit |
