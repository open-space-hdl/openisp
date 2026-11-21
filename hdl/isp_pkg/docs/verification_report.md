# isp_pkg: Verification Report

## 1. Test results

Run on 2026-11-19 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM (commit 4f1e13b), Open Logic 4.8.0-ft.2:
`python run.py "*isp_pkg*"`. QuestaSim Pro Microchip Edition 2024.3 ran the release regression with code coverage on
2026-11-21 on commit b50efd1: `python run.py --questa --coverage -p 1`, 669 of 669 tests passed (3 of them `isp_pkg`), 0
skipped; the code coverage is in [docs/coverage.md](../../../docs/coverage.md).

The output dimensions of a window filter and of a bin (PKG-06, PKG-07) came later, with their use in `isp_window` and
`isp_bin`: `python run.py -p 4` on 2026-11-20 on commit 2d4b4c8, 602 of 602 tests passed (2 of them `isp_pkg`), 0
skipped; `lint/synth_check.py` passed; the test files of every module are identical to those before the change (600
tests of the eight modules).

The parity bit of a register write (PKG-08) came with the fail-safe partial writes of `isp_conv`, `isp_point` and
`isp_crop`: `python run.py -p 4` on 2026-11-20 on commit e9116a7 (with develop fbc18fd), 669 of 669 tests passed (3 of
them `isp_pkg`), 0 skipped; `lint/synth_check.py` passed.

| Test | Passed |
| --- | --- |
| `test_package` (TC-PKG-01) | 1 of 1 |
| `test_dimensions` (TC-PKG-03) | 1 of 1 |
| `test_write_parity` (TC-PKG-04) | 1 of 1 |
| TC-PKG-02 (`lint/synth_check.py`): the package synthesised with `isp_frame_sync` in its five configurations | 5 of 5 |

## 2. Summary

The four flag constants equal their literals. `ispPosWidth(n)` equals the number of bits of n - 1, at least 1, for
every n from 1 to 65536. `ispIsImageStart` is true exactly for a first beat with the flags "01" or "11", and false
for every metavalue in the first-beat flag and in each bit of the flags. `ispConvFullBits` and `ispConvOutBits` equal
their definitions for every pixel width, coefficient width and number of taps of their range. `ispWinOut` equals the
number of reference pixels of the window generator of the model for every window size and stride from 1 to 16, every
border mode and 48 sizes from 1 to 65536 (49152 values), and `ispBinOut` equals the definition of a bin of the model
for every factor from 1 to 16 and the three border modes of `isp_bin` (2304 values).

`ispWriteParity` equals the parity bit of the reference model (`write_parity` of `tools/isp_model.py`, written from the
definition: the parity of the resulting value, with the syndrome before the write on top unless every byte with bits is
written) in each of the 3840 rows of its table: every pattern of the four byte strobes, the register widths 0, 1, 2, 7,
8, 9, 15, 16, 17, 18, 23, 24, 25, 31 and 32 bits, both parity bits, the words of zeros and of ones and five random pairs
of words for each width and pattern. The table holds the full write (also of a register of 0 bits, which gives 0), the
write that keeps a byte with bits with and without a mismatch, the write of only bytes without bits and the write
without a strobe (both leave the parity bit unchanged).

## 3. Requirement coverage

| Requirement | Test case | Status |
| --- | --- | --- |
| PKG-01 | TC-PKG-01 | Passed |
| PKG-02 | TC-PKG-01 | Passed |
| PKG-03 | TC-PKG-01 | Passed |
| PKG-04 | TC-PKG-02 | Passed |
| PKG-05 | TC-PKG-01 | Passed |
| PKG-06, PKG-07 | TC-PKG-03 | Passed |
| PKG-08 | TC-PKG-04; in the modules TC-CNV-04, TC-PNT-05, TC-CRP-05 | Passed |

## 4. Mutations

Run on 2026-11-20 on commit 2189d17 in a worktree of its own (`git diff --quiet` before and after every mutant), with
the 3 tests of `isp_pkg_tb` and test_static of the configurations `rep3` and `valid3` of `isp_window` and `bin2_zero`
and `bin2_valid` of `isp_bin`, which use the dimension functions. The package and its bench are the same at e9116a7.
Every mutant fails at least one test of `isp_pkg_tb`: `test_dimensions` for the dimension functions, `test_write_parity`
for `ispWriteParity`. The three mutants of the dimension functions ran first on 2d4b4c8 (6 tests) and failed the same
tests. The five mutants of `ispWriteParity` run as well in the mutation runs of `isp_conv`, `isp_point` and `isp_crop`,
which use it (their reports, section 4).

| Mutation | Result | Failing tests |
| --- | --- | --- |
| None (reference) | passes (7 tests) | - |
| ispWinOut rounds down in the border modes other than valid | killed by 2 of 7 tests | test_dimensions, test_static |
| ispWinOut one reference pixel more in the border mode valid | killed by 3 of 7 tests | test_dimensions, test_static |
| ispBinOut with the stride 1 instead of the factor | killed by 3 of 7 tests | test_dimensions, test_static |
| The parity of a kept byte taken from the write data | killed by 1 of 7 tests | test_write_parity |
| The parity of a written byte taken from the stored bits | killed by 1 of 7 tests | test_write_parity |
| A write that keeps a byte with bits sets the parity for the resulting value (the re-seal before PKG-08) | killed by 1 of 7 tests | test_write_parity |
| A write of every byte with bits keeps the syndrome | killed by 1 of 7 tests | test_write_parity |
| A write of only bytes without bits sets the parity for the stored value | killed by 1 of 7 tests | test_write_parity |

## 5. Findings

| Finding | Correction |
| --- | --- |
| `ispIsImageStart` compared only bit 0 of the flags (the flags "01" and "11" are the values with bit 0 set), so the flags "X1" would have started an image, against PKG-03. Found while writing the test of metavalues in each bit, before the first simulation | The function compares both bits with the constants `SeqFirst_c` and `SeqOnly_c`; the test covers a metavalue in each bit |
| The user guide (section 5, step 1) and the roadmap named functions of `isp_pkg` for the output dimensions of the modules, from which an integrator computes the generics of the next module of a chain; the package had none, and `isp_window` and `isp_bin` computed their dimensions with formulas of their own | `ispWinOut` and `ispBinOut` (PKG-06, PKG-07); `isp_window` and `isp_bin` use them, so that the generics of an integrator equal those of the modules by construction; the user guide names the functions |
| The architecture listed only the constants and the functions of PKG-01 to PKG-03; the functions of PKG-05 to PKG-07 came with the modules that use them and were not entered. Found while adding `ispWriteParity` | The contents table of the architecture lists every constant and function with its requirement, and the table of use names every module that uses one |
