# isp_conv: Verification Report

## 1. Test results

Run on 2026-11-19 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM (commit 4f1e13b), Open Logic 4.8.0-ft.2:
`python run.py -p 4`, 425 of 425 tests passed (122 of them `isp_conv`), 0 skipped.
QuestaSim runs with the release regression (with and without code coverage).

| Test | Configurations | Passed |
| --- | --- | --- |
| `test_static` (TC-CNV-01) | 42 (with the sweeps) | 42 |
| `test_runtime` (TC-CNV-02) | 10 | 10 |
| `test_hold` (TC-CNV-03) | 4 | 4 |
| `test_parity` (TC-CNV-04) | 42 (with the sweeps) | 42 |
| `test_registers` (TC-CNV-05) | 6 | 6 |
| `test_flag_coincidence` (TC-CNV-06) | 1 | 1 |
| `test_exhaustive` (TC-CNV-07) | 2 | 2 |
| `test_packets` (TC-CNV-08) | 6 | 6 |
| `test_reset` (TC-CNV-09) | 6 | 6 |
| `test_rate` (TC-CNV-10) | 3 | 3 |
| TC-CNV-11 (`lint/synth_check.py`) | 8 configurations synthesise without latches; 10 generics out of range stop the elaboration with a message naming the generic | 18 |
| TC-CNV-12 (`lint/vivado_ooc.py`) | Section 5 | Not run |

## 2. Summary

Every output pixel of every test equals the reference model, which computes the sum in unbounded integers, with and
without gaps of the source and stalls of the sink; the contract checker of the sink found the output contract in every
test with well-formed window streams.

- The arithmetic: the MTF kernels 3 x 3 (gain 16) and 5 x 5, the sum of four ones of the binning, every window size
  n x (17 - n), every depth of the adder tree (0 to 8 levels, with a full and a partly filled last level), the
  smallest configuration (1-bit pixels, 2-bit coefficients, 1-bit output) and the widest (16 x 16 windows of 32-bit
  pixels with 18-bit coefficients and a 64-bit output), the coefficient bounds -2^17 and 2^17 - 1. Every image
  contains the windows of largest and of zero elements, of the largest and of the most negative sum, and a window of
  nonzero elements whose sum is exactly 0. `test_exhaustive` ran every coefficient pair of 3-bit coefficients (64
  sets) as a run-time set over an image of every pair of 3-bit elements, at the full precision and saturated to 3
  bits: 8192 pixels, each equal to the model.
- The output width: the full precision (`OutBits_g` 0) and the saturation below it (1, 3, 12 bits), at it (F = 52)
  and above it (64 bits).
- Run-time sets: random sets, the sets of both bounds, a set with the sign of every coefficient changed, every
  coefficient read back sign-extended; a set written during an image applies from the next image.
- `CTRL.HOLD`: a set written over two images is not taken while `HOLD` is 1 and is taken as a whole after it; a
  register of bad parity is neither taken nor reported while `HOLD` is 1.
- Parity: the injection into each coefficient register in turn (for more than 16 coefficients the first, the last and
  eight random ones) makes every image use the generic with one `Err_Config` until the register is written; the
  injection into `CTRL` with `CTRL.HOLD` 1 makes every image start take the held set with one `Err_Config` until
  `CTRL` is written; two injections in one set, a second injection that restores the parity, an index of T or above,
  an injection without the strobe of byte 0 and injections with `RuntimeCoef_g` false have no effect beyond the model.
- Registers: identification, the window and the widths, the reset values of all coefficients (the generic,
  sign-extended), every single byte strobe on the first, the middle and the last coefficient, read-only registers,
  the gaps, the address above the last coefficient and the end of the address space, the sticky flag. Every access
  was answered with OKAY.
- Packets: a "01" packet after "00" packets, single-window packets, `In_Last` on every beat, other flags on the later
  beats of a packet, images back to back: the set changes only at an image start.
- Resets idle, held and running, of one and two cycles, in the middle of an image and between the image start and the
  first output pixel: the registers hold the generic again and the next images are correct.
- The control outputs carry no metavalue after the first reset, no output pixel carries a metavalue, and `Out_Valid`
  and `Err_Config` are 0 after every reset.

Measured timing (test_rate) and coincidence (test_flag_coincidence):

| Quantity | Bound | Design value | Measured |
| --- | --- | --- | --- |
| Throughput (CNV-PF-01) | One window per cycle | One per cycle | `In_Ready` high for every window of three images back to back, for T = 9, 25 and 256 |
| Latency (CNV-PF-02) | 3 + log2ceil(T) cycles | 3 + log2ceil(T) | 7, 8 and 11 cycles for T = 9, 25 and 256, for each of the 288 pixels |
| Clear of the flag in the cycle of its event (CNV-RG-02) | The flag stays set | The event wins | `ERR_CONFIG`: 12 steps, with the clear from two cycles before to nine cycles after the pulse |

## 3. Generic ranges

| Generic | Declared range | Simulated | Synthesised |
| --- | --- | --- | --- |
| `PixelBits_g` | 1 to 32 | 1, 3, 6, 8, 12, 16, 31, 32 | 1, 12, 32; 33 stops the elaboration |
| `WinX_g`, `WinY_g` | 1 to 16 | every value | 1, 3, 4, 5, 16; 17 stops the elaboration |
| `CoefBits_g` | 2 to 18 | 2, 3, 6, 8, 16, 17, 18 | 2, 16, 18; 1 and 19 stop the elaboration |
| `Coef_g` | T values of -2^(`CoefBits_g` - 1) to 2^(`CoefBits_g` - 1) - 1 | both bounds of 18-bit coefficients, 0, 1, -1, the MTF kernels, random sets of every simulated width | both bounds; T - 1 and T + 1 values and a value beyond either bound stop the elaboration |
| `RuntimeCoef_g` | false, true | both | both |
| `OutBits_g` | 0, 1 to 64 | 0, 1, 3, 12, 52 (F), 64 | 0, 1, 12, 64; 65 stops the elaboration |

## 4. Mutations

Run on 2026-11-19 on commit acb925d in a worktree of its own (`git diff --quiet` before and after every mutant), with
the 24 tests of the configurations `mtf3`, `mtf5_const`, `ones4`, `exhaustive`, `exhaustive_sat` and `rate_3`,
test_static of `taps_5` and `taps_33` and test_registers of `wide`. Every mutant of the plan (section 6) fails at
least one test, and the tests that fail include those the plan expects.

| Mutation | Result | Failing tests |
| --- | --- | --- |
| None (reference) | passes (24 tests) | - |
| A negative sum not set to 0 (wraps) | killed by 19 of 24 tests | test_exhaustive, test_flag_coincidence, test_hold, test_packets, test_parity, test_rate, test_registers, test_reset, test_runtime, test_static |
| No saturation below the full precision (truncation) | killed by 6 of 24 tests | test_exhaustive, test_packets, test_parity, test_registers, test_reset, test_static |
| An element multiplied as a signed number (its top bit as sign) | killed by 24 of 24 tests | test_exhaustive, test_flag_coincidence, test_hold, test_packets, test_parity, test_rate, test_registers, test_reset, test_runtime, test_static |
| The last product dropped when a level of the adder tree has an odd count | killed by 12 of 24 tests | test_flag_coincidence, test_hold, test_packets, test_parity, test_rate, test_registers, test_reset, test_runtime, test_static |
| The working set loaded at the first beat of every packet, not only at the image start | killed by 7 of 24 tests | test_flag_coincidence, test_hold, test_packets, test_parity, test_registers, test_runtime |
| CTRL.HOLD without effect | killed by 2 of 24 tests | test_hold, test_parity |
| No parity check of the coefficients | killed by 5 of 24 tests | test_flag_coincidence, test_hold, test_parity, test_registers |
| No parity check of CTRL | killed by 1 of 24 tests | test_parity |
| No Err_Config pulse | killed by 5 of 24 tests | test_flag_coincidence, test_hold, test_parity, test_registers |
| INJECT.INDEX ignored (always coefficient 0) | killed by 1 of 24 tests | test_parity |
| A coefficient read back without sign extension | killed by 6 of 24 tests | test_registers, test_reset, test_runtime |
| Out_Last one stage early | killed by 24 of 24 tests | test_exhaustive, test_flag_coincidence, test_hold, test_packets, test_parity, test_rate, test_registers, test_reset, test_runtime, test_static |
| A stage that does not wait for the common enable (the adder tree advances in every cycle) | killed by 20 of 24 tests | test_hold, test_packets, test_parity, test_registers, test_reset, test_runtime, test_static |

## 5. Synthesis and timing

Not run yet: TC-CNV-12 runs out-of-context synthesis and implementation at 150 MHz on the device of the Timing level
(architecture of the suite, section 10); the run is open (roadmap). The script `lint/vivado_ooc.py` is ready with the
configurations `cnv_mtf3`, `cnv_mtf5` (12-bit pixels, 16-bit run-time coefficients), `cnv_max` (16 x 16 at run time) and
`cnv_bin4` (four ones).

The GHDL synthesis of TC-CNV-11 shows that the module is synthesisable at the bounds of its generics with both values
of `RuntimeCoef_g`, without latches; it gives no timing.

## 6. Requirement coverage

| Requirement | Test cases | Status |
| --- | --- | --- |
| CNV-IF-01, CNV-IF-02 | TC-CNV-01 to 10 | Passed |
| CNV-IF-03 | TC-CNV-05 | Passed |
| CNV-IF-04 | TC-CNV-04 | Passed |
| CNV-IF-05 | TC-CNV-09 and review (one clock, the reset sampled in the clocked process only) | Passed |
| CNV-FN-01 | TC-CNV-01, 02, 07 | Passed |
| CNV-FN-02 | TC-CNV-01, 08 | Passed |
| CNV-FN-03 | TC-CNV-01 | Passed |
| CNV-FN-04 | TC-CNV-02, 03, 08 | Passed |
| CNV-FN-05 | TC-CNV-01, 08 | Passed |
| CNV-PF-01, CNV-PF-02 | TC-CNV-10 | Passed |
| CNV-ER-01, CNV-ER-02 | TC-CNV-04 | Passed |
| CNV-FT-01 | TC-CNV-04, 09 and review: the stages hold no state between windows; the working set is loaded with every image start | Passed |
| CNV-FT-02 | TC-CNV-04 | Passed |
| CNV-FT-03 | TC-CNV-09 and the monitor of every test | Passed |
| CNV-RG-01, CNV-RG-03 | TC-CNV-02, 05 | Passed |
| CNV-RG-02 | TC-CNV-05, 06 | Passed |
| CNV-RG-04 | TC-CNV-04 | Passed |
| CNV-CF-01, CNV-CF-02 | TC-CNV-11 | Passed |
| CNV-CF-03 | TC-CNV-12 | Open (section 5) |

## 7. Findings

| Finding | Correction |
| --- | --- |
| The synthesis check with a `Coef_g` of T - 1 values stopped with an index error in the function that builds the coefficient set of the generic, before the check of CNV-CF-01 could name the generic | The function fills the missing values with 0, so that the elaboration reaches the check and stops with its message |
| `test_static` sent one image as a single packet with the flags "11", which `isp_window` never delivers; the contract checker of the sink rejected it. `test_reset` resumed the interrupted image after the reset, which a window stream does not do either, since `isp_window` is reset with the module and restarts at an image start | `test_static` sends window streams of one packet per line (the other packet shapes stay in `test_packets`, with the checker off); `test_reset` stops the window stream at the reset and sends the next image; the plan states it. No change of the RTL |
| `lint/vivado_ooc.py` read one declaration per line and wrote generic values as plain text: the port `Out_Data` of `isp_conv` continues on a second line, and `Coef_g` is a vector | The script joins continued declarations and writes lists as named aggregates; the top levels of the earlier configurations are unchanged, byte for byte |
