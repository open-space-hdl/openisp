# isp_filter2d: Verification Plan

## 1. Overview

`isp_filter2d` adds no logic of its own: it is an `isp_window` whose window stream feeds an `isp_conv`. The parts are
verified by their own plans; this plan verifies the connection and the requirements of the filter as a whole, with
the configurations that the suite uses (the MTF compensation and the filters of `isp_bin`).

The testbench `isp_filter2d_tb` uses the shared [testbench components](../../../docs/testbench.md) as the benches of
the parts do: the source, the sink with the contract checker (Wo x Ho), the register script on the AXI4-Lite slave of
the filter, the injection script for the line buffers and the pulse counters of the status outputs.

The reference model `filter2d` of `tools/isp_model.py` connects the models of the parts: the windows of the model
`window` (with the line buffers and their error injection) are the input of the kernel of the model `conv` (with its
coefficient set, image starts and registers). FLT-FN-01 is the composition of the definitions of the two
specifications, so a model of the filter written from FLT-FN-01 alone would add no check that the parts do not
already make; the composition checks that the module connects them as the two models do.

Simulators: GHDL (regression, CI) and QuestaSim (code coverage at the release); VUnit with UVVM, test end
`ispTestEnd`. Tests observe ports and the AXI4-Lite interface only. The coefficient set is a string generic of the
testbench, as for `isp_conv`.

## 2. Configurations

| Configuration | W x H | Bits (pixel / coefficient / output) | Window, anchor, stride | Border | Coefficients | Gaps / stalls |
| --- | --- | --- | --- | --- | --- | --- |
| `mtf3` | 12 x 8 | 12 / 16 / 0 | 3 x 3, middle, 1 | replicate | Run time; default a sharpening kernel of gain 16 | 20 % / 20 % |
| `mtf5_mirror` | 14 x 10 | 12 / 16 / 0 | 5 x 5, middle, 1 | mirror | Run time; default a symmetric 5 x 5 kernel | 30 % / 40 % |
| `mtf5_const` | 14 x 10 | 16 / 12 / 16 (saturates) | 5 x 5, middle, 1 | zero | Constant | 20 % / 20 % |
| `valid` | 12 x 8 | 12 / 16 / 0 | 3 x 3, middle, 1 | valid | Constant | 20 % / 20 % |
| `strided` | 13 x 9 | 12 / 16 / 0 | 4 x 2, (1, 0), 3 x 2 | replicate | Run time | 20 % / 20 % |
| `bin_h`, `bin_v` | 13 x 9 | 12 / 2 / 14 | 4 x 1 and 1 x 4, anchor 0, stride 4 | zero | Ones, constant (the two filters of `isp_bin`) | 20 % / 20 % |
| `separable` | 12 x 8 | 12 / 16 / 0 | 1 x 5 and 5 x 1 in two instances | replicate | Constant | 20 % / 20 % |
| `max` | 18 x 17 | 32 / 18 / 0 | 16 x 16, middle, 1 | zero | Run time, random | 10 % / 10 % |
| `ecc` | 10 x 7 | 12 / 16 / 0 | 3 x 3, middle, 1 | replicate | Run time | none |
| `rate_3`, `rate_5` | 16 x 6 | 12 / 16 / 0 | 3 x 3 and 5 x 5, middle, 1 | replicate | Run time | none |

The configuration `separable` instantiates two filters in series in the testbench (the use that the specification
names in section 6); its model is the composition of two models `filter2d`.

## 3. Test cases

### 3.1 Checks in every test

| Check | Where | Requirements |
| --- | --- | --- |
| Every output beat (pixel, `Out_Last`, `Out_User`) equals the model | Sink | FLT-IF-02, FLT-FN-01, FLT-FN-02 |
| Output contract with Wo x Ho | Sink | FLT-FN-02, FLT-ER-01 |
| The numbers of `Err_Framing`, `Stat_EccSec`, `Stat_EccDed` and `Err_Config` pulses equal the model | Testbench | FLT-IF-04 |
| Control and status outputs free of metavalues after the first reset, `Out_Valid` and the pulses 0 after every reset | Testbench | FLT-IF-05 |
| Every AXI4-Lite access answered with OKAY | BFM | FLT-IF-03 |

### 3.2 Test list

| Test | Description | Requirements |
| --- | --- | --- |
| `test_static` (TC-FLT-01) | Five images of random pixels with the coefficients of the generic, in different divisions into packets, back to back and with pauses | FLT-IF-01, FLT-IF-02, FLT-FN-01 to 03 |
| `test_input_stream` (TC-FLT-02) | Malformed input streams through the frame sync of the window: complete output images, `Err_Framing`, `Stat_ImageOpen` | FLT-ER-01, FLT-IF-04, FLT-FN-03 |
| `test_runtime` (TC-FLT-03) | Coefficient sets written through the slave of the filter between images (also with `CTRL.HOLD`), read back; the kernel of an image changes with the next image start of the window stream | FLT-IF-03, FLT-FN-03 |
| `test_errors` (TC-FLT-04) | A double error injected into a line buffer of the window changes the windows that contain the pixel, and the output pixels of these windows follow; a single error leaves them unchanged; a parity injection of a coefficient applies the generic for an image; all pulses reach the ports of the filter | FLT-IF-04, FLT-FT-01 |
| `test_reset` (TC-FLT-05) | Resets during an image, during the virtual lines of the window and while the kernel holds windows; the next image complete and correct | FLT-IF-05, FLT-FT-01, FLT-ER-01 |
| `test_rate` (TC-FLT-06) | Configurations `rate_*`: hold cycles of the input and image period as `isp_window` (design values of its plan), latency of every pixel from the acceptance of p(x + Rr, y + Rb): bound log2ceil(T) + 9, design value 6 + log2ceil(T) to 8 + log2ceil(T) (window 3 to 5, kernel 3 + log2ceil(T)) | FLT-PF-01, FLT-PF-02 |
| TC-FLT-07 (`lint/synth_check.py`) | GHDL synthesis without latches of the configurations `mtf3`, `mtf5_mirror`, `valid`, `strided`, `bin_h` and of `mtf3` with constant coefficients; a generic out of range (`WinX_g` 17, `CoefBits_g` 19, an unknown border mode, a `Coef_g` of T - 1 values) stops the elaboration with the message of the part that checks it | FLT-CF-01, FLT-CF-02 |
| TC-FLT-08 (`lint/vivado_ooc.py`) | Out-of-context synthesis and implementation at 150 MHz on the device of the Timing level (architecture, section 10): 5 x 5 mirror, 12-bit pixels, 16-bit run-time coefficients, 4096 pixels per line (the MTF compensation) | FLT-CF-03 |

## 4. Requirement coverage

| Requirement | Test cases | Method |
| --- | --- | --- |
| FLT-IF-01, FLT-IF-02 | TC-FLT-01 to 06 | Test |
| FLT-IF-03 | TC-FLT-03 | Test |
| FLT-IF-04 | TC-FLT-02, 04 | Test |
| FLT-IF-05 | TC-FLT-05 | Test |
| FLT-FN-01, FLT-FN-02 | TC-FLT-01 (all configurations) | Test |
| FLT-FN-03 | TC-FLT-01 to 03 | Test |
| FLT-PF-01, FLT-PF-02 | TC-FLT-06 | Test |
| FLT-ER-01 | TC-FLT-02, 05 | Test |
| FLT-FT-01 | TC-FLT-04, 05 | Test |
| FLT-CF-01, FLT-CF-02 | TC-FLT-07 | Synthesis |
| FLT-CF-03 | TC-FLT-08 | Timing |

## 5. Timing bounds

| Bound | Design value | Derivation |
| --- | --- | --- |
| Hold cycles and image period as `isp_window` (FLT-PF-01) | The design values of the plan of `isp_window` | The kernel takes one window per cycle and adds no hold (plan of `isp_conv`) |
| Latency log2ceil(T) + 9 (FLT-PF-02) | 6 + log2ceil(T), up to 8 + log2ceil(T) | Window 3, up to 5 after a hold of the input; kernel 3 + log2ceil(T) |

The bench checks the design values: the hold cycles and the image period of the plan of `isp_window`, a latency
between 6 + log2ceil(T) and 8 + log2ceil(T). A measured value outside the derivation is a finding: the cause is found
(the RTL or the derivation), recorded in the findings of the verification report, and the wrong one is corrected. A
derivation is never adjusted to fit a measurement.

## 6. Negative tests and mutations

| Mutation | Expected to fail |
| --- | --- |
| `Out_Last` and `Out_User` of the window not passed to the kernel (constant) | TC-FLT-01 (contract) |
| The window elements reversed in order at the connection | TC-FLT-01 (asymmetric kernels of `strided`, `max`) |
| `ErrInj_Valid` not connected | TC-FLT-04 |
| `Err_Config` of the kernel not connected | TC-FLT-04 |
| `Stat_EccSec` and `Stat_EccDed` of the window exchanged | TC-FLT-04 |
| `Stat_ImageOpen` of the window not connected | TC-FLT-02 (the probes of the source) |
| The register slave of the kernel not connected (reads 0) | TC-FLT-03 |

## 7. Expected coverage exclusions

The coverage of the parts is measured by their own benches; this bench adds the connection. No exclusion of its own.

## 8. Test data

Random pixels over the full range; random and bounded coefficient sets as in the plan of `isp_conv`; the asymmetric
kernels of `strided` and `max` make an exchange of elements visible.
