# isp_bin: Verification Report

## 1. Test results

Run on 2026-11-20 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM (commit 4f1e13b), Open Logic 4.8.0-ft.2:
`python run.py -p 4` on 2eb6d50, 601 of 601 tests passed (59 of them `isp_bin`), 0 skipped. The tests of `isp_bin` ran
again on 4ba63f8, which changes only the wait of the probes after complete images (section 7): 59 of 59 passed, 0
skipped. QuestaSim runs with the release regression (with and without code coverage).

The configuration checks of the audit of every module (section 7) came later: `python run.py -p 4` on 2026-11-20 on
commit 4cef90a, 601 of 601 tests passed (59 of them `isp_bin`), 0 skipped; `lint/synth_check.py` (TC-BIN-07) passed.

The rate configurations with W not a multiple of `BinX_g` and with p >= W (section 7) came later: `python run.py -p 4`
on 2026-11-20 on commit 9f48b53, 663 of 663 tests passed (97 of them `isp_bin`), 0 skipped.

| Test | Configurations | Passed |
| --- | --- | --- |
| `test_static` (TC-BIN-01) | 54 (with the sweep) | 54 |
| `test_input_stream` (TC-BIN-02) | 8 | 8 |
| `test_ecc` (TC-BIN-03) | 3 | 3 |
| `test_reset` (TC-BIN-04) | 7 | 7 |
| `test_rate` (TC-BIN-05) | 25 | 25 |
| TC-BIN-06 (review) | Section 6 | Passed |
| TC-BIN-07 (`lint/synth_check.py`) | 8 configurations synthesise without latches; 10 generics out of range stop the elaboration with a message naming the generic | 18 |
| TC-BIN-08 (`lint/vivado_ooc.py`) | Section 5 | Not run |

## 2. Summary

Every output pixel of every test equals the reference model, which computes the sum of every bin from the definition
of the specification (the image extended by the border mode), with and without gaps of the source and stalls of the
sink; the contract checker of the sink found the output contract (Wo x Ho) in every test. The model of the two filters
in series, which gives the pulse counts, `Stat_ImageOpen` and the timing, gave the same output pixels in every test
without an injection (an assertion of the model).

- Bins: 2 x 2 in the modes valid (the last column and line dropped) and zero, 3 x 5 replicate (an output width below
  the sum of the widths of the two filters), 4 x 4 on shift registers with `EccPipeline_g` 0, the shapes without the
  vertical filter (4 x 1), without the horizontal filter (1 x 4) and without both (1 x 1, the frame sync), 16 x 16 of
  28-bit pixels on block RAM with Wo = 4 (the bound of the block RAM), 1-bit pixels (2 x 3), an image of one bin
  (4 x 4), a 1 x 1 image of 1-bit pixels, lines of 65536 pixels, and the sweep of every factor 1 to 16 in both
  directions in the three border modes. Every `test_static` contains images in five divisions into packets (two for
  65536 pixels per line), a pause of the source, an image of the largest pixels (the largest sums, the top of the
  output width) and an image of zeros.
- The input stream: an image cut after its first pixel and probed (`Stat_ImageOpen` 1 with only the frame sync of
  the input open), then the malformed streams with an image cut after half of its pixels and probed while open,
  images cut short and completed at the next image start, pixels without an image start, wrong end flags, random
  packets; the output images are complete and the `Err_Framing` counts equal the model (12 to 39 pulses per test).
- ECC: for every line buffer of the vertical filter a single and a double error on data bits of a pixel that the
  window of a bin reads, and one more single error: the single errors leave the sums unchanged, the double error
  shows in the sum of its bin; `Stat_EccSec` and `Stat_EccDed` pulsed 3 and 2 times in `ecc` and `bits1`. With
  `BinY_g` 1 (`sweep_16`) the injection has no effect.
- Resets idle, held during a line and after the last pixel (with the virtual pixels in progress), held with the sink
  stopped while the filters held bins, running during a line and after the last pixel: the next images are correct.
- The control outputs carry no metavalue after the first reset, no output pixel carries a metavalue, and `Out_Valid`
  and the status outputs are 0 after every reset.

Measured timing (test_rate, four images back to back from the reset, the sink never stalls), every value checked
against the design value of the plan (section 5):

| Configuration | Holds per line | Wait for the virtual lines | Image period | Latency | Fall of `Stat_ImageOpen` |
| --- | --- | --- | --- | --- | --- |
| `rate_valid` (4 x 2 valid) | 0 | 0 | 128 | 15 (design 15 to 19) | 9 = 7 + log2ceil(4) |
| `rate_rep` (4 x 2 replicate) | 3 | 0 (N = 4 < 2 x `BinX_g` - 2) | 152 | 15 | 9 |
| `rate_tall` (2 x 8 replicate) | 1 | 51, exactly as derived | 323 | 16 to 17 (design 16 to 20) | 8 = 7 + log2ceil(2) |
| `rate_x_only` (4 x 1) | 3 | 0 | 152 | 8 (design 8 to 10) | 1 |
| `rate_y_only` (1 x 4) | 0 | 48 = N, the lower border of `isp_window` | 176 | 8 (design 8 to 10) | 1 |
| `rate_none` (1 x 1) | 0 | 0 | 128 | 2 | 1 |
| `rate_odd_w33` (2 x 2, W 33, e = 1) | 1 | 13, exactly as derived | 285 | 14 to 15 | 9 = 7 + 1 + e |
| `rate_odd_w33_tall` (2 x 8 zero, W 33, e = 1) | 1 | 115, exactly as derived | 659 | 16 to 17 | 9 |
| `rate_odd_w13` (2 x 8, W 13, e = 1) | 1 | 45 (design 32 to 47) | 269 | 16 to 17 | 9 |
| `rate_odd_w13_bx4` (4 x 2, W 13, e = 3) | 3 | 0 (bound 0) | 128 | 15 | 12 = 7 + 2 + e |
| `rate_odd_w17_bx8` (8 x 2 zero, W 17, e = 7) | 7 | 0 | 192 | 16 | 17 = 7 + 3 + e |
| `rate_odd_w17_bx8_tall` (8 x 16, W 17, e = 7) | 7 | 15 (design 0 to 31) | 399 | 19 | 17 |
| `rate_odd_w17_bx16_tall` (16 x 16, W 17, e = 15) | 15 | 0 (bound 0) | 512 | 20 | 26 = 7 + 4 + e |
| `rate_odd_w3` (2 x 2, W 3, e = 1, s = 1) | 1 | 0 (bound 0) | 32 | 15 | 10 = 7 + 1 + e + s |
| `rate_odd_w5_bx4` (4 x 4 zero, W 5, e = 3) | 3 | 0 (bound 0) | 64 | 16 | 12 |
| `rate_odd_x_only` (2 x 1, W 9) | 1 | 0 | 60 | 7 to 8 | 1 |
| `rate_odd_x_only_w3` (2 x 1 zero, W 3, s = 1) | 1 | 0 | 24 | 7 to 8 | 2 = 1 + s |

In the configurations with both filters the probe 4 cycles after the last pixel read `Stat_ImageOpen` 1 from the
vertical filter alone, and the port fell 7 + log2ceil(`BinX_g`) + e + s cycles after the last pixel, after the last
image only; with one filter or none it fell 1 + s cycles after the last pixel of every image.

The configurations with p >= W, where the plan checks the wait from max(0, d - A) up to the bound of BIN-PF-01 (the
requirement verified by test, plan section 5):

| Configuration | Wait | Range of the plan | Bound of BIN-PF-01 | Exact formula | Period | Fall |
| --- | --- | --- | --- | --- | --- | --- |
| `rate_odd_w13` (2 x 8, e = 1) | 45 | 32 to 47 | 47 | 45 | 269 | 9 |
| `rate_odd_w17_bx8_tall` (8 x 16, e = 7) | 15 | 0 to 31 | 31 | 15 | 399 | 17 |
| `rate_range_w22_bx4` (4 x 16, e = 2) | 74 | 56 to 84 | 84 | 74 | 474 | 11 |
| `rate_range_w21_bx4` (4 x 16, e = 3) | 75 | 57 to 84 | 84 | 75 | 459 | 12 |
| `rate_range_w23_bx4` (4 x 16, e = 1) | 73 | 55 to 84 | 84 | 73 | 489 | 10 |
| `rate_range_w16_bx4` (4 x 16, e = 0) | 43 | 24 to 54 | 54 | 42 | 347 | 9 |
| `rate_range_w10_bx4` (4 x 16, e = 2) | 28 | 11 to 39 | 39 | 29 | 236 | 11 |
| `rate_range_w12_bx2` (2 x 8, e = 0) | 37 | 24 to 40 | 40 | 37 | 245 | 8 |
| `rate_range_w9_bx2` (2 x 16, e = 1) | 71 | 58 to 73 | 73 | 71 | 231 | 9 |
| `rate_range_w20_bx8` (8 x 16, e = 4) | 9 | 0 to 31 | 31 | 12 | 441 | 14 |

The wait lies below the bound of BIN-PF-01 in every configuration. The smallest margin is 2 cycles, with `BinX_g` 2
(`rate_odd_w13` and `rate_range_w9_bx2`): a change that lengthens the wait breaks the requirement there first. The exact
formula does not hold for p >= W in general (`rate_range_w16_bx4` waits one cycle more, `rate_range_w10_bx4` one and
`rate_range_w20_bx8` three cycles less), so the plan keeps the range there. The latency stayed in the design range of
every configuration, and the fall of `Stat_ImageOpen` was 7 + lx + e + s in every configuration.

The wait of `rate_tall`, explained from the design (plan, section 5), with h0 the PIX event of the horizontal filter
for the last pixel of an image: the vertical filter makes its last PIX event at h0 + 7 and its 56 VPIX events, and
takes its first pixel of the next image at h0 + 64. Meanwhile its frame sync takes bins 0 to 2 of the next image (the
output register and both entries of its input stage), the kernel of the horizontal filter freezes with bin 3 in its
output register and bin 4 in stage 2 (bubbles in stages 1 and 3), bin 5 waits in the window register and the frame
sync of the horizontal filter takes pixels 12 to 14: pixel 15, due at h0 + 15, is the first held. The input is
released at h0 + 66, after the registered ready of both input stages: 51 cycles.

## 3. Generic ranges

| Generic | Declared range | Simulated | Synthesised |
| --- | --- | --- | --- |
| `ImageWidth_g` | `BinX_g` to 65536 | 1, `BinX_g` (4 of `image_equals_bin`), 4 to 19, 64, 65536 | 1, 2 (`BinX_g`), 1024, 4096, 65536; `BinX_g` - 1 and 65537 stop the elaboration |
| `ImageHeight_g` | `BinY_g` to 65536 | 1, `BinY_g` (4 of `image_equals_bin`), 2, 4 to 19, 34 | 1, 2 (`BinY_g`), 1024, 65536; `BinY_g` - 1 stops the elaboration |
| `PixelBits_g` | 1 to 28 | 1, 8, 12, 16, 28 | 1, 12, 28; 29 stops the elaboration |
| `BinX_g`, `BinY_g` | 1 to 16 | every value | 1, 2, 3, 4, 5, 16; 17 stops the elaboration |
| `BorderMode_g` | valid, zero, replicate | every value | every value; mirror stops the elaboration |
| `EccPipeline_g` | as `isp_window` (0, 1) | 0, 1 | 0, 1; 2 stops the elaboration |
| `Resource_g` | AUTO, SRL, BRAM | every value | every value; BRAM with Wo below 3 + `EccPipeline_g` and an unknown value stop the elaboration |

## 4. Mutations

Run on 2026-11-20 on commit 4ba63f8 in a worktree of its own (`git diff --quiet` before and after every mutant), with 14
tests: the 3 of `bin2_zero`, test_static of `bin2_valid` and `bin3x5_rep`, test_input_stream of `bin_none` and `min`,
test_ecc of `ecc` and `bits1`, and test_rate of `rate_rep`, `rate_tall`, `rate_x_only`, `rate_y_only` and `rate_none`.
Every one of the 13 mutants of the plan (section 6) fails at least one test, and the tests that fail include those the
plan expects. The bench changed with the terms e and s (section 7): the run again on commit 9f48b53 killed all 13
mutants with the same 14 tests. A mutant that changes several places of the source carries all of them in one run. A
first run on 2eb6d50, before the change of the probe wait, gave the same results. The width of the narrowed image moved
into `isp_pkg` (`ispBinOut`); its mutant, now on the call of the function, ran alone on 2026-11-20 on commit 2d4b4c8
with the same 14 tests and failed the same 4 tests.

| Mutation | Result | Failing tests |
| --- | --- | --- |
| None (reference) | passes (14 tests) | - |
| The output width of the horizontal filter one bit short | killed by 10 of 14 tests | test_ecc, test_input_stream, test_rate, test_reset, test_static |
| The stride of the vertical filter 1 instead of BinY_g | killed by 10 of 14 tests | test_ecc, test_input_stream, test_rate, test_reset, test_static |
| The border mode not passed to the vertical filter (valid) | killed by 7 of 14 tests | test_ecc, test_input_stream, test_rate, test_reset, test_static |
| The width of the narrowed image floor(W / BinX_g) in every border mode | killed by 4 of 14 tests | test_input_stream, test_reset, test_static |
| The vertical filter kept for BinY_g 1 (a window of one line) | killed by 1 of 14 tests | test_rate |
| The horizontal filter kept for BinX_g 1 (a window of one pixel) | killed by 1 of 14 tests | test_rate |
| The frame sync left out for 1 x 1 (a connection) | killed by 3 of 14 tests | test_input_stream, test_rate |
| Stat_ImageOpen of the horizontal filter not connected | killed by 2 of 14 tests | test_input_stream, test_rate |
| Stat_ImageOpen of the vertical filter not connected | killed by 3 of 14 tests | test_rate |
| Err_Framing of the horizontal filter not connected | killed by 2 of 14 tests | test_input_stream, test_reset |
| Stat_EccDed of the vertical filter not connected | killed by 2 of 14 tests | test_ecc |
| Stat_EccSec and Stat_EccDed exchanged | killed by 2 of 14 tests | test_ecc |
| ErrInj_Valid not connected | killed by 2 of 14 tests | test_ecc |

`Err_Framing` of the vertical filter not connected is equivalent at the ports and was not run: the horizontal filter
outputs complete images only (a short image is padded, an image start completes an open image) and `Rst` is common to
both filters, so the frame sync of the vertical filter sees a malformed stream only after an upset between the two
filters.

## 5. Synthesis and timing

Not run yet: TC-BIN-08 runs out-of-context synthesis and implementation at 150 MHz on the device of the Timing level
(architecture of the suite, section 10); the run is open (roadmap). The script `lint/vivado_ooc.py` is ready with the
configurations `bin_default` (2 x 2 valid, 12-bit pixels, 4096 pixels per line) and `bin_4x4_rep`.

The GHDL synthesis of TC-BIN-07 shows that the module is synthesisable at the bounds of its generics, in every border
mode and with every line buffer resource, without latches; it gives no timing.

## 6. Requirement coverage

TC-BIN-06 (review of `src/isp_bin.vhd`): the horizontal filter is an `isp_filter2d` on W x H pixels of P bits with
the window `BinX_g` x 1, anchor 0, the stride (`BinX_g`, 1), `BinX_g` constant coefficients of 1 (`CoefBits_g` 2) and
the output width P + log2ceil(`BinX_g`); the vertical filter an `isp_filter2d` on Wo x H pixels of that width with the
window 1 x `BinY_g`, anchor 0, the stride (1, `BinY_g`), `BinY_g` coefficients of 1, the output width Q and the
generics of its line buffers; the border mode goes to both. A filter whose factor is 1 is left out (generate), with
both factors 1 an `isp_frame_sync` connects the input to the output; `Err_Framing` and `Stat_ImageOpen` are the OR of
the parts, the ECC status and the injection belong to the vertical filter. The register slaves of the filters are
not connected; with constant coefficients they hold read-only registers only.

| Requirement | Test cases | Status |
| --- | --- | --- |
| BIN-IF-01, BIN-IF-02 | TC-BIN-01 to 05 | Passed |
| BIN-IF-03 | TC-BIN-02, 03, 05 | Passed |
| BIN-IF-04 | TC-BIN-04 | Passed |
| BIN-FN-01, BIN-FN-02, BIN-FN-03 | TC-BIN-01 (every configuration and the sweep) | Passed |
| BIN-FN-04 | TC-BIN-01, 05 (the shapes with one filter or none), 06 | Passed |
| BIN-PF-01, BIN-PF-02 | TC-BIN-05 | Passed |
| BIN-ER-01 | TC-BIN-02, 04 | Passed |
| BIN-FT-01 | TC-BIN-03, 04 | Passed |
| BIN-CF-01, BIN-CF-02 | TC-BIN-07 | Passed |
| BIN-CF-03 | TC-BIN-08 | Open (section 5) |

## 7. Findings

| Finding | Correction |
| --- | --- |
| BIN-PF-01 as written in phase A bounded the hold cycles of every line interval by `BinX_g` - 1 in the modes zero and replicate. A derivation before the first measurement showed that after every image the vertical filter makes (`BinY_g` - 1) x Wo virtual pixels, one per cycle, during which its input waits; once the buffers of the horizontal filter are full the input of the next image waits as well, up to max(0, (`BinY_g` - 1) x Wo + 2 - 2 x `BinX_g`) cycles (about 2000 cycles for 2 x 2 bins on lines of 4096 pixels). No design change: the module is two configurations of the window filter, and this is the lower border of `isp_window` behind the buffers of the horizontal filter | BIN-PF-01 amended (lead decision), the architecture, the plan (section 5, with the derivation) and section 2.4 of the user guide state the wait; `rate_tall` measures it |
| The first derivation of the buffers that take part of that wait counted two registers in the frame sync of each filter. Its input stage is an `olo_base_pl_stage` with a registered ready, which holds two beats, so the frame sync holds three. The trace with two registers gave 52 cycles for `rate_tall`, the measurement 51; a trace of the handshakes (section 2) showed the three entries | The plan counts three entries; the occupancy gives the wait exactly where the buffers fill within line 0 (`rate_tall`: 51, checked exactly), elsewhere the range from the corrected bound |
| The shared probe after complete images (wait for the sink, 8 cycles, probe 0) failed in `sweep_03` and `sweep_12`: the vertical filter closes an image 7 + log2ceil(`BinX_g`) cycles after its last pixel, and in the mode valid with lines or columns that no bin uses no output follows the last pixel, so the wait for the sink ends at once | The probes of this bench after a wait for the sink wait 7 + log2ceil(`BinX_g`) + 8 cycles, the fall of the vertical filter plus the 8 cycles of the shared probe: the probe reads `Stat_ImageOpen` 7 cycles after the fall (plan, section 5) |
| The model `bin_sum` emitted a line of bins at the end of the line; with a reset in the middle of a line the expected beats before the reset lacked the bins already complete. The model test against the two filters in series (`test_bin_filters_equal_definition` of `tools/tests/test_isp_model.py`) found it with `BinY_g` 1 | The model emits every bin with its last pixel, as the filters do; the sums are unchanged. `bin_sum` is used by `isp_bin` only: the test files of the other modules are unchanged (section 1) |
| The width of the narrowed image was 0 for an `ImageWidth_g` below `BinX_g` in the mode valid, and the elaboration stopped with a range error before the check of `ImageWidth_g` | The width is at least 1, so the check names the generic (`bin_width_below`) |
| The audit of the configuration checks found that `EccPipeline_g` 2 and an unknown `Resource_g`, which the module passes to the vertical filter, were not checked by a module of the suite (BIN-CF-01), and that the check of `Resource_g` BRAM compared with regard to case | `isp_window` checks both generics, the BRAM check compares without case as Open Logic does; the negatives `bin_ecc_2` and `bin_resource` show the messages through the module. The bench is unchanged |
| The rate configurations covered only W a multiple of `BinX_g`, so the timing derivations were never measured outside that case. The chain test found it: behind a binning with W = 33 the filter waited one cycle longer than the exact wait of the plan. With W not a multiple of `BinX_g` the last bin of a line is completed by the e-th HCOL event after the last pixel, e = (`BinX_g` - W mod `BinX_g`) mod `BinX_g`, so the vertical filter starts its virtual pixels and closes the image e cycles later; in a line of at most 3 pixels the last pixel also waits s = `BinX_g` - 1 cycles in the input stage of the frame sync behind the HCOL events of the line before (a trace of the handshakes of `rate_odd_w3`: the last pixel enters the second entry of the input stage, the frame sync closes the image at e0 + 2) | The plan (section 5) states e and s in the wait, its bound d and the fall; the bench takes them, and eleven rate configurations with W not a multiple of `BinX_g` (zero and replicate, both filters with p < W and p >= W, the horizontal filter alone, the low bound W = `BinX_g` + 1) measure them. BIN-PF-01 bounds the wait without e: the exact wait stays below that bound for every `BinX_g` (plan, section 5); for p >= W, where the bins come from several lines and the exact formula does not hold, the bench checks the bound itself in eight more configurations (`rate_range_*`: every e of `BinX_g` 4, `BinX_g` 2 and 8, bins across two line boundaries). The requirement is unchanged |
