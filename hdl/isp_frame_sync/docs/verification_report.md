# isp_frame_sync: Verification Report

## 1. Test results

Run on 2026-11-19 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM (commit 4f1e13b), Open Logic 4.8.0-ft.2:
`python run.py -p 4 "*isp_frame_sync*"`, 75 of 75 tests passed, 0 skipped. QuestaSim runs with the release
regression (with and without code coverage).

| Test | Configurations | Passed |
| --- | --- | --- |
| `test_images` (TC-FSY-01) | 22 | 22 |
| `test_short_images` (TC-FSY-02) | 10 | 10 |
| `test_excess_pixels` (TC-FSY-03) | 8 | 8 |
| `test_end_flags` (TC-FSY-04) | 8 | 8 |
| `test_reset` (TC-FSY-05) | 8 | 8 |
| `test_status` (TC-FSY-06) | 8 | 8 |
| `test_rate` (TC-FSY-07) | 3 | 3 |
| `test_random_streams` (TC-FSY-08) | 8 | 8 |
| TC-FSY-09 (`lint/synth_check.py`) | 5 configurations synthesise without latches; 6 generics out of range stop the elaboration with their message | 11 |
| TC-FSY-10 (`lint/vivado_ooc.py`) | Section 5 | Not run (licence) |

## 2. Summary

Every output beat of every test (pixel, `Out_Last`, `Out_User`, `Out_PosX`, `Out_PosY`) equals the reference model,
with and without gaps of the source and stalls of the sink, and the contract checker of the sink found the output
contract in every test: one packet per line, the flags in order and constant within a packet, the number of lines.
Images in every division into packets (one per line, one per image, one pixel per packet, packets across lines),
short images completed with zeros at the next image start, pixels outside an image discarded, images ended by the
count against wrong end flags, resets idle, held and running, of one and of two cycles: the number of `Err_Framing`
pulses equals the model in every test. `Stat_ImageOpen` follows the open image, also during a pause of the source and
while missing pixels are generated. The control outputs carry no metavalue after the first reset, and `Out_Valid`,
`Err_Framing` and `Stat_ImageOpen` are 0 after every reset.

Measured timing (test_rate):

| Quantity | Bound | Measured |
| --- | --- | --- |
| Throughput | One pixel per cycle, at the input and at the output, across lines and images | One per cycle (images of 20, 7 and 2048 pixels back to back) |
| Latency (FSY-PF-02) | 2 cycles | 2 cycles |
| First pixel after m missing pixels (FSY-PF-03) | m + 4 cycles | m + 3 cycles for m = 1, 5, 6, 19, 64 and 2047 |
| Discard with the output held (FSY-PF-04) | One pixel per cycle | One per cycle (3W + 5 pixels) |

## 3. Generic ranges

| Generic | Declared range | Simulated | Synthesised |
| --- | --- | --- | --- |
| `ImageWidth_g` | 1 to 65536 | 1, 2, 3, 5, 7, 33, 64, 65536 | 1, 4096, 65536; 0 and 65537 stop the elaboration |
| `ImageHeight_g` | 1 to 65536 | 1, 2, 4, 6, 9, 32, 65536 | 1, 4096, 65536; 0 and 65537 stop the elaboration |
| `PixelBits_g` | 1 to 64 | 1, 2, 7, 8, 12, 13, 16, 31, 32, 33, 63, 64 | 1, 8, 12, 32, 64; 0 and 65 stop the elaboration |

The image of 65536 x 65536 pixels is synthesised only (section 3 of the plan).

## 4. Mutations

Run on 2026-11-19 on commit b3c08f5 in a worktree of its own (`git diff --quiet` before and after every mutant), with
the 16 tests of the configurations `w5_h4_p12`, `w5_h4_p12_bp` and the test_rate of `w7_h1_p16`. Every mutant of the
plan (section 6) fails at least one test; the tests that fail are those the plan expects.

| Mutation | Result | Failing tests |
| --- | --- | --- |
| None (reference) | passes (16 tests) | - |
| No completion of a short image | killed by 12 of 16 tests | test_end_flags, test_random_streams, test_rate, test_reset, test_short_images, test_status |
| Missing pixels with the input pixel instead of 0 | killed by 12 of 16 tests | test_end_flags, test_random_streams, test_rate, test_reset, test_short_images, test_status |
| One Err_Framing per discarded pixel | killed by 8 of 16 tests | test_excess_pixels, test_random_streams, test_rate, test_reset |
| No E3 check | killed by 8 of 16 tests | test_end_flags, test_excess_pixels, test_random_streams, test_status |
| No E4 check | killed by 4 of 16 tests | test_end_flags, test_random_streams |
| The image start taken from any beat | killed by 16 of 16 tests | test_end_flags, test_excess_pixels, test_images, test_random_streams, test_rate, test_reset, test_short_images, test_status |
| The line counter not advanced | killed by 15 of 16 tests | test_end_flags, test_excess_pixels, test_images, test_random_streams, test_rate, test_reset, test_short_images, test_status |
| Out_User "00" instead of "10" for the last line | killed by 15 of 16 tests | test_end_flags, test_excess_pixels, test_images, test_random_streams, test_rate, test_reset, test_short_images, test_status |
| Stat_ImageOpen low while missing pixels are generated | killed by 2 of 16 tests | test_status |
| An extra register stage | killed by 2 of 16 tests | test_rate |
| Out_Valid not cleared by the reset | killed by 16 of 16 tests | test_end_flags, test_excess_pixels, test_images, test_random_streams, test_rate, test_reset, test_short_images, test_status |
| Stat_ImageOpen not cleared by the reset | killed by 2 of 16 tests | test_reset |

## 5. Synthesis and timing

Not run. TC-FSY-10 needs Vivado synthesis for the Versal device of the reference systems (xcvc1902-vsva2197-2MP-e-S);
the licence for that device has expired on the development host (Vivado 2025.2, 2026-11-19: "A license feature for
Synthesis was found but is expired"). The run is open until a licence or another host is available; the script
(`lint/vivado_ooc.py`, configuration `fsy_max`) is ready.

The GHDL synthesis of TC-FSY-09 shows that the module is synthesisable at every bound of its generics without latches;
it gives no timing.

## 6. Requirement coverage

| Requirement | Test cases | Status |
| --- | --- | --- |
| FSY-IF-01, FSY-IF-02, FSY-IF-03 | TC-FSY-01 to 08 | Passed |
| FSY-IF-04 | TC-FSY-02, 03, 04, 08 | Passed |
| FSY-IF-05 | TC-FSY-06 | Passed |
| FSY-IF-06 | TC-FSY-05 and review (one clock, the reset sampled in the clocked processes only) | Passed |
| FSY-FN-01 to FSY-FN-03, FSY-FN-05 | TC-FSY-01, 08 | Passed |
| FSY-FN-04 | TC-FSY-01 to 08 | Passed |
| FSY-FN-06 | TC-FSY-03, 05 | Passed |
| FSY-PF-01 to FSY-PF-04 | TC-FSY-07 | Passed |
| FSY-ER-01 to FSY-ER-06 | TC-FSY-02 to 05, 08 | Passed |
| FSY-FT-01 | TC-FSY-08 and review: the `when others` branch of the state machine leads to `Idle_s` and clears the position; the counters are compared with "greater or equal"; the position is set with every image start | Passed |
| FSY-FT-02 | TC-FSY-05, 06 and the monitor of every test | Passed |
| FSY-PB-01 | TC-FSY-01, 08 | Passed |
| FSY-CF-01, FSY-CF-02 | TC-FSY-09 | Passed |
| FSY-CF-03 | TC-FSY-10 | Open (section 5) |

## 7. Findings

| Finding | Correction |
| --- | --- |
| FSY-PF-03 bounded the acceptance of the pixel of the image start. The input stage takes that pixel at once, so the bound measured nothing; the completion of a short image delays the output of the next image | FSY-PF-03 bounds the time until the first pixel of the next image is at the output (phase C) |
| `ispIsImageStart` of `isp_pkg` looked only at bit 0 of the flags (isp_pkg verification report) | Corrected in `isp_pkg` before the first simulation |
| A reset inside a packet with the flags "01" or "11" makes the rest of that packet an image start at a wrong position (lead review of the module); the behaviour was neither specified nor tested | Specified (section 6 of the specification, integration constraints of the user guide) and tested: test_reset has a held reset inside the "01" packet of the first line; the model gives the misaligned image, its `Err_Framing` pulses and the correct image after it |
