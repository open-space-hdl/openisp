# isp_bin: Verification Plan

## 1. Overview

`isp_bin` adds no logic of its own: a horizontal `isp_filter2d` adds `BinX_g` pixels of a line, a vertical one adds
`BinY_g` lines of the narrowed image. This plan verifies the function of the module against the definition of a bin
(specification, section 1.1) and the connection of the two filters.

The testbench `isp_bin_tb` uses the shared [testbench components](../../../docs/testbench.md): the source, the sink
with the contract checker (Wo x Ho), the injection script for the line buffers of the vertical filter and the pulse
counters of the status outputs.

The reference model `bin_model` of `tools/isp_model.py` computes every output pixel from the definition of a bin
(`bin_sum`): the sum of the pixels p'(n x `BinX_g` + i, m x `BinY_g` + j) of the image extended by the border mode, for
the Wo x Ho bins of the specification. It does not use the models of the parts, so it checks that the two filters in
series give the sums of the bins. The composition of the models of the two filters (`bin_filters`: frame sync,
window and kernel of each, a filter of factor 1 left out) gives the numbers of the status pulses, `Stat_ImageOpen` at
the probes and the input beat that completes every bin; without an injection the model asserts that both give the
same output pixels. With an injection into the line buffers of the vertical filter, whose double errors change the
sums, the output pixels come from the composition.

Simulators: GHDL (regression, CI) and QuestaSim (code coverage at the release); VUnit with UVVM, test end
`ispTestEnd`. Tests observe ports only.

## 2. Configurations

### 2.1 Configurations

| Configuration | W x H | Pixel bits | Bin | Border | Line buffers | Gaps / stalls | Tests |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `bin2_valid` | 13 x 9 | 12 | 2 x 2 | valid (the last column and line dropped) | AUTO, pipeline 1 | 20 % / 20 % | static, input stream, reset |
| `bin2_zero` | 13 x 9 | 12 | 2 x 2 | zero | AUTO, pipeline 1 | 30 % / 40 % | static, input stream, reset |
| `bin3x5_rep` | 14 x 12 | 12 | 3 x 5 (Q = P + 4, less than the sum of the two filter widths) | replicate | AUTO, pipeline 1 | 20 % / 20 % | static, input stream, reset |
| `bin4` | 16 x 16 | 16 | 4 x 4 | valid | SRL, pipeline 0 | 20 % / 20 % | static, reset |
| `bin_x_only` | 12 x 5 | 12 | 4 x 1 (no vertical filter) | zero | none | 20 % / 20 % | static, input stream, reset |
| `bin_y_only` | 5 x 12 | 12 | 1 x 4 (no horizontal filter) | replicate | AUTO, pipeline 1 | 20 % / 20 % | static, input stream, reset |
| `bin_none` | 6 x 4 | 12 | 1 x 1 (the frame sync only) | valid | none | 20 % / 20 % | static, input stream, reset |
| `max` | 64 x 34 (Wo = 4, the block RAM bound) | 28 | 16 x 16 | replicate | BRAM, pipeline 1 | 10 % / 10 % | static |
| `bits1` | 8 x 6 | 1 | 2 x 3 | zero | AUTO, pipeline 0 | 20 % / 20 % | static, ECC |
| `image_equals_bin` | 4 x 4 | 12 | 4 x 4 | valid (one bin) | SRL, pipeline 1 | 20 % / 20 % | static, input stream |
| `min` | 1 x 1 | 1 | 1 x 1 | valid | none | 20 % / 20 % | static, input stream |
| `w65536` | 65536 x 2 | 12 | 2 x 2 | valid | BRAM, pipeline 1 | 10 % / 10 % | static |
| `ecc` | 12 x 8 | 12 | 2 x 3 | zero | SRL, pipeline 1 | none | static, ECC |
| `rate_valid`, `rate_rep` | 16 x 8 | 12 | 4 x 2 | valid; replicate | AUTO, pipeline 1 | none | static, rate |
| `rate_tall` | 16 x 16 | 12 | 2 x 8 (the vertical filter waits longer than the buffers of the horizontal one take) | replicate | AUTO, pipeline 1 | none | static, rate |
| `rate_x_only`, `rate_y_only`, `rate_none` | 16 x 8 | 12 | 4 x 1; 1 x 4; 1 x 1 | replicate | AUTO, pipeline 1 | none | static, rate |
| `rate_odd_w33`, `rate_odd_w33_tall` | 33 x 8; 33 x 16 | 12 | 2 x 2; 2 x 8 | replicate; zero | AUTO, pipeline 1 | none | static, rate |
| `rate_odd_w13`, `rate_odd_w13_bx4` | 13 x 16; 13 x 8 | 12 | 2 x 8; 4 x 2 | replicate | AUTO, pipeline 1 | none | static, rate |
| `rate_odd_w17_bx8`, `rate_odd_w17_bx8_tall`, `rate_odd_w17_bx16_tall` | 17 x 8; 17 x 16; 17 x 16 | 12 | 8 x 2; 8 x 16; 16 x 16 | zero; replicate; replicate | AUTO, pipeline 1 | none | static, rate |
| `rate_odd_w3`, `rate_odd_w5_bx4` | 3 x 8; 5 x 8 | 12 | 2 x 2; 4 x 4 (W = `BinX_g` + 1) | replicate; zero | AUTO, pipeline 1 | none | static, rate |
| `rate_odd_x_only`, `rate_odd_x_only_w3` | 9 x 6; 3 x 6 | 12 | 2 x 1 | replicate; zero | AUTO, pipeline 1 | none | static, rate |
| `rate_range_w<W>_bx4`, W = 22, 21, 23, 16, 10 | W x 16 | 12 | 4 x 16 | replicate | AUTO, pipeline 1 | none | static, rate |
| `rate_range_w12_bx2`, `rate_range_w9_bx2`, `rate_range_w20_bx8` | 12 x 16; 9 x 16; 20 x 16 | 12 | 2 x 8; 2 x 16; 8 x 16 | replicate | AUTO, pipeline 1 | none | static, rate |

### 2.2 Sweep (test `test_static`)

| Sweep | Configurations | What it covers |
| --- | --- | --- |
| Factors | n = 1 to 16: bin n x (17 - n), 8-bit pixels, image (n + 3) x (20 - n), the border modes valid, zero and replicate in turn; `sweep_16` (bin 16 x 1) also runs `test_ecc` | Every value of `BinX_g` and `BinY_g` |

### 2.3 Generic coverage

| Generic | Declared range | Simulated | Synthesised (TC-BIN-07) |
| --- | --- | --- | --- |
| `ImageWidth_g` | `BinX_g` to 65536 | 1 (`min`), `BinX_g` (4 of `image_equals_bin`), 4 to 19, 64, 65536 | `BinX_g`, 65536 |
| `ImageHeight_g` | `BinY_g` to 65536 | 1 (`min`), `BinY_g` (4 of `image_equals_bin`), 2, 4 to 19, 34 | `BinY_g`, 65536 |
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
| `Stat_ImageOpen` at the probes of the stimulus (after complete images: 0) | Source | BIN-IF-03 |
| Control and status outputs free of metavalues after the first reset, `Out_Valid` and the status outputs 0 after every reset | Testbench | BIN-IF-04 |

### 3.2 Test list

| Test | Description | Requirements |
| --- | --- | --- |
| `test_static` (TC-BIN-01) | Five images per configuration with random pixels over the full range, plus an image of largest pixels (the largest sums, no saturation) and an image of zeros, in different divisions into packets, back to back and with pauses | BIN-IF-01, BIN-IF-02, BIN-FN-01 to 04 |
| `test_input_stream` (TC-BIN-02) | An image cut after its first pixel and probed: `Stat_ImageOpen` 1 with only the frame sync of the input open (with `BinX_g` > 1 the horizontal filter has no bin yet, so the vertical filter has seen nothing). Then the malformed input streams of `tools/isp_tbgen.py`, which begin with an image cut after half of its pixels and probed while it is open: complete output images, `Err_Framing` | BIN-ER-01, BIN-IF-03 |
| `test_ecc` (TC-BIN-03) | Configurations `ecc`, `bits1` and `sweep_16`. For every line buffer of the vertical filter a single error and a double error on data bits of a pixel of narrowed line `BinY_g` - 2, which the window of the last line of bin row 0 reads: the single error corrected, the double error in the sum of the bin; one more single error, so that the counts of `Stat_EccSec` and `Stat_EccDed` differ (`ecc`: 3 and 2). With `BinY_g` 1 the injection has no effect | BIN-IF-03, BIN-FT-01 |
| `test_reset` (TC-BIN-04) | Resets idle, held during a line and after the last pixel (with the virtual pixels in progress), held with the sink stopped while the filters hold bins, running during a line and after the last pixel; the next image complete and correct | BIN-IF-04, BIN-FT-01, BIN-ER-01 |
| `test_rate` (TC-BIN-05) | Configurations `rate_*`, four images back to back: the hold cycles of the input per line and the wait for the virtual lines of the vertical filter, the image period and the latency of every output pixel against the design values of section 5; the fall of `Stat_ImageOpen` after the last pixel of every image; with both filters a probe of `Stat_ImageOpen` 4 cycles after the last pixel, when only the vertical filter has the image open | BIN-PF-01, BIN-PF-02, BIN-FN-04, BIN-IF-03 |
| TC-BIN-06 (review) | The RTL consists of the two filters with the generics of the specification (section 4) and leaves out a filter of factor 1 | BIN-FN-04 |
| TC-BIN-07 (`lint/synth_check.py`) | GHDL synthesis without latches at the bounds of section 2.3 and every border mode; elaboration stops with the message naming the generic for: `BinX_g` 17, `BinY_g` 17, `PixelBits_g` 29, the border mode mirror, `ImageWidth_g` below `BinX_g` and 65537, `ImageHeight_g` below `BinY_g`, `Resource_g` BRAM with Wo below 3 + `EccPipeline_g`; `EccPipeline_g` 2 and an unknown `Resource_g` stop it with the message of the vertical filter, which names the generic | BIN-CF-01, BIN-CF-02 |
| TC-BIN-08 (`lint/libero_synth.py`) | Preliminary synthesis on PolarFire MPF100T (Libero, Synplify Pro) with a clock of 125 MHz, the Timing level (architecture, section 10): 2 x 2 valid, 12-bit pixels, 4096 pixels per line (the default); 4 x 4 replicate; the resources and the estimated worst slack recorded in the verification report, a pre-layout estimate. The default configuration meets 125 MHz in the estimate; a further configuration records the frequency it reaches | BIN-CF-03 |

## 4. Requirement coverage

| Requirement | Test cases | Method |
| --- | --- | --- |
| BIN-IF-01, BIN-IF-02 | TC-BIN-01 to 05 | Test |
| BIN-IF-03 | TC-BIN-02, 03, 05 | Test |
| BIN-IF-04 | TC-BIN-04 | Test |
| BIN-FN-01, BIN-FN-02, BIN-FN-03 | TC-BIN-01 (all configurations and the sweep) | Test |
| BIN-FN-04 | TC-BIN-01 (`bin_x_only`, `bin_y_only`, `bin_none`), 05 (the latencies of `rate_x_only`, `rate_y_only`, `rate_none`), 06 | Test and review |
| BIN-PF-01, BIN-PF-02 | TC-BIN-05 | Test |
| BIN-ER-01 | TC-BIN-02, 04 | Test |
| BIN-FT-01 | TC-BIN-03, 04 | Test |
| BIN-CF-01, BIN-CF-02 | TC-BIN-07 | Synthesis |
| BIN-CF-03 | TC-BIN-08 | Timing |

## 5. Timing bounds

Wo is the width of the narrowed image, N = (`BinY_g` - 1) x Wo the number of virtual pixels of the vertical filter
after every image in the border modes zero and replicate (0 in the mode valid), lx = log2ceil(`BinX_g`) and
ly = log2ceil(`BinY_g`).

| Bound | Design value | Derivation |
| --- | --- | --- |
| Hold cycles between the first pixels of two lines (BIN-PF-01) | `BinX_g` - 1 in the modes zero and replicate, 0 in the mode valid; in an image that follows an image one line interval also holds the wait for the virtual lines | The virtual columns of the horizontal filter (Rr = `BinX_g` - 1 with the anchor 0); the vertical filter has no virtual columns (`WinX_g` = 1) and takes one bin in `BinX_g` cycles |
| Wait for the virtual lines of the vertical filter, in an image that follows an image (BIN-PF-01) | Exactly N + 8 + lx + e - `BinX_g` x (5 + c), c = ceil((3 + lx) / `BinX_g`), e = (`BinX_g` - W mod `BinX_g`) mod `BinX_g` in the modes zero and replicate (0 for W a multiple of `BinX_g`), when the buffers fill within line 0 of the image (p = `BinX_g` x (4 + c) + 3 < W) and the value is positive; otherwise from max(0, d - A) to the bound of BIN-PF-01, max(0, N + 2 - 2 x `BinX_g`), with d = max(0, N + 2 + e - 2 x `BinX_g`) and A = `BinX_g` x (4 + c) + `BinX_g` + 2; with one filter or none exactly d = N | Below |
| Image period (BIN-PF-02) | H x W in the mode valid; H x (W + `BinX_g` - 1) plus the wait in the modes zero and replicate; the same for every interval from the second on, the first interval after an idle module at most the largest value | The events of the horizontal filter: W pixels and `BinX_g` - 1 virtual columns per line; the wait adds what the buffers do not take |
| Latency from the acceptance of the last pixel of a bin to its output | 12 + lx + ly to 16 + lx + ly with both filters; 6 + lx to 8 + lx or 6 + ly to 8 + ly with one; 2 with the frame sync alone | Per filter the window 3 (frame sync 2, event 1), up to 2 more for a pixel that the frame sync took while the filter held its input, and the kernel 3 + log2ceil(T) (FLT-PF-02); the frame sync alone 2 (FSY-PF-02) |
| Fall of `Stat_ImageOpen` after the acceptance of the last pixel of an image | 7 + lx + e + s cycles with both filters; 1 + s cycles with one filter or the frame sync alone; s = `BinX_g` - 1 in lines of at most 3 pixels in the modes zero and replicate, 0 otherwise | Below |

**Rate configurations.**

| Configuration | d | A | Wait | Period |
| --- | --- | --- | --- | --- |
| `rate_valid` | 0 (no virtual pixels) | - | 0 | 128 |
| `rate_rep` | 0 (N = 4) | 30 | 0 | 152 |
| `rate_tall` | 54 (N = 56) | 16 | 51 exactly (p = 15) | 323 |
| `rate_x_only` | 0 | 0 | 0 | 152 |
| `rate_y_only` | 48 (N = 48) | 0 | 48 | 176 = (H + 3) x W, the lower border of `isp_window` |
| `rate_none` | 0 | 0 | 0 | 128 |
| `rate_odd_w33` (e = 1) | 16 (N = 17) | 16 | 13 exactly (p = 15) | 285 |
| `rate_odd_w33_tall` (e = 1) | 118 (N = 119) | 16 | 115 exactly (p = 15) | 659 |
| `rate_odd_w13` (e = 1) | 48 (N = 49) | 16 | 32 to 47 (p = 15 >= W) | 256 to 271 |
| `rate_odd_w13_bx4` (e = 3) | 1 (N = 4) | 30 | 0 (bound 0) | 128 |
| `rate_odd_w17_bx8` (e = 7) | 0 (N = 3) | 50 | 0 | 192 |
| `rate_odd_w17_bx8_tall` (e = 7) | 38 (N = 45) | 50 | 0 to 31 (p = 43 >= W) | 384 to 415 |
| `rate_odd_w17_bx16_tall` (e = 15) | 15 (N = 30) | 98 | 0 (bound 0) | 512 |
| `rate_odd_w3` (e = 1, s = 1) | 1 (N = 2) | 16 | 0 (bound 0) | 32 |
| `rate_odd_w5_bx4` (e = 3) | 3 (N = 6) | 30 | 0 (bound 0) | 64 |
| `rate_odd_x_only`, `rate_odd_x_only_w3` (s = 1) | 0 | 0 | 0 | 60; 24 |
| `rate_range_w22_bx4` (e = 2) | 86 (N = 90) | 30 | 56 to 84 (p = 27 >= W) | 456 to 484 |
| `rate_range_w21_bx4` (e = 3) | 87 (N = 90) | 30 | 57 to 84 | 441 to 468 |
| `rate_range_w23_bx4` (e = 1) | 85 (N = 90) | 30 | 55 to 84 | 471 to 500 |
| `rate_range_w16_bx4` (e = 0) | 54 (N = 60) | 30 | 24 to 54 | 328 to 358 |
| `rate_range_w10_bx4` (e = 2) | 41 (N = 45) | 30 | 11 to 39 | 219 to 247 |
| `rate_range_w12_bx2` (e = 0) | 40 (N = 42) | 16 | 24 to 40 (p = 15 >= W) | 232 to 248 |
| `rate_range_w9_bx2` (e = 1) | 74 (N = 75) | 16 | 58 to 73 | 218 to 233 |
| `rate_range_w20_bx8` (e = 4) | 35 (N = 45) | 50 | 0 to 31 (p = 43 >= W) | 432 to 463 |

**The wait for the virtual lines.** After the PIX event of the last bin of an image (cycle v0) the vertical filter makes
N VPIX events in N consecutive cycles, and its input waits. Without them, its first PIX event of the next image would
come 2 x `BinX_g` - 1 cycles after v0: the horizontal filter makes `BinX_g` - 1 HCOL events after the last pixel of the
image and then takes the `BinX_g` pixels of the first bin of the next one, and that bin passes the same pipeline of
constant length to the vertical filter. The VPIX events therefore delay the events of the vertical filter by d = max(0,
N + 2 + e - 2 x `BinX_g`) cycles (e below), and the input waits at most d cycles. It waits less by what the buffers
between the window of the vertical filter and the input take meanwhile, at most A input cycles: the frame sync of the
vertical filter (3 bins: its output register and the two entries of its input stage, an `olo_base_pl_stage` with a
registered ready), the kernel of the horizontal filter (c = ceil(S / `BinX_g`) bins, S = 3 + lx stages, which freeze
together with the bubbles between their bins), its window register (1 bin), the `BinX_g` - 1 events before its next
window and its frame sync (3 pixels). Without the horizontal filter nothing is buffered and the input waits for all N
virtual pixels, the lower border of `isp_window` (WIN-PF-01).

The occupancy of these buffers is deterministic when the input runs without gaps and the sink without stalls, and it
gives the wait exactly where the buffers fill within line 0. Let h0 be the PIX event of the horizontal filter for the
last pixel of an image; the vertical filter makes its last PIX event at v0 = h0 + 6 + lx (the kernel, the two cycles of
its frame sync and the event). Pixel x of line 0 of the next image is accepted at h0 + `BinX_g` + x - 2 (its event comes
2 cycles later, after the `BinX_g` - 1 HCOL events). The first bins of the next image fill the frame sync of the
vertical filter (bins 0 to 2); the next bin reaches the output register of the kernel and cannot leave, so the kernel
freezes with c bins; the next bin waits in the window register, the frame sync of the horizontal filter takes 3 more
pixels, and pixel p = `BinX_g` x (4 + c) + 3 is the first that waits, at h0 + `BinX_g` + p - 2. The vertical filter
makes its first PIX event at v0 + N + 1; its input stage is ready one cycle later (registered), the kernel and the
window of the horizontal filter advance in that cycle, and the input stage of the horizontal filter is ready one more
cycle later: the input is released at v0 + N + 3. The wait is therefore N + 8 + lx - `BinX_g` x (5 + c) when that is
positive and p < W; `rate_tall` waits 51 cycles. This holds for W a multiple of `BinX_g`, as in every rate
configuration: the PIX event of the last pixel completes the last bin. Otherwise (the modes zero and replicate) the e-th
HCOL event after it completes the bin, e = (`BinX_g` - W mod `BinX_g`) mod `BinX_g`; v0 and the release of the input
come e cycles later, while the pixels of the next image do not, and the wait is N + 8 + lx + e - `BinX_g` x (5 + c). The
chain `reordered` of `isp_chain` (W = 33, `BinX_g` 2, e = 1) waits 36 cycles. Elsewhere the bench checks the range,
which follows from the same buffers without fixing their occupancy.

**The bound of BIN-PF-01.** BIN-PF-01 bounds the wait by max(0, N + 2 - 2 x `BinX_g`), the value of d without e. The
exact wait stays below it for every `BinX_g` >= 2: the difference is 6 + lx + e - `BinX_g` x (3 + c), and with
e <= `BinX_g` - 1 and c >= 1 it is negative (-2 or less for `BinX_g` 2, -5 for 3, -9 for 4, and less beyond). Where
p >= W the bins that fill the buffers come from two or three lines: the last bin of a line has `BinX_g` - e pixels, the
HCOL events of the line end hold the input and leave gaps between the bins, so the frozen kernel holds a different
number of bins. The derivation fixes no exact value there (the exact formula is off by -3 to +1 cycles in the
configurations `rate_range_*`); the bench checks the wait from max(0, d - A) up to the bound of BIN-PF-01, and for
p >= W the requirement is verified by test on the configurations with p >= W: `BinX_g` 2, 4, 8 and 16, every e of
`BinX_g` 4 (0 to 3), e 0 and 1 of `BinX_g` 2 and e up to 15, the bins of the buffers across one and two line
boundaries (W from 3 to 23), N up to 90, and the bound 0 with a positive d (`rate_odd_w3`, `rate_odd_w5_bx4`,
`rate_odd_w13_bx4`, `rate_odd_w17_bx16_tall`). The smallest margin to the bound comes with `BinX_g` 2, where the exact
case leaves the least room.

**`Stat_ImageOpen` and the probe of `test_rate`.** e0 is the edge that accepts the last pixel of the last image. The
frame sync of the horizontal filter closes the image when the pixel moves from its input stage into its output register,
at e0 + 1 + s. After the last pixel of a line the window makes `BinX_g` - 1 HCOL events, and the frame sync takes three
more pixels before its input holds (its output register and the two entries of its input stage), so the hold comes in
the fourth cycle after that pixel. A line of more than 3 pixels passes the hold before its last pixel, which then moves
on at once (s = 0); in a line of at most 3 pixels the last pixel waits behind the `BinX_g` - 1 events (s = `BinX_g` -
1). The window takes the pixel at e0 + 2 + s and completes the last bin with it, or e HCOL events later; the kernel
loads the bin at e0 + 3 + e + s, multiplies one cycle later, adds in lx stages and loads its output register at e0 + 5 +
lx + e + s; the frame sync of the vertical filter takes the bin at e0 + 6 + lx + e + s (the latency 6 + log2ceil(T) of
`isp_filter2d`) and closes the image at e0 + 7 + lx + e + s. The probe ("T 4" after the last pixel) reads
`Stat_ImageOpen` after e0 + 3: after the fall of the horizontal filter (e0 + 1 + s, s at most 2 with both filters)
and at least 4 cycles before the fall of the vertical one, so it reads 1 from the vertical filter alone. Every rate
configuration with both filters carries it; with one filter the port has a single source. The bench also measures the
fall of the port after the last pixel of every image: with both filters the horizontal filter opens the next image
before the vertical filter closes the image before, so the port falls only after the last image, 7 + lx + e + s cycles
after its last pixel; with one filter or the frame sync alone it falls 1 + s cycles after the last pixel of every image
and rises again with the next image.

**The probes after complete images.** The probe of the shared components after complete images waits for the sink and
8 cycles. In the mode valid with lines or columns that no bin uses, no output follows the last pixel of an image, so
the wait for the sink ends with the last pixel, while the vertical filter closes the image only 7 + lx cycles after
it. The probes of this bench after complete images therefore wait 7 + lx + 8 cycles after the wait for the sink and
read `Stat_ImageOpen` 7 cycles after its fall (the shared probe has the same margin after the fall of a single frame
sync, 1 cycle after the last pixel).

The bench checks the design values. A measured value outside the derivation is a finding: the cause is found (the
RTL or the derivation), recorded in the findings of the verification report, and the wrong one is corrected. A
derivation is never adjusted to fit a measurement.

## 6. Negative tests and mutations

| Mutation | Expected to fail |
| --- | --- |
| The output width of the horizontal filter one bit short | TC-BIN-01 (the image of largest pixels) |
| The stride of the vertical filter 1 instead of `BinY_g` | TC-BIN-01 (contract) |
| The border mode not passed to the vertical filter (valid) | TC-BIN-01 (`bin2_zero`, `bin3x5_rep`) |
| The width of the narrowed image floor(W / `BinX_g`) in every border mode | TC-BIN-01 (`bin2_zero`: W = 13) |
| The vertical filter kept for `BinY_g` 1 (a window of one line) | TC-BIN-05 (the latency of `rate_x_only`) |
| The horizontal filter kept for `BinX_g` 1 (a window of one pixel) | TC-BIN-05 (the latency of `rate_y_only`) |
| The frame sync left out for 1 x 1 (a connection) | TC-BIN-02 (`Err_Framing` of `bin_none`) |
| `Stat_ImageOpen` of the horizontal filter not connected | TC-BIN-02 (the probe after the first pixel) |
| `Stat_ImageOpen` of the vertical filter not connected | TC-BIN-05 (the probe 4 cycles after the last pixel) |
| `Err_Framing` of the horizontal filter not connected | TC-BIN-02 |
| `Stat_EccDed` of the vertical filter not connected | TC-BIN-03 |
| `Stat_EccSec` and `Stat_EccDed` exchanged | TC-BIN-03 (3 single and 2 double errors) |
| `ErrInj_Valid` not connected | TC-BIN-03 |

`Err_Framing` of the vertical filter not connected is equivalent at the ports and is not run: the horizontal filter
outputs complete images only (a short image is padded, an image start completes an open image) and `Rst` is common to
both filters, so the frame sync of the vertical filter sees a malformed stream only after an upset between the two
filters (section 7).

## 7. Expected coverage exclusions

The coverage of the parts is measured by their own benches. The frame sync of the vertical filter acts only after an
upset between the two filters (architecture, section 4).

## 8. Test data

Random pixels over the full range of `PixelBits_g`, and in every configuration an image of largest pixels, so that
the sums reach the top of the output width.
