# isp_replace: Verification Plan

## 1. Overview

The testbench `isp_replace_tb` writes defect maps through the AXI4-Lite slave, sends images to the module and checks
every output pixel against a reference model. It uses the shared [testbench components](../../../docs/testbench.md):
the source (probe `Stat_ImageOpen`), the sink with the contract checker (W x H), the register script `ispRegsRun`,
pulse counters of `Err_Framing`, `Stat_Unreplaced`, `Stat_EccSec`, `Stat_EccDed` and of the scrubber outputs, and an
injection process that drives `ErrInj_BitFlip`, `ErrInj_Valid` and `Scrub_Enable` at markers of the stimulus (entries
`<m> J <pattern>` and `<m> S <0 or 1>` of an injection script; the source waits for its acknowledge with `K`, as for
the register script).

The reference model `replace` of `tools/isp_model.py` takes the images of the model `frame_sync` and computes every
output pixel with the definitions of the specification (section 1.1): the marks from the defect map, the distances
dl and dr within G in the same line, the rounded interpolation, the one-sided replacement and the unchanged pixel
(E5). It keeps a model of the registers (`MAP_ADDR` with its 32 bits, the map words with their injected error
patterns, `CTRL.CLEAR`, the sticky flags) and reads a word of the map when the architecture does (section 5): words
0 to 2 with pixel (0, 0), and word k + 2 when word k comes in use, never across the image start. Writes during an
image are placed after a pause of the source in which every accepted pixel has passed the map lookup, so this rule
decides which words of the image see a write; the tests check the bounds of RPL-FN-04 only and write no word that
the bound leaves open (the first two words after the current one). An error pattern of a word is decoded with the
code of `olo_ft_pkg_ecc`, as in the model of `isp_window`.

The clock frequency and the scrub period are `real` generics, which GHDL cannot set from the command line: the
testbench takes them in Hz and ns as integers and converts them; `lint/synth_check.py` uses a wrapper entity.

Simulators: GHDL (regression, CI) and QuestaSim (code coverage at the release); VUnit with UVVM, test end
`ispTestEnd`. Tests observe ports and the AXI4-Lite interface only.

## 2. Configurations

### 2.1 Configurations of every test

| Configuration | W x H | Map words | Bits | G | RAM latency, ECC pipeline | Gaps / stalls |
| --- | --- | --- | --- | --- | --- | --- |
| `g2` | 40 x 6 | 12 (the last word of a line holds 8 pixels) | 12 | 2 | 1, 0 | 20 % / 20 % |
| `g1_min` | 3 x 5 (W = 2 G + 1) | 5 | 8 | 1 | 3, 2 (the longest read) | 30 % / 40 % |
| `w33` | 33 x 6 (the last word of a line holds one pixel) | 12 | 12 | 1 | 3, 2 | none |
| `g7` | 15 x 4 (W = 2 G + 1) | 4 | 12 | 7 | 2, 1 | 20 % / 20 % |
| `g7_wide` | 100 x 4 | 16 | 24 | 7 | 1, 1 | 20 % / 20 % |
| `w64` | 64 x 3 (whole words) | 6 | 12 | 3 | 1, 2 | 20 % / 20 % |
| `bits1` | 10 x 3 | 3 | 1 | 2 | 1, 0 | 20 % / 20 % |
| `one_word` | 20 x 1 (a map of one word) | 1 | 12 | 2 | 1, 0 | 20 % / 20 % |
| `clear` | 64 x 40 | 80 | 12 | 2 | 1, 0 | none |
| `w65536` | 65536 x 2 | 4096 | 12 | 2 | 1, 0 | 10 % / 10 % |
| `h65536` | 5 x 65536 | 65536 | 12 | 2 | 1, 0 | 10 % / 10 % |
| `exhaustive` | 120 x 256 | 1024 | 4 | 7 | 1, 0 | none |
| `scrub_period`, `scrub_overrun` | 40 x 6 | 12 | 12 | 2 | 1, 0; a scrub period of 2 µs, and one shorter than a pass | none |
| `rate_g2`, `rate_g7`, `rate_w33` | as `g2`, `g7`, `w33` with 6 lines | | | | | none |

### 2.2 Sweeps (test `test_static`)

| Sweep | Configurations | What it covers |
| --- | --- | --- |
| Gap | G = 1 to 7, W = 4 x G + 5, 6 lines, 10-bit pixels | Every value of `MaxGap_g` |
| Read latency | `RamRdLatency_g` 1 to 3 crossed with `EccPipeline_g` 0 to 2, W = 33, G = 1 | Every combination of the read latency of the map with the shortest word |

### 2.3 Generic coverage

| Generic | Declared range | Simulated | Synthesised (TC-RPL-12) |
| --- | --- | --- | --- |
| `ImageWidth_g` | 2 x `MaxGap_g` + 1 to 65536 | 3, 15 (2 x G + 1), 9 to 33 (gap sweep), 20, 33, 40, 64, 100, 120, 65536 | 2 x G + 1, 65536 |
| `ImageHeight_g` | 1 to 65536 | 1, 2, 3, 4, 5, 6, 40, 256, 65536 | 1, 65536 |
| `PixelBits_g` | 1 to 24 | 1, 4, 8, 10, 12, 24 | 1, 24 |
| `MaxGap_g` | 1 to 7 | every value | 1, 7 |
| `RamRdLatency_g` | 1 to 3 | every value | 1, 3 |
| `EccPipeline_g` | 0 to 2 | every value | 0, 2 |
| `RamStyle_g` | values of Open Logic | the default (an attribute for the synthesis tool only) | the default |
| `ClkFreqHz_g`, `ScrubPeriod_g` | range of Open Logic | 150 MHz with the periods 0.0 (free running), 2 µs and one shorter than a pass | 0.0 and 1 ms |

## 3. Test cases

### 3.1 Checks in every test

| Check | Where | Requirements |
| --- | --- | --- |
| Every output beat (pixel, `Out_Last`, `Out_User`) equals the model | Sink | RPL-IF-02, RPL-FN-01, RPL-FN-02 |
| Output contract with W x H | Sink | RPL-FN-03, RPL-ER-01 |
| The numbers of `Err_Framing`, `Stat_Unreplaced`, `Stat_EccSec` and `Stat_EccDed` pulses equal the model | Testbench | RPL-IF-04, RPL-ER-02 |
| Control and status outputs free of metavalues after the first reset, `Out_Valid` and the pulses 0 after every reset; no metavalue in an output pixel while `Out_Valid` is high | Testbench | RPL-FT-03, RPL-IF-06 |
| Every AXI4-Lite access answered with OKAY | BFM | RPL-RG-01 |

### 3.2 Test list

| Test | Description | Requirements |
| --- | --- | --- |
| `test_static` (TC-RPL-01) | The first image after the start of the simulation without a write of the map: every pixel unchanged (the map of the configured device marks no pixel). Then random maps, written between images, with isolated defects, groups of 2 to 2 x G and longer, groups at the left and the right border and lines without an operational pixel within G; five images per map with random pixels over the full range, in different divisions into packets | RPL-IF-01 to 03, RPL-FN-01 to 03, RPL-FN-05, RPL-FN-06, RPL-ER-02 |
| `test_input_stream` (TC-RPL-02) | Malformed input streams through the frame sync (short images, pixels without an image start, E3, E4, random packets) with a map: the padded pixels are pixels of the image; `Stat_ImageOpen` probed | RPL-FN-03, RPL-ER-01, RPL-IF-04 |
| `test_map_update` (TC-RPL-03) | Images back to back; between two images the source pauses after the last pixel and the script writes words 0, 1, 2 and the last word: the next image uses them all. During an image the source pauses after pixel n and the script writes words from the third after the word of pixel n on, which the image uses. `MAP_DATA` written word by word over several lines with the counting `MAP_ADDR`; `MAP_ADDR` set to the number of map words and to 0xFFFFFFFF: a write of `MAP_DATA` changes neither the map nor `MAP_ADDR`, which reads back all 32 bits | RPL-FN-04, RPL-RG-03, RPL-ER-04 |
| `test_clear` (TC-RPL-04) | Configuration `clear` (80 words): `CTRL.CLEAR` after a full map; `STATUS.BUSY` read high during the clear and low after it; a write of `MAP_DATA` during the clear changes neither the map nor `MAP_ADDR`; a second `CTRL.CLEAR` during the clear does not extend it (`STATUS.BUSY` low at the time of the first clear); the next image is unchanged. A map written before a reset of the module still applies after it | RPL-RG-04, RPL-ER-04, RPL-FN-05 |
| `test_ecc` (TC-RPL-05) | `Scrub_Enable` 0. Error patterns injected into writes of map words: a single error on a data, a Hamming parity and the overall parity bit (the marks unchanged, `Stat_EccSec` with every image that reads the word); a double error on two data bits of which one marks a defect (the word is used as read: a defect appears or disappears in the output, `Stat_EccDed` with every image); `STATUS.ECC_SEC` and `STATUS.ECC_DED`; a new write of the word ends the reports | RPL-IF-05, RPL-FT-01, RPL-ER-03 |
| `test_scrub` (TC-RPL-06) | Single and double errors injected with `Scrub_Enable` 0, then `Scrub_Enable` 1 without images for a time of several passes: `Scrub_EccSec` and `Scrub_EccDed` pulse, `Scrub_PassDone` pulses; then `Scrub_Enable` 0 and an image: no `Stat_EccSec` for the corrected words, `Stat_EccDed` for the double error. Images with the scrubber running are output as by the model. Configurations `scrub_period` and `scrub_overrun`: the number of `Scrub_PassDone` pulses over a time and `Scrub_Overrun` | RPL-IF-05, RPL-FT-01 |
| `test_registers` (TC-RPL-07) | `ID`, `IMAGE`, `PARAM`, `MAP_LINE`, `MAP_WORDS`, the reset values; `MAP_DATA` and `CTRL` read 0; writes to read-only registers without effect; byte strobes on `MAP_ADDR`; a write of `MAP_DATA` with partial strobes writes all 32 bits; unused addresses read 0; every `STATUS` flag set by its event, kept by a write of 0, cleared by a write of 1 | RPL-RG-01, RPL-RG-02, RPL-RG-03, RPL-IF-03 |
| `test_flag_coincidence` (TC-RPL-08) | The clears of `STATUS.ERR_FRAMING` and `STATUS.UNREPLACED` swept cycle by cycle across their pulses, as in `isp_crop` (TC-CRP-07) | RPL-RG-02 |
| `test_exhaustive` (TC-RPL-09) | Configuration `exhaustive`: every line holds groups of 1 to 13 defects between two operational pixels, line y with the left value y mod 16 and the right value y / 16: every pair of 4-bit values with every pair (dl, dr) of 1 to 7, and the one-sided and the unreplaced pixels of the longer groups | RPL-FN-01, RPL-ER-02 |
| `test_reset` (TC-RPL-10) | Resets idle, held and running, of one and two cycles, during a line, during the virtual columns of the window and between images; the next image is checked completely | RPL-IF-06, RPL-FT-02, RPL-FT-03 |
| `test_rate` (TC-RPL-11) | Configurations `rate_*`: images back to back with `In_Valid` and `Out_Ready` high: hold cycles between the first pixels of two lines (at most G), the interval between two image starts, the latency of every pixel from the acceptance of p(x + G, y) | RPL-PF-01, RPL-PF-02, RPL-PF-03 |
| TC-RPL-12 (`lint/synth_check.py`) | GHDL synthesis without latches at the bounds of section 2.3; elaboration stops with the message naming the generic for: `MaxGap_g` 0 and 8, `ImageWidth_g` 2 x G and 65537, `ImageHeight_g` 65537, `PixelBits_g` 25, `RamRdLatency_g` 4, `EccPipeline_g` 3 | RPL-CF-01, RPL-CF-02 |
| TC-RPL-13 (`lint/vivado_ooc.py`) | Out-of-context synthesis and implementation at 150 MHz on the Versal device of the reference systems, on the build machine: 2048 x 1024 pixels of 12 bits, G = 2 (the default; a map of 65536 words), and G = 7 with 24-bit pixels | RPL-CF-03 |
| TC-RPL-14 (review) | The RTL consists of `isp_frame_sync`, the map lookup, `isp_window` (one line of 2 x G + 1 pixels with their flags, border mode zero) and the interpolation; `when others` of the state machines leads to their idle state; the word counter restarts with pixel (0, 0); the division constant: for K = `PixelBits_g` + 8 and d = 2 to 14 the error of ceil(2^K / d) stays below one unit of the quotient (architecture, section 6) | RPL-FN-07, RPL-FT-02, RPL-FN-01 |

## 4. Requirement coverage

| Requirement | Test cases | Method |
| --- | --- | --- |
| RPL-IF-01, RPL-IF-02 | TC-RPL-01 to 11 | Test |
| RPL-IF-03 | TC-RPL-07 | Test |
| RPL-IF-04 | TC-RPL-01, 02, 05 | Test |
| RPL-IF-05 | TC-RPL-05, 06 | Test |
| RPL-IF-06 | TC-RPL-10 | Test |
| RPL-FN-01 | TC-RPL-01, 09, 14 | Test and review |
| RPL-FN-02, RPL-FN-03 | TC-RPL-01, 02 | Test |
| RPL-FN-04 | TC-RPL-03 | Test |
| RPL-FN-05 | TC-RPL-01, 04 | Test |
| RPL-FN-06 | TC-RPL-01 (configurations with and without gaps and stalls) | Test |
| RPL-FN-07 | TC-RPL-14 | Review |
| RPL-PF-01, RPL-PF-02, RPL-PF-03 | TC-RPL-11 | Test |
| RPL-ER-01 | TC-RPL-02 | Test |
| RPL-ER-02 | TC-RPL-01, 09 | Test |
| RPL-ER-03 | TC-RPL-05 | Test |
| RPL-ER-04 | TC-RPL-03, 04 | Test |
| RPL-FT-01 | TC-RPL-05, 06 | Test |
| RPL-FT-02 | TC-RPL-10, 14 | Test and review |
| RPL-FT-03 | TC-RPL-10 and the checks of section 3.1 | Test |
| RPL-RG-01, RPL-RG-03 | TC-RPL-03, 07 | Test |
| RPL-RG-02 | TC-RPL-07, 08 | Test |
| RPL-RG-04 | TC-RPL-04 | Test |
| RPL-CF-01, RPL-CF-02 | TC-RPL-12 | Synthesis |
| RPL-CF-03 | TC-RPL-13 | Timing |

## 5. Timing bounds

| Bound | Design value | Derivation |
| --- | --- | --- |
| Hold cycles between the first pixels of two lines: at most G (RPL-PF-01) | G | G virtual columns of the window per line; the read-ahead of two words keeps the map ahead of the pixels also for a last word of one pixel (architecture, section 5) |
| Image period H x (W + G) + `RamRdLatency_g` + `EccPipeline_g` + 16 (RPL-PF-02) | H x (W + G) + `RamRdLatency_g` + `EccPipeline_g` + 1 | One pixel or virtual column per cycle; the first pixel of an image waits for word 0 |
| Latency at most 13 + `RamRdLatency_g` + `EccPipeline_g` (RPL-PF-03) | 10; up to 12 after a hold of the input; up to 11 + `RamRdLatency_g` + `EccPipeline_g` for the first pixels of an image | Frame sync 2, lookup 1, window 3, interpolation 4 (architecture, section 8) |

The bench checks the design values. A measured value outside the derivation means that the derivation is wrong; it is
corrected in the architecture before the test passes.

## 6. Negative tests and mutations

| Mutation | Expected to fail |
| --- | --- |
| The weights of the interpolation swapped (L x dl + R x dr) | TC-RPL-01, 09 |
| No rounding term | TC-RPL-09 |
| The search one place too far (G + 1) | TC-RPL-01 (groups longer than 2 x G), 09 |
| A place outside the image taken as operational | TC-RPL-01 (groups at the border) |
| A one-sided replacement from the wrong side | TC-RPL-01, 09 |
| An unreplaced pixel output as 0 or not reported | TC-RPL-01, 09 |
| The division constant one bit shorter (K = `PixelBits_g` + 7) | TC-RPL-09 |
| The read-ahead across the image start (word 0 read at the end of the image before) | TC-RPL-03 |
| The word counter not advanced at the end of a line with a partial last word | TC-RPL-01 (`g2`, `w33`) |
| `MAP_ADDR` cut to the width of the map address | TC-RPL-03 |
| `MAP_ADDR` counted up by a write without effect | TC-RPL-03, 04 |
| A `CTRL.CLEAR` during a clear restarts it | TC-RPL-04 |
| The map lookup takes the uncorrected word | TC-RPL-05 |
| No `Stat_EccSec` pulse with a read | TC-RPL-05 |

## 7. Expected coverage exclusions

- The `when others` branches of the state machines of the module, of `isp_frame_sync`, of `isp_window` and of
  `olo_axi_lite_slave` (review TC-RPL-14).
- The `isp_frame_sync` inside the window acts only after an upset between the blocks (architecture, section 4): its
  error branches are covered by the tests of `isp_frame_sync`, not here.

## 8. Test data

The pixels are random over the full range of `PixelBits_g`; every map is random with the structures of
`test_static` placed on purpose. The pixel values of `test_exhaustive` are chosen per line so that every pair of
values meets every pair of distances.
