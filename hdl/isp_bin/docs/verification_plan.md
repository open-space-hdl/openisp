# isp_bin: Verification Plan

## 1. Overview

`isp_bin` adds no logic of its own: a horizontal `isp_filter2d` adds `BinX_g` pixels of a line, a vertical one adds
`BinY_g` lines of the narrowed image. This plan verifies the function of the module against the definition of a bin
(specification, section 1.1) and the connection of the two filters.

The testbench `isp_bin_tb` uses the shared [testbench components](../../../docs/testbench.md): the source, the sink
with the contract checker (Wo x Ho), the injection script for the line buffers of the vertical filter and the pulse
counters of the status outputs.

The reference model `bin` of `tools/isp_model.py` computes every output pixel from the definition of a bin: the sum of
the pixels p'(n x `BinX_g` + i, m x `BinY_g` + j) of the image extended by the border mode, for the Wo x Ho bins of
the specification. It does not use the models of the parts, so it checks that the two filters in series give the
sums of the bins. For the error injection into the line buffers of the vertical filter, the model computes the
narrowed image from the definition and passes it through the model `window` with the geometry of the vertical filter.

Simulators: GHDL (regression, CI) and QuestaSim (code coverage at the release); VUnit with UVVM, test end
`ispTestEnd`. Tests observe ports only.

## 2. Configurations

### 2.1 Configurations of every test

| Configuration | W x H | Pixel bits | Bin | Border | Line buffers | Gaps / stalls |
| --- | --- | --- | --- | --- | --- | --- |
| `bin2_valid` | 13 x 9 | 12 | 2 x 2 | valid (the last column and line dropped) | AUTO, pipeline 1 | 20 % / 20 % |
| `bin2_zero` | 13 x 9 | 12 | 2 x 2 | zero | AUTO, pipeline 1 | 30 % / 40 % |
| `bin3x5_rep` | 14 x 12 | 12 | 3 x 5 (Q = P + 4, less than the sum of the two filter widths) | replicate | AUTO, pipeline 1 | 20 % / 20 % |
| `bin4` | 16 x 16 | 16 | 4 x 4 | valid | SRL, pipeline 0 | 20 % / 20 % |
| `bin_x_only` | 12 x 5 | 12 | 4 x 1 (no vertical filter) | zero | none | 20 % / 20 % |
| `bin_y_only` | 5 x 12 | 12 | 1 x 4 (no horizontal filter) | replicate | AUTO, pipeline 1 | 20 % / 20 % |
| `bin_none` | 6 x 4 | 12 | 1 x 1 (the frame sync only) | valid | none | 20 % / 20 % |
| `max` | 64 x 34 (Wo = 4, the block RAM bound) | 28 | 16 x 16 | replicate | BRAM, pipeline 1 | 10 % / 10 % |
| `bits1` | 8 x 6 | 1 | 2 x 3 | zero | AUTO, pipeline 0 | 20 % / 20 % |
| `image_equals_bin` | 4 x 4 | 12 | 4 x 4 | valid (one bin) | SRL, pipeline 1 | 20 % / 20 % |
| `w65536` | 65536 x 2 | 12 | 2 x 2 | valid | BRAM, pipeline 1 | 10 % / 10 % |
| `ecc` | 12 x 8 | 12 | 2 x 3 | zero | SRL, pipeline 1 | none |
| `rate_valid`, `rate_rep` | 16 x 8 | 12 | 4 x 2 | valid; replicate | AUTO, pipeline 1 | none |

### 2.2 Sweep (test `test_static`)

| Sweep | Configurations | What it covers |
| --- | --- | --- |
| Factors | n = 1 to 16: bin n x (17 - n), 8-bit pixels, image (n + 3) x (20 - n), the border modes valid, zero and replicate in turn | Every value of `BinX_g` and `BinY_g` |

### 2.3 Generic coverage

| Generic | Declared range | Simulated | Synthesised (TC-BIN-07) |
| --- | --- | --- | --- |
| `ImageWidth_g` | `BinX_g` to 65536 | `BinX_g` (4 of `image_equals_bin`), 5 to 20, 64, 65536 | `BinX_g`, 65536 |
| `ImageHeight_g` | `BinY_g` to 65536 | `BinY_g`, 4 to 34 | `BinY_g`, 65536 |
| `PixelBits_g` | 1 to 28 | 1, 8, 12, 16, 28 | 1, 28 |
| `BinX_g`, `BinY_g` | 1 to 16 | every value | 1, 16 |
| `BorderMode_g` | valid, zero, replicate | every value | every value |
| `EccPipeline_g`, `Resource_g` | as `isp_window` | 0, 1; AUTO, SRL, BRAM | every value |

## 3. Test cases

### 3.1 Checks in every test

| Check | Where | Requirements |
| --- | --- | --- |
| Every output beat (pixel, `Out_Last`, `Out_User`) equals the model | Sink | BIN-IF-02, BIN-FN-01, BIN-FN-03 |
| Output contract with Wo x Ho | Sink | BIN-FN-03, BIN-ER-01 |
| The numbers of `Err_Framing`, `Stat_EccSec` and `Stat_EccDed` pulses equal the model | Testbench | BIN-IF-03 |
| Control and status outputs free of metavalues after the first reset, `Out_Valid` and the pulses 0 after every reset | Testbench | BIN-IF-04 |

### 3.2 Test list

| Test | Description | Requirements |
| --- | --- | --- |
| `test_static` (TC-BIN-01) | Five images per configuration with random pixels over the full range, plus an image of largest pixels (the largest sums, no saturation), in different divisions into packets, back to back and with pauses | BIN-IF-01, BIN-IF-02, BIN-FN-01 to 04 |
| `test_input_stream` (TC-BIN-02) | Malformed input streams: complete output images; `Err_Framing` and `Stat_ImageOpen` | BIN-ER-01, BIN-IF-03 |
| `test_ecc` (TC-BIN-03) | Configuration `ecc` and the sweep with `BinY_g` 1: single and double errors injected into the line buffers of the vertical filter, the double error visible in the sums of the bins that use the narrowed pixel; with `BinY_g` 1 no effect | BIN-IF-03, BIN-FT-01 |
| `test_reset` (TC-BIN-04) | Resets during a line, between the two filters' virtual lines and between images; the next image complete and correct | BIN-IF-04, BIN-FT-01, BIN-ER-01 |
| `test_rate` (TC-BIN-05) | Configurations `rate_*`: hold cycles of the input between the first pixels of two lines (at most `BinX_g` - 1 with replicate, none with valid) and the interval between two image starts against the bounds of BIN-PF-02; the latency after the last pixel of a bin is recorded (architecture, section 5) | BIN-PF-01, BIN-PF-02 |
| TC-BIN-06 (review) | The RTL consists of the two filters with the generics of the specification (section 4) and leaves out a filter of factor 1 | BIN-FN-04 |
| TC-BIN-07 (`lint/synth_check.py`) | GHDL synthesis without latches at the bounds of section 2.3 and every border mode; elaboration stops with the message naming the generic for: `BinX_g` 17, `BinY_g` 17, `PixelBits_g` 29, the border mode mirror, `ImageWidth_g` below `BinX_g`, `Resource_g` BRAM with Wo below 3 + `EccPipeline_g` | BIN-CF-01, BIN-CF-02 |
| TC-BIN-08 (`lint/vivado_ooc.py`) | Out-of-context synthesis and implementation at 150 MHz on the device of the Timing level (architecture, section 10): 2 x 2 valid, 12-bit pixels, 4096 pixels per line (the default); 4 x 4 replicate | BIN-CF-03 |

## 4. Requirement coverage

| Requirement | Test cases | Method |
| --- | --- | --- |
| BIN-IF-01, BIN-IF-02 | TC-BIN-01 to 05 | Test |
| BIN-IF-03 | TC-BIN-02, 03 | Test |
| BIN-IF-04 | TC-BIN-04 | Test |
| BIN-FN-01, BIN-FN-02, BIN-FN-03 | TC-BIN-01 (all configurations and the sweep) | Test |
| BIN-FN-04 | TC-BIN-01 (`bin_x_only`, `bin_y_only`, `bin_none`), 06 | Test and review |
| BIN-PF-01, BIN-PF-02 | TC-BIN-05 | Test |
| BIN-ER-01 | TC-BIN-02, 04 | Test |
| BIN-FT-01 | TC-BIN-03, 04 | Test |
| BIN-CF-01, BIN-CF-02 | TC-BIN-07 | Synthesis |
| BIN-CF-03 | TC-BIN-08 | Timing |

## 5. Timing bounds

| Bound | Design value | Derivation |
| --- | --- | --- |
| Hold cycles between the first pixels of two lines: at most `BinX_g` - 1, none in the mode valid (BIN-PF-01) | `BinX_g` - 1; 0 | The virtual columns of the horizontal filter (Rr = `BinX_g` - 1 with the anchor 0); the vertical filter has no virtual columns (`WinX_g` = 1) and takes one pixel in `BinX_g` cycles |
| Image period (BIN-PF-02) | H x W, H x (W + `BinX_g` - 1) + (`BinY_g` - 1) x Wo, plus the registers of the two filters | Specification, section 2.3 and architecture, section 5 |

The bench checks the design values. A measured value outside the derivation is a finding: the cause is found (the
RTL or the derivation), recorded in the findings of the verification report, and the wrong one is corrected. A
derivation is never adjusted to fit a measurement.

## 6. Negative tests and mutations

| Mutation | Expected to fail |
| --- | --- |
| The output width of the horizontal filter one bit short | TC-BIN-01 (the image of largest pixels) |
| The stride of the vertical filter 1 instead of `BinY_g` | TC-BIN-01 (contract) |
| The border mode not passed to the vertical filter | TC-BIN-01 (`bin2_zero`, `bin3x5_rep`) |
| The vertical filter kept for `BinY_g` 1 with a window of one line | TC-BIN-06 (review), ports of the line buffers |
| `Stat_EccDed` of the vertical filter not connected | TC-BIN-03 |

## 7. Expected coverage exclusions

The coverage of the parts is measured by their own benches. The frame sync of the vertical filter acts only after an
upset between the two filters (architecture, section 4).

## 8. Test data

Random pixels over the full range of `PixelBits_g`, and in every configuration an image of largest pixels, so that
the sums reach the top of the output width.
