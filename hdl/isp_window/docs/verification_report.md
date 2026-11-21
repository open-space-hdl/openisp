# isp_window: Verification Report

## 1. Test results

Run on 2026-11-19 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM (commit 4f1e13b), Open Logic 4.8.0-ft.2:
`python run.py -p 4`, 303 of 303 tests passed (128 of them `isp_window`), 0 skipped. QuestaSim Pro Microchip Edition
2024.3 ran the release regression with code coverage on 2026-11-21 on commit b50efd1:
`python run.py --questa --coverage -p 1`, 669 of 669 tests passed (128 of them `isp_window`), 0 skipped; the code
coverage is in [docs/coverage.md](../../../docs/coverage.md).

The status-output audit added a probe of `Stat_ImageOpen` while an image is open to test_input_stream:
`python run.py -p 4` on 2026-11-20 on commit 399d8b9, 542 of 542 tests passed (128 of them `isp_window`), 0 skipped.

The configuration checks of the audit of every module (section 7) came later: `python run.py -p 4` on 2026-11-20 on
commit 4cef90a, 601 of 601 tests passed (128 of them `isp_window`), 0 skipped; `lint/synth_check.py` (TC-WIN-08) passed.

`python run.py -p 4` on 2026-11-20 on commit e167a73 (the selections of section 7 and develop 572dbd7), 668 of 668
tests passed (128 of them `isp_window`), 0 skipped; `lint/synth_check.py` (TC-WIN-08) passed.

The border and row selections without the selection of the event position and the row selection of the next line by
compares (architecture, section 7) keep every cycle: in every test of the benches that contain the module, the signals
at the top level of the bench (the reset, the input and output streams, the status and error outputs and the injection
inputs; 21 in `isp_window_tb` and `isp_bin_tb`, 22 in `isp_filter2d_tb`, 29 in `isp_replace_tb`, 48 in `isp_chain_tb`)
are identical in every time step between commit 1f169a2 (before the change) and commit 5a47ea5: 128 tests of
`isp_window`, 32 of `isp_filter2d`, 97 of `isp_bin`, 89 of `isp_replace` and 21 of the chain, 367 in all, with every
border mode, the smallest images (1 x 1 in the configurations `min` of `isp_filter2d` and `isp_bin`, 3 x 3 with a 3 x 3
window), lines and columns of 65536 pixels, and images back to back. The generated stimuli and expected outputs of the
five benches are unchanged (1673 files).

| Test | Configurations | Passed |
| --- | --- | --- |
| `test_static` (TC-WIN-01) | 83 (with the sweeps) | 83 |
| `test_input_stream` (TC-WIN-02) | 11 | 11 |
| `test_handshake` (TC-WIN-03) | 11 | 11 |
| `test_ecc` (TC-WIN-04) | 8 | 8 |
| `test_reset` (TC-WIN-05) | 11 | 11 |
| `test_rate` (TC-WIN-06) | 4 | 4 |
| TC-WIN-07 (review) | Section 6 | Passed |
| TC-WIN-08 (`lint/synth_check.py`) | 8 configurations synthesise without latches; 19 generics out of range stop the elaboration with a message naming the generic | 27 |
| TC-WIN-09 (`lint/libero_synth.py`) | 3 configurations (section 5) | 3 of 3 synthesised |

## 2. Summary

Every output window of every test equals the reference model, which builds the windows from the definitions of the
specification; the contract checker of the sink found the output contract (Wo x Ho windows, one packet per line) in
every test, and no window carried a metavalue.

- Windows and borders: the modes valid, zero, replicate and mirror; every window size 1 to 16 in both directions
  (`WinY_g` 1 without line buffers), every odd mirror size, every anchor of a 4 x 3 window in the modes zero and
  replicate, every stride 1 to 16 in both directions, binning windows (2 x 2 and 4 x 4 with their stride), a row and a
  column window, the largest window (16 x 16 of 32-bit pixels), an image equal to the window, images of 65536 x 3 and
  3 x 65536 pixels, pixel widths of 1, 2, 6, 8, 12, 14, 16, 31 and 32 bits. Every image follows an image with other
  content, so a window element from a line of the image before would fail the comparison (WIN-FT-04).
- Input streams in every division into packets and malformed: the output images are complete, `Err_Framing` follows
  the model, and `Stat_ImageOpen` is 1 while an image is open and 0 after complete images.
- Handshakes: the sink held during the virtual columns, during the windows of the lower border and while the first
  pixels of the next image arrive; gaps and stalls in most configurations.
- ECC: per line buffer single errors on a data bit, a Hamming parity bit and the overall parity bit (corrected, one
  `Stat_EccSec` in the event that reads the word), double errors on two data bits and on a data and a parity bit (the
  pixel as read, in every element from that line buffer on, one `Stat_EccDed`), errors in two line buffers in one
  event (one pulse) and a single and a double error in one event (one pulse each); an injection in the last line of an
  image, reported in the windows of the lower border where the line is used and, with `AnchorY_g` = `WinY_g` - 1
  (`ecc_bottom`, `ecc_bottom_zero`), read in the first line of the next image where it is not used and not reported;
  injections into a line buffer whose row the border rule replaces (not reported, WIN-FT-02); with SRL and block RAM
  line buffers, with and without the ECC pipeline, and in the window of 16 x 16.
- Resets idle, held and running, during a line, at the end of an image and while the windows of the borders are
  output: the next images are correct, also their first lines.
- The control outputs carry no metavalue after the first reset, and `Out_Valid`, `Err_Framing`, `Stat_ImageOpen` and
  the ECC pulses are 0 after every reset.

Measured timing (test_rate, images back to back):

| Configuration | Latency (bound 6, design 3 to 5) | Hold cycles per line (WIN-PF-01, design) | Image period (WIN-PF-02, design) |
| --- | --- | --- | --- |
| `rate_rep` (3 x 3, replicate, Rr = 1, Rb = 1) | 3 to 4 | at most 1 (1); 18 between the first two lines after an image (Rb x (W + Rr) + Rr = 18) | 119 ((H + Rb) x (W + Rr) = 119) |
| `rate_valid` (3 x 3, valid) | 3 | 0 (0) | 96 (H x W = 96) |
| `rate_bin` (2 x 2, stride 2, valid) | 3 | 0 (0) | 96 (96) |
| `rate_right` (16 x 2, anchor (0, 0), zero, Rr = 15) | 3 | at most 15 (15); 46 between the first two lines after an image (46) | 217 (217) |

The first interval between two image starts after an idle module is shorter than the period (section 7); every
further interval equals the design value.

## 3. Generic ranges

| Generic | Declared range | Simulated | Synthesised |
| --- | --- | --- | --- |
| `ImageWidth_g` | `WinX_g` to 65536 | `WinX_g` (3 in `image_equals_window`), 4 to 20, 65536 | `WinX_g` (1), 4, 16, 64, 4096, 65536; below `WinX_g` and 65537 stop the elaboration |
| `ImageHeight_g` | `WinY_g` to 65536 | `WinY_g` (3), 4 to 20, 65536 | `WinY_g` (1), 8, 16, 64, 4096, 65536; below `WinY_g` stops the elaboration |
| `PixelBits_g` | 1 to 32 | 1, 2, 6, 8, 12, 14, 16, 31, 32 | 1, 8, 12, 16, 32; 33 stops the elaboration |
| `WinX_g`, `WinY_g` | 1 to 16 | every value | 1, 2, 3, 4, 5, 9, 16; 17 stops the elaboration |
| `AnchorX_g`, `AnchorY_g` | 0 to `WinX_g` - 1, 0 to `WinY_g` - 1 | every value of the window 4 x 3, the middle of every size, 0 and the last | 0, the middle, the last; `WinX_g` and `WinY_g` stop the elaboration |
| `StrideX_g`, `StrideY_g` | 1 to 16 | every value | 1, 2, 3, 16; 17 stops the elaboration |
| `BorderMode_g` | valid, zero, replicate, mirror | every value | every value; an unknown mode, mirror with an even window or an anchor beside the middle stop the elaboration |
| `EccPipeline_g` | 0, 1 | both | both; 2 stops the elaboration |
| `Resource_g` | AUTO, SRL, BRAM | every value | every value; BRAM with `ImageWidth_g` below 3 + `EccPipeline_g` and an unknown value stop the elaboration |

## 4. Mutations

Run on 2026-11-19 on commit 9195a3c in a worktree of its own (`git diff --quiet` before and after every mutant), with
the 21 tests of the configurations `rep3`, `zero3` and the ECC, rate and sweep configurations named in the plan, among
them `col5` and `anchor_0_2_zero` (`AnchorY_g` > Rb) and `ecc_bottom` and `ecc_bottom_zero` (`AnchorY_g` = `WinY_g` -
1). Every mutant of the plan (section 6) fails at least one test.

The mutant that takes the rows above the image from the line buffers instead of 0 needs a configuration with
`AnchorY_g` > Rb. In the mode zero the line buffers above the first line of an image hold the virtual lines of the
image before, which are 0, so the mutant is equivalent wherever the rows above the image reach no further than those
lines (`AnchorY_g` <= Rb). A first run on a882181 without `col5` and `anchor_0_2_zero` kept it alive; the set of tests
has them since.

The mutant `Stat_ImageOpen` tied to 0 came with the status-output audit (section 7) and ran alone on 2026-11-20 on
commit 399d8b9 with the same 21 tests; the reference run passed again.

The mutation run was repeated on 2026-11-20 on commit 31cca42, the selections without the selection of the event
position and the row selection of the next line by compares (architecture, section 7), with the same 21 tests and seven
mutants of the changed decisions. 23 of the 24 mutants fail at least one test. The column of pixel (0, 0) from the
registered row selection survives: it is equivalent at the ports, because every image that reaches the event control is
complete (the frame sync fills a short image, E1) and the reset loads the selection of line 0, so at every pixel (0, 0)
the registered selection already is that of line 0; only an upset of the register makes the restart act, which the bench
cannot cause through the ports. The restart is verified by review (TC-WIN-07, WIN-FT-03).

The output dimensions moved into `isp_pkg` (`ispWinOut`, section 7); the mutant that computes them in the border mode
valid for every border mode ran alone on 2026-11-20 on commit 2d4b4c8 with the same 21 tests (the reference run passed
again).

The mutation run was repeated on 2026-11-21 on commit 9ddf49d, the sources and benches of release 0.1.0, with the same
21 tests, a new reference run and every mutant of the module in one run, also `Stat_ImageOpen` tied to 0 and the mutant
of the output dimensions on the call of `ispWinOut`, which ran alone before; the table shows that run. 23 of the 24
mutants fail at least one test. The column of pixel (0, 0) from the registered row selection survives again; it is
equivalent at the ports (above). The failing tests of every other mutant are the same as before.

| Mutation | Result | Failing tests |
| --- | --- | --- |
| None (reference) | passes (21 tests) |  |
| Left border of the mode replicate not loaded | killed by 9 of 21 tests | test_ecc, test_handshake, test_input_stream, test_rate, test_reset, test_static |
| Mirror at the right border one column off (2m instead of 2m - 1) | killed by 2 of 21 tests | test_static |
| Row selection of the lower border one line too far (replicate) | killed by 8 of 21 tests | test_ecc, test_handshake, test_input_stream, test_rate, test_reset, test_static |
| Rows outside the image not cleared in the mode zero (line 0 instead) | killed by 7 of 21 tests | test_ecc, test_handshake, test_input_stream, test_reset, test_static |
| One virtual column too few for Rr = 1 | killed by 14 of 21 tests | test_ecc, test_handshake, test_input_stream, test_rate, test_reset, test_static |
| One virtual pixel too few per virtual line | killed by 14 of 21 tests | test_ecc, test_handshake, test_input_stream, test_rate, test_reset, test_static |
| Stride counter not counting | killed by 2 of 21 tests | test_static |
| Out_Last at the last column instead of the last reference pixel | killed by 3 of 21 tests | test_static |
| Out_User 01 instead of 11 for an output image of one line | killed by 1 of 21 tests | test_static |
| Elements in column-major order | killed by 20 of 21 tests | test_ecc, test_handshake, test_input_stream, test_rate, test_reset, test_static |
| ECC flags of the line buffers sampled in every event | killed by 3 of 21 tests | test_ecc |
| ECC flags of every delay counted, also of the delays the row selection does not use | killed by 4 of 21 tests | test_ecc |
| Injection patterns of the delays in reverse order | killed by 4 of 21 tests | test_ecc |
| An event that does not wait for Out_Ready | killed by 15 of 21 tests | test_handshake, test_input_stream, test_reset, test_static |
| Rows above the image taken from the line buffers (the image before) instead of 0 | killed by 3 of 21 tests | test_ecc, test_static |
| Pixel (0, 0) detected from x alone (the rows of line 0 at the first pixel of every line) | killed by 21 of 21 tests | test_ecc, test_handshake, test_input_stream, test_rate, test_reset, test_static |
| Pixel (0, 0) detected outside the state of the image pixels (a waiting pixel (0, 0) during the virtual events) | killed by 14 of 21 tests | test_ecc, test_handshake, test_input_stream, test_rate, test_reset, test_static |
| The column of pixel (0, 0) from the registered row selection (no restart of the rows) | SURVIVED |  |
| The left border of a virtual line not taken (the first VPIX) | killed by 8 of 21 tests | test_ecc, test_handshake, test_input_stream, test_rate, test_reset, test_static |
| The selection of a line of the upper border one line late | killed by 19 of 21 tests | test_ecc, test_handshake, test_input_stream, test_rate, test_reset, test_static |
| The last virtual line with the selection of the lines without a border | killed by 10 of 21 tests | test_ecc, test_handshake, test_input_stream, test_rate, test_reset, test_static |
| The left mirror of a virtual line not taken | killed by 2 of 21 tests | test_static |
| Stat_ImageOpen tied to 0 | killed by 2 of 21 tests | test_input_stream |
| The output dimensions of the border mode valid in every border mode | killed by 18 of 21 tests | test_ecc, test_handshake, test_input_stream, test_rate, test_reset, test_static |

## 5. Synthesis and timing

TC-WIN-09 (`lint/libero_synth.py`), the preliminary synthesis on PolarFire MPF100T (Libero, Synplify Pro, speed grade
STD) with a clock of 125 MHz, on commit 4c1744f (the RTL of develop 06a41e5). The results are pre-layout estimates, not
a timing closure and not on the reference device. The out-of-context run at 150 MHz on the Versal device of the
reference systems is open (ISP-GEN-04, roadmap).

| Configuration | Estimate (MHz) | Slack (ns) | 4LUT | DFF | LSRAM | Math | Worst path (logic levels) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `win_default`: 3 x 3 replicate, 12 bits, 4096 pixels per line (the default) | 146.9 | 1.194 | 1139 | 720 | 8 | 0 | the state of the event control -> the line buffer RAM (4) |
| `win_mirror5`: 5 x 5 mirror, 16 bits, 4096 pixels per line | 139.5 | 0.833 | 2329 | 1688 | 20 | 0 | the state -> the row select register (8) |
| `win_max`: 16 x 16 zero, 32 bits, 4096 pixels per line | 106.7 | -1.370 | 10798 | 14987 | 120 | 0 | the state -> the decision of the left border -> the synchronous clear of 7680 window register bits (5; one net of 7680 loads) |

The default configuration and 5 x 5 mirror meet 125 MHz in the estimate (section 5.1). `win_max`, the largest window and
not a default, reaches 106.7 MHz (user guide, section 8).

The GHDL synthesis of TC-WIN-08 shows that the module is synthesisable at the bounds of its generics, with every
border mode and every line buffer resource, without latches; it gives no timing.

### 5.1 The event control

The preliminary synthesis on PolarFire MPF100T (Libero, Synplify Pro) with a clock of 125 MHz, pre-layout estimates,
not a timing closure and not on the reference device:

| Configuration | Before (MHz, 4LUT) | Worst path before | The decisions per state (b0dfcbb) | With the row selection by compares (the design) | Worst path of the design |
| --- | --- | --- | --- | --- | --- |
| `win_default` (3 x 3 replicate) | 141.8, 1118 | the state -> a column of the window register (6 logic levels) | 151.3, 1199 | 146.9, 1139 | the state -> the write of line buffer 1 (4) |
| `win_mirror5` (5 x 5 mirror, 16 bits) | 120.5, 2292 | the state -> the event position -> pixel (0, 0) -> the row multiplexer -> the window register (10) | 112.0, 2406 | 139.5, 2329 | the state -> the row select register (8) |

The first step took the decisions off the selection of the event position (architecture, section 7.2); in `win_mirror5`
the row selection of the next line then limited, `rowSelect`(ye + 1) synthesised as 14-bit subtractions and compares (19
logic levels). The second step compares the event line with the few lines whose selection differs (architecture, section
7.1). In `isp_filter2d` 5 x 5 mirror (`flt_mtf5`) the ready path from `isp_conv` into the event control limits after
this change.

## 6. Requirement coverage

| Requirement | Test cases | Status |
| --- | --- | --- |
| WIN-IF-01, WIN-IF-02, WIN-IF-03 | TC-WIN-01 to 06 | Passed |
| WIN-IF-04 | TC-WIN-02, 04 | Passed |
| WIN-IF-05 | TC-WIN-04 | Passed |
| WIN-IF-06 | TC-WIN-05 | Passed |
| WIN-FN-01, WIN-FN-02 | TC-WIN-01 | Passed |
| WIN-FN-03 | TC-WIN-01, 02 | Passed |
| WIN-FN-04, WIN-FN-05 | TC-WIN-03, 06 | Passed |
| WIN-FN-06 | TC-WIN-01, 03 | Passed |
| WIN-PF-01, WIN-PF-02, WIN-PF-03 | TC-WIN-06 | Passed |
| WIN-ER-01, WIN-ER-02 | TC-WIN-02, 05 | Passed |
| WIN-ER-03 | TC-WIN-04 | Passed |
| WIN-FT-01, WIN-FT-02 | TC-WIN-04 | Passed |
| WIN-FT-03 | TC-WIN-05 and review (TC-WIN-07): the `when others` branch of the event state machine leads to `Pix_s`; pixel (0, 0) restarts the row selection and the stride counters; the line of the next event follows the position of the frame sync at the end of every line | Passed |
| WIN-FT-04 | TC-WIN-01, 05 and the monitor of every test | Passed |
| WIN-CF-01, WIN-CF-02, WIN-CF-03, WIN-CF-05 | TC-WIN-08 | Passed |
| WIN-CF-04 | TC-WIN-09 | Open (section 5) |

## 7. Findings

| Finding | Correction |
| --- | --- |
| The first rate test measured 101 cycles between the first two image starts where the plan derived (H + Rb) x (W + Rr) = 119. The RTL is right: the input stage of `isp_frame_sync` takes the first pixel of the next image during the virtual lines of the image before, so the first interval after an idle module is shorter; from the second interval on the input waits for those virtual lines and the period is exact | The derivation of the plan and the interpretation of the specification state the first interval; the bench checks it against the bound and every further interval against the period |
| For the same reason the hold cycles between the first pixels of the first two lines of an image that follows an image include the virtual lines of the image before (18 and 46 cycles, Rb x (W + Rr) + Rr exactly); WIN-PF-01 as written in phase C bounded them by Rr | WIN-PF-01 bounds these cycles separately; the plan and the bench follow |
| test_handshake, as first built, held the sink right after an image and then sent two pixels of the next image; with pixels of the image still in the input stage, the source waited on a beat that could not enter and never released the sink | The builder holds the sink only with no input pending and sends the first pixels of the next image from an idle module |
| Review of the pull request: `Stat_EccSec` and `Stat_EccDed` were the OR over all line buffers in every pixel event, so the rows that the border rule replaces reported errors although their pixels never reach a window: the image before, and after power-up any content of a RAM that the device does not initialise | The flags of a line buffer count only when the row selection of the event uses it (WIN-FT-02, WIN-IF-04); `test_ecc` injects into replaced rows, the configurations `ecc_bottom` and `ecc_bottom_zero` read a last-line injection in the first line of the next image, and the plan has a mutant without the gate |
| The anchors out of range failed at a derived constant before the check that names the generic; the comparisons of the virtual columns used `VCols_c - 1`, which is -1 without virtual columns | The derived constants are limited to 0 and the comparison is an integer comparison; the positions have one value more |
| The audit of the status outputs of every module (after the mutation run of `isp_filter2d`) found `Stat_ImageOpen` probed only after complete images, where it is 0: a port tied to 0 would have passed every test | test_input_stream begins with an image cut after half of its pixels and probes `Stat_ImageOpen` while it is open (the malformed streams of `tools/isp_tbgen.py`); the mutant of a port tied to 0 is killed (section 4). No change of the RTL |
| An audit of the configuration checks of every module found `EccPipeline_g` and `Resource_g` without a check of the module: `EccPipeline_g` 2 stopped the elaboration inside the delay of Open Logic with a range error that does not name the generic, an unknown `Resource_g` only at an assertion of Open Logic of severity error, which not every tool stops at (WIN-CF-01); and the check of WIN-CF-05 compared `Resource_g` with "BRAM" with regard to case, while Open Logic takes "bram" as block RAM | The module checks both generics with severity failure and gives the delays the values in range, so that the elaboration reaches the checks; WIN-CF-05 compares without case. Negatives `win_ecc_2`, `win_resource` and `win_bram_narrow_case` (TC-WIN-08). The bench is unchanged |
| The output dimensions came from a formula of the module, and in the border mode valid an `ImageWidth_g` below `WinX_g` gave 0 for a positive constant: the elaboration stopped with a range error before the check that names the generic | The dimensions come from `ispWinOut` of `isp_pkg` (one definition with the integrator) and are at least 1, so that the check names the generic (negative `win_width_below_valid`, TC-WIN-08). The test files are unchanged |
| The plan expected the mutant that takes the column of pixel (0, 0) from the registered row selection to fail TC-WIN-02 and 05 (an image cut inside a line). An image cut by the input is completed by the frame sync (E1) and a reset loads the selection of line 0, so the registered selection is that of line 0 at every pixel (0, 0): the mutant survived the mutation run | Plan section 6: the mutant is equivalent at the ports; the restart of the row selection by pixel (0, 0) acts only after an upset of the register and is verified by review (TC-WIN-07, WIN-FT-03), as before |
