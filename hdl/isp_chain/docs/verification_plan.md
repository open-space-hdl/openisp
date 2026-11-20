# isp_chain: Verification Plan

## 1. Overview

The chain test verifies the requirements of the [specification](specification.md): the chains of section 1.1 of the
specification, connected as the user guide describes, against the composition of the reference models of their
modules. It is the phase G of the suite (architecture, section 9) and closes ISP-STR-06.

The testbench `isp_chain_tb` instantiates the modules of a chain and uses the shared
[testbench components](../../../docs/testbench.md):

- the source at the input of the chain and the sink with the contract checker at its output;
- a contract monitor on every connection between two modules: the checks of the contract checker of the sink
  (sequence flags in order, one packet per line, constant flags within a packet, the dimensions of the next module),
  observing only;
- the AXI4-Lite BFM of UVVM with an address decoder in the bench: address bits 15 to 12 select the module (0
  `isp_replace`, 1 the first `isp_point`, 2 `isp_crop`, 3 `isp_filter2d`, 4 the second `isp_point`; in `reordered`
  its `isp_point` is slot 1, and `isp_bin` has no slave), bits 11 to 0 go to its slave; the register script addresses
  the modules with these addresses and can run while the source goes on (section 5.4);
- one injection script per ECC port (the defect map of `isp_replace`, the line buffers of `isp_filter2d` and of
  `isp_bin`) and a module reset script (the reset of one module at a marker of the stimulus);
- the pulse counters of the status outputs of every module, an `olo_ft_ecc_monitor` (Open Logic 4.8.0-ft.2) with one
  channel per ECC source behind the chain (user guide, section 5, step 4), and an `olo_ft_fifo_sync` in front of the
  chain for `test_fifo`.

The reference model `chain` of `tools/isp_model.py` composes the models of the modules: the output stream of each model
is the input stream of the next; register accesses, injections and resets go to the model of the module they address.
It uses the module models as they are; it adds no model of a module.

Simulators: GHDL (regression, CI) and QuestaSim (code coverage at the release); VUnit with UVVM, test end
`ispTestEnd`. Tests observe ports, the AXI4-Lite interface and the observing monitors on the connections only.

## 2. Configurations

| Configuration | Input | Modules and generics | Output |
| --- | --- | --- | --- |
| `typical` | 40 x 20, 12 bits | `isp_replace` G 2 (latency 1, pipeline 0, scrubber free running); `isp_point` 12 -> 12 bits, run time, 2 multiplier stages; `isp_crop` 32 x 16 at (4, 2), run time; `isp_filter2d` 3 x 3 MTF (sum 16), replicate, run-time coefficients of 16 bits, output 16 bits; `isp_bin` 2 x 2 valid; `isp_point` 18 -> 12 bits, run time, shift 6 | 16 x 8, 12 bits |
| `reordered` | 33 x 12, 12 bits | `isp_bin` 2 x 1 zero; `isp_filter2d` 5 x 5 MTF (sum 8), mirror, block RAM, constant coefficients, output 16 bits; `isp_crop` 12 x 8 at (3, 2); `isp_point` 16 -> 12 bits, shift 4 | 12 x 8, 12 bits |
| `small` | 5 x 3, 1 bit | `isp_replace` G 2 (W = 2 x G + 1); `isp_point` 1 -> 1 bit, run time, 1 multiplier stage; `isp_crop` 3 x 3 at (1, 0); `isp_filter2d` 3 x 3 replicate on a 3 x 3 image (the window; the output keeps 3 x 3), 2-bit run-time coefficients, full precision (6 bits), shift registers, pipeline 0; `isp_bin` 3 x 3 valid (one bin of the 3 x 3 image, 10 bits), shift registers, pipeline 0; `isp_point` 10 -> 1 bit, run time, shift 4 | 1 x 1, 1 bit |

Every generic of a module behind the first follows from the module before (CHN-FN-04) through functions of `isp_pkg`:
the output width of a kernel (`ispConvOutBits`, existing) and the output dimensions of a window filter and of a bin
(new functions of `isp_pkg`, section 7).

Gaps of the source and stalls of the sink: 20 % / 20 % in `test_static`, `test_input_stream` and `test_reset`; none in
`test_rate` and `test_fifo`.

## 3. Test cases

### 3.1 Checks in every test

| Check | Where | Requirements |
| --- | --- | --- |
| Every output beat of the chain equals the composed model | Sink | CHN-FN-01 |
| The output contract of the chain and the input contract of every module (dimensions of the next module) | Sink, monitors on the connections | CHN-FN-02 |
| The numbers of the status pulses of every module (`Err_Framing`, `Err_Config`, `Stat_EccSec`, `Stat_EccDed`, `Stat_Unreplaced`, the scrubber pulses) equal the composed model, also the modules that must report 0 | Testbench | CHN-FN-03, CHN-IF-02 |
| Control and status outputs free of metavalues after the first reset | Testbench | CHN-FN-02 |

### 3.2 Test list

| Test | Chains | Description | Requirements |
| --- | --- | --- | --- |
| `test_static` (TC-CHN-01) | all | Images with random pixels over the full range and with a random defect map, in every division into packets, back to back and with pauses; an image of the largest pixels (the saturation of the filter and of the second `isp_point`) | CHN-FN-01, CHN-FN-02, CHN-FN-04 |
| `test_input_stream` (TC-CHN-02) | all | The malformed streams of `tools/isp_tbgen.py` (with the probe of an open image) at the input: the first module reports `Err_Framing` as its model, every other module 0 and receives complete images | CHN-FN-02, CHN-FN-03 |
| `test_registers` (TC-CHN-03) | `typical`, `small` | Without gaps and stalls, so that the times of section 5.4 hold. The ID register of every module read through the decoder; run-time sets of every module written with `CTRL.HOLD` 1 and read back; the procedure of section 5.4 releases them at the time it derives from the image start at the chain input, so that one image takes the new set in every module; a release of the two `isp_point` alone in the middle of the interval from s_first(k) to s_last(k) gives image k the old set in the first `isp_point` and the new one in the second (the mixed image the model predicts). In `small` the window of section 5.4 does not exist for back-to-back images: the release comes in a pause between two images | CHN-IF-01 |
| `test_ecc` (TC-CHN-04) | `typical`, `small` | Single and double errors injected into the defect map of `isp_replace` and the line buffers of `isp_filter2d` and `isp_bin`: each module reports its pulses as its model; a double error changes the data that flows through every module behind it (the model shows the change at the chain output for every double error; with the 1-bit output of `small` the image of the injection is drawn until it does); the scrubber of `isp_replace`, on for several passes without images, corrects the single error of the map and reports the double error in its last word once per pass; the counters of the `olo_ft_ecc_monitor` (one channel per source) equal the pulses of the modules | CHN-IF-02, CHN-FN-01 |
| `test_reset` (TC-CHN-05) | all | The common reset idle, during an image and during the virtual lines of the filters; the reset of `isp_crop` alone in both cases of section 5.5; the next images correct through the whole chain | CHN-FN-02, CHN-FN-03 |
| `test_rate` (TC-CHN-06) | `typical`, `reordered` | Images back to back without gaps and stalls: the hold cycles of the chain input per line, the wait at the image start, the image period and the latency of every output pixel against the design values of section 5 | CHN-PF-01 |
| `test_fifo` (TC-CHN-07) | `typical` | A source that cannot wait (one pixel per cycle within a line, a line blanking L and an image blanking F) in front of an `olo_ft_fifo_sync` whose depth and image blanking are the rule of section 5.3: the FIFO never holds the source (its `In_Ready` stays high while the source sends), every image finds it empty, and its largest `In_Level` equals the design value | CHN-PF-02 |
| TC-CHN-08 (`lint/synth_check.py`) | `typical`, `reordered` | The synthesis wrapper `lint/isp_chain_synth.vhd` synthesises each chain as one netlist without latches | CHN-CF-01 |

### 3.3 Negative tests

Each of these is a test of the bench that must fail; it runs as an expected failure (UVVM expected alerts, the exact
number of errors that the provocation causes), so that it fails the regression if the check stops firing or fires
for another reason.

| Negative | Provocation in the harness | Check that must fire |
| --- | --- | --- |
| `neg_seam_dimension` | The monitor of the connection behind `isp_crop` one pixel short | Contract monitor of that connection: two errors per line (no `Last` on the pixel the monitor expects it, a line one pixel long) |
| `neg_seam_beat` | One beat between `isp_crop` and `isp_filter2d` with a data bit inverted (bench generics); the model chooses the beat and the bit (0 or the highest) whose inversion changes the chain output | Sink: one error per output beat that differs, the number from the model |
| `neg_pulse_count` | The expected `Err_Framing` count of the first module one more than the model | Pulse counter check of the test end: one error |
| `neg_fifo_depth` | The FIFO of `test_fifo` one entry short of the rule of section 5.3 | The check of the held source in `test_fifo`: one error |
| `neg_fifo_drain` | The image blanking of `test_fifo` one cycle short of the rule of section 5.3 | The check of the empty FIFO at every image start in `test_fifo`: one error |

## 4. Requirement coverage

| Requirement | Test cases | Method |
| --- | --- | --- |
| CHN-FN-01 | TC-CHN-01, 04 | Test |
| CHN-FN-02 | TC-CHN-01, 02, 05 | Test |
| CHN-FN-03 | TC-CHN-02, 05 | Test |
| CHN-FN-04 | TC-CHN-01, 08 | Test and synthesis |
| CHN-IF-01 | TC-CHN-03 | Test |
| CHN-IF-02 | TC-CHN-04 | Test |
| CHN-PF-01 | TC-CHN-06 | Test |
| CHN-PF-02 | TC-CHN-07 | Test |
| CHN-CF-01 | TC-CHN-08 | Synthesis |

The chain test verifies these claims of the user guide: section 2.4 (the waiting times of the modules, their
combination at the input of a chain), 4.2 (run-time parameters, for several modules: section 5.4 of this plan), 4.4
(the defect map across images) and the steps of section 5: 1 (the generics of the next module), 2 (the scaling behind
filters and binning), 3 (the FIFO in front of the chain) and 4 (the ECC monitor).

## 5. Derivations

The bench checks the design values below. A measured value outside the derivation is a finding: the cause is found
(the RTL or the derivation), recorded in the findings of the verification report, and the wrong one is corrected. A
derivation is never adjusted to fit a measurement.

### 5.1 Image period and waits at the chain input (`test_rate`)

The modules run concurrently; the chain takes one image per period of its slowest part. A module holds its input
only for its own events without an input pixel (virtual columns and lines) and when its output is held. A wait of a
module reaches the module before it only when the buffers between them are full, and it reaches the chain input only
when no module before it has a slack that takes it (for example the pixels outside the region of `isp_crop`, which it
discards at one per cycle also with its output held, CRP-PF-03).

The virtual columns of a line hold the input in the interval of the next line: after the last pixel of a line the
frame sync of the module takes three more pixels (its output register and the two entries of its input stage, an
`olo_base_pl_stage` with a registered ready) before its input holds (plan of `isp_replace`, section 5). The bench
counts the hold cycles between the first pixels of two lines, so the interval of line y holds the virtual columns of
line y - 1, and those of the last line fall into the next image.

`typical`:

| Seam | Wait of the module behind | Absorbed by | At the chain input |
| --- | --- | --- | --- |
| Input -> `isp_replace` | G = 2 cycles per line; max(G, `RamRdLatency_g` + `EccPipeline_g` + 1) = 2 between lines 0 and 1 (RPL-PF-01) | - | 2 per line |
| `isp_crop` -> `isp_filter2d` | Rr = 1 per line of the region; Rr + Rb x (32 + Rr) = 34 events after its last pixel | The 8 pixels outside the region in every input line; the 4 pixels after the region in row 17, the rows 18 and 19 below the region and 0 and 1 of the next image (more than 160 cycles) | 0 |
| `isp_filter2d` -> `isp_bin` | None in the mode valid | - | 0 |
| Other seams | None (`isp_point` and `isp_crop` take one pixel per cycle) | - | 0 |

The period is the period of `isp_replace`: H x (W + G) + max(0, `RamRdLatency_g` + `EccPipeline_g` + 1 - G) = 20 x 42
= 840 cycles; the first interval after an idle chain H x W + (H - 1) x G + `RamRdLatency_g` + `EccPipeline_g` + 1 =
840 as well. Holds per line interval: 2, between lines 0 and 1 the wait for word 0 of the defect map
(`RamRdLatency_g` + `EccPipeline_g` + 1 = 2 after an idle chain, max(G, 2) = 2 after an image).

`reordered`: the filter behind the binning makes N = Rr + Rb x (W + Rr) = 2 + 2 x (17 + 2) = 40 events without an
input pixel after its last pixel, while the horizontal filter of `isp_bin` sends it the first bins of the next image.
This is the case of `rate_tall` of `isp_bin` (plan of `isp_bin`, section 5) with `isp_filter2d` in the place of the
vertical filter. The buffers fill within line 0 (p = `BinX_g` x (4 + c) + 3 = 15 < 33, c = ceil(4 / 2) = 2), so the
wait is exactly N + 8 + lx + e - `BinX_g` x (5 + c), e = (`BinX_g` - W mod `BinX_g`) mod `BinX_g`: with W = 33 the
virtual column completes the last bin of a line, e = 1 cycle after the last pixel, and the filter starts its virtual
pixels e cycles later. The wait is 40 + 8 + 1 + 1 - 14 = 36 cycles. Holds per line interval: 1 (the virtual column of
the line before); between lines 0 and 1 of the first image after an idle chain 0, of every further image 1 + 36 = 37.
The first interval between two image starts is H x W + (H - 1) = 407 cycles, every further one
H x (W + `BinX_g` - 1) + 36 = 12 x 34 + 36 = 444 cycles.

### 5.2 Latency (`test_rate`)

The latency of an output pixel is counted from the acceptance of the input beat that completes it (the composition of
the timing of the module models) to its output. It is the sum of the latencies of the modules, each from the beat
that completes its own output; a wait of a module behind adds to the latency of the module before it for the beats it
holds.

| Module | Latency (its plan) | `typical` | `reordered` |
| --- | --- | --- | --- |
| `isp_replace` | 10, up to 12 after a hold or for the first pixels of an image | 10 to 12 | - |
| `isp_point` | `MultStages_g` + 5 | 7, 7 | 7 |
| `isp_crop` | 4 | 4 | 4 |
| `isp_filter2d` | 6 + log2ceil(T) to 8 + log2ceil(T) | 10 to 12 | 11 to 13 |
| `isp_bin` | 12 + lx + ly to 16 + lx + ly (both filters); 6 + lx to 8 + lx (one) | 14 to 18 | 7 to 9 |
| Waits at seams that can hold a completing beat | `isp_filter2d` holds `isp_crop` for Rr cycles per line; in `reordered` it holds `isp_bin` for Rr per line | up to 1 | up to 2 |
| Chain | | 52 to 61 | 29 to 35 |

The module plans give their latencies as ranges (a pixel that a frame sync took while its module held the input
waits up to two cycles more), and the composed model gives the beat that completes an output pixel, not the
latency of every pixel, so the bench checks the range above for every output pixel; the report gives the measured
minimum and maximum of every chain and explains them from the design.

### 5.3 The FIFO in front of a chain (`test_fifo`, user guide section 5, step 3)

The source delivers the W pixels of a line in W cycles, then pauses for the line blanking L; after the last line of an
image it pauses for the image blanking F. Let r_y be the hold cycles of the chain input between the first pixels of
lines y and y + 1 (section 5.1: the waits of the first module and the waits of the modules behind it that reach the
input). The FIFO gains r_y - L pixels in the interval of line y when that is positive and loses up to L otherwise; with
D_-1 = 0 and D_y = max(0, D_(y-1) + r_y - L) it holds up to D_(y-1) + r_y pixels more than in a continuous flow.

- The holds of `isp_replace` come at the start of a line interval: the wait for word 0 of the defect map in line 0
  (`RamRdLatency_g` + `EccPipeline_g` + 1 cycles after an idle input), the G virtual columns of the line before in
  every further line (the input stage of its frame sync takes three pixels first, section 5.1). The FIFO delays every
  pixel, so the line blanking at the source does not come before these holds; each line gains r_y and then drains L.
- In `test_fifo` every image follows an idle input (the image blanking drains the FIFO, below): r_0 = 2, r_y = G = 2
  for y >= 1, and the virtual columns of the last line fall into the image blanking. With L = 1, D_y = y + 1 and the
  largest D_(y-1) + r_y = D_18 + r_19 = 21.
- The image blanking drains the FIFO: when the first pixel of the next image is written, every pixel of the image
  before has been read (a read in the same cycle counts). After the last write the FIFO holds D_(H-2) + r_(H-1)
  pixels more than in a continuous flow and the pixel written the cycle before (a pixel is read two edges after its
  write, below); it reads one per cycle, and the virtual columns of the last line hold the input of `isp_replace`
  only after its last pixel. The first pixel of the next image is written F + 1 cycles after the last one, so the
  condition is F >= D_(H-2) + r_(H-1) + 1 = 22 <= 30. Otherwise part of an image remains in the FIFO at the next one;
  when the source is faster than the chain over an image, no depth suffices.
- `In_Level` of the `olo_ft_fifo_sync` (the `olo_base_fifo_sync` inside) is 3 in a continuous flow: the FIFO shows a
  write at its output one cycle after it registered it, so a pixel is read two edges after its write, and `In_Level`
  counts a read one cycle late. Its largest value is 3 + 21 = 24, checked exactly. A cycle-level evaluation of these
  facts (the FIFO, the input stage and the output register of the frame sync, the wait for word 0, G HCOL events per
  line) gives 24 as well, and an empty FIFO at the first pixel of every image for F of at least 22.
- The FIFO holds the source when `In_Level` equals `Depth_g` before a write. `test_fifo` uses the depth and the
  image blanking of the rule below, 25 entries and F = 22: `In_Ready` stays high and every image finds the FIFO
  empty. `neg_fifo_depth` uses 24 entries (F = 30): the FIFO holds the source. `neg_fifo_drain` uses F = 21: every
  further image finds a pixel of the image before in the FIFO. The bench reports both.

The rule goes to the user guide (section 5, step 3) with what an integrator needs without the bench:

- r_y from the table of section 2.4: the holds of the first module between the first pixels of two lines (for
  `isp_replace` the line 0 value after an idle input), plus the waits of a module behind it that the modules between
  do not absorb. A module absorbs a wait of the module behind it when it has idle output cycles in the same time:
  `isp_crop` discards the pixels outside its region at one per cycle also with its output held, a binning outputs one
  pixel per `BinX_g` input cycles; the conditions of section 5.1.
- `Depth_g` >= max over the lines of D_(y-1) + r_y, plus 4, and the image blanking F >= D_(H-2) + r_(H-1) + 1.
- The worked example of `typical`: r_y = 2 (the wait for word 0 in line 0, the virtual columns of `isp_replace` in
  every further line; the waits of `isp_filter2d` absorbed by `isp_crop`), with L = 1: the depth 25 and F >= 22.
- The warning that the plain sum of the waits of all modules overestimates: in `typical` it would add the virtual
  column and the 34 events of the lower border of `isp_filter2d` and give D_19 = 40 > F, "no depth suffices", although
  25 entries suffice.

### 5.4 One parameter set for one image in several modules (`test_registers`, user guide 4.2 and 5)

Every module with run-time parameters takes its set at its own image start, when pixel (0, 0) of the image reaches it
(PNT-FN-04, CNV-FN-04, CRP-FN-06). Along a chain these starts come later from module to module: the start of image k
reaches module j at s_j(k), with s_j(k) increasing with j. To give image k + 1 the new set in every module:

1. write 1 to `CTRL.HOLD` of every module with `CTRL.HOLD` that changes, and write the new sets;
2. at a time t with s_last(k) < t < s_first(k + 1), where first and last are the first and the last module of the
   chain with run-time parameters that change, write 0 to every `CTRL.HOLD` and write `ROI_POS` of `isp_crop` (which
   takes its position at every image start and has no `CTRL.HOLD`); every write is finished before s_first(k + 1).

Every module then has image k open at t and takes the new set at its start of image k + 1.

The software cannot see these starts at the modules: with back-to-back images `STATUS.IMAGE_OPEN` of a module may show
no edge between two images (one image closes and the next opens in the same step), and no module counts images. It
times the release from the image start at the chain input instead (the frame start of the source, an event of the
system). The image start reaches module j S_j cycles after it, the sum of the delays of the modules before j:

| Module | Delay of the image start |
| --- | --- |
| `isp_point` | its latency, `MultStages_g` + 5 |
| `isp_replace` | G pixels (the interpolation waits for the place G to the right) and its latency |
| `isp_crop` | `RoiY_g` lines and `RoiX_g` pixels and its latency, 4 |
| `isp_window`, `isp_filter2d` | Rb lines and Rr pixels (`WinY_g` - 1 lines and `WinX_g` - 1 pixels in the border mode valid) and its latency |
| `isp_bin` | `BinY_g` - 1 lines and `BinX_g` - 1 pixels and its latency |

A line is the line period at the chain input (W plus the waits per line at the input, section 5.1), a pixel one
cycle. The window for the release is S_last < t < S_first + P after the image start at the input, P the image period,
and every write has to be finished before its end. A window that holds in every case is narrower than the true one at
both ends: its start takes S_last with the upper latencies of the module plans, its end S_first with the lower ones.
It exists when Delta = S_last - S_first is shorter than P. When it is not (a region near the lower edge of the image,
large windows), back-to-back images leave no window: the source pauses after an image, the release comes S_last after
its start, and the next image starts after the writes.

`typical` (first: the first `isp_point`, last: the second; line period 42, P = 840):

- S_first = 2 + 10 = 12 (`isp_replace`) with its lower latency for the end of the window, 2 + 12 = 14 with the upper
  one for the mixed release below;
- S_last = 14 + 7 (`isp_point`) + 2 x 42 + 4 + 4 (`isp_crop`) + 42 + 1 + 12 (`isp_filter2d`) + 42 + 1 + 18
  (`isp_bin`) = 229, with the lower values of the latencies 221;
- the window is 229 < t < 852. `test_registers` starts the writes of the procedure with input pixel (0, 10), 420 cycles
  after the image start (ten line intervals of 42 cycles): 191 cycles after S_last. The four single writes (`CTRL.HOLD`
  0 of both `isp_point` and of `isp_filter2d`, `ROI_POS` of `isp_crop`) end long before the end of the window; the
  bench logs their times. The source waits for them before the next image, so the end of the window holds in any
  case.

`small` (line period 7, P = 21): S_last = 14 + 6 (`isp_point`) + 1 + 4 (`isp_crop`) + 7 + 1 + 12 (`isp_filter2d`) +
2 x 7 + 2 + 20 (`isp_bin`) = 81 with the upper latencies, S_first = 12 with the lower: Delta = 69 > P, so
back-to-back images leave no window.
`test_registers` runs the variant with a pause: the source stops after the last pixel of image k (18 cycles after
its start), sets the release S_last + 1 = 82 cycles after the image start, and starts image k + 1 only after the
writes (it waits for them). The pause between the two images is therefore at least Delta - P plus the time of the
writes, and the window becomes S_last < t < S_first + P + the pause.

The procedure as the user guide states it today (4.2) concerns one module. Applied to several modules at an arbitrary
time, it can give one image different sets: a release between s_first(k) and s_last(k) gives image k the old set in the
first modules (they took their set of image k before the release) and the new one in the last (they take it at their
start of image k, after the release). `test_registers` releases the two `isp_point` alone in the middle of that
interval, at input pixel (37, 2) (123 cycles after the image start: two line intervals, the virtual columns of line 1 at
the start of line 2, section 5.1, and 37 pixels; 109 after S_first, 98 before the lower value of S_last); the model
gives image k the old set in the first `isp_point` and the new one in the second, and the chain output follows it. This
goes to the findings of the report, and the user guide (section 4.2 and 5) gets the procedure above with the table of
the delays.

The defect map of `isp_replace` is not a set taken at the image start (RPL-FN-04): words written during an image can
apply in that image. A new map for one whole image needs the input of `isp_replace` to have no image open while it is
written; with back-to-back images that is not possible, which the user guide states.

### 5.5 The reset of one module (`test_reset`)

The source pauses in image k inside the rows of the region of `isp_crop` (input rows 2 to 17 in `typical`, so that
`isp_filter2d` has image k open); after the drain time of the chain no beat moves. The bench holds the reset of
`isp_crop` for two cycles, then the source continues image k where it paused, so that the input stream stays legal
and only the reset acts; image k + 1 follows. The model resets the model of that module at the same place of the
stream. Two pauses:

- after the region within the line (the output of `isp_crop` ends with a whole line);
- inside the region (the output of `isp_crop` ends inside a line: its packet is cut).

In both:

- `isp_replace` and the first `isp_point` see a legal stream and report nothing.
- `isp_crop` has lost its open image and receives the rest of image k without an image start: it discards it and
  reports `Err_Framing` once (E2).
- `isp_bin` and the second `isp_point` receive complete images and report nothing.

`isp_filter2d` holds the part of image k that `isp_crop` delivered before the reset:

- After a whole line it receives the image start of k + 1 while image k is open, completes image k with pixels of
  value 0 and reports `Err_Framing` once (E1); image k + 1 passes.
- After a cut line the next beat is not the first beat of a packet, so it is no image start (FSY-ER-01 to 04): the
  module continues the cut packet with the beats of image k + 1, ends image k at its pixel count (E3) and discards the
  rest of image k + 1 (E2). Image k + 1 is lost behind `isp_crop`; image k + 2 passes.

A reset transmitter cannot close its packet, so the stream behind a module reset inside a packet is not a legal input
(CHN-FN-02 holds for a reset between two packets); the module behind reports it as its frame sync specifies and
outputs complete images (CHN-FN-03). The contract monitor of a connection restarts with the reset of the module in
front of it: it checks the output of that module; the view of the module behind is in the pulse counts of the model.
The pulse counts of every module, the completed image k at the output and the images after it equal the model.

## 6. Mutations

The chain has no RTL of its own; the mutations of the modules are run by their benches. The checks of the chain bench
are shown to fire by the negative tests of section 3.3.

## 7. Additions to other parts

- `isp_pkg`: the functions for the output dimensions of a window filter and of a bin along one axis
  (`ispWinOut`, `ispBinOut`), with tests in `isp_pkg_tb`; the chain bench and the chain wrapper use them.
- User guide: section 2.4 (where the holds of the right border come, the line 0 wait of `isp_replace` after an idle
  input), section 4.2 (the procedure of section 5.4 with the table of the delays), section 4.4 (the defect map across
  images), section 5 step 3 (the FIFO rule of section 5.3) and section 7 (the reset of a module alone, section 5.5).
- The plan of `isp_bin`: the wait for W not a multiple of `BinX_g` (the term e of section 5.1).
- Architecture: the matrix entry of ISP-STR-06 and `docs/compliance.md` with the chain test cases.
- `pr_tests.txt`: the chain `small` (the low bounds); `typical` and `reordered` run in the full tier unless short.
