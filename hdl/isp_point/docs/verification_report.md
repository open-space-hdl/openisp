# isp_point: Verification Report

## 1. Test results

Run on 2026-11-19 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM (commit 4f1e13b), Open Logic 4.8.0-ft.2:
`python run.py -p 3`, 175 of 175 tests passed (51 of them `isp_point`), 0 skipped. QuestaSim runs with the release
regression (with and without code coverage).

The configuration `w1_h4` (`ImageWidth_g` 1 in a small image, test_static) came later, with the pull-request tests of
the CI, which run the low bound of every generic: `python run.py -p 4` on 2026-11-19 on commit 30a4acc, 510 of 510
tests passed (52 of them `isp_point`), 0 skipped.

The status-output audit added a probe of `Stat_ImageOpen` while an image is open to test_input_stream:
`python run.py -p 4` on 2026-11-20 on commit 399d8b9, 542 of 542 tests passed (52 of them `isp_point`), 0 skipped.

| Test | Configurations | Passed |
| --- | --- | --- |
| `test_static` (TC-PNT-01) | 15 | 15 |
| `test_input_stream` (TC-PNT-02) | 5 | 5 |
| `test_runtime` (TC-PNT-03) | 4 | 4 |
| `test_hold` (TC-PNT-04) | 1 | 1 |
| `test_parity` (TC-PNT-05) | 7 | 7 |
| `test_registers` (TC-PNT-06) | 8 | 8 |
| `test_flag_coincidence` (TC-PNT-07) | 1 | 1 |
| `test_exhaustive` (TC-PNT-08) | 1 | 1 |
| `test_reset` (TC-PNT-09) | 5 | 5 |
| `test_rate` (TC-PNT-10) | 5 | 5 |
| TC-PNT-11 (`lint/synth_check.py`) | 7 configurations synthesise without latches; 13 generics out of range stop the elaboration with a message naming the generic | 20 |
| TC-PNT-12 (`lint/vivado_ooc.py`) | Section 5 | Not run (licence) |

## 2. Summary

Every output pixel of every test equals the reference model, which computes the operation in unbounded integers, with
and without gaps of the source and stalls of the sink; the contract checker of the sink found the output contract in
every test.

- The arithmetic: a bit shift, a dark level with a gain of 1.2, both thresholds active, the neutral set, the widest
  configuration (64-bit input pixels, 32-bit output pixels, an 18-bit gain, shifts up to 83) and the narrowest (one
  bit each), the parameters of the generics at their bounds (-2^31, 2^18 - 1, a shift of 50, 2^31 - 1, full scale).
  `test_exhaustive` ran every offset (-16 to 15), gain (0 to 7) and shift (0 to 8 and 127; above `MaxShift_g` = 6
  taken as 6) of a 4-bit configuration as a run-time set over all 16 pixel values, with the thresholds 0 / 15, 2 / 13
  and `Low` above `High`: 40960 pixels, each equal to the model.
- Run-time sets: random sets, the gains 0, 1 and the largest, the shifts 0, `MaxShift_g`, `MaxShift_g` + 1 and 127
  (taken as `MaxShift_g`; in `shift_limit` with `MaxShift_g` 8 far below the width of the product, so that the limit
  changes the result), the most negative and the largest offset, `Low` above and equal to `High`, every register
  read back; a set written during an image applies from the next image.
- `CTRL.HOLD`: a set written over two images is not taken while `HOLD` is 1 and is taken as a whole after it; a
  register of bad parity is neither taken nor reported while `HOLD` is 1.
- Parity: the injection into each of the six parameter registers makes every image use the generics with one
  `Err_Config` until the register is written; the injection into `CTRL` with `CTRL.HOLD` 1 makes every image start
  take the held set with one `Err_Config` until `CTRL` is written; two injections at once, a second injection that
  restores the parity, an injection without the strobe of byte 0 and injections with `Runtime_g` false have no effect
  beyond the model.
- Registers: identification, dimensions and widths, the reset values (also `HIGH` from the sentinel -1 and
  `OFFSET_HI` as the sign of the offset), every single byte strobe on every parameter register with random data and
  its read-back (the offset sign-extended, the other registers zero-extended), read-only registers and unused
  addresses, the sticky flags. Every access was answered with OKAY.
- `Stat_ImageOpen` is 1 while an image is open (an image cut after half of its pixels) and 0 after complete images.
- Resets idle, held and running in the middle of an image, of one and of two cycles: the registers hold the generics
  again and the next images are correct.
- The control outputs carry no metavalue after the first reset, and `Out_Valid`, `Err_Framing`, `Err_Config` and
  `Stat_ImageOpen` are 0 after every reset.

Measured timing (test_rate) and coincidence (test_flag_coincidence):

| Quantity | Bound | Design value | Measured |
| --- | --- | --- | --- |
| Throughput (PNT-PF-01) | One pixel per cycle | One per cycle | `In_Ready` high for every beat of three images back to back, for every `MultStages_g` |
| Latency (PNT-PF-02) | `MultStages_g` + 5 cycles | `MultStages_g` + 5 | 6, 7, 8 and 9 cycles for `MultStages_g` 1 to 4, for each of the 72 pixels of phase 1 |
| Clear of a flag in the cycle of its event (PNT-RG-02) | The flag stays set | The event wins | `ERR_FRAMING` and `ERR_CONFIG`: 12 steps each, with the clear before, in and after the cycle of the pulse |

## 3. Generic ranges

| Generic | Declared range | Simulated | Synthesised |
| --- | --- | --- | --- |
| `ImageWidth_g`, `ImageHeight_g` | 1 to 65536 | 1 (width: `w1_h65536` and `w1_h4`), 2, 3, 4, 6, 16, 65536 | 1, 64, 4096, 65536; 65537 stops the elaboration |
| `InBits_g` | 1 to 64 | 1, 4, 8, 12, 16, 32, 64 | 1, 16, 32, 64; 65 stops the elaboration |
| `OutBits_g` | 1 to 32 | 1, 4, 8, 12, 32 | 1, 12, 32; 33 stops the elaboration |
| `GainBits_g` | 1 to 18 | 1, 3, 16, 18 | 1, 16, 18; 19 stops the elaboration |
| `MaxShift_g` | 0 to `InBits_g` + `GainBits_g` + 1 | 0, 6, 8, 9, 28, 32, 50, 83 | 0, 3, 32, 50, 83; above the bound stops the elaboration |
| `MultStages_g` | 1 to 4 | every value | 1, 2, 3, 4; 0 and 5 stop the elaboration |
| `Runtime_g` | false, true | both | both |
| `Offset_g`, `Gain_g`, `Shift_g`, `Low_g`, `High_g` | Specification, section 4 | the bounds and typical values | the bounds; values out of range stop the elaboration |

## 4. Mutations

Run on 2026-11-19 on commit d2a9a6b in a worktree of its own (`git diff --quiet` before and after every mutant), with
the 14 tests of the configurations `runtime`, `runtime_rate`, `exhaustive`, `shift_limit`, test_static of
`dark_gain` and `clamp`, and test_rate of `stages_3`. Every mutant of the plan (section 6) fails at least one test; the
tests that fail are those the plan expects. The mutant that drops the top bit of the gain did not compile in its
first form (an ambiguous concatenation); it was repaired and run alone on the same commit (reference run passed
again). The first mutation run, on 3c5cc2c, kept the mutant without the limit of the shift alive (section 7).

The mutant `Stat_ImageOpen` tied to 0 came with the status-output audit (section 7) and ran alone on 2026-11-20 on
commit 399d8b9 with the same 14 tests; the reference run passed again.

| Mutation | Result | Failing tests |
| --- | --- | --- |
| None (reference) | passes (14 tests) | - |
| No lower clamp | killed by 9 of 14 tests | test_exhaustive, test_hold, test_parity, test_registers, test_reset, test_runtime, test_static |
| No upper clamp | killed by 8 of 14 tests | test_exhaustive, test_hold, test_parity, test_registers, test_runtime, test_static |
| A logical instead of an arithmetic shift | killed by 6 of 14 tests | test_exhaustive, test_hold, test_parity, test_runtime, test_static |
| The offset not sign-extended | killed by 5 of 14 tests | test_exhaustive, test_parity, test_runtime, test_static |
| The top bit of the gain dropped | killed by 3 of 14 tests | test_exhaustive, test_hold, test_runtime |
| A shift above MaxShift_g not limited | killed by 2 of 14 tests | test_exhaustive, test_runtime |
| CTRL.HOLD without effect | killed by 2 of 14 tests | test_hold, test_parity |
| No parity check of GAIN | killed by 3 of 14 tests | test_flag_coincidence, test_hold, test_parity |
| No parity check of CTRL | killed by 1 of 14 tests | test_parity |
| No parity check of OFFSET_HI | killed by 1 of 14 tests | test_parity |
| The thresholds taken from the registers, not from the working set | killed by 4 of 14 tests | test_hold, test_parity, test_registers, test_runtime |
| Out_Last one stage early | killed by 14 of 14 tests | test_exhaustive, test_flag_coincidence, test_hold, test_input_stream, test_parity, test_rate, test_registers, test_reset, test_runtime, test_static |
| One multiplier stage too few against the packet signals | killed by 14 of 14 tests | test_exhaustive, test_flag_coincidence, test_hold, test_input_stream, test_parity, test_rate, test_registers, test_reset, test_runtime, test_static |
| No Err_Config pulse for a rejected parameter set | killed by 4 of 14 tests | test_flag_coincidence, test_hold, test_parity, test_registers |
| No Err_Config pulse for a CTRL of wrong parity | killed by 1 of 14 tests | test_parity |
| The parity bit of GAIN not set by a write | killed by 5 of 14 tests | test_exhaustive, test_hold, test_parity, test_runtime |
| The offset stored with the sign of the 64-bit value (resize) instead of its lower bits | killed by 4 of 14 tests | test_exhaustive, test_parity, test_runtime |
| The clear of ERR_CONFIG wins over the event | killed by 1 of 14 tests | test_flag_coincidence |
| Stat_ImageOpen tied to 0 | killed by 1 of 14 tests | test_input_stream |

## 5. Synthesis and timing

Not run. TC-PNT-12 needs Vivado synthesis for the Versal device of the reference systems (xcvc1902-vsva2197-2MP-e-S);
the licence for that device has expired on the development host. The runs are open until a licence or another host is
available; the script is ready with the configurations `pnt_default` (16 / 12 / 16 bits, run-time registers) and
`pnt_wide` (64 / 32 / 18 bits, four multiplier stages).

The GHDL synthesis of TC-PNT-11 shows that the module is synthesisable at every bound of its generics without latches;
it gives no timing.

## 6. Requirement coverage

| Requirement | Test cases | Status |
| --- | --- | --- |
| PNT-IF-01, PNT-IF-02 | TC-PNT-01 to 10 | Passed |
| PNT-IF-03 | TC-PNT-06 | Passed |
| PNT-IF-04 | TC-PNT-02, 05 | Passed |
| PNT-IF-05 | TC-PNT-09 and review (one clock, the reset sampled in the clocked processes only) | Passed |
| PNT-FN-01 | TC-PNT-01, 03, 08 | Passed |
| PNT-FN-02 | TC-PNT-02 | Passed |
| PNT-FN-03 | TC-PNT-01 | Passed |
| PNT-FN-04 | TC-PNT-03, 04 | Passed |
| PNT-FN-05 | TC-PNT-03, 08 | Passed |
| PNT-FN-06 | TC-PNT-01 to 10 | Passed |
| PNT-PF-01, PNT-PF-02 | TC-PNT-10 | Passed |
| PNT-ER-01, PNT-ER-02 | TC-PNT-02, 09 | Passed |
| PNT-ER-03, PNT-ER-04 | TC-PNT-05 | Passed |
| PNT-FT-01 | TC-PNT-05 and review: the stages hold no state between pixels; the working set is loaded with pixel (0, 0) of every image | Passed |
| PNT-FT-02 | TC-PNT-05 | Passed |
| PNT-FT-03 | TC-PNT-09 and the monitor of every test | Passed |
| PNT-RG-01, PNT-RG-03, PNT-RG-05 | TC-PNT-03, 06 | Passed |
| PNT-RG-02 | TC-PNT-06, 07 | Passed |
| PNT-RG-04 | TC-PNT-05 | Passed |
| PNT-CF-01, PNT-CF-02 | TC-PNT-11 | Passed |
| PNT-CF-03 | TC-PNT-12 | Open (section 5) |

The register map of the specification and the register description agree (`tools/regmap.py --check`).

## 7. Findings

| Finding | Correction |
| --- | --- |
| `resize` of `numeric_std` keeps the sign bit when it narrows a signed value; storing the offset with it would keep bit 63 of the written value instead of the bits of the offset width that the specification names | The RTL stores the lower bits of the offset width; a mutation with `resize` is killed by the read-back of `test_registers` |
| The first mutation run kept a module without the limit of `SHIFT` alive: in every configuration `MaxShift_g` was at the width of the product, where a larger shift gives the same result, so the limit was invisible | The configuration `shift_limit` (`MaxShift_g` 8) runs test_runtime with shift sets whose result shows the limit, and test_exhaustive uses `MaxShift_g` 6 with the shifts 0 to 8 and 127; the mutant is killed in the second run |
| The mutation script counted a mutant that did not compile (no results) as survived | A mutant without results is reported as invalid, repaired and run again; the gain mutant was repaired |
| `CTRL.HOLD` had no protection: an upset that set it would have frozen the parameter set without a report (lead decision Q-PNT-1) | `CTRL` has a parity bit; a mismatch counts as `HOLD` 0 and pulses `Err_Config` (PNT-ER-04); tested through `INJECT` bit 6 |
| The plan named 82 as the upper bound of `MaxShift_g` for 64-bit pixels and an 18-bit gain; the bound is `InBits_g` + `GainBits_g` + 1 = 83 | Plan corrected; `wide` simulates 83 |
| The audit of the status outputs of every module (after the mutation run of `isp_filter2d`) found `Stat_ImageOpen` probed only after complete images, where it is 0: a port tied to 0 would have passed every test | test_input_stream begins with an image cut after half of its pixels and probes `Stat_ImageOpen` while it is open (the malformed streams of `tools/isp_tbgen.py`); the mutant of a port tied to 0 is killed (section 4). No change of the RTL |
