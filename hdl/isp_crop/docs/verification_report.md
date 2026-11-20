# isp_crop: Verification Report

## 1. Test results

Run on 2026-11-19 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM (commit 4f1e13b), Open Logic 4.8.0-ft.2:
`python run.py -p 4`, 124 of 124 tests passed (48 of them `isp_crop`), 0 skipped. QuestaSim runs with the release
regression (with and without code coverage).

The status-output audit added a probe of `Stat_ImageOpen` while an image is open to test_input_stream:
`python run.py -p 4` on 2026-11-20 on commit 399d8b9, 542 of 542 tests passed (48 of them `isp_crop`), 0 skipped.

| Test | Configurations | Passed |
| --- | --- | --- |
| `test_static` (TC-CRP-01) | 11 | 11 |
| `test_input_stream` (TC-CRP-02) | 8 | 8 |
| `test_runtime_position` (TC-CRP-03) | 6 | 6 |
| `test_invalid_position` (TC-CRP-04) | 5 | 5 |
| `test_parity` (TC-CRP-05) | 5 | 5 |
| `test_registers` (TC-CRP-06) | 4 | 4 |
| `test_flag_coincidence` (TC-CRP-07) | 1 | 1 |
| `test_reset` (TC-CRP-08) | 5 | 5 |
| `test_rate` (TC-CRP-09) | 3 | 3 |
| TC-CRP-10 (`lint/synth_check.py`) | 9 configurations synthesise without latches; 9 generics out of range stop the elaboration with a message naming the generic | 18 |
| TC-CRP-11 (`lint/vivado_ooc.py`) | Section 5 | Not run (licence) |

## 2. Summary

Every output beat of every test (pixel, `Out_Last`, `Out_User`) equals the reference model, with and without gaps of
the source and stalls of the sink, and the contract checker of the sink found the output contract in every test:
`RoiHeight_g` packets of `RoiWidth_g` pixels with the flags of the lines. Regions at the corners and edges of the
image, as one pixel, a line, a column and the whole image, in images from 1 x 1 to 65536 x 1 and 1 x 65536 pixels.

- Input streams in every division into packets and malformed (short images, pixels without an image start, wrong end
  flags, random packets): the output images are complete, the numbers of `Err_Framing` pulses equal the model, and
  `Stat_ImageOpen` is 1 while an image is open and 0 after complete images.
- Run-time positions: (0, 0), the largest valid position and random ones, a write during an image (used from the
  next image), writes with single byte strobes (the other bytes keep their value), each read back. Invalid positions
  (one column or line too far, both, 0xFFFF in both fields): the image uses the generics, `Err_Config` pulses once per
  image, `STATUS.ERR_CONFIG` is set and `ROI_POS` keeps the written value.
- Parity: after `INJECT` every image uses the generics with one `Err_Config` until `ROI_POS` is written; a second
  injection restores the parity; an injection without the strobe of byte 0 and an injection with `RuntimeRoi_g` false
  have no effect.
- Registers: identification, dimensions, reset values, read-only registers and unused addresses, `IMAGE_OPEN` during
  an image, the sticky flags kept by a write of 0 and by a write without the strobe of their byte, cleared by a write
  of 1. Every access was answered with OKAY.
- Resets idle, held and running in the middle of an image, with pixels of the region in the module and with the last
  pixel outside the region, of one and of two cycles: `ROI_POS` holds the generics again, the next images are correct.
- The control outputs carry no metavalue after the first reset, and `Out_Valid`, `Err_Framing`, `Err_Config` and
  `Stat_ImageOpen` are 0 after every reset.

Measured timing (test_rate) and coincidence (test_flag_coincidence):

| Quantity | Bound | Design value | Measured |
| --- | --- | --- | --- |
| Throughput (CRP-PF-01) | One pixel per cycle | One per cycle | `In_Ready` high for every beat of three images back to back, in 8 x 6 and 33 x 9 |
| Latency (CRP-PF-02) | 4 cycles | 4 cycles | 4 cycles for each of the 36 and 360 pixels of the region of phase 1 |
| Pixels outside the region with the output held (CRP-PF-03) | One per cycle up to the next pixel of the region | One per cycle | One per cycle for the 4 and 13 pixels after a held pixel of the region |
| Clear of a flag in the cycle of its event (CRP-RG-02) | The flag stays set | The event wins | `ERR_FRAMING` and `ERR_CONFIG`: 12 steps each, with the clear before, in and after the cycle of the pulse; the flag was set exactly when the pulse came in the cycle of the clear or later |

## 3. Generic ranges

| Generic | Declared range | Simulated | Synthesised |
| --- | --- | --- | --- |
| `ImageWidth_g` | 1 to 65536 | 1, 8, 33, 65536 | 1, 4096, 65536; 65537 stops the elaboration |
| `ImageHeight_g` | 1 to 65536 | 1, 6, 9, 65536 | 1, 4096, 65536; 65537 stops the elaboration |
| `PixelBits_g` | 1 to 64 | 1, 7, 8, 12, 13, 16, 64 | 1, 12, 64; 65 stops the elaboration |
| `RoiX_g`, `RoiY_g` | 0 to W - 1, 0 to H - 1 | 0, 2, 3, 5, 7, 65535 (the last column) | 0, 512, 65535; W and H stop the elaboration |
| `RoiWidth_g`, `RoiHeight_g` | 1 to W - X, 1 to H - Y | 1, 3, 4, 6, 8, 20, 65536 | 1, 1024, 65536; 0 and W - X + 1 stop the elaboration |
| `RuntimeRoi_g` | false, true | both | both |

## 4. Mutations

Run on 2026-11-19 on commit a974705 in a worktree of its own (`git diff --quiet` before and after every mutant), with
the 15 tests of the configurations `w8_h6_runtime`, `w8_h6_runtime_rate`, `w33_h9_rate` and `w8_h6_static`. Every mutant
of the plan (section 6) fails at least one test; the tests that fail are those the plan expects. The mutant without
a range check changes the number of output pixels; the watchdog of the bench ends those tests.

The mutant `Stat_ImageOpen` tied to 0 came with the status-output audit (section 7) and ran alone on 2026-11-20 on
commit 399d8b9 with the same 15 tests; the reference run passed again.

| Mutation | Result | Failing tests |
| --- | --- | --- |
| None (reference) | passes (15 tests) | - |
| The last column of the region dropped | killed by 15 of 15 tests | test_flag_coincidence, test_input_stream, test_invalid_position, test_parity, test_rate, test_registers, test_reset, test_runtime_position, test_static |
| Out_Last at the first column of the region | killed by 15 of 15 tests | test_flag_coincidence, test_input_stream, test_invalid_position, test_parity, test_rate, test_registers, test_reset, test_runtime_position, test_static |
| The limits loaded only while they hold the generics (once after the reset) | killed by 3 of 15 tests | test_invalid_position, test_parity, test_runtime_position |
| No range check of the position | killed by 3 of 15 tests | test_flag_coincidence, test_invalid_position, test_registers |
| No parity check | killed by 1 of 15 tests | test_parity |
| The parity bit not updated by a write | killed by 3 of 15 tests | test_invalid_position, test_parity, test_runtime_position |
| INJECT without effect | killed by 1 of 15 tests | test_parity |
| The byte strobes ignored | killed by 1 of 15 tests | test_runtime_position |
| The clear of ERR_FRAMING wins over the event | killed by 1 of 15 tests | test_flag_coincidence |
| The clear of ERR_CONFIG wins over the event | killed by 1 of 15 tests | test_flag_coincidence |
| Pixels outside the region wait for the output | killed by 1 of 15 tests | test_rate |
| No Err_Config pulse | killed by 4 of 15 tests | test_flag_coincidence, test_invalid_position, test_parity, test_registers |
| ROI_POS not set to the generics by the reset | killed by 5 of 15 tests | test_input_stream, test_rate, test_registers, test_reset, test_static |
| Stat_ImageOpen tied to 0 | killed by 2 of 15 tests | test_input_stream |

## 5. Synthesis and timing

Not run. TC-CRP-11 needs Vivado synthesis for the Versal device of the reference systems (xcvc1902-vsva2197-2MP-e-S);
the licence for that device has expired on the development host. The run is open until a licence or another host is
available; the script (`lint/vivado_ooc.py`, configuration `crp_default`: 4096 x 4096 pixels of 12 bits, a region of
1024 x 1024 with the position at run time) is ready.

The GHDL synthesis of TC-CRP-10 shows that the module is synthesisable at every bound of its generics, with both
values of `RuntimeRoi_g`, without latches; it gives no timing.

## 6. Requirement coverage

| Requirement | Test cases | Status |
| --- | --- | --- |
| CRP-IF-01, CRP-IF-02 | TC-CRP-01 to 09 | Passed |
| CRP-IF-03 | TC-CRP-02 | Passed |
| CRP-IF-04 | TC-CRP-08 and review (one clock, the reset sampled in the clocked processes only) | Passed |
| CRP-IF-05 | TC-CRP-03, 06 | Passed |
| CRP-IF-06 | TC-CRP-04, 05 | Passed |
| CRP-FN-01, CRP-FN-03, CRP-FN-05 | TC-CRP-01 | Passed |
| CRP-FN-02 | TC-CRP-02 | Passed |
| CRP-FN-04 | TC-CRP-01 to 09 | Passed |
| CRP-FN-06 | TC-CRP-01, 03 | Passed |
| CRP-PF-01 to CRP-PF-03 | TC-CRP-09 | Passed |
| CRP-ER-01, CRP-ER-02 | TC-CRP-02, 08 | Passed |
| CRP-ER-03 | TC-CRP-04 | Passed |
| CRP-ER-04 | TC-CRP-05 | Passed |
| CRP-FT-01 | TC-CRP-05 and review: the selection compares the position that `isp_frame_sync` delivers with the limits; the limits are loaded with pixel (0, 0) of every image | Passed |
| CRP-FT-02 | TC-CRP-08 and the monitor of every test | Passed |
| CRP-FT-03 | TC-CRP-05 | Passed |
| CRP-RG-01 | TC-CRP-06 and the OKAY check of every access | Passed |
| CRP-RG-02 | TC-CRP-06, 07 | Passed |
| CRP-RG-03, CRP-RG-04 | TC-CRP-03, 05 | Passed |
| CRP-CF-01, CRP-CF-02 | TC-CRP-10 | Passed |
| CRP-CF-03 | TC-CRP-11 | Open (section 5) |

The register map of the specification and the register description agree (`tools/regmap.py --check`).

## 7. Findings

| Finding | Correction |
| --- | --- |
| Phase 2 of test_rate, as first built, sent the pixels before the region with an empty output register: a module whose pixels outside the region wait for the output would have passed | Phase 2 holds a pixel of the region in the output register and sends more pixels outside the region than the module holds; the configuration `w33_h9_rate` gives 13 such pixels |
| The first mutation run hung on a mutant that changed the number of output pixels: the sink waited for a beat that never came | Every testbench has a watchdog derived from the size of the test files (docs/testbench.md, section 6) |
| The UVVM AXI4-Lite BFM rejects an address wider than the bus, also with zero upper bits | The register script gives the address in the width of the bus |
| The flag sweep, as first built, started the clear after the pixel that causes the pulse: all steps lay after the pulse | The source pauses 4 cycles after the acknowledge; the sweep checks that it has steps before, at and after the pulse |
| The audit of the status outputs of every module (after the mutation run of `isp_filter2d`) found `Stat_ImageOpen` probed only after complete images, where it is 0: a port tied to 0 would have passed every test | test_input_stream begins with an image cut after half of its pixels and probes `Stat_ImageOpen` while it is open (the malformed streams of `tools/isp_tbgen.py`); the mutant of a port tied to 0 is killed (section 4). No change of the RTL |
