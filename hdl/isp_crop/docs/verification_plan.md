# isp_crop: Verification Plan

## 1. Overview

The testbench `isp_crop_tb` sends images to the module, programs its registers through the AXI4-Lite slave and
checks every output beat against a reference model. It uses the shared
[testbench components](../../../docs/testbench.md):

- The source drives `In_*` from the stimulus file, with random gaps; its probe input is `Stat_ImageOpen`.
- The sink compares `Out_*` with the expected file (no sideband) and checks the output contract with the dimensions
  of the region, `RoiWidth_g` x `RoiHeight_g`.
- The register script of the test (`<test>.regs`, testbench components section 7) is executed by the procedure
  `ispRegsRun` of `isp_tb_axilite_pkg` with the AXI4-Lite BFM of UVVM: the source sets a marker, the script performs
  the accesses of that marker (writes, reads with a check of the value) and acknowledges, and the source goes on.
  Register accesses therefore fall between two known beats of the stream.
- The reference model `crop` of `tools/isp_model.py` takes the output of the model `frame_sync` (the module takes its
  input through `isp_frame_sync`) and the position of the region for every image, and selects the pixels of the
  region with the packets of the output image. The position of every image is computed by the generator from the
  register writes that precede the image start, with the rules of the specification: a written position is used when
  it lies inside the image and its parity bit matches; otherwise the generics apply and `Err_Config` pulses.
- The testbench counts the pulses of `Err_Framing` and `Err_Config` and compares them with the model, monitors the
  control outputs for metavalues and their values after every reset, and checks the timing of test_rate and the
  coincidence of test_flag_coincidence.

Simulators: GHDL (regression, CI) and QuestaSim (code coverage at the release); VUnit with UVVM, test end
`ispTestEnd`. Tests observe ports and the AXI4-Lite interface only. The latency for the drain time of the test end is
4 cycles (testbench components, section 6).

## 2. Configurations

| Configuration | W x H | `PixelBits_g` | Region (X, Y, width, height) | `RuntimeRoi_g` | Gaps / stalls | Tests |
| --- | --- | --- | --- | --- | --- | --- |
| `w8_h6_static` | 8 x 6 | 12 | 2, 1, 4, 3 | false | none | static, input_stream, registers, reset, rate |
| `w8_h6_static_bp` | 8 x 6 | 12 | 2, 1, 4, 3 | false | 30 % / 40 % | static, input_stream, parity, registers, reset |
| `w8_h6_runtime` | 8 x 6 | 12 | 2, 1, 4, 3 | true | 30 % / 40 % | all except rate and flag_coincidence |
| `w8_h6_runtime_rate` | 8 x 6 | 12 | 2, 1, 4, 3 | true | none | rate, flag_coincidence |
| `w8_h6_full` | 8 x 6 | 8 | 0, 0, 8, 6 | true | 20 % / 20 % | static, input_stream, runtime_position, invalid_position |
| `w8_h6_corner` | 8 x 6 | 16 | 7, 5, 1, 1 | true | 20 % / 20 % | static, runtime_position, invalid_position, parity |
| `w8_h6_line` | 8 x 6 | 1 | 0, 5, 8, 1 | false | 20 % / 20 % | static, input_stream |
| `w8_h6_column` | 8 x 6 | 64 | 3, 0, 1, 6 | false | 20 % / 20 % | static, input_stream |
| `w1_h1` | 1 x 1 | 7 | 0, 0, 1, 1 | true | 30 % / 40 % | static, input_stream, runtime_position, parity, reset |
| `w33_h9` | 33 x 9 | 13 | 5, 2, 20, 6 | true | 20 % / 20 % | all except rate and flag_coincidence |
| `w33_h9_rate` | 33 x 9 | 13 | 5, 2, 20, 6 | false | none | rate (13 pixels outside the region between two lines of the region, more than the module holds) |
| `w65536_h1` | 65536 x 1 | 12 | 65535, 0, 1, 1 | true | 10 % / 10 % | static, runtime_position, invalid_position |
| `w1_h65536` | 1 x 65536 | 12 | 0, 0, 1, 65536 | false | 10 % / 10 % | static |

Generic coverage:

| Generic | Declared range | Simulated | Synthesised (TC-CRP-10) |
| --- | --- | --- | --- |
| `ImageWidth_g` | 1 to 65536 | 1, 8, 33, 65536 | 1, 4096, 65536 |
| `ImageHeight_g` | 1 to 65536 | 1, 6, 9, 65536 | 1, 4096, 65536 |
| `PixelBits_g` | 1 to 64 | 1, 7, 8, 12, 13, 16, 64 | 1, 12, 64 |
| `RoiX_g`, `RoiY_g` | 0 to W - 1, 0 to H - 1 | 0, 2, 3, 5, 7, 65535 (the last column) | 0, the last column and line |
| `RoiWidth_g`, `RoiHeight_g` | 1 to W - X, 1 to H - Y | 1 (the smallest region), 4, 20, the whole line and the whole image, 65536 | 1, the whole image |
| `RuntimeRoi_g` | false, true | both | both |

The selection does no arithmetic on the pixel, so a representative set of pixel widths covers that range (as for
`isp_frame_sync`); the region is simulated at the corners and edges of the image, as a single pixel, a line, a column
and the whole image.

## 3. Test cases

### 3.1 Checks in every test

| Check | Where | Requirements |
| --- | --- | --- |
| Every output beat (pixel, `Out_Last`, `Out_User`) equals the model, in order, none missing, none extra | Sink | CRP-IF-02, CRP-FN-01, CRP-FN-04 |
| Output contract with the dimensions of the region: `RoiHeight_g` packets of `RoiWidth_g` pixels, flags in order and constant within a packet | Sink | CRP-FN-03, CRP-ER-01 |
| The numbers of cycles with `Err_Framing` high and with `Err_Config` high equal the model | Testbench | CRP-IF-03, CRP-IF-06 |
| `In_Ready`, `Out_Valid`, `Err_Framing`, `Err_Config` and `Stat_ImageOpen` free of metavalues after the first reset; `Out_Valid`, `Err_Framing`, `Err_Config` and `Stat_ImageOpen` 0 after every reset | Testbench | CRP-FT-02, CRP-IF-04 |
| Every AXI4-Lite access answered with OKAY | BFM of UVVM | CRP-RG-01 |

### 3.2 Test list

| Test | Description | Requirements |
| --- | --- | --- |
| `test_static` (TC-CRP-01) | Eight complete images back to back in different divisions into packets (one per line, one per image, one pixel per packet, random lengths); with `RuntimeRoi_g` true and no register written, the position of the generics | CRP-IF-01, CRP-IF-02, CRP-FN-01, CRP-FN-03, CRP-FN-04, CRP-FN-05, CRP-FN-06 |
| `test_input_stream` (TC-CRP-02) | Malformed input streams through the frame sync: short images completed with zeros (the missing pixels inside and outside the region), pixels without an image start, images ended by E3 and E4, random packets with random flags; `Stat_ImageOpen` probed while an image is open (1, an image cut after half of its pixels) and after complete images (0). The model is `crop` over `frame_sync` | CRP-FN-02, CRP-IF-03, CRP-ER-01, CRP-ER-02 |
| `test_runtime_position` (TC-CRP-03) | `RuntimeRoi_g` true: positions written between images: (0, 0), the largest valid (W - width, H - height), random; a write during an image, which takes effect with the next image; writes with single byte strobes (only X, only Y, one byte of each), each read back | CRP-FN-06, CRP-IF-05, CRP-RG-03 |
| `test_invalid_position` (TC-CRP-04) | X + width = W + 1, Y + height = H + 1, both, the largest X with a valid Y and the reverse (valid), a value of 65535 in both fields: an invalid position processes the image with the generics and pulses `Err_Config` once per image; `STATUS.ERR_CONFIG` set; `ROI_POS` reads back the written value; a valid write afterwards is used | CRP-ER-03, CRP-IF-06 |
| `test_parity` (TC-CRP-05) | `INJECT.ROI_POS_PARITY`: the next image and every further image use the generics with one `Err_Config` each, until `ROI_POS` is written; a second injection after the first restores the parity (the position is used again); an injection followed by a write; with `RuntimeRoi_g` false the injection has no effect. Partial writes (PKG-08): an injection, then a write of the bytes of X alone: the next images still use the generics with `Err_Config`; a write of all four bytes clears the mismatch; a write of the bytes of X without a mismatch is taken. Every byte of `ROI_POS` holds bits, so the write of only bytes without bits is the write without a strobe: it leaves the position and the parity bit unchanged, without and with a mismatch | CRP-ER-04, CRP-FT-01, CRP-FT-03, CRP-RG-03, CRP-RG-04, PKG-08 |
| `test_registers` (TC-CRP-06) | `ID`, `IMAGE`, `ROI_SIZE` and the reset values of `ROI_POS` and `STATUS`; writes to the read-only registers (and to `ROI_POS` with `RuntimeRoi_g` false) leave them unchanged; unused addresses read 0; `STATUS.IMAGE_OPEN` follows `Stat_ImageOpen`; `ERR_FRAMING` and `ERR_CONFIG` set by their events, kept by a write of 0, cleared by a write of 1; `INJECT` reads 0 | CRP-RG-01, CRP-RG-02, CRP-IF-05 |
| `test_flag_coincidence` (TC-CRP-07) | The clear of `STATUS.ERR_FRAMING` against an `Err_Framing` pulse (a discarded pixel) and the clear of `STATUS.ERR_CONFIG` against an `Err_Config` pulse (an image start with an invalid position): twelve steps move the write of 1 to `STATUS` cycle by cycle against the pulse. The write takes effect in the first cycle in which `BVALID` is high (`olo_axi_lite_slave` raises the write strobe and `BVALID` together); the testbench records the cycles of the pulse and of `BVALID` and, after every step, reads `STATUS`: the flag is set exactly when the pulse came in that cycle or later. Each sweep must contain steps before, at and after the pulse | CRP-RG-02 |
| `test_reset` (TC-CRP-08) | Resets idle, held and running in the middle of an image (inside and outside the region), resets of one cycle; after the reset `ROI_POS` holds the generics again and the images are correct | CRP-FT-02, CRP-IF-04, CRP-ER-02 |
| `test_rate` (TC-CRP-09) | Configurations without gaps and stalls. Phase 1: images back to back: `In_Ready` high for every beat, every pixel of the region at the output exactly 4 cycles after the acceptance of its input beat (the index of the input beat of every output pixel comes from the model, docs/testbench.md section 9), so the pixels of a line of the region leave in consecutive cycles. Phase 2: the last pixel of the first line of the region held in the output register (`Out_Ready` low): every pixel outside the region up to the next pixel of the region accepted in its cycle | CRP-PF-01, CRP-PF-02, CRP-PF-03 |
| TC-CRP-10 (`lint/synth_check.py`) | GHDL synthesis without latches at the bounds of section 2, both values of `RuntimeRoi_g`; `ImageWidth_g` 65537, `RoiWidth_g` 0, `RoiX_g` + `RoiWidth_g` > W, `RoiY_g` + `RoiHeight_g` > H and `PixelBits_g` 65 stop the elaboration with their message | CRP-CF-01, CRP-CF-02 |
| TC-CRP-11 (`lint/libero_synth.py`) | Preliminary synthesis on PolarFire MPF100T (Libero, Synplify Pro) with a clock of 125 MHz, the Timing level (architecture, section 10): 4096 x 4096 pixels, 12 bits, region at run time (the default); the resources and the estimated worst slack recorded in the verification report, a pre-layout estimate. The default configuration meets 125 MHz in the estimate; a further configuration records the frequency it reaches | CRP-CF-03 |

## 4. Requirement coverage

| Requirement | Test cases | Method |
| --- | --- | --- |
| CRP-IF-01, CRP-IF-02 | TC-CRP-01 to 09 | Test |
| CRP-IF-03 | TC-CRP-02 (count of the pulses, probes of `Stat_ImageOpen`) | Test |
| CRP-IF-04 | TC-CRP-08 | Test and review (one clock, the reset sampled in the clocked processes only) |
| CRP-IF-05 | TC-CRP-03, 06 | Test |
| CRP-IF-06 | TC-CRP-04, 05 | Test |
| CRP-FN-01, CRP-FN-03, CRP-FN-05 | TC-CRP-01 | Test |
| CRP-FN-02 | TC-CRP-02 | Test |
| CRP-FN-04 | TC-CRP-01 to 09 (configurations with and without gaps and stalls) | Test |
| CRP-FN-06 | TC-CRP-01, 03 | Test |
| CRP-PF-01 to CRP-PF-03 | TC-CRP-09 | Test |
| CRP-ER-01, CRP-ER-02 | TC-CRP-02, 08 | Test |
| CRP-ER-03 | TC-CRP-04 | Test |
| CRP-ER-04 | TC-CRP-05 | Test |
| CRP-FT-01 | TC-CRP-05 (the limits reloaded with every image) and review (no pixel position of its own) | Test and review |
| CRP-FT-02 | TC-CRP-08 and the checks of section 3.1 | Test |
| CRP-FT-03 | TC-CRP-05 | Test |
| CRP-RG-01 | TC-CRP-06 and the OKAY check of every access | Test |
| CRP-RG-02 | TC-CRP-06, 07 | Test |
| CRP-RG-03, CRP-RG-04 | TC-CRP-03, 05 | Test |
| CRP-CF-01, CRP-CF-02 | TC-CRP-10 | Synthesis |
| CRP-CF-03 | TC-CRP-11 | Timing |

## 5. Timing bounds

| Bound | Design value | Derivation |
| --- | --- | --- |
| Latency 4 cycles for a pixel of the region (CRP-PF-02) | 4 | 2 cycles in `isp_frame_sync`, 1 in the position stage, 1 in the output register |
| One pixel per cycle (CRP-PF-01) | 1 | Every stage is loaded when it is empty or read in the same cycle |
| Pixels outside the region with the output held (CRP-PF-03) | One per cycle until the next pixel of the region | A pixel outside the region leaves the position stage without the output register; the input waits only once a pixel of the region waits in the position stage, so phase 2 holds a pixel of the region in the output register and sends more pixels outside the region than the frame sync and the position stage hold (4) |
| Clear and event in the same cycle (CRP-RG-02) | The flag stays set | The write strobe of `olo_axi_lite_slave` is high in the first cycle of `BVALID`; the flag register takes the event and the clear at the end of that cycle, the event first |

## 6. Negative tests and mutations

The error paths are provoked from the bench: invalid positions, parity errors through `INJECT`, writes to read-only
registers, malformed input streams, resets. The pulse counts are compared exactly.

| Mutation | Expected to fail |
| --- | --- |
| The last column of the region dropped (`<` instead of `<=` for X1) | TC-CRP-01 |
| `Out_Last` at the first column of the region | TC-CRP-01 (contract) |
| The limits loaded once after the reset, not with every image | TC-CRP-03 |
| No range check of the position | TC-CRP-04 |
| No parity check | TC-CRP-05 |
| The parity bit not updated by a write | TC-CRP-03, 05 |
| `INJECT` without effect | TC-CRP-05 |
| The byte strobes ignored | TC-CRP-03 |
| The clear of `ERR_FRAMING` wins over the event | TC-CRP-07 |
| The clear of `ERR_CONFIG` wins over the event | TC-CRP-07 |
| Pixels outside the region wait for the output | TC-CRP-09 |
| No `Err_Config` pulse | TC-CRP-04, 05 |
| `ROI_POS` not set to the generics by the reset | TC-CRP-08 |
| `Stat_ImageOpen` tied to 0 (a port stuck at 1 fails every probe after a complete image, which expects 0) | TC-CRP-02 (the probe of the open image) |
| A write that keeps a byte with bits sets the parity for the resulting value (the re-seal before PKG-08) | TC-CRP-05 (an injection, then a partial write) |
| A write of every byte with bits keeps the syndrome | TC-CRP-05 (the full write after an injection) |
| A write of only bytes without bits sets the parity for the stored value | TC-CRP-05 (the write without a strobe, without and with a mismatch: the mutant sets the parity bit to 0, which differs from the parity bit before the write in one of the two states, whatever the parity of the position) |
| The parity of a kept byte taken from the write data | TC-CRP-05 (a partial write) |
| The parity of a written byte taken from the stored bits | TC-CRP-05 (a partial write, and every write that changes a byte) |

## 7. Expected coverage exclusions

- The `when others` branches of the state machines of `isp_frame_sync` and of `olo_axi_lite_slave` (Open Logic).
- With `RuntimeRoi_g` false the parity and range logic does not exist; its coverage comes from the configurations with
  `RuntimeRoi_g` true.

## 8. Test data

The pixels are random over the full range of `PixelBits_g`, from a seed per configuration and test. The positions of
the region are written at the corners, at the edges and at random, so that every bit of both fields changes.
