# isp_chain: Verification Report

## 1. Test results

Run on 2026-11-20 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM (commit 4f1e13b), Open Logic 4.8.0-ft.2:
`python run.py -p 2 "*isp_chain_tb*"`, 21 of 21 tests passed, 0 skipped; `python lint/synth_check.py` passed
(TC-CHN-08). The full regression of the suite with the chain test is in section 1.1. QuestaSim runs with the release
regression (with and without code coverage).

| Test | Chains | Passed |
| --- | --- | --- |
| `test_static` (TC-CHN-01) | `typical`, `reordered`, `small` | 3 |
| `test_input_stream` (TC-CHN-02) | `typical`, `reordered`, `small` | 3 |
| `test_registers` (TC-CHN-03) | `typical`, `small` | 2 |
| `test_ecc` (TC-CHN-04) | `typical`, `small` | 2 |
| `test_reset` (TC-CHN-05) | `typical`, `reordered`, `small` | 3 |
| `test_rate` (TC-CHN-06) | `typical`, `reordered` | 2 |
| `test_fifo` (TC-CHN-07) | `typical` | 1 |
| Negative tests (section 3.3 of the plan) | `typical`: `neg_seam_dimension`, `neg_seam_beat`, `neg_pulse_count`, `neg_fifo_depth`, `neg_fifo_drain` | 5 |
| TC-CHN-08 (`lint/synth_check.py`) | `chain_typical`, `chain_reordered` synthesise as one netlist each without latches | 2 |

### 1.1 Regression of the suite

`python run.py -p 4` on the chain test without the boundary tests of the FIFO (section 7) and the register log of
`test_registers`: 621 of 621 tests passed, 0 skipped; `python lint/synth_check.py` passed. The chain test replaced the
contract checker of the shared sink by the entity `tb/isp_tb_monitor.vhd`, so every module bench ran through it.

## 2. Summary

Every output beat of every test equals the composition of the reference models of the modules, with and without gaps
of the source and stalls of the sink; the contract monitor on every connection and the contract checker of the sink
found the input contract of every module and the output contract of the chain in every test, and the pulse counts of
every module (`Err_Framing`, `Err_Config`, `Stat_EccSec`, `Stat_EccDed`, `Stat_Unreplaced` and the scrubber outputs)
equal the model, also the modules that report nothing.

- Chains: `typical` (40 x 20 pixels of 12 bits through six modules to 16 x 8 pixels of 12 bits, 16-bit pixels behind
  the filter and 18-bit pixels behind the binning), `small` (5 x 3 pixels of 1 bit to one pixel of 1 bit, the low
  bounds of the generics: W = 2 x `MaxGap_g` + 1, a window of the image size, a bin of the image size, one multiplier
  stage, shift registers without the ECC pipeline) and `reordered` (a binning with a virtual column in front of a
  5 x 5 mirror filter on block RAM, then the crop and the point operation). Every generic behind the first module comes
  from the module before through `isp_pkg` (CHN-FN-04).
- The input stream: the malformed streams of `tools/isp_tbgen.py` reach the first module only: it reports them as its
  model, every other module reports 0 and receives complete images (CHN-FN-03).
- Registers: the identification and the static registers of every module through the decoder; run-time sets of both
  `isp_point`, of `isp_filter2d` and the position of `isp_crop` written with `CTRL.HOLD` 1, read back, and released at
  input pixel (0, 10) of an image: that image keeps the old sets, the next one takes the new sets in every module. A
  release of the two `isp_point` alone at input pixel (37, 2) gives that image the old set in the first and the new
  one in the second, as the model predicts. In `small` (no window for back-to-back images) the source pauses after
  an image, the release is set 84 cycles after its start (S_last + 1 = 82 derived), its writes end at 108, and the
  next image follows them. The times of the register script in `typical`, logged by the bench:

  | Release (`typical`) | Set after the image start | Done after the image start | Window of section 5.4 |
  | --- | --- | --- | --- |
  | Four writes at input pixel (0, 10) | 420 cycles | 444 cycles | 229 < t < 852 |
  | Two writes at input pixel (37, 2) | 123 cycles | 135 cycles | after S_first = 14, before s_last of the lower latencies 221 |

- ECC: in `typical` the defect map reports 9 single and 10 double errors, `isp_filter2d` 2 and 2, `isp_bin` 1 and 1;
  in `small` 11 and 12, 2 and 2, 2 and 2. Every double error changes the chain output (the model shows it before the
  run; in `small` the image of the injection is drawn until the 1-bit output shows it). The scrubber, on for several
  passes without images, reports the single error of the map once and the double error in the last word once per
  pass. The four channels of the `olo_ft_ecc_monitor` count the pulses of the modules.
- Resets: the common reset idle, held inside an image and running while the chain makes its last output line, then
  complete images through the chain; the reset of `isp_crop` alone after a whole line (E2 in `isp_crop`, E1 in the
  module behind it) and inside a line (E2 in `isp_crop`, E3 and E2 behind it, the next image lost behind `isp_crop`),
  in all three chains.
- Timing (images back to back, no gaps and no stalls), every value equal to the design value of section 5 of the plan:

  | Chain | Hold cycles per line interval | Lines 0 and 1 | Image intervals | Latency of every output pixel |
  | --- | --- | --- | --- | --- |
  | `typical` | 2 | 2 (the wait for word 0 of the defect map) | 840, 840, 840 | 52 (design 52 to 61) |
  | `reordered` | 1 | 0 in the first image, 37 in every further one | 407, 444, 444 | 29 (design 29 to 35) |

  Every output pixel leaves at the lower bound of the latency: no module holds a beat that completes an output pixel
  in these streams; the upper bound covers a pixel that a frame sync takes while its module holds the input.
- FIFO in front of `typical` (a source of one pixel per cycle within a line, line blanking 1, image blanking 22): at
  the depth of the rule, 25 entries, the FIFO never holds the source, its largest `In_Level` is 24 as derived, and
  every image finds it empty. One entry less holds the source for 4 cycles; one cycle of image blanking less leaves
  one pixel of the image before in the FIFO at every further image. Both are detected (`neg_fifo_depth`,
  `neg_fifo_drain`).

## 3. Chains and generics

The chain test has no generics of its own; the generic ranges of the modules are verified by their benches. The
chains use the modules in these configurations, beside those of the module benches:

| Module | `typical` | `small` | `reordered` |
| --- | --- | --- | --- |
| `isp_replace` | 40 x 20, 12 bits, G 2, scrubber free running | 5 x 3, 1 bit, G 2 | - |
| `isp_point` | 12 -> 12 bits and 18 -> 12 bits, run time | 1 -> 1 bit and 10 -> 1 bit, run time, one stage | 16 -> 12 bits, constant |
| `isp_crop` | 32 x 16 at (4, 2), run time | 3 x 3 at (1, 0), run time | 12 x 8 at (3, 2), constant |
| `isp_filter2d` | 3 x 3 replicate, 16-bit run-time coefficients, 16-bit output | 3 x 3 replicate on 3 x 3 pixels, 2-bit run-time coefficients, full precision, shift registers, pipeline 0 | 5 x 5 mirror on 13-bit pixels, block RAM, constant coefficients, 16-bit output |
| `isp_bin` | 2 x 2 valid on 16-bit pixels | 3 x 3 valid on 6-bit pixels, shift registers, pipeline 0 | 2 x 1 zero, W odd |

## 4. Negative tests

The chain has no RTL of its own; the mutations of the modules are run by their benches. Each check of the chain bench
is shown to fire by a negative test that expects the exact number of errors its provocation causes:

| Negative | Provocation | Errors expected and reported |
| --- | --- | --- |
| `neg_seam_dimension` | The contract monitor behind `isp_crop` one pixel short | 64: two per line, 16 lines in each of two images |
| `neg_seam_beat` | Beat 341 behind `isp_crop` with bit 11 inverted (chosen by the model) | 4: the output beats that differ |
| `neg_pulse_count` | The expected `Err_Framing` count of `isp_replace` one too high | 1 |
| `neg_fifo_depth` | The FIFO one entry short of the rule | 1: the held source |
| `neg_fifo_drain` | The image blanking one cycle short of the rule | 1: the images that find a pixel of the image before |

## 5. Synthesis and timing

TC-CHN-08: `lint/isp_chain_synth.vhd` synthesises the chains `typical` and `reordered` with GHDL as one netlist each,
without latches (CHN-CF-01); the generics of every module behind the first come from `isp_pkg`. The timing of the
modules is in their verification reports; the chain adds no logic between them.

## 6. Requirement coverage

| Requirement | Test cases | Status |
| --- | --- | --- |
| CHN-FN-01 | TC-CHN-01, 04 | Passed |
| CHN-FN-02 | TC-CHN-01, 02, 05 | Passed |
| CHN-FN-03 | TC-CHN-02, 05 | Passed |
| CHN-FN-04 | TC-CHN-01, 08 | Passed |
| CHN-IF-01 | TC-CHN-03 | Passed |
| CHN-IF-02 | TC-CHN-04 | Passed |
| CHN-PF-01 | TC-CHN-06 | Passed |
| CHN-PF-02 | TC-CHN-07 | Passed |
| CHN-CF-01 | TC-CHN-08 | Passed |

## 7. Findings

| Finding | Correction |
| --- | --- |
| The plan derived the reset of `isp_crop` alone with one E1 in the module behind it. With the source paused inside the region, `isp_crop` has delivered part of a line: its output packet is cut, the next beat is no first beat of a packet and so no image start, and the module behind continues the packet with the next image (E3, then E2 for the rest), which is lost behind `isp_crop`. A reset transmitter cannot close its packet | CHN-FN-02 holds for a reset between two packets, CHN-FN-03 states the case of a reset inside a packet; the plan (5.5) tests both cases; the user guide (section 7) resets a module alone only between two packets of its output |
| The plan placed the virtual columns of a line in the interval of that line. The frame sync of a module takes three pixels after the last pixel of a line before its input holds, so they come in the interval of the next line: in `reordered` the first image after an idle chain has no hold between lines 0 and 1, and its first interval is 407 cycles, not 408 | Plan 5.1 and the user guide (section 2.4) state where the holds come; the bench checks the first image separately |
| The plan took the exact wait of `isp_bin` for the filter behind the binning in `reordered` from the plan of `isp_bin`, which derives it for W a multiple of `BinX_g`. With W = 33 the virtual column completes the last bin of a line one cycle after the last pixel, and the filter starts its virtual pixels one cycle later: the wait is 36 cycles, not 35, the interval 444, not 443 | Plan 5.1 with the term e = (`BinX_g` - W mod `BinX_g`) mod `BinX_g`; the plan of `isp_bin` states the general form. The timing derivations of `isp_bin` for W not a multiple of `BinX_g` are measured by its own bench in a follow-up (rate configurations of `isp_bin`) |
| The plan derived the largest `In_Level` of the FIFO as 21. Two facts were missing: `olo_base_fifo_sync` shows a write at its output one cycle after it registered it, so a pixel is read two edges after its write and `In_Level` is 3 in a continuous flow; and every image in `test_fifo` follows an idle input, so `isp_replace` waits for word 0 of the defect map in line 0. The bench measured 24; a trace of the level per line (5 in line 0, one more in every further line) matched the corrected derivation | Plan 5.3: the largest `In_Level` 3 + max over the lines of D_(y-1) + r_y = 24, the depth rule of the user guide (section 5, step 3) `Depth_g` >= max of D_(y-1) + r_y, plus 4, and the image blanking F >= D_(H-2) + r_(H-1) + 1, both tested at their boundary (`test_fifo`, `neg_fifo_depth`, `neg_fifo_drain`) |
| The first check of the drained FIFO read `In_Level` at the first pixel of an image and reported pixels of the image before at F = 23. `In_Level` shows a read one cycle late: a pixel read in the cycle before still counts. A measurement artefact of the check, not a property of the design | The check counts the writes of the source and the reads of the FIFO (a read in the cycle of the write counts): the FIFO is empty at every image start from F = 22 on, measured at F = 22 and F = 21 |
| The plan placed the mixed release at input pixel (37, 2) 121 cycles after the image start; the virtual columns of line 1 hold the input at the start of line 2, so it is 123 cycles; the plan counted six writes for the release, which has four | Plan 5.4 corrected; the bench logs the times of the register script (section 2) |
| The synthesis wrapper of the chain was the first instance of `isp_point` that left `MaxShift_g` at its default: the entity default was 82, which the range check of the module rejects for every input below 64 bits with an 18-bit gain, while the specification gives `InBits_g` + `GainBits_g` | Corrected in `isp_point` (its verification report, section 7); the chain sets `MaxShift_g` to the value of the specification |
