# isp_window: Verification Plan

## 1. Overview

The testbench `isp_window_tb` sends images to the module and checks every output window against a reference model.
It uses the shared [testbench components](../../../docs/testbench.md): the source (probe `Stat_ImageOpen`), the sink
with the contract checker (output dimensions Wo x Ho; the data of a beat is the whole window), and pulse counters of
`Err_Framing`, `Stat_EccSec` and `Stat_EccDed`. An injection process of the testbench drives `ErrInj_BitFlip` and
`ErrInj_Valid` at markers of the stimulus and acknowledges them to the source (entry `K`).

The reference model `window` of `tools/isp_model.py` takes the images that the model `frame_sync` delivers and builds
the windows from the definitions of the specification (section 1.1 and section 6): the reference pixels, the
extension p' of every border mode, the element order and the packets of the output image. For the error injection it
uses one property of the architecture that the specification states (WIN-FT-01): the line buffers are a chain of
delays of one line each, so in the pixel event of line ye the pixel of line ye - d comes from delay d. The model
counts the pixel events (PIX and VPIX), applies an injected pattern to the codeword that delay t writes in the next
pixel event, and decodes it with the code of Open Logic (`olo_ft_pkg_ecc`: overall parity in bit 0, Hamming parity
bits at the powers of two, data bits at the other positions):

- a single bit error is corrected; `Stat_EccSec` pulses in the event that reads it, W pixel events later;
- a double bit error leaves the data as read; `Stat_EccDed` pulses in that event, and every element taken from delay
  t or a later one shows the changed pixel, since the delays after t take the changed value as their input;
- the pulses of one event count once, and only for the delays that the row selection of the event uses (the
  delays whose line the border rule replaces do not count) (WIN-FT-02).

The model also gives, for every window, the input pixel that completes it (p(x + Rr, y + Rb) when it is inside the
image), which the rate check uses.

Simulators: GHDL (regression, CI) and QuestaSim (code coverage at the release); VUnit with UVVM, test end
`ispTestEnd`. Tests observe ports only.

## 2. Configurations

### 2.1 Configurations of every test

| Configuration | W x H | Bits | Window, anchor | Stride | Border | Line buffers | Gaps / stalls |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `rep3` | 10 x 7 | 12 | 3 x 3, (1, 1) | 1 | replicate | AUTO, pipeline 1 | 20 % / 20 % |
| `zero3` | 10 x 7 | 12 | 3 x 3, (1, 1) | 1 | zero | AUTO, pipeline 1 | 30 % / 40 % |
| `mirror5` | 12 x 9 | 16 | 5 x 5, (2, 2) | 1 | mirror | AUTO, pipeline 1 | 20 % / 20 % |
| `valid3` | 10 x 7 | 12 | 3 x 3, (1, 1) | 1 | valid | AUTO, pipeline 1 | 20 % / 20 % |
| `bin2_valid` | 11 x 7 | 12 | 2 x 2, (0, 0) | 2 | valid (the incomplete windows at the right and lower edge are dropped) | AUTO, pipeline 1 | 20 % / 20 % |
| `bin2_zero` | 11 x 7 | 12 | 2 x 2, (0, 0) | 2 | zero (they are completed) | AUTO, pipeline 1 | 20 % / 20 % |
| `bin4_rep` | 10 x 9 | 14 | 4 x 4, (0, 0) | 4 | replicate | AUTO, pipeline 0 | 20 % / 20 % |
| `row9` | 20 x 4 | 12 | 9 x 1, (4, 0) | 1 | mirror (no line buffer) | none | 20 % / 20 % |
| `col5` | 4 x 12 | 12 | 1 x 5, (0, 4) | 1 | zero | SRL, pipeline 0 | 20 % / 20 % |
| `max` | 18 x 17 | 32 | 16 x 16, (7, 7) | 1 | zero | BRAM, pipeline 1 | 10 % / 10 % |
| `image_equals_window` | 3 x 3 | 8 | 3 x 3, (1, 1) | 1 | replicate | SRL, pipeline 1 | 20 % / 20 % |
| `image_equals_window_valid` | 3 x 3 | 8 | 3 x 3, (1, 1) | 1 | valid (one window per image) | SRL, pipeline 0 | 20 % / 20 % |
| `ecc_srl_0`, `ecc_srl_1`, `ecc_bram_0`, `ecc_bram_1` | 8 x 6 | 12 | 3 x 3, (1, 1) | 1 | replicate | SRL or BRAM, pipeline 0 or 1 | none |
| `ecc_bram_min` | 4 x 6 | 12 | 3 x 3, (1, 1) | 1 | mirror | BRAM, pipeline 1 (W = 3 + `EccPipeline_g`, the bound of WIN-CF-05) | none |
| `w65536` | 65536 x 3 | 12 | 3 x 3, (1, 1) | 1 | replicate | AUTO, pipeline 1 | 10 % / 10 % |
| `h65536` | 3 x 65536 | 12 | 3 x 3, (1, 1) | 1 | mirror | SRL, pipeline 1 | 10 % / 10 % |
| `bits1` | 7 x 5 | 1 | 3 x 3, (1, 1) | 1 | replicate | AUTO, pipeline 1 | 20 % / 20 % |
| `rate_rep`, `rate_valid`, `rate_bin`, `rate_right` | 16 x 6 | 12 | 3 x 3; 3 x 3; 2 x 2 stride 2; 16 x 2 anchor (0, 0) (Rr = 15) | as stated | replicate; valid; valid; zero | AUTO, pipeline 1 | none |

### 2.2 Sweeps (test `test_static`)

| Sweep | Configurations | What it covers |
| --- | --- | --- |
| Size | n = 1 to 16: window n x (17 - n), default anchors, replicate, 6-bit pixels, image (n + 3) x (20 - n) | Every value of `WinX_g` and `WinY_g`, `WinY_g` 1 (no line buffer) |
| Mirror | n = 1, 3, ..., 15: window n x (16 - n), default anchors, mirror, image (n + 4) x (20 - n) | Every odd window size in both directions in the mirror mode |
| Anchor | Window 4 x 3, every anchor (12) in the modes zero and replicate | Every anchor of a window with an even and an odd size |
| Stride | n = 1 to 16: `StrideX_g` n, `StrideY_g` 17 - n, window 3 x 3, image 20 x 20, the modes valid and zero alternating | Every stride in both directions |
| Pixel bits | 1, 2, 12, 31, 32 with window 3 x 3 | The bounds of `PixelBits_g` and the widths around a 32-bit word |

### 2.3 Generic coverage

| Generic | Declared range | Simulated | Synthesised (TC-WIN-08) |
| --- | --- | --- | --- |
| `ImageWidth_g` | `WinX_g` to 65536 | `WinX_g` (3, and every n of the size sweep), 4 to 20, 65536 | `WinX_g`, 65536 |
| `ImageHeight_g` | `WinY_g` to 65536 | `WinY_g` (3), 4 to 20, 65536 | `WinY_g`, 65536 |
| `PixelBits_g` | 1 to 32 | 1, 2, 6, 8, 12, 14, 16, 31, 32 | 1, 32 |
| `WinX_g`, `WinY_g` | 1 to 16 | every value | 1, 16 |
| `AnchorX_g`, `AnchorY_g` | 0 to `WinX_g` - 1, 0 to `WinY_g` - 1 | every value for the window 4 x 3, the default anchor of every size, the bounds 0 and `WinX_g` - 1 | 0, `WinX_g` - 1 |
| `StrideX_g`, `StrideY_g` | 1 to 16 | every value | 1, 16 |
| `BorderMode_g` | valid, zero, replicate, mirror | every value | every value |
| `EccPipeline_g` | 0, 1 | both | both; 2 stops the elaboration |
| `Resource_g` | AUTO, SRL, BRAM | every value | every value |
| `RamStyle_g` | values of Open Logic | the default (an attribute for the synthesis tool only) | the default |

## 3. Test cases

### 3.1 Checks in every test

| Check | Where | Requirements |
| --- | --- | --- |
| Every output beat (window, `Out_Last`, `Out_User`) equals the model | Sink | WIN-IF-02, WIN-IF-03, WIN-FN-01, WIN-FN-02 |
| Output contract with Wo x Ho | Sink | WIN-IF-03, WIN-ER-01 |
| The numbers of `Err_Framing`, `Stat_EccSec` and `Stat_EccDed` pulses equal the model | Testbench | WIN-IF-04, WIN-FT-02 |
| Control and status outputs free of metavalues after the first reset; `Out_Valid` and the pulses 0 after every reset; no metavalue in a window while `Out_Valid` is high | Testbench | WIN-FT-04, WIN-IF-06 |

### 3.2 Test list

| Test | Description | Requirements |
| --- | --- | --- |
| `test_static` (TC-WIN-01) | Five images with random pixels over the full range in different divisions into packets (one packet, one per line, random lengths), back to back and with pauses; the image before every image has different content, so an element taken from a line that the image in progress has not written fails the comparison | WIN-IF-01 to 03, WIN-FN-01 to 03, WIN-FN-06, WIN-FT-04 |
| `test_input_stream` (TC-WIN-02) | Malformed input streams through the frame sync (short images, pixels without an image start, E3, E4, random packets): the padded images produce complete output images; `Stat_ImageOpen` probed while an image is open (1, an image cut after half of its pixels) and after complete images (0) | WIN-FN-03, WIN-ER-01, WIN-ER-02, WIN-IF-04 |
| `test_handshake` (TC-WIN-03) | The sink held during the HCOL events of a line, from the last pixel of an image on during the windows of the right and the lower border (no input pending), and from an idle module while the first two pixels of the next image arrive; a cut image completed by the next image start with the sink held and the source pausing; the source pauses at the same points. The source never sends a beat that cannot enter the module while the sink is held, so the test cannot block | WIN-FN-04, WIN-FN-05, WIN-FN-06 |
| `test_ecc` (TC-WIN-04) | Configurations `ecc_*`, the size sweep with `WinY_g` 1 and `max`: per delay a single error on a data bit, on a Hamming parity bit and on the overall parity bit (output unchanged, one `Stat_EccSec`); a double error on two data bits and on a data and a parity bit (the changed pixel in every element from that delay on, one `Stat_EccDed`); errors in two delays in the same event (one pulse); a single and a double error in the same event (one pulse of each); an injection in the last line of an image into the first delay (read and reported in the windows of the lower border, where the line is used; in `ecc_bottom` and `ecc_bottom_zero`, `AnchorY_g` = `WinY_g` - 1 without a lower border, read in the first line of the next image, where it is not used: not reported); an injection in the first line of an image into a delay whose codeword is read in the next line where the border rule replaces that delay (not reported); with `WinY_g` 1 an injection has no effect | WIN-IF-05, WIN-FT-01, WIN-FT-02, WIN-ER-03 |
| `test_reset` (TC-WIN-05) | Resets idle, held and running, of one and two cycles, during the pixels of a line, during the HCOL events, during the virtual lines and between images; the next image after the reset is checked completely, also its first lines (no line of the image before the reset) | WIN-IF-06, WIN-FT-03, WIN-FT-04, WIN-ER-02 |
| `test_rate` (TC-WIN-06) | Configurations `rate_*`: images back to back with `In_Valid` and `Out_Ready` high. The hold cycles of the input between the first pixels of two lines (at most Rr; none in the mode valid), the interval between two image starts (bound of WIN-PF-02, design value (H + Rb) x (W + Rr), H x W in the mode valid) and the latency of every window from the acceptance of its completing pixel (bound 6, design value 3 to 5) | WIN-PF-01, WIN-PF-02, WIN-PF-03 |
| TC-WIN-07 (review) | `when others` of the event state machine leads to `Pix_s`, pixel (0, 0) restarts the counters | WIN-FT-03 |
| TC-WIN-08 (`lint/synth_check.py`) | GHDL synthesis without latches at the bounds of section 2.3 and every border mode and resource; elaboration stops with the message naming the generic for: `WinX_g` 17, `WinY_g` 17, `ImageWidth_g` below `WinX_g`, `ImageHeight_g` below `WinY_g`, `ImageWidth_g` 65537, `PixelBits_g` 33, `AnchorX_g` = `WinX_g`, `AnchorY_g` = `WinY_g`, `StrideX_g` 17, `StrideY_g` 17, an unknown border mode, mirror with an even window, mirror with an anchor beside the middle (both directions), `EccPipeline_g` 2, an unknown `Resource_g`, `Resource_g` BRAM (also in lower case) with `ImageWidth_g` 2 + `EccPipeline_g` | WIN-CF-01, WIN-CF-02, WIN-CF-03, WIN-CF-05 |
| TC-WIN-09 (`lint/vivado_ooc.py`) | Out-of-context synthesis and implementation at 150 MHz on the device of the Timing level (architecture, section 10): 3 x 3 replicate, 12 bits, 4096 pixels per line (the default); 5 x 5 mirror, 16 bits, 4096; 16 x 16 zero, 32 bits, 4096 | WIN-CF-04 |

## 4. Requirement coverage

| Requirement | Test cases | Method |
| --- | --- | --- |
| WIN-IF-01, WIN-IF-02, WIN-IF-03 | TC-WIN-01 to 06 | Test |
| WIN-IF-04 | TC-WIN-02, 04 | Test |
| WIN-IF-05 | TC-WIN-04 | Test |
| WIN-IF-06 | TC-WIN-05 | Test |
| WIN-FN-01, WIN-FN-02 | TC-WIN-01 (all configurations and sweeps) | Test |
| WIN-FN-03 | TC-WIN-01, 02 | Test |
| WIN-FN-04, WIN-FN-05 | TC-WIN-03, 06 | Test |
| WIN-FN-06 | TC-WIN-01 (gaps and stalls), 03 | Test |
| WIN-PF-01, WIN-PF-02, WIN-PF-03 | TC-WIN-06 | Test |
| WIN-ER-01, WIN-ER-02 | TC-WIN-02, 05 | Test |
| WIN-ER-03 | TC-WIN-04 | Test |
| WIN-FT-01, WIN-FT-02 | TC-WIN-04 | Test |
| WIN-FT-03 | TC-WIN-05, 07 | Test and review |
| WIN-FT-04 | TC-WIN-01, 05 and the checks of section 3.1 | Test |
| WIN-CF-01, WIN-CF-02, WIN-CF-03, WIN-CF-05 | TC-WIN-08 | Synthesis |
| WIN-CF-04 | TC-WIN-09 | Timing |

## 5. Timing bounds

| Bound | Design value | Derivation |
| --- | --- | --- |
| Hold cycles between the first pixels of two lines: at most Rr (WIN-PF-01) | Rr; 0 in the mode valid; between the first two lines of an image that follows an image, Rb x (W + Rr) + Rr | One HCOL event per column right of the reference pixel; the input stage of `isp_frame_sync` moves the hold by up to two pixels, not its length, and takes the first pixels of an image during the virtual lines of the image before |
| Image period (H + Rb) x (W + Rr) + 8, H x W + 8 in the mode valid (WIN-PF-02) | (H + Rb) x (W + Rr); H x W; the first interval after an idle module is shorter | One event per cycle; W + Rr events per line, Rb virtual lines (architecture, section 9); the input stage takes the next image start before the virtual lines of the image before |
| Latency at most 6 (WIN-PF-03) | 3, up to 5 | 2 cycles in `isp_frame_sync`, one into the window register; a pixel that the input stage of `isp_frame_sync` took while the module held the input waits behind at most two pixels |

The bench checks the design values: Rr hold cycles, the exact image period, a latency between 3 and 5. A measured
value outside the derivation is a finding: the cause is found (the RTL or the derivation), recorded in the findings of
the verification report, and the wrong one is corrected. A derivation is never adjusted to fit a measurement.

## 6. Negative tests and mutations

| Mutation | Expected to fail |
| --- | --- |
| Left border of the mode replicate not loaded (the columns keep the line before) | TC-WIN-01 (`rep3`) |
| Mirror at the right border one column off (2m instead of 2m - 1) | TC-WIN-01 (`mirror5`, mirror sweep) |
| Row select of the lower border takes the delay one line too far | TC-WIN-01 (`rep3`, `mirror5`) |
| Rows outside the image not cleared in the mode zero (line 0 instead) | TC-WIN-01 (`zero3`) |
| No HCOL event for Rr = 1 | TC-WIN-01 (contract), 06 |
| One VPIX event too few per virtual line | TC-WIN-01 (the next image) |
| Stride counter not counting (the restart at the start of a line has a second path, the restart with column 0, so a mutant without one of them is equivalent) | TC-WIN-01 (stride sweep, `bin2_*`) |
| `Out_Last` from the last column instead of the last reference pixel | TC-WIN-01 (`bin2_valid`, contract) |
| `Out_User` "01" instead of "11" when Ho = 1 | TC-WIN-01 (`image_equals_window_valid`) |
| Elements in column-major order | TC-WIN-01 (non-square windows) |
| ECC flags of the delays not sampled in the event (held values counted again) | TC-WIN-04 (`ecc_*_1`) |
| ECC flags of every delay counted, also of the delays the row selection does not use | TC-WIN-04 |
| Injection patterns of the delays in reverse order | TC-WIN-04 |
| An event that does not wait for `Out_Ready` | TC-WIN-01 (stalls), 03 |
| Rows above the image taken from the line buffers (the image before) instead of 0 | TC-WIN-01, 05 |
| `Stat_ImageOpen` tied to 0 (a port stuck at 1 fails every probe after a complete image, which expects 0) | TC-WIN-02 (the probe of the open image) |
| Pixel (0, 0) detected from x alone (the rows of line 0 at the first pixel of every line) | TC-WIN-01 (`WinY_g` > 1) |
| Pixel (0, 0) detected outside the state of the image pixels (a pixel (0, 0) that waits at the frame sync during the virtual events of the image before) | TC-WIN-06 (images back to back with a lower border) |
| The column of pixel (0, 0) from the registered row selection (no restart of the rows) | TC-WIN-02, 05 (an image cut inside a line, WIN-FT-03) |
| The left border of a virtual line not taken (the first VPIX) | TC-WIN-01 (`rep3`, `zero3`: the lower border) |
| The left mirror of a virtual line not taken | TC-WIN-01 (`mirror5`, mirror sweep: the lower border) |

## 7. Expected coverage exclusions

- The `when others` branches of the event state machine and of `isp_frame_sync` (review TC-WIN-07).
- The generate branches of the border modes and resources not selected by a configuration are covered by the other
  configurations; the merged coverage of all configurations is the measure.

## 8. Test data

The pixels are random over the full range of `PixelBits_g`, independently for every pixel and every image, so that no
window repeats and every element of every window depends on its own pixel. The injection patterns are chosen per
delay and per bit class (data, Hamming parity, overall parity); the data bits for the double errors are picked at
random from the data positions of the codeword.
