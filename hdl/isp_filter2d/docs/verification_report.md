# isp_filter2d: Verification Report

## 1. Test results

Run on 2026-11-20 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM (commit 4f1e13b), Open Logic 4.8.0-ft.2:
`python run.py -p 4` on 2e4971c, 542 of 542 tests passed (32 of them `isp_filter2d`), 0 skipped.
QuestaSim runs with the release regression (with and without code coverage).

The status-output audit moved the probe of the open image of test_input_stream into the malformed streams of
`tools/isp_tbgen.py`, which every module uses: `python run.py -p 4` on 2026-11-20 on commit 399d8b9, 542 of 542 tests
passed (32 of them `isp_filter2d`), 0 skipped.

The configuration checks of the audit of every module (section 7) came later: `python run.py -p 4` on 2026-11-20 on
commit 4cef90a, 601 of 601 tests passed (32 of them `isp_filter2d`), 0 skipped; `lint/synth_check.py` (TC-FLT-07)
passed.

| Test | Configurations | Passed |
| --- | --- | --- |
| `test_static` (TC-FLT-01) | 14 | 14 |
| `test_input_stream` (TC-FLT-02) | 3 | 3 |
| `test_runtime` (TC-FLT-03) | 5 | 5 |
| `test_errors` (TC-FLT-04) | 3 | 3 |
| `test_reset` (TC-FLT-05) | 5 | 5 |
| `test_rate` (TC-FLT-06) | 2 | 2 |
| TC-FLT-07 (`lint/synth_check.py`) | 6 configurations synthesise without latches; 6 generics out of range stop the elaboration with the message of the part that checks them | 12 |
| TC-FLT-08 (`lint/vivado_ooc.py`) | Section 5 | Not run |

## 2. Summary

Every output pixel of every test equals the reference model `filter2d`, which feeds the windows of the model `window`
into the kernel of the model `conv`, with and without gaps of the source and stalls of the sink; the contract checker
of the sink found the output contract (Wo x Ho) in every test.

- The filters of the suite: the MTF kernels 3 x 3 (gain 16, border mode replicate) and 5 x 5 (mirror, on block RAM;
  zero, with 16-bit pixels, 12-bit coefficients and an output saturated to 16 bits), the border mode valid, a window
  of 4 x 2 with the anchor (1, 0) and the stride 3 x 2, the two filters of `isp_bin` (4 x 1 and 1 x 4 with a stride
  of 4, coefficients of 1), a separable kernel as two filters in series (1 x 5, then 5 x 1 at full precision between
  them), the largest window (16 x 16, 32-bit pixels, 18-bit run-time coefficients), and the low bounds: an image of
  one pixel with a window of one pixel (1-bit pixels, 2-bit coefficients, a 1-bit output), and an image as large as
  its 3 x 3 window with 1-bit pixels, `EccPipeline_g` 0 and shift registers. Every `test_static` contains images in
  five divisions into packets, a pause of the source, an image of the largest pixels (the largest sums, the
  saturation) and an image of zeros (16 x 16: two divisions and the image of the largest pixels).
- The input stream: images cut short and completed at the next image start, pixels without an image start, wrong end
  flags, random packets; `Err_Framing` counts and `Stat_ImageOpen`, also probed while an image is open, equal the
  model.
- The kernel through the slave of the filter: random sets, the sets of both bounds, read back; `CTRL.HOLD` keeps the
  set of an image while a new one is written; a set written during an image applies from the next image start of the
  window stream.
- Errors: single and double errors injected into every line buffer of the window (two data bits, or the data bit and
  the overall parity bit for 1-bit pixels): a single error leaves the output unchanged and pulses `Stat_EccSec`, a
  double error changes the windows that contain the pixel and their output pixels and pulses `Stat_EccDed`; a parity
  error of a coefficient makes the next image use the coefficients of the generic, with one `Err_Config`, until the
  coefficient is written. Every pulse reached the ports of the filter, in the numbers of the model, which differ
  between the three outputs (3, 2 and 1 pulses), so that an exchange of two of them shows.
- Resets idle, held and running, of one and two cycles: during a line, during the windows of the lower border, and
  while the sink held the output and the kernel held windows. The next images are correct, the registers return to
  their reset values.
- The control outputs carry no metavalue after the first reset, no output pixel carries a metavalue, and `Out_Valid`
  and the status outputs are 0 after every reset.

Measured timing (test_rate, images back to back from the reset, the sink never stalls):

| Quantity | Bound | Design value | Measured |
| --- | --- | --- | --- |
| Hold cycles between the first pixels of two lines (FLT-PF-01) | As `isp_window`: Rr (WIN-PF-01) | Rr: 1 (3 x 3), 2 (5 x 5); between the first two lines of an image that follows an image Rb x (W + Rr) + Rr | At most 1 and 2 cycles |
| Image period (FLT-PF-01) | As `isp_window`: (H + Rb) x (W + Rr) + 8 (WIN-PF-02) | (H + Rb) x (W + Rr): 119 (3 x 3) and 144 (5 x 5) cycles | 119 and 144 cycles for every interval after the first |
| Latency (FLT-PF-02) | log2ceil(T) + 9: 13 and 14 cycles | 6 + log2ceil(T) to 8 + log2ceil(T): 10 to 12 and 11 to 13 cycles | 10 to 11 and 11 to 13 cycles, every output pixel of four images |

## 3. Generic ranges

The generics go to `isp_window` and `isp_conv`, whose reports cover their ranges in full; this bench simulates the
values below through the filter.

| Generic | Declared range | Simulated | Synthesised |
| --- | --- | --- | --- |
| `ImageWidth_g`, `ImageHeight_g` | as `isp_window` | 1 x 1 (window 1 x 1), 3 x 3 (window 3 x 3), 10 x 7 to 18 x 17 | 1024 x 1024 |
| `PixelBits_g` | 1 to 32 | 1, 12, 16, 30 (the second filter of `separable`), 32 | 12 |
| `WinX_g`, `WinY_g` | 1 to 16 | 1, 2, 3, 4, 5, 16 | 1, 2, 3, 4, 5; 17 stops the elaboration |
| `AnchorX_g`, `AnchorY_g` | as `isp_window` | 0, 1, the middle | 0, 1, the middle |
| `StrideX_g`, `StrideY_g` | 1 to 16 | 1, 2, 3, 4 | 1, 2, 3, 4 |
| `BorderMode_g` | valid, zero, replicate, mirror | every value | every value; an unknown mode stops the elaboration |
| `EccPipeline_g` | as `isp_window` | 0, 1 | 1; 2 stops the elaboration |
| `Resource_g` | AUTO, SRL, BRAM | every value | AUTO; an unknown value stops the elaboration |
| `CoefBits_g` | 2 to 18 | 2, 12, 16, 18 | 2, 16; 19 stops the elaboration |
| `Coef_g` | as `isp_conv` | the MTF kernels, ones, random and asymmetric sets | both bounds, ones; T - 1 values stop the elaboration |
| `RuntimeCoef_g` | false, true | both | both |
| `OutBits_g` | 0, 1 to 64 | 0, 1, 14, 16 | 0, 14 |

## 4. Mutations

Run on 2026-11-20 on commit 2e4971c in a worktree of its own (`git diff --quiet` before and after every mutant), with
11 tests: the 5 of `mtf3`, test_static of `strided`, `valid`, `separable` and `bin_h`, test_errors of `ecc` and
test_rate of `rate_3`. Every one of the 8 mutants of the plan (section 6) fails at least one test, and the tests that
fail include those the plan expects. A mutant that changes several places of the source carries all of them in one
run.

A first run on 69c2e15 kept two mutants alive, the exchange of `Stat_EccSec` and `Stat_EccDed` and `Stat_ImageOpen`
not connected; both were gaps of the bench (section 7). An audit of the status outputs of every module then found the
counts of `Stat_EccDed` and `Err_Config` equal in every test, a third gap of the same kind; its mutant is the
exchange of the two.

The mutation run was repeated on 2026-11-20 on commit 399d8b9, after the probe of the open image moved into the shared
stream generator (section 7), with the same 11 tests: every result is the same.

| Mutation | Result | Failing tests |
| --- | --- | --- |
| None (reference) | passes (11 tests) | - |
| Out_Last and Out_User of the window not passed to the kernel (constant) | killed by 11 of 11 tests | test_errors, test_input_stream, test_rate, test_reset, test_runtime, test_static |
| The window elements reversed in order at the connection | killed by 6 of 11 tests | test_errors, test_reset, test_runtime, test_static |
| ErrInj_Valid not connected | killed by 2 of 11 tests | test_errors |
| Err_Config of the kernel not connected | killed by 2 of 11 tests | test_errors |
| The register slave of the kernel not connected (reads 0) | killed by 4 of 11 tests | test_errors, test_reset, test_runtime |
| Stat_EccSec and Stat_EccDed of the window exchanged | killed by 2 of 11 tests | test_errors |
| Stat_EccDed of the window and Err_Config of the kernel exchanged | killed by 2 of 11 tests | test_errors |
| Stat_ImageOpen of the window not connected | killed by 1 of 11 tests | test_input_stream |

## 5. Synthesis and timing

Not run yet: TC-FLT-08 runs out-of-context synthesis and implementation at 150 MHz on the device of the Timing level
(architecture of the suite, section 10); the run is open (roadmap). The script `lint/vivado_ooc.py` is ready with the
configuration `flt_mtf5` (5 x 5 mirror, 12-bit pixels, 16-bit run-time coefficients, 4096 pixels per line).

The GHDL synthesis of TC-FLT-07 shows that the module is synthesisable in the configurations of the suite with both
values of `RuntimeCoef_g` and every border mode, without latches; it gives no timing.

## 6. Requirement coverage

| Requirement | Test cases | Status |
| --- | --- | --- |
| FLT-IF-01, FLT-IF-02 | TC-FLT-01 to 06 | Passed |
| FLT-IF-03 | TC-FLT-03 | Passed |
| FLT-IF-04 | TC-FLT-02, 04 | Passed |
| FLT-IF-05 | TC-FLT-05 | Passed |
| FLT-FN-01, FLT-FN-02 | TC-FLT-01 (every configuration) | Passed |
| FLT-FN-03 | TC-FLT-01 to 03 | Passed |
| FLT-PF-01, FLT-PF-02 | TC-FLT-06 | Passed |
| FLT-ER-01 | TC-FLT-02, 05 | Passed |
| FLT-FT-01 | TC-FLT-04, 05 | Passed |
| FLT-CF-01, FLT-CF-02 | TC-FLT-07 | Passed |
| FLT-CF-03 | TC-FLT-08 | Open (section 5) |

## 7. Findings

| Finding | Correction |
| --- | --- |
| The first mutation run kept two mutants alive. The exchange of `Stat_EccSec` and `Stat_EccDed` survived because `test_errors` injected as many single as double errors, so both counts stayed equal; `Stat_ImageOpen` not connected survived because every probe of the source came after a complete image, where the flag is 0 | `test_errors` injects a third single error; `test_input_stream` starts with an image cut after half of its pixels and probes `Stat_ImageOpen` while it is open. Both mutants are killed (section 4). No change of the RTL |
| An audit of the status outputs found the counts of `Stat_EccDed` and `Err_Config` equal (2 and 2) in every test of `test_errors`, so an exchange of the two would survive | `test_errors` runs one image with the parity error of a coefficient: `Stat_EccSec` 3, `Stat_EccDed` 2, `Err_Config` 1 pulses; the plan has the mutant of the exchange (section 4) |
| The configurations of the plan held no low bound of the image size, `PixelBits_g`, `EccPipeline_g` or `Resource_g` | Configurations `min` and `small` (plan, section 2), `mtf5_mirror` on block RAM |
| `lint/vivado_ooc.py` wrote string generics without quotes (`BorderMode_g`) | The script quotes strings; the top levels of the earlier configurations are unchanged |
| The status-output audit found the probe of an open image in this bench only; the other benches probed `Stat_ImageOpen` after complete images only | The probe is part of the malformed streams of `tools/isp_tbgen.py` for every module (`open_image_probe`, with a random generator of its own); test_input_stream uses it there instead of its own cut image. The mutation run on 399d8b9 gives the same results (section 4) |
| The audit of the configuration checks found that `EccPipeline_g` 2 and an unknown `Resource_g`, which the filter passes to `isp_window`, were not checked by a module of the suite (FLT-CF-01) | `isp_window` checks both; the negatives `flt_ecc_2` and `flt_resource` show its messages through the filter (the synthesis wrapper takes both generics). The bench is unchanged |
