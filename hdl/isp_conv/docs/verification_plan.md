# isp_conv: Verification Plan

## 1. Overview

The testbench `isp_conv_tb` sends window streams to the module, programs its coefficient registers through the
AXI4-Lite slave and checks every output pixel against a reference model. It uses the shared
[testbench components](../../../docs/testbench.md): the source with the window as its data, the sink with the
contract checker (the dimensions of the image that the window stream carries), the register script `ispRegsRun` and
a pulse counter of `Err_Config`.

The reference model `conv` of `tools/isp_model.py` computes every output pixel with the definitions of the
specification (section 1.1) in unbounded integers: S = sum of c(k) x e(k), q = 0 for S < 0, otherwise min(S, 2^B - 1).
It finds the image starts from the packets as the specification defines them (the first beat of a packet with the
sequence flags "01" or "11"), and keeps a model of the registers: the stored bits and the parity flag of every
coefficient register, `CTRL.HOLD`, `STATUS.ERR_CONFIG` and the expected read values. At every image start it takes
the coefficient set as the specification says and counts `Err_Config`.

The coefficient generic `Coef_g` is a vector of integers, which GHDL cannot set from the command line. The testbench
takes the coefficients as a string generic (decimal values separated by commas) and converts them with a function of
`tb/isp_tb_pkg.vhd`; `lint/synth_check.py` uses a wrapper entity in `lint/` with the coefficient sets of its
configurations.

Simulators: GHDL (regression, CI) and QuestaSim (code coverage at the release); VUnit with UVVM, test end
`ispTestEnd`. Tests observe ports and the AXI4-Lite interface only. The latency for the drain time of the test end is
3 + log2ceil(T) cycles.

## 2. Configurations

### 2.1 Configurations of every test

| Configuration | Window (T) | Pixel / coefficient / output bits | Run time | Coefficients of the generic | Image (windows) | Gaps / stalls |
| --- | --- | --- | --- | --- | --- | --- |
| `mtf3` | 3 x 3 (9) | 12 / 16 / 0 (F = 31) | true | A sharpening kernel: centre 28, edges -2, corners -1 (gain 16) | 8 x 6 | 20 % / 20 % |
| `mtf5_const` | 5 x 5 (25) | 12 / 16 / 12 (saturates) | false | A symmetric 5 x 5 sharpening kernel with negative and positive values | 8 x 6 | 30 % / 40 % |
| `ones4` | 1 x 4 (4) | 12 / 2 / 0 | false | Ones (the binning of `isp_bin`) | 6 x 4 | 20 % / 20 % |
| `exhaustive` | 1 x 2 (2) | 3 / 3 / 0 (F = 6) | true | 1, 1 | 8 x 8 | none |
| `exhaustive_sat` | 1 x 2 (2) | 3 / 3 / 3 (saturates) | true | 1, 1 | 8 x 8 | none |
| `min` | 1 x 1 (1) | 1 / 2 / 1 | true | 1 | 5 x 3 | 20 % / 20 % |
| `max` | 16 x 16 (256) | 32 / 18 / 64 (wider than F = 57) | true | Random over the full range | 4 x 3 | 10 % / 10 % |
| `wide` | 3 x 3 (9) | 32 / 18 / 0 (F = 53) | true | The bounds -2^17 and 2^17 - 1 and random values | 6 x 4 | 20 % / 20 % |
| `rate_3`, `rate_5`, `rate_256` | 3 x 3, 5 x 5, 16 x 16 | 12 / 16 / 0 | true | Random | 16 x 6 | none |

### 2.2 Sweeps (tests `test_static` and `test_parity`)

| Sweep | Configurations | What it covers |
| --- | --- | --- |
| Size | n = 1 to 16: window n x (17 - n), 8-bit pixels, 8-bit coefficients, run time | Every value of `WinX_g` and `WinY_g` |
| Taps | 1 x 1, 1 x 2, 1 x 3, 2 x 2, 1 x 5, 2 x 4, 3 x 11 (33), 2 x 16 (32), 5 x 13 (65), 4 x 16 (64), 10 x 13 (130), 8 x 16 (128), 15 x 16 (240), 16 x 16 (256); 6-bit pixels, 6-bit coefficients, constant | Every depth of the adder tree (0 to 8 levels) with a full and a partly filled last level |
| Widths | Window 3 x 3 with (pixel, coefficient, output) bits (1, 2, 1), (3, 3, 0), (16, 17, 12), (31, 18, F), (32, 18, 64), (32, 2, 0) | The bounds of `PixelBits_g`, `CoefBits_g` and `OutBits_g` and the saturation at, below and above the full precision |

### 2.3 Generic coverage

| Generic | Declared range | Simulated | Synthesised (TC-CNV-11) |
| --- | --- | --- | --- |
| `PixelBits_g` | 1 to 32 | 1, 3, 6, 8, 12, 16, 31, 32 | 1, 32 |
| `WinX_g`, `WinY_g` | 1 to 16 | every value | 1, 16 |
| `CoefBits_g` | 2 to 18 | 2, 3, 6, 8, 16, 17, 18 | 2, 18 |
| `Coef_g` | T values of -2^(`CoefBits_g` - 1) to 2^(`CoefBits_g` - 1) - 1 | both bounds of every simulated `CoefBits_g`, 0, 1, -1, random | both bounds |
| `RuntimeCoef_g` | false, true | both | both |
| `OutBits_g` | 0, 1 to 64 | 0, 1, 3, 12, F, 64 | 0, 1, 64 |

## 3. Test cases

### 3.1 Checks in every test

| Check | Where | Requirements |
| --- | --- | --- |
| Every output beat (pixel, `Out_Last`, `Out_User`) equals the model | Sink | CNV-IF-02, CNV-FN-01, CNV-FN-02 |
| Output contract with the dimensions of the image (tests with well-formed images) | Sink | CNV-FN-02 |
| The number of `Err_Config` pulses equals the model | Testbench | CNV-IF-04 |
| Control outputs free of metavalues after the first reset, `Out_Valid` and `Err_Config` 0 after every reset; no metavalue in an output pixel while `Out_Valid` is high | Testbench | CNV-FT-03, CNV-IF-05 |
| Every AXI4-Lite access answered with OKAY | BFM | CNV-RG-01 |

### 3.2 Test list

| Test | Description | Requirements |
| --- | --- | --- |
| `test_static` (TC-CNV-01) | Four images of random windows with the coefficients of the generic, plus in every image a window of largest elements (the largest sum) and of zero elements, and windows that give the most negative sum and a sum of exactly 0; back to back and with pauses | CNV-IF-01, CNV-IF-02, CNV-FN-01 to 03, CNV-FN-05 |
| `test_runtime` (TC-CNV-02) | Coefficient sets written between images: random sets, both bounds, a set that changes the sign of every coefficient; a set written during an image takes effect with the next image; every coefficient read back sign-extended | CNV-FN-01, CNV-FN-04, CNV-RG-03 |
| `test_hold` (TC-CNV-03) | `CTRL.HOLD` 1: coefficients written over two images, which keep the set before; `CTRL.HOLD` 0: the next image takes the whole new set; `CTRL.HOLD` 1 with a register of bad parity takes no set and reports nothing | CNV-FN-04 |
| `test_parity` (TC-CNV-04) | `INJECT` for every coefficient in turn for T up to 16; above, the first, the last and eight random ones, because the parity paths of all coefficients come from one generate loop of the RTL: the next image and every further image use the generic with one `Err_Config` each until the register is written; two injections in one set; a second injection that restores the parity; an index of T or above without effect. `INJECT.CTRL_PARITY` with `CTRL.HOLD` 1: the held set is taken at every image start, with one `Err_Config` each, until `CTRL` is written. With `RuntimeCoef_g` false no effect. Partial writes (PKG-08): an injection, then a write that keeps a byte with bits of the register and a write of only bytes without bits: the next images still use the generics with `Err_Config`; a write of every byte with bits clears the mismatch; a partial write without a mismatch is taken (one random coefficient; with `CoefBits_g` above 8 and below 25 both kinds of write) | CNV-IF-04, CNV-ER-01, CNV-ER-02, CNV-FT-02, CNV-RG-03, CNV-RG-04, CNV-FT-01, PKG-08 |
| `test_registers` (TC-CNV-05) | `ID`, `PARAM`, the reset values of all coefficients (the generic, sign-extended); writes with every single byte strobe; writes to read-only registers and with `RuntimeCoef_g` false to the coefficients without effect; the addresses above the last coefficient and the gaps read 0; `STATUS.ERR_CONFIG` set, kept by a write of 0, cleared by a write of 1; `INJECT` reads 0 | CNV-RG-01, CNV-RG-02, CNV-RG-03, CNV-IF-03 |
| `test_flag_coincidence` (TC-CNV-06) | The clear of `STATUS.ERR_CONFIG` swept cycle by cycle across an `Err_Config` pulse, as in `isp_crop` (TC-CRP-07) | CNV-RG-02 |
| `test_exhaustive` (TC-CNV-07) | Configurations `exhaustive` and `exhaustive_sat`: every coefficient pair (64 sets) as a run-time set, each over an image of all 64 element pairs: every sign, carry and saturation case of the arithmetic | CNV-FN-01 |
| `test_packets` (TC-CNV-08) | Streams that `isp_window` does not produce but that define the image start: a "01" packet after "00" packets, single-window packets, `In_Last` on every beat, other flags on the later beats of a packet, images back to back without a gap; the contract checker is off | CNV-FN-02, CNV-FN-04, CNV-FN-05 |
| `test_reset` (TC-CNV-09) | Resets idle, held and running, of one and two cycles, also between the image start and the first output pixel; the window stream stops at the reset and the next image follows, as from an `isp_window` reset with the module; after the reset the registers hold the generic and the next image uses it | CNV-IF-05, CNV-FT-03, CNV-FT-01 |
| `test_rate` (TC-CNV-10) | Configurations `rate_*`: images back to back with `In_Valid` and `Out_Ready` high: one window per cycle at the input and one pixel per cycle at the output, every pixel exactly 3 + log2ceil(T) cycles after its window | CNV-PF-01, CNV-PF-02 |
| TC-CNV-11 (`lint/synth_check.py`) | GHDL synthesis without latches at the bounds of section 2.3 and both values of `RuntimeCoef_g`; elaboration stops with the message naming the generic for: `PixelBits_g` 33, `WinX_g` 17, `WinY_g` 17, `CoefBits_g` 1 and 19, `OutBits_g` 65, a `Coef_g` with T - 1 and T + 1 values, a coefficient of 2^(`CoefBits_g` - 1) and of -2^(`CoefBits_g` - 1) - 1 | CNV-CF-01, CNV-CF-02 |
| TC-CNV-12 (`lint/vivado_ooc.py`) | Out-of-context synthesis and implementation at 150 MHz on the device of the Timing level (architecture, section 10): 3 x 3 and 5 x 5 with 12-bit pixels and 16-bit run-time coefficients (the defaults of the MTF filter), 16 x 16 run-time (the largest), 1 x 4 ones (the binning) | CNV-CF-03 |

## 4. Requirement coverage

| Requirement | Test cases | Method |
| --- | --- | --- |
| CNV-IF-01, CNV-IF-02 | TC-CNV-01 to 10 | Test |
| CNV-IF-03 | TC-CNV-05 | Test |
| CNV-IF-04 | TC-CNV-04 | Test |
| CNV-IF-05 | TC-CNV-09 | Test and review |
| CNV-FN-01 | TC-CNV-01, 02, 07 | Test |
| CNV-FN-02 | TC-CNV-01, 08 | Test |
| CNV-FN-03 | TC-CNV-01 | Test |
| CNV-FN-04 | TC-CNV-02, 03, 08 | Test |
| CNV-FN-05 | TC-CNV-01 (configurations with and without gaps and stalls), 08 | Test |
| CNV-PF-01, CNV-PF-02 | TC-CNV-10 | Test |
| CNV-ER-01, CNV-ER-02 | TC-CNV-04 | Test |
| CNV-FT-01 | TC-CNV-04, 09 and review (no state between windows) | Test and review |
| CNV-FT-02 | TC-CNV-04 | Test |
| CNV-FT-03 | TC-CNV-09 and the checks of section 3.1 | Test |
| CNV-RG-01 | TC-CNV-02, 05 | Test |
| CNV-RG-03 | TC-CNV-02, 04, 05 | Test |
| CNV-RG-02 | TC-CNV-05, 06 | Test |
| CNV-RG-04 | TC-CNV-04 | Test |
| CNV-CF-01, CNV-CF-02 | TC-CNV-11 | Synthesis |
| CNV-CF-03 | TC-CNV-12 | Timing |

## 5. Timing bounds

| Bound | Design value | Derivation |
| --- | --- | --- |
| One window per cycle (CNV-PF-01) | 1 | All stages advance with one common enable when the output register is free (architecture, section 4) |
| Latency at most 3 + log2ceil(T) (CNV-PF-02) | 3 + log2ceil(T) | Input register, products, log2ceil(T) adder levels, output register |

The arithmetic is exact: the model computes in unbounded integers, and every output pixel is compared bit for bit.

## 6. Negative tests and mutations

| Mutation | Expected to fail |
| --- | --- |
| A negative sum not set to 0 (wraps) | TC-CNV-01, 07 |
| No saturation below the full precision (truncation) | TC-CNV-01 (`mtf5_const`), 07 (`exhaustive_sat`) |
| An element multiplied as a signed number (its top bit as sign) | TC-CNV-01, 07 |
| The last product dropped when a level of the adder tree has an odd count | TC-CNV-01 (taps sweep) |
| The working set loaded at the first beat of every packet, not only at the image start | TC-CNV-08 |
| `CTRL.HOLD` without effect | TC-CNV-03 |
| No parity check of the coefficients | TC-CNV-04 |
| No parity check of `CTRL` | TC-CNV-04 |
| No `Err_Config` pulse | TC-CNV-04 |
| `INJECT.INDEX` ignored (always coefficient 0) | TC-CNV-04 |
| A coefficient read back without sign extension | TC-CNV-02, 05 |
| `Out_Last` one stage early | TC-CNV-01 (contract) |
| A stage that does not wait for the common enable | TC-CNV-01 (stalls) |
| `In_Ready` from a copy of the output valid flag stuck at 0 (always ready) | TC-CNV-01 and every test with stalls of the sink |
| The copy of the output valid flag one advance late | TC-CNV-01 and every test with stalls of the sink |
| A coefficient write that lands in the coefficient after its address | TC-CNV-02, 05 |
| The parity bit of a coefficient not set by its write | TC-CNV-02, 04 (a written set counts as a parity error at the image start) |
| A write with byte enables merged into zeros instead of the stored coefficient | TC-CNV-05 (writes with random strobes, CNV-RG-03) |
| `INJECT.PARITY` flips the parity bit of every coefficient | TC-CNV-04 |
| A write that keeps a byte with bits sets the parity for the resulting value (the re-seal before PKG-08) | TC-CNV-04 (an injection, then a partial write) |
| A write of every byte with bits keeps the syndrome | TC-CNV-04 (the full write after an injection) |
| A write of only bytes without bits sets the parity for the stored value | TC-CNV-04 (an injection, then a write of only bytes without bits) |
| The parity of a kept byte taken from the write data | TC-CNV-04, 05 (writes with random strobes) |
| The parity of a written byte taken from the stored bits | TC-CNV-04 (a partial write, and every write that changes a byte) |

## 7. Expected coverage exclusions

- The `when others` branch of the register decoder and of `olo_axi_lite_slave` (Open Logic).
- With `RuntimeCoef_g` false the coefficient registers and the parity logic do not exist; their coverage comes from
  the configurations with `RuntimeCoef_g` true.

## 8. Test data

The elements of the windows are random over the full range of `PixelBits_g`, independently for every element, with
the extreme windows of `test_static` added. The coefficient sets are random within their range and at their bounds;
`test_exhaustive` covers every combination of the small configurations.
