# isp_pkg: Verification Report

## 1. Test results

Run on 2026-11-19 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM (commit 4f1e13b), Open Logic 4.8.0-ft.2:
`python run.py "*isp_pkg*"`. QuestaSim runs with the release regression.

The output dimensions of a window filter and of a bin (PKG-06, PKG-07) came later, with their use in `isp_window` and
`isp_bin`: `python run.py -p 4` on 2026-11-20 on commit 2d4b4c8, 602 of 602 tests passed (2 of them `isp_pkg`), 0
skipped; `lint/synth_check.py` passed; the test files of every module are identical to those before the change (600
tests of the eight modules).

| Test | Passed |
| --- | --- |
| `test_package` (TC-PKG-01) | 1 of 1 |
| `test_dimensions` (TC-PKG-03) | 1 of 1 |
| TC-PKG-02 (`lint/synth_check.py`): the package synthesised with `isp_frame_sync` in its five configurations | 5 of 5 |

## 2. Summary

The four flag constants equal their literals. `ispPosWidth(n)` equals the number of bits of n - 1, at least 1, for
every n from 1 to 65536. `ispIsImageStart` is true exactly for a first beat with the flags "01" or "11", and false
for every metavalue in the first-beat flag and in each bit of the flags. `ispConvFullBits` and `ispConvOutBits` equal
their definitions for every pixel width, coefficient width and number of taps of their range. `ispWinOut` equals the
number of reference pixels of the window generator of the model for every window size and stride from 1 to 16, every
border mode and 48 sizes from 1 to 65536 (49152 values), and `ispBinOut` equals the definition of a bin of the model
for every factor from 1 to 16 and the three border modes of `isp_bin` (2304 values).

## 3. Requirement coverage

| Requirement | Test case | Status |
| --- | --- | --- |
| PKG-01 | TC-PKG-01 | Passed |
| PKG-02 | TC-PKG-01 | Passed |
| PKG-03 | TC-PKG-01 | Passed |
| PKG-04 | TC-PKG-02 | Passed |
| PKG-05 | TC-PKG-01 | Passed |
| PKG-06, PKG-07 | TC-PKG-03 | Passed |

## 4. Mutations

Run on 2026-11-20 on commit 2d4b4c8 in a worktree of its own (`git diff --quiet` before and after every mutant), with
the 2 tests of `isp_pkg_tb` and test_static of the configurations `rep3` and `valid3` of `isp_window` and `bin2_zero`
and `bin2_valid` of `isp_bin`, which use the dimension functions. Every mutant fails at least `test_dimensions`.

| Mutation | Result | Failing tests |
| --- | --- | --- |
| None (reference) | passes (6 tests) | - |
| ispWinOut rounds down in the border modes other than valid | killed by 2 of 6 tests | test_dimensions, test_static |
| ispWinOut one reference pixel more in the border mode valid | killed by 3 of 6 tests | test_dimensions, test_static |
| ispBinOut with the stride 1 instead of the factor | killed by 3 of 6 tests | test_dimensions, test_static |

## 5. Findings

| Finding | Correction |
| --- | --- |
| `ispIsImageStart` compared only bit 0 of the flags (the flags "01" and "11" are the values with bit 0 set), so the flags "X1" would have started an image, against PKG-03. Found while writing the test of metavalues in each bit, before the first simulation | The function compares both bits with the constants `SeqFirst_c` and `SeqOnly_c`; the test covers a metavalue in each bit |
| The user guide (section 5, step 1) and the roadmap named functions of `isp_pkg` for the output dimensions of the modules, from which an integrator computes the generics of the next module of a chain; the package had none, and `isp_window` and `isp_bin` computed their dimensions with formulas of their own | `ispWinOut` and `ispBinOut` (PKG-06, PKG-07); `isp_window` and `isp_bin` use them, so that the generics of an integrator equal those of the modules by construction; the user guide names the functions |
