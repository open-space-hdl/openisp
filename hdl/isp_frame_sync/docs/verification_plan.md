# isp_frame_sync: Verification Plan

## 1. Overview

The testbench `isp_frame_sync_tb` sends images as stream packets to the module and checks every output beat against
the output of a reference model. The model and the stimulus are written by Python before the simulation; the
testbench reads them from files. The model is written from the specification, not from the RTL.

- `tools/isp_model.py`, function `frame_sync`: takes the input beats (pixel, `Last`, sequence flags) and the image
  dimensions and returns the output beats (pixel, `Last`, sequence flags, column, line) and the number of
  `Err_Framing` pulses, following section 3 of the specification: image start on the first beat of a packet with
  the flags "01" or "11", pixel count from the image start, completion with zeros at an early image start (E1),
  discard while no image is open with one pulse per run (E2), end of the image by the count (E3, E4).
- `hdl/isp_frame_sync/tb/vunit_config.py`: generates the images and their division into packets for every test and
  configuration (`tools/isp_tbgen.py`), runs the model and writes the stimulus file and the expected file of every
  test.
- The shared source and sink of the [testbench components](../../../docs/testbench.md): the source drives `In_*`
  with random gaps (`GapPct_g`) and `'X'` on `In_Data` between the beats, so that a module that takes invalid data
  produces metavalues at its output; the sink takes `Out_*` with random stalls (`StallPct_g`), compares every beat
  and its sideband (`Out_PosY` and `Out_PosX`) with the expected file and checks the output contract of the pixel
  stream with its contract checker (section 3.1). The probe input of the source is `Stat_ImageOpen`.
- The testbench counts the cycles in which `Err_Framing` is high and compares the count with the model; it checks the
  timing of test_rate (section 3.2) and the absence of metavalues on the control outputs after the reset.

Simulators: GHDL (regression, CI) and QuestaSim (code coverage at the release); VUnit with UVVM, test end
`ispTestEnd`. Tests observe ports only. The latency for the drain time of the test end is 2 cycles
(testbench components, section 6). The stimulus and expected files and their entries (beats, pauses, waits,
probes, holds, markers, resets) are those of the testbench components, section 3.

## 2. Configurations

| Configuration | W | H | `PixelBits_g` | Gaps / stalls | Tests |
| --- | --- | --- | --- | --- | --- |
| `w5_h4_p12` | 5 | 4 | 12 | none | all of section 3.2 |
| `w5_h4_p12_bp` | 5 | 4 | 12 | 30 % / 40 % | all except test_rate |
| `w1_h1_p1` | 1 | 1 | 1 | 30 % / 40 % | all except test_rate |
| `w1_h6_p8` | 1 | 6 | 8 | 30 % / 40 % | all except test_rate |
| `w7_h1_p16` | 7 | 1 | 16 | none | all of section 3.2 |
| `w2_h2_p64` | 2 | 2 | 64 | 30 % / 40 % | all except test_rate |
| `w33_h9_p13` | 33 | 9 | 13 | 20 % / 20 % | all except test_rate |
| `w64_h32_p32` | 64 | 32 | 32 | none | all of section 3.2 |
| `w65536_h1_p12` | 65536 | 1 | 12 | 10 % / 10 % | test_images, test_short_images |
| `w1_h65536_p12` | 1 | 65536 | 12 | 10 % / 10 % | test_images, test_short_images |
| `w3_h2_p<n>`, n = 1, 2, 7, 8, 12, 13, 16, 31, 32, 33, 63, 64 | 3 | 2 | n | 20 % / 20 % | test_images |

Generic coverage:

| Generic | Declared range | Simulated | Synthesised (TC-FSY-09) |
| --- | --- | --- | --- |
| `ImageWidth_g` | 1 to 65536 | 1, 2, 3, 5, 7, 33, 64, 65536 | 1, 4096, 65536 |
| `ImageHeight_g` | 1 to 65536 | 1, 2, 4, 6, 9, 32, 65536 | 1, 4096, 65536 |
| `PixelBits_g` | 1 to 64 | 1, 2, 7, 8, 12, 13, 16, 31, 32, 33, 63, 64 | 1, 8, 12, 32, 64 |

`PixelBits_g` is a numeric range: the data path passes the pixel without arithmetic, so a representative set covers
it: the bounds, odd widths, and the widths around 32 and 64, where the hexadecimal file reader and the comparisons of
the bench fail first. The two bounds of the image dimensions are simulated in images of one line and of one column;
the image of 65536 x 65536 pixels (2^32 pixels) is synthesised only. The widths of the counters and of
`Out_PosX` and `Out_PosY` follow from the dimensions, from 1 bit (dimension 1 and 2) to 16 bits (65536).

## 3. Test cases

### 3.1 Checks in every test

| Check | Where | Requirements |
| --- | --- | --- |
| Every output beat (pixel, `Out_Last`, `Out_User`, `Out_PosX`, `Out_PosY`) equals the model, in order, none missing, none extra | Sink | FSY-IF-02, FSY-IF-03, FSY-FN-01, FSY-FN-04 |
| Output contract: `Out_Last` on every W-th beat of an image and nowhere else; `Out_User` constant within a packet; the first packet of an image "01" ("11" when H = 1), then "00", the last "10"; exactly H packets per image | Sink, independent of the expected file | FSY-FN-03, FSY-ER-05 |
| The number of cycles with `Err_Framing` high equals the model | Testbench | FSY-IF-04 |
| `In_Ready`, `Out_Valid`, `Err_Framing` and `Stat_ImageOpen` free of metavalues in every cycle after the first reset; `Out_Valid` low in the cycle after every reset | Testbench | FSY-FT-02, FSY-IF-06 |

### 3.2 Test list

| Test | Description | Requirements |
| --- | --- | --- |
| `test_images` (TC-FSY-01) | Eight complete images back to back, each in another division into packets: one packet per line, one packet for the image ("11"), one pixel per packet, packets of W + 1 pixels, random lengths of 1 to 2W + 1 pixels across the lines, a single packet ending exactly at a line end inside the image. Random pixels. `Stat_ImageOpen` 0 after the last image | FSY-IF-01, FSY-IF-02, FSY-IF-03, FSY-FN-01, FSY-FN-02, FSY-FN-03, FSY-FN-05, FSY-ER-05, FSY-PB-01 |
| `test_short_images` (TC-FSY-02) | Images cut after 1 pixel, after a line, in the middle of a line and one pixel before the end; the next image start in a "01" and in a "11" packet; two short images in a row; each followed by a complete image. The missing pixels are 0 with their positions; one `Err_Framing` per short image | FSY-ER-01, FSY-ER-05, FSY-ER-06, FSY-IF-04 |
| `test_excess_pixels` (TC-FSY-03) | Pixels without an image start after the reset (a "00" and a "10" packet); after a complete image a "00" packet, a "10" packet, and a last packet longer than the image (E3, then a run of E2); two runs separated by an image give two pulses; each followed by a complete image | FSY-ER-02, FSY-ER-03, FSY-ER-05, FSY-ER-06, FSY-FN-06, FSY-IF-04 |
| `test_end_flags` (TC-FSY-04) | The last pixel with `Last` in a "00" and in a "01" packet; an image in one "01" packet; the last pixel without `Last`; a "10" packet and a "11" packet that end before the last pixel (E4), the image completed by further packets; E4 followed by an early image start (E1) | FSY-ER-03, FSY-ER-04, FSY-ER-06, FSY-IF-04 |
| `test_reset` (TC-FSY-05) | Reset with the module idle; in the middle of an image with the output held; in the middle of an image while beats transfer (running reset: the sink keeps its stalls and takes the beats until the reset without comparing them); while missing pixels are generated, held and running; resets of one cycle and of two cycles. After every reset the rest of the interrupted image arrives (discarded, E2) and complete images follow | FSY-FN-06, FSY-FT-02, FSY-IF-06, FSY-ER-06 |
| `test_status` (TC-FSY-06) | `Stat_ImageOpen` checked: 0 after the reset, 1 after an image start, 1 during a pause of the source in an image, 1 while missing pixels are generated with the output held, 0 after the last pixel of a complete image and after an image ended by E3 | FSY-IF-05, FSY-FT-02 |
| `test_rate` (TC-FSY-07) | Configurations without gaps and stalls. Phase 1: images back to back in lines and in random packets: `In_Ready` high in every cycle with `In_Valid` high, `Out_Valid` high in every cycle from the first to the last output beat, the first output beat 2 cycles after the first accepted beat. Phase 2: images cut by 1, by W and by W x H - 1 pixels (where W x H > 1), each followed at once by an image start: `Out_Valid` high during the missing pixels, the first pixel of the new image at the output at most m + 4 cycles after it was accepted. Phase 3: with the output held, 3W + 5 pixels without an image start: `In_Ready` high for every one of them | FSY-PF-01, FSY-PF-02, FSY-PF-03, FSY-PF-04 |
| `test_random_streams` (TC-FSY-08) | 400 packets of random length (1 to 2 W x H pixels) with random flags, in one packet out of five the flags changing within the packet, complete images inserted at random; random pixels. Every output beat and the number of `Err_Framing` pulses against the model; the stream ends with two complete images that must be correct | FSY-FN-02, FSY-FN-04, FSY-ER-01, FSY-ER-02, FSY-ER-03, FSY-ER-04, FSY-ER-05, FSY-ER-06, FSY-FT-01, FSY-PB-01 |
| TC-FSY-09 (`lint/synth_check.py`) | GHDL synthesis without latches of (W, H, P) = (1, 1, 1), (4096, 4096, 12), (1, 65536, 32), (65536, 1, 8), (65536, 65536, 64); `ImageWidth_g` 0 and 65537, `ImageHeight_g` 0 and 65537, `PixelBits_g` 0 and 65 stop the elaboration with their message | FSY-CF-01, FSY-CF-02 |
| TC-FSY-10 (`lint/vivado_ooc.py`) | Out-of-context synthesis and implementation of (65536, 65536, 64), the widest counters and data path, at 150 MHz on the Versal device of the reference systems: no failing timing path; resources and the worst slack recorded in the verification report | FSY-CF-03 |

The tests of section 3.2 run in the configurations of section 2. In the configurations with a single pixel or a
single line some cases do not exist (no image can be cut in an image of one pixel); the generator leaves them out
and the verification report lists which cases ran where.

## 4. Requirement coverage

| Requirement | Test cases | Method |
| --- | --- | --- |
| FSY-IF-01, FSY-IF-02 | TC-FSY-01 to 08 | Test |
| FSY-IF-03 | TC-FSY-01 to 08 (sideband of every beat) | Test |
| FSY-IF-04 | TC-FSY-02, 03, 04, 08 (count of the pulses) | Test |
| FSY-IF-05 | TC-FSY-06 | Test |
| FSY-IF-06 | TC-FSY-05 | Test and review: one clock port, the reset sampled in the clocked processes only |
| FSY-FN-01, FSY-FN-02, FSY-FN-03, FSY-FN-05 | TC-FSY-01, 08 | Test |
| FSY-FN-04 | TC-FSY-01 to 08 (configurations with and without gaps and stalls compare to the same model) | Test |
| FSY-FN-06 | TC-FSY-03, 05 | Test |
| FSY-PF-01 to FSY-PF-04 | TC-FSY-07 | Test |
| FSY-ER-01 to FSY-ER-06 | TC-FSY-02 to 05, 08 | Test |
| FSY-FT-01 | TC-FSY-08 | Test (realignment after any input stream) and review: `when others` of the state machine, comparisons "greater or equal" of the counters, counters set with every image start. An upset of a register cannot be produced through the ports; the review covers it |
| FSY-FT-02 | TC-FSY-05, 06 and the checks of section 3.1 | Test |
| FSY-PB-01 | TC-FSY-01, 08 | Test |
| FSY-CF-01, FSY-CF-02 | TC-FSY-09 | Synthesis |
| FSY-CF-03 | TC-FSY-10 | Timing |

## 5. Timing bounds

The bounds of test_rate are those of the specification. They follow from the architecture:

| Bound | Design value | Derivation |
| --- | --- | --- |
| Latency 2 cycles (FSY-PF-02) | 2 | One register in the input stage (`olo_base_pl_stage`, one stage), one in the output register |
| m + 4 cycles for the first pixel of the next image (FSY-PF-03) | m + 3 | The image start reaches the control 1 cycle after its acceptance; the state changes to `Pad_s` in the next cycle; the m missing pixels take m cycles; the image start is taken in the next cycle and is at the output 1 cycle later. The bound leaves one cycle of margin |
| One pixel per cycle (FSY-PF-01, FSY-PF-04) | 1 | The registered ready of the input stage and the output register that is loaded when it is empty or read in the same cycle |

The test reports the measured values, so that the verification report states them.

## 6. Negative tests and mutations

Every error path is provoked from the source: early image starts (E1), pixels outside an image (E2), the end of an
image in the wrong packet or without `Last` (E3), packets that end early with the last flags (E4), resets in every
state. The number of `Err_Framing` pulses is compared exactly, so a missing and a doubled pulse both fail.

A check is proven when a mutation of the design makes a test fail. After the regression passes, a script applies
each mutation below to the committed RTL in turn, runs the tests and restores the source; every mutation must fail at
least one test. The script runs in a worktree of its own, checks with `git diff --quiet` that the tree is clean
before and after every mutation, and never runs beside another job that reads the same tree. The verification
report lists the result.

| Mutation | Expected to fail |
| --- | --- |
| No completion of a short image (the image start is taken at once) | TC-FSY-02, 08 |
| Missing pixels with the input pixel instead of 0 | TC-FSY-02 |
| One `Err_Framing` per discarded pixel instead of one per run | TC-FSY-03, 08 |
| No E3 check | TC-FSY-03, 04 |
| No E4 check | TC-FSY-04 |
| The image start taken from any beat, not only from the first beat of a packet | TC-FSY-01, 08 |
| The line counter not advanced | TC-FSY-01 (sideband, contract) |
| `Out_User` "00" instead of "10" for the last line | TC-FSY-01 (contract) |
| `Stat_ImageOpen` low while missing pixels are generated | TC-FSY-06 |
| An extra register stage at the output | TC-FSY-07 |
| `Out_Valid` not cleared by the reset | TC-FSY-05 |
| `Stat_ImageOpen` not cleared by the reset | TC-FSY-05, 06 |

## 7. Expected coverage exclusions

The code coverage of the release run will miss these items, which no stimulus at the ports can reach; they are the
recovery of FSY-FT-01 and are justified by the review:

- the `when others` branch of the image state machine (three states in a type of three values, or the encoding that
  the synthesis tool adds);
- the "greater" part of the comparisons of the column and line counters with their limits (`>=`): a counter above its
  limit needs an upset.

## 8. Test data

The pixels are random over the full range of `PixelBits_g`, from a seed per configuration and test, so that no
pattern repeats with a period; the position of every pixel is compared as well, so that a counting error shows even
where two pixels have the same value. The packet lengths and the gaps and stalls are random from their own seeds.
