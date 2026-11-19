# isp_point: Verification Plan

## 1. Overview

The testbench `isp_point_tb` sends images to the module, programs its parameter registers through the AXI4-Lite slave
and checks every output pixel against a reference model. It uses the shared
[testbench components](../../../docs/testbench.md): the source (probe `Stat_ImageOpen`), the sink with the contract
checker (output dimensions W x H), the register script `ispRegsRun` and the pulse counters of `Err_Framing` and
`Err_Config`.

The reference model `point` of `tools/isp_model.py` takes the output of the model `frame_sync` and computes every
output pixel with the operation of the specification (section 1.1) in unbounded integers: q = min(max(v, Low), High)
with v = floor((p + Offset) x Gain / 2^Shift). It keeps a model of the registers: the stored bits of every
parameter register, its parity flag, `CTRL.HOLD` and the sticky flags; at every image start it takes the parameter
set as the specification says (registers when `CTRL.HOLD` is 0 and every parity bit matches, the generics when a parity
bit does not match, the set of the image before when `CTRL.HOLD` is 1) and counts `Err_Config`. It also gives the
expected value of every register read.

Simulators: GHDL (regression, CI) and QuestaSim (code coverage at the release); VUnit with UVVM, test end
`ispTestEnd`. Tests observe ports and the AXI4-Lite interface only. The latency for the drain time of the test end is
`MultStages_g` + 5 cycles.

## 2. Configurations

| Configuration | W x H | In / out / gain bits | `MaxShift_g` | `MultStages_g` | `Runtime_g` | Parameters of the generics (offset, gain, shift, low, high) | Gaps / stalls |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `shift` | 6 x 4 | 16 / 12 / 16 | 32 | 2 | false | 0, 1, 4, 0, -1 (a bit shift) | 20 % / 20 % |
| `dark_gain` | 6 x 4 | 12 / 12 / 16 | 28 | 2 | false | -100, 1229, 10, 0, -1 (dark level and gain 1.2) | 30 % / 40 % |
| `clamp` | 6 x 4 | 12 / 8 / 16 | 28 | 3 | false | 7, 3, 2, 20, 200 (both thresholds active) | none |
| `neutral` | 6 x 4 | 8 / 8 / 1 | 9 | 1 | false | the defaults (pass, limit to the output width) | 20 % / 20 % |
| `runtime` | 6 x 4 | 12 / 12 / 16 | 28 | 2 | true | the defaults | 30 % / 40 % |
| `runtime_rate` | 6 x 4 | 12 / 12 / 16 | 28 | 2 | true | the defaults | none |
| `exhaustive` | 16 x 1 | 4 / 4 / 3 | 6 | 4 | true | the defaults | none |
| `shift_limit` | 6 x 4 | 12 / 12 / 16 | 8 | 2 | true | the defaults (`MaxShift_g` far below the width of the product, so that the limit of the shift is visible) | 20 % / 20 % |
| `wide` | 4 x 3 | 64 / 32 / 18 | 83 | 4 | true | 0, 1, 0, 0, -1 | 20 % / 20 % |
| `narrow` | 3 x 2 | 1 / 1 / 1 | 0 | 1 | true | 0, 1, 0, 0, -1 | 20 % / 20 % |
| `stages_<n>`, n = 1 to 4 | 6 x 4 | 12 / 12 / 16 | 28 | n | true | the defaults | none |
| `w65536_h1` | 65536 x 1 | 12 / 12 / 16 | 28 | 2 | false | -100, 1229, 10, 0, -1 | 10 % / 10 % |
| `w1_h65536` | 1 x 65536 | 12 / 12 / 16 | 28 | 2 | false | -100, 1229, 10, 0, -1 | 10 % / 10 % |
| `generic_bounds` | 4 x 3 | 32 / 32 / 18 | 50 | 2 | false | -2^31, 2^18 - 1, 50, 2^31 - 1, -1 | none |

Generic coverage:

| Generic | Declared range | Simulated | Synthesised (TC-PNT-11) |
| --- | --- | --- | --- |
| `ImageWidth_g`, `ImageHeight_g` | 1 to 65536 | 1, 3, 4, 6, 16, 65536 | 1, 4096, 65536 |
| `InBits_g` | 1 to 64 | 1, 4, 8, 12, 16, 32, 64 | 1, 12, 64 |
| `OutBits_g` | 1 to 32 | 1, 4, 8, 12, 32 | 1, 12, 32 |
| `GainBits_g` | 1 to 18 | 1, 3, 16, 18 | 1, 16, 18 |
| `MaxShift_g` | 0 to `InBits_g` + `GainBits_g` + 1 | 0, 6, 8, 9, 28, 32, 50, 83 (the upper bound for 64 / 18) | 0 and the upper bound |
| `MultStages_g` | 1 to 4 | every value | every value |
| `Runtime_g` | false, true | both | both |
| `Offset_g`, `Gain_g`, `Shift_g`, `Low_g`, `High_g` | section 4 of the specification | the bounds (-2^31, 2^31 - 1, 0, 2^18 - 1, the largest shift, -1 and 0 for `High_g`) and typical values | the bounds |

`MultStages_g` changes the pipeline, so every value is simulated. The widths are numeric ranges of an arithmetic data
path: the bounds, the widths where an intermediate value reaches 32 and 64 bits, and a small configuration in which
the run-time parameters are swept exhaustively (`exhaustive`) cover them.

## 3. Test cases

### 3.1 Checks in every test

| Check | Where | Requirements |
| --- | --- | --- |
| Every output beat (pixel, `Out_Last`, `Out_User`) equals the model | Sink | PNT-IF-02, PNT-FN-01 |
| Output contract with W x H | Sink | PNT-FN-02, PNT-ER-01 |
| The numbers of `Err_Framing` and `Err_Config` pulses equal the model | Testbench | PNT-IF-04 |
| Control outputs free of metavalues after the first reset, `Out_Valid` and the pulses 0 after every reset | Testbench | PNT-FT-03, PNT-IF-05 |
| Every AXI4-Lite access answered with OKAY | BFM | PNT-RG-01 |

### 3.2 Test list

| Test | Description | Requirements |
| --- | --- | --- |
| `test_static` (TC-PNT-01) | Six images in different divisions into packets with the parameters of the generics: random pixels over the full input range, plus the pixels 0 and the largest value in every image | PNT-IF-01, PNT-IF-02, PNT-FN-01, PNT-FN-03, PNT-FN-06 |
| `test_input_stream` (TC-PNT-02) | Malformed input streams through the frame sync (short images, pixels without an image start, E3, E4, random packets): the missing pixels (value 0) pass the operation; `Stat_ImageOpen` probed | PNT-FN-02, PNT-ER-01, PNT-ER-02, PNT-IF-04 |
| `test_runtime` (TC-PNT-03) | Parameter sets written between images: random sets, the gains 0, 1 and the largest, the shifts 0, the largest, `MaxShift_g` + 1 and 127 (taken as `MaxShift_g`), the most negative and the largest offset, `Low` above `High`, `Low` equal to `High`; a set written during an image takes effect with the next image; every register read back (offset sign-extended, unused bits) | PNT-FN-01, PNT-FN-04, PNT-FN-05, PNT-RG-03, PNT-RG-05 |
| `test_hold` (TC-PNT-04) | `CTRL.HOLD` 1: several registers written over two images, which keep the set before; `CTRL.HOLD` 0: the next image takes the whole new set; `CTRL.HOLD` 1 with a register of bad parity takes no set and reports nothing | PNT-FN-04 |
| `test_parity` (TC-PNT-05) | Every bit of `INJECT` in turn: the next image and every further image use the generics with one `Err_Config` each until the register is written; two bits at once; a second injection that restores the parity; with `Runtime_g` false no effect | PNT-ER-03, PNT-FT-02, PNT-RG-04, PNT-FT-01 |
| `test_registers` (TC-PNT-06) | `ID`, `IMAGE`, `PARAM`, the reset values (also `HIGH` from the sentinel -1, `OFFSET_HI` the sign of `Offset_g`); writes with every single byte strobe; writes to read-only registers (and to the parameter registers with `Runtime_g` false) without effect; unused addresses read 0; `STATUS` flags set by their events, kept by a write of 0, cleared by a write of 1; `INJECT` reads 0 | PNT-RG-01, PNT-RG-02, PNT-RG-03, PNT-RG-05, PNT-IF-03 |
| `test_flag_coincidence` (TC-PNT-07) | The clears of `STATUS.ERR_FRAMING` and `STATUS.ERR_CONFIG` swept cycle by cycle across an `Err_Framing` pulse (a discarded pixel) and an `Err_Config` pulse (an image start with a register of bad parity), as in `isp_crop` (TC-CRP-07); each sweep has steps before, at and after the pulse | PNT-RG-02 |
| `test_exhaustive` (TC-PNT-08) | Configuration `exhaustive` (4-bit pixels, 3-bit gain): every combination of offset (-16 to 15), gain (0 to 7) and shift (0 to 8 and 127, of which 7, 8 and 127 are taken as `MaxShift_g` = 6, below the width of the product) as a run-time set, each over an image of all 16 pixel values (2560 sets), with the thresholds 0 / 15, 2 / 13 and 9 / 5 (`Low` above `High`) in turn: every output against the model | PNT-FN-01, PNT-FN-05 |
| `test_reset` (TC-PNT-09) | Resets idle, held and running during an image, of one and two cycles; after the reset the registers hold the generics and the next image uses them | PNT-FT-03, PNT-IF-05, PNT-ER-02 |
| `test_rate` (TC-PNT-10) | Configurations `runtime_rate` and `stages_<n>`: images back to back, `In_Ready` high for every beat, every pixel at the output exactly `MultStages_g` + 5 cycles after its acceptance, one pixel per cycle at the output | PNT-PF-01, PNT-PF-02 |
| TC-PNT-11 (`lint/synth_check.py`) | GHDL synthesis without latches at the bounds of section 2 and both values of `Runtime_g`; `InBits_g` 65, `OutBits_g` 33, `GainBits_g` 19, `MaxShift_g` above `InBits_g` + `GainBits_g` + 1, `MultStages_g` 5, `Gain_g` 2^`GainBits_g` and `Low_g` 2^`OutBits_g` stop the elaboration with their message | PNT-CF-01, PNT-CF-02 |
| TC-PNT-12 (`lint/vivado_ooc.py`) | Out-of-context synthesis and implementation of the default configuration (4096 x 4096 pixels, 16 / 12 / 16 bits, run-time registers) and of `wide` (64 / 32 / 18 bits, four multiplier stages) at 150 MHz on the Versal device of the reference systems, on the build machine | PNT-CF-03 |

## 4. Requirement coverage

| Requirement | Test cases | Method |
| --- | --- | --- |
| PNT-IF-01, PNT-IF-02 | TC-PNT-01 to 10 | Test |
| PNT-IF-03 | TC-PNT-06 | Test |
| PNT-IF-04 | TC-PNT-02, 05 | Test |
| PNT-IF-05 | TC-PNT-09 | Test and review |
| PNT-FN-01 | TC-PNT-01, 03, 08 | Test |
| PNT-FN-02 | TC-PNT-02 | Test |
| PNT-FN-03 | TC-PNT-01 | Test |
| PNT-FN-04 | TC-PNT-03, 04 | Test |
| PNT-FN-05 | TC-PNT-03, 08 | Test |
| PNT-FN-06 | TC-PNT-01 to 10 (configurations with and without gaps and stalls) | Test |
| PNT-PF-01, PNT-PF-02 | TC-PNT-10 | Test |
| PNT-ER-01, PNT-ER-02 | TC-PNT-02, 09 | Test |
| PNT-ER-03 | TC-PNT-05 | Test |
| PNT-FT-01 | TC-PNT-05 (the set reloaded with every image) and review (no state between pixels) | Test and review |
| PNT-FT-02 | TC-PNT-05 | Test |
| PNT-FT-03 | TC-PNT-09 and the checks of section 3.1 | Test |
| PNT-RG-01, PNT-RG-03, PNT-RG-05 | TC-PNT-03, 06 | Test |
| PNT-RG-02 | TC-PNT-06, 07 | Test |
| PNT-RG-04 | TC-PNT-05 | Test |
| PNT-CF-01, PNT-CF-02 | TC-PNT-11 | Synthesis |
| PNT-CF-03 | TC-PNT-12 | Timing |

## 5. Timing bounds

| Bound | Design value | Derivation |
| --- | --- | --- |
| Latency `MultStages_g` + 5 cycles (PNT-PF-02) | `MultStages_g` + 5 | 2 cycles in `isp_frame_sync`; the sum stage, `MultStages_g` multiplier stages, the shift stage and the output register (architecture, section 4) |
| One pixel per cycle (PNT-PF-01) | 1 | Every stage advances with the common enable when the output register is free |

The arithmetic is exact: the model computes in unbounded integers, and every output pixel is compared bit for bit.

## 6. Negative tests and mutations

| Mutation | Expected to fail |
| --- | --- |
| No lower clamp | TC-PNT-01 (`clamp`), 03, 08 |
| No upper clamp | TC-PNT-01, 03, 08 |
| A logical instead of an arithmetic shift (negative values) | TC-PNT-01 (`dark_gain`), 08 |
| The offset not sign-extended | TC-PNT-01 (`dark_gain`), 08 |
| The top bit of the gain dropped | TC-PNT-03, 08 |
| A shift above `MaxShift_g` not limited | TC-PNT-03 (`shift_limit`), 08 |
| `CTRL.HOLD` without effect | TC-PNT-04 |
| No parity check of `GAIN` | TC-PNT-05 |
| No parity check of `OFFSET_HI` | TC-PNT-05 |
| The parity bit of `GAIN` not set by a write | TC-PNT-03, 05 |
| The thresholds taken from the registers directly, not from the working set | TC-PNT-03 (write during an image) |
| `Out_Last` one stage early | TC-PNT-01 (contract) |
| One multiplier stage too few against the pipeline of the packet signals | TC-PNT-10 |
| No `Err_Config` pulse | TC-PNT-05 |
| The offset stored with the sign of the 64-bit value instead of its lower bits | TC-PNT-06 |
| The clear of `ERR_CONFIG` wins over the event | TC-PNT-07 |

## 7. Expected coverage exclusions

- The `when others` branches of the state machines of `isp_frame_sync` and of `olo_axi_lite_slave` (Open Logic).
- With `Runtime_g` false the registers and the parity logic do not exist; their coverage comes from the configurations
  with `Runtime_g` true.

## 8. Test data

The pixels are random over the full input range, with 0 and the largest value in every image. The parameter sets are
random within their ranges and at their bounds; `test_exhaustive` covers every combination in the small
configuration, so that every carry, sign and rounding case of the arithmetic occurs.
