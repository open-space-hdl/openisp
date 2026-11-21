# isp_point: Verification Report

## 1. Test results

Run on 2026-11-19 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM (commit 4f1e13b), Open Logic 4.8.0-ft.2:
`python run.py -p 3`, 175 of 175 tests passed (51 of them `isp_point`), 0 skipped. QuestaSim Pro Microchip Edition
2024.3 ran the release regression with code coverage on 2026-11-21 on commit b50efd1:
`python run.py --questa --coverage -p 1`, 669 of 669 tests passed (54 of them `isp_point`), 0 skipped; the code coverage
is in [docs/coverage.md](../../../docs/coverage.md).

The configuration `w1_h4` (`ImageWidth_g` 1 in a small image, test_static) came later, with the pull-request tests of
the CI, which run the low bound of every generic: `python run.py -p 4` on 2026-11-19 on commit 30a4acc, 510 of 510
tests passed (52 of them `isp_point`), 0 skipped.

The status-output audit added a probe of `Stat_ImageOpen` while an image is open to test_input_stream:
`python run.py -p 4` on 2026-11-20 on commit 399d8b9, 542 of 542 tests passed (52 of them `isp_point`), 0 skipped.

The parity bit of a write after PKG-08 (`ispWriteParity` of `isp_pkg`: a write that keeps a byte with bits of the
register keeps a mismatch, a write of only bytes without bits leaves the parity bit unchanged) came with the partial
writes of test_parity; the configuration `defaults` (2 tests) came before with the default of `MaxShift_g` (section 7):
`python run.py -p 4` on 2026-11-20 on commit e9116a7 (with develop fbc18fd), 669 of 669 tests passed (54 of them
`isp_point`), 0 skipped; `lint/synth_check.py` (TC-PNT-11) passed.

The code coverage of the release run ([docs/coverage.md](../../../docs/coverage.md)) found a register access that no
test made, a write of `CTRL` without the strobe of byte 0; test_registers makes it now and also reads `ID` + 2 (section
2): `python run.py -p 2 "*isp_conv_tb*" "*isp_crop_tb*" "*isp_point_tb*" "*isp_replace_tb*"` on 2026-11-21 on commit
92a444e, 313 of 313 tests passed (54 of them `isp_point`), 0 skipped. QuestaSim ran the 76 changed tests of the four
modules with code coverage on the same commit: 76 of 76 passed (9 of them `isp_point`), 0 skipped. The generated test
files of every other test of the release run are identical to those of b50efd1, so their QuestaSim results apply to
92a444e.

| Test | Configurations | Passed |
| --- | --- | --- |
| `test_static` (TC-PNT-01) | 16 | 16 |
| `test_input_stream` (TC-PNT-02) | 5 | 5 |
| `test_runtime` (TC-PNT-03) | 4 | 4 |
| `test_hold` (TC-PNT-04) | 1 | 1 |
| `test_parity` (TC-PNT-05) | 7 | 7 |
| `test_registers` (TC-PNT-06) | 9 | 9 |
| `test_flag_coincidence` (TC-PNT-07) | 1 | 1 |
| `test_exhaustive` (TC-PNT-08) | 1 | 1 |
| `test_reset` (TC-PNT-09) | 5 | 5 |
| `test_rate` (TC-PNT-10) | 5 | 5 |
| TC-PNT-11 (`lint/synth_check.py`) | 9 configurations synthesise without latches (2 with the defaults of the entity); 13 generics out of range stop the elaboration with a message naming the generic | 22 |
| TC-PNT-12 (`lint/libero_synth.py`) | 2 configurations (section 5) | 2 of 2 synthesised |

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
  beyond the model. Partial writes (PKG-08), for every parameter register: after an injection, a write that keeps
  a byte with bits of the register and a write of only bytes without bits keep the mismatch (the next images use
  the generics with `Err_Config`), and a write of every byte with bits clears it; each kind of write the width of
  the register allows (`SHIFT` and the registers of up to 8 bits only the write of bytes without bits, for `SHIFT`
  the write without byte 0; `OFFSET_HI` without bits, an offset of up to 32 bits: every write is full and clears
  the mismatch). A partial write of `GAIN` without a mismatch is taken.
- Registers: identification, dimensions and widths, the reset values (also `HIGH` from the sentinel -1 and `OFFSET_HI`
  as the sign of the offset), every single byte strobe on every parameter register with random data and its read-back
  (the offset sign-extended, the other registers zero-extended), read-only registers and unused addresses (also `ID` +
  2, an address that is not a multiple of 4), a write of `CTRL` without the strobe of byte 0 without effect, the sticky
  flags. Every access was answered with OKAY.
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
| `MaxShift_g` | 0 to `InBits_g` + `GainBits_g` + 1 | 0, 6, 8, 9, 28 (also as the default of the entity), 32, 50, 83 | 0, 3, 28 and 80 (the default of the entity), 32, 50, 83; above the bound stops the elaboration |
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

The mutation run was repeated on 2026-11-20 on commit 2189d17, the parity bit of a write from `ispWriteParity` of
`isp_pkg` (PKG-08), with the 14 tests and test_static and test_registers of the configuration `defaults`, which the
mutant of the old default of `MaxShift_g` needs (section 7), and the sources of the module are the same at e9116a7. Five
mutants of `ispWriteParity` came with it: the parity of a kept byte from the write data, of a written byte from the
stored bits, a write that keeps a byte with bits sets the parity bit for the resulting value (the rule before PKG-08), a
write of every byte with bits keeps the syndrome, and a write of only bytes without bits sets the parity bit. Every one
of the 24 mutants fails at least one test; the mutants of PKG-08 are killed by test_parity.

The mutation run was repeated on 2026-11-21 on commit 92a444e, the coverage closure (section 1), with the same 16 tests;
the table shows that run. Two mutants came with it, one for each access the closure added: `CTRL` written without the
strobe of byte 0 and a read at an address that is not a multiple of 4 decoded as the register at the aligned address
(`ID` + 2), both killed by test_registers. The read-decode mutant ran alone on the same commit with the same 16 tests;
the reference run passed again. Every one of the 27 mutants fails at least one test.

| Mutation | Result | Failing tests |
| --- | --- | --- |
| None (reference) | passes (16 tests) | - |
| No lower clamp | killed by 9 of 16 tests | test_exhaustive, test_hold, test_parity, test_registers, test_reset, test_runtime, test_static |
| No upper clamp | killed by 8 of 16 tests | test_exhaustive, test_hold, test_parity, test_registers, test_runtime, test_static |
| A logical instead of an arithmetic shift | killed by 6 of 16 tests | test_exhaustive, test_hold, test_parity, test_runtime, test_static |
| The offset not sign-extended | killed by 5 of 16 tests | test_exhaustive, test_parity, test_runtime, test_static |
| The top bit of the gain dropped | killed by 3 of 16 tests | test_exhaustive, test_hold, test_runtime |
| A shift above MaxShift_g not limited | killed by 2 of 16 tests | test_exhaustive, test_runtime |
| CTRL.HOLD without effect | killed by 2 of 16 tests | test_hold, test_parity |
| No parity check of GAIN | killed by 3 of 16 tests | test_flag_coincidence, test_hold, test_parity |
| No parity check of CTRL | killed by 1 of 16 tests | test_parity |
| No parity check of OFFSET_HI | killed by 1 of 16 tests | test_parity |
| The thresholds taken from the registers, not from the working set | killed by 4 of 16 tests | test_hold, test_parity, test_registers, test_runtime |
| Out_Last one stage early | killed by 16 of 16 tests | test_exhaustive, test_flag_coincidence, test_hold, test_input_stream, test_parity, test_rate, test_registers, test_reset, test_runtime, test_static |
| One multiplier stage too few against the packet signals | killed by 16 of 16 tests | test_exhaustive, test_flag_coincidence, test_hold, test_input_stream, test_parity, test_rate, test_registers, test_reset, test_runtime, test_static |
| No Err_Config pulse for a rejected parameter set | killed by 4 of 16 tests | test_flag_coincidence, test_hold, test_parity, test_registers |
| No Err_Config pulse for a CTRL of wrong parity | killed by 1 of 16 tests | test_parity |
| The parity bit of GAIN not set by a write | killed by 5 of 16 tests | test_exhaustive, test_hold, test_parity, test_runtime |
| The offset stored with the sign of the 64-bit value (resize) instead of its lower bits | killed by 5 of 16 tests | test_exhaustive, test_hold, test_parity, test_runtime |
| The clear of ERR_CONFIG wins over the event | killed by 1 of 16 tests | test_flag_coincidence |
| CTRL written without the strobe of byte 0 | killed by 2 of 16 tests | test_registers |
| A read at an address that is not a multiple of 4 decoded as the register at the aligned address | killed by 2 of 16 tests | test_registers |
| Stat_ImageOpen tied to 0 | killed by 1 of 16 tests | test_input_stream |
| MaxShift_g default 82 | killed by 2 of 16 tests | test_registers, test_static |
| The parity of a kept byte taken from the write data | killed by 1 of 16 tests | test_parity |
| The parity of a written byte taken from the stored bits | killed by 6 of 16 tests | test_exhaustive, test_hold, test_parity, test_reset, test_runtime |
| A write that keeps a byte with bits sets the parity for the resulting value (the re-seal before PKG-08) | killed by 1 of 16 tests | test_parity |
| A write of every byte with bits keeps the syndrome | killed by 2 of 16 tests | test_hold, test_parity |
| A write of only bytes without bits sets the parity for the stored value | killed by 1 of 16 tests | test_parity |

## 5. Synthesis and timing

TC-PNT-12 (`lint/libero_synth.py`), the preliminary synthesis on PolarFire MPF100T (Libero, Synplify Pro, speed grade
STD) with a clock of 125 MHz, on commit 4c1744f (the RTL of develop 06a41e5). The results are pre-layout estimates, not
a timing closure and not on the reference device. The out-of-context run at 150 MHz on the Versal device of the
reference systems is open (ISP-GEN-04, roadmap).

| Configuration | Estimate (MHz) | Slack (ns) | 4LUT | DFF | LSRAM | Math | Worst path (logic levels) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `pnt_default`: 4096 x 4096 pixels, 16 / 12 / 16 bits (input, output, gain), run-time registers, two multiplier stages (the default) | 172.6 | 2.206 | 917 | 597 | 0 | 1 | the flags of the multiplier pipeline -> the shadow register of the input stage of the frame sync (4) |
| `pnt_wide`: 64 / 32 / 18 bits, four multiplier stages | 80.6 | -4.402 | 2362 | 2076 | 0 | 8 | the sum of pixel and offset -> a cascade of four Math blocks and 32 carry cells -> the first product register (36) |

The default configuration meets 125 MHz in the estimate. `pnt_wide`, the widest configuration and not a default, reaches
80.6 MHz (section 5.1, user guide, section 8).

The GHDL synthesis of TC-PNT-11 shows that the module is synthesisable at every bound of its generics without latches;
it gives no timing.

The parity bit of a write after PKG-08 (`ispWriteParity` of `isp_pkg`) in the preliminary synthesis on PolarFire MPF100T
(Libero, Synplify Pro) with a clock of 125 MHz, pre-layout estimates, not a timing closure and not on the reference
device. `pnt_default` gives 170.7 MHz with 942 4LUT on develop fbc18fd and 172.6 MHz with 917 4LUT on commit e9116a7.
The worst path of both is the flags of the multiplier pipeline -> the input stage of the frame sync (5 and 4 logic
levels); it does not contain the parity of the writes.

### 5.1 The multiplier stages of `pnt_wide`

The worst path of `pnt_wide` is the product: the sum of pixel and offset passes a cascade of four of the eight Math
blocks and 32 carry cells and reaches the first product register in one cycle (36 logic levels). The four stages of
`MultStages_g` are registers behind the product (4 x 84 flip-flops), and the Math blocks use none of their internal
registers. A probe of the same configuration with the register retiming of Synplify Pro enabled
(`set_option -retiming 1`):

| Synthesis | Estimate (MHz) | 4LUT | DFF | Worst path | Stages of `MultStages_g` |
| --- | --- | --- | --- | --- | --- |
| Without retiming (the flow of `lint/libero_synth.py`) | 80.6 | 2362 | 2076 | the sum -> the first product register (36) | 4 x 84 flip-flops behind the product |
| With retiming | 80.6 | 2650 | 2547 | the same | the same; the synthesis reports 486 registers retimed to 834, mainly those of the shifted value (84 to 226 flip-flops), none into the multiplier |

The stages are meant for a synthesis tool that takes the registers behind a multiplier into its pipeline; on PolarFire
neither the synthesis nor its retiming does so. `pnt_wide` is not a default; the user guide (section 8) records its
limit, and a product pipelined in the RTL itself is an open item (roadmap).

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
| PNT-RG-01, PNT-RG-05 | TC-PNT-03, 06 | Passed |
| PNT-RG-03 | TC-PNT-03, 05, 06 | Passed |
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
| The default of `MaxShift_g` in the entity was 82; the specification gives `InBits_g` + `GainBits_g`. The range check of the module (at most `InBits_g` + `GainBits_g` + 1) rejects 82 for every input below 64 bits with an 18-bit gain, so the module did not elaborate with `MaxShift_g` left at its default. Every configuration of the benches and of `lint/synth_check.py` set the generic; the synthesis wrapper of the chain test (`isp_chain`) was the first to rely on the default | The default is `InBits_g` + `GainBits_g` (a generic of the same list, VHDL-2008). The configuration `defaults` simulates the module with every generic but the dimensions and the pixel bits at its default and reads `PARAM.MAX_SHIFT`; `pnt_defaults` and `pnt_defaults_64` synthesise it. A mutant with the old default is killed (section 4). The defaults of every entity of the suite were compared with the tables of generics of their specifications: no other differs |
| A write with byte strobes set the parity bit for the resulting value. An upset in a byte that the write kept, for example while `CTRL.HOLD` is 1 and the registers are not checked, therefore became a valid word with the next partial write: masked, not detected (found in review) | The parity bit of a write follows PKG-08 (`ispWriteParity` of `isp_pkg`): a write of every byte that holds bits of the register sets it for the written value, a write that keeps such a byte keeps a mismatch, so that the error is reported until the register is written in full; PNT-RG-03, the error table, the user guide (4.3: the software writes every byte with bits after `ERR_CONFIG`); test_parity: an injection, then a partial write and a write of only bytes without bits, then the images with the generics, a full write that clears it, and a partial write without a mismatch |
| A write of `SHIFT` without the strobe of byte 0 stores none of its 7 bits but set the parity bit again, the same masking for a write of only bytes without bits | Such a write leaves the parity bit unchanged (PKG-08); test_parity writes `SHIFT` without byte 0 after an injection |
| The architecture said that the register stages of the multiplier are placed by the retiming of the synthesis tool. The preliminary synthesis on PolarFire keeps them behind the product, with and without retiming, so that the product of the widest configuration is computed in one cycle (80.6 MHz) | The architecture (sections 4 and 7) and the specification (generics) state the intent of the stages and the result on PolarFire (section 5.1); the user guide gives the limit of the widest configuration; a product pipelined in the RTL is an open item of the roadmap. No change of the RTL |
| The code coverage of the release run showed that no test wrote `CTRL` without the strobe of byte 0 | test_registers writes it and also reads `ID` + 2; the two new mutants are killed (section 4). No change of the RTL |
