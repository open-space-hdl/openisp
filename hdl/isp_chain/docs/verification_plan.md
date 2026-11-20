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
  `isp_replace`, 1 the first `isp_point`, 2 `isp_crop`, 3 `isp_filter2d`, 4 the second `isp_point`), bits 11 to 0 go
  to its slave; the register script addresses the modules with these addresses;
- one injection script per ECC port (the defect map of `isp_replace`, the line buffers of `isp_filter2d` and of
  `isp_bin`);
- the pulse counters of the status outputs of every module, an `olo_ft_ecc_monitor` (Open Logic 4.8.0-ft.2) with one
  channel per ECC source behind the chain `typical` (user guide 5.4), and an `olo_ft_fifo_sync` in front of the chain
  for `test_fifo`.

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
| `small` | 5 x 3, 1 bit | `isp_replace` G 2 (W = 2 x G + 1); `isp_point` 1 -> 1 bit, run time, 1 multiplier stage; `isp_crop` 3 x 3 at (1, 0); `isp_filter2d` 3 x 3 on a 3 x 3 image (the window), 2-bit coefficients, full precision (6 bits), shift registers, pipeline 0; `isp_bin` 3 x 3 valid (one bin, 10 bits), shift registers, pipeline 0; `isp_point` 10 -> 1 bit | 1 x 1, 1 bit |

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
| `test_registers` (TC-CHN-03) | `typical`, `small` | The ID register of every module read through the decoder; run-time sets of every module written with `CTRL.HOLD` 1 and read back; the procedure of section 5.4 releases them so that one image takes the new set in every module; the same release at a time outside the window of the procedure gives one image with the new set in the first modules and the old one in the last (the mixed image the model predicts) | CHN-IF-01 |
| `test_ecc` (TC-CHN-04) | `typical`, `small` | Single and double errors injected into the defect map of `isp_replace` and the line buffers of `isp_filter2d` and `isp_bin`: each module reports its pulses as its model; a double error changes the data that flows through every module behind it; the counters of the `olo_ft_ecc_monitor` (one channel per source) equal the pulses of the modules | CHN-IF-02, CHN-FN-01 |
| `test_reset` (TC-CHN-05) | all | The common reset idle, during an image and during the virtual lines of the filters; the reset of one module alone (section 5.5); the next images correct through the whole chain | CHN-FN-02, CHN-FN-03 |
| `test_rate` (TC-CHN-06) | `typical`, `reordered` | Images back to back without gaps and stalls: the hold cycles of the chain input per line, the wait at the image start, the image period and the latency of every output pixel against the design values of section 5 | CHN-PF-01 |
| `test_fifo` (TC-CHN-07) | `typical` | A source that cannot wait (one pixel per cycle within a line, a line blanking L and an image blanking F) in front of an `olo_ft_fifo_sync` whose depth follows the rule of section 5.3: the FIFO never overflows (its `In_Ready` stays high), and its largest fill level equals the value that the rule gives | CHN-PF-02 |
| TC-CHN-08 (`lint/synth_check.py`) | `typical`, `reordered` | The synthesis wrapper `lint/isp_chain_synth.vhd` synthesises each chain as one netlist without latches | CHN-CF-01 |

### 3.3 Negative tests

Each of these is a test of the bench that must fail; it runs as an expected failure (UVVM expected alerts), so that
it fails the regression if the check stops firing.

| Negative | Provocation in the harness | Check that must fire |
| --- | --- | --- |
| `neg_seam_dimension` | The monitor of one connection configured with a width one pixel short | Contract monitor of that connection |
| `neg_seam_beat` | One beat between `isp_crop` and `isp_filter2d` inverted in bit 0 (a harness generic) | Sink (output beat against the model) |
| `neg_pulse_count` | The expected `Err_Framing` count of the first module one more than the model | Pulse counter check of the test end |

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

The chain test verifies these claims of the user guide: 2.4 (the waiting times of the modules, their combination at
the input of a chain), 4.2 (run-time parameters, for several modules: section 5.4), 5.1 (the generics of the next
module), 5.2 (the scaling behind filters and binning), 5.3 (the FIFO in front of the chain) and 5.4 (the ECC monitor).

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

`typical`:

| Seam | Wait of the module behind | Absorbed by | At the chain input |
| --- | --- | --- | --- |
| Input -> `isp_replace` | G = 2 cycles per line; max(G, `RamRdLatency_g` + `EccPipeline_g` + 1) = 2 between lines 0 and 1 (RPL-PF-01) | - | 2 per line |
| `isp_crop` -> `isp_filter2d` | Rr = 1 per line of the region; Rr + Rb x (32 + Rr) = 34 events after its last pixel | The 8 pixels outside the region in every input line; the 4 pixels after the region in row 17, the rows 18 and 19 below the region and 0 and 1 of the next image (more than 160 cycles) | 0 |
| `isp_filter2d` -> `isp_bin` | None in the mode valid | - | 0 |
| Other seams | None (`isp_point` and `isp_crop` take one pixel per cycle) | - | 0 |

The period is the period of `isp_replace`: H x (W + G) + max(0, `RamRdLatency_g` + `EccPipeline_g` + 1 - G) = 20 x 42
= 840 cycles, the same for every interval from the second on; holds per line: 2.

`reordered`: the filter behind the binning makes N = Rr + Rb x (W + Rr) = 2 + 2 x (17 + 2) = 40 events without an
input pixel after its last pixel, while the horizontal filter of `isp_bin` sends it the first bins of the next image.
This is the case of `rate_tall` of `isp_bin` (plan of `isp_bin`, section 5) with `isp_filter2d` in the place of the
vertical filter: d = N + 2 - 2 x `BinX_g` = 38; the buffers fill within line 0 (p = `BinX_g` x (4 + c) + 3 = 15 < 33,
c = ceil(4 / 2) = 2), so the wait is exactly N + 8 + lx - `BinX_g` x (5 + c) = 40 + 9 - 14 = 35 cycles. The period:
H x (W + `BinX_g` - 1) + 35 = 12 x 34 + 35 = 443 cycles; holds per line: 1, and once per image 1 + 35.

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

### 5.3 The FIFO in front of a chain (`test_fifo`, user guide 5.3)

The source delivers the W pixels of a line in W cycles, then pauses for the line blanking L; after the last line of an
image it pauses for the image blanking F. Let r_y be the hold cycles of the chain input during line y (section 5.1:
the waits of the first module and the waits of the modules behind it that reach the input). The FIFO gains r_y - L
pixels in line y when that is positive and loses up to L otherwise; with D_-1 = 0 and D_y = max(0, D_(y-1) + r_y - L),
the fill level reaches D_(y-1) + r_y within line y, and after the image it falls by F. The depth is

- max over the lines of D_(y-1) + r_y, when D_(H-1) <= F (the image blanking drains what the lines left);
- unbounded otherwise: the source is faster than the chain, and no depth suffices.

`typical` with L = 1 and F = 30: r_y = 2 for every line, so D grows by 1 per line to D_19 = 20, which F = 30 drains; the
depth is D_18 + r_19 = 21. The bench uses a FIFO of 32 entries, more than the depth, so that its largest fill level is
measured and not limited; the design value of that level is 21. The rule, with the waits of section 2.4 and the
combination of section 5.1, goes to the user guide (section 5, step 3).

### 5.4 One parameter set for one image in several modules (`test_registers`, user guide 4.2 and 5)

Every module with run-time parameters takes its set at its own image start, when pixel (0, 0) of the image reaches it
(PNT-FN-04, CNV-FN-04, CRP-FN-06). Along a chain these starts come later from module to module: the start of image k
reaches module j at s_j(k), with s_j(k) increasing with j. To give image k + 1 the new set in every module:

1. write 1 to `CTRL.HOLD` of every module with `CTRL.HOLD` that changes, and write the new sets;
2. at a time t with s_last(k) < t < s_first(k + 1), where first and last are the first and the last module of the
   chain with run-time parameters that change, write 0 to every `CTRL.HOLD` and write `ROI_POS` of `isp_crop` (which
   takes its position at every image start and has no `CTRL.HOLD`).

Every module then has image k open at t and takes the new set at its start of image k + 1. The window exists when the
delay Delta = s_last(k) - s_first(k) of the image start from the first to the last module is shorter than the image
period; then it lasts the period minus Delta. In `typical` (first: the first `isp_point`, last: the second), the image
start reaches the second `isp_point` with the first bin of the image: `isp_crop` starts the region at input line 2,
`isp_filter2d` outputs its line 0 after its input line 1, and `isp_bin` its first bin after the filter line 1, so the
image start reaches it with input pixel (6, 4) plus the latencies of the modules, about 230 cycles after the start at
the input. The first `isp_point` starts about 15 cycles after the input, so Delta is about 215 cycles against a period
of 840. When Delta reaches the period (a region near the lower edge of the image, large windows), back-to-back images
leave no window, and the source has to pause between two images for at least Delta minus the period plus the time the
software needs.

The procedure as the user guide states it today (4.2) concerns one module. Applied to several modules at an arbitrary
time, it can give one image the new set in the first modules and the old one in the last; `test_registers` shows such
an image against the model. This goes to the findings of the report, and section 4.2 or 5 of the user guide gets the
procedure above.

The defect map of `isp_replace` is not a set taken at the image start (RPL-FN-04): words written during an image can
apply in that image. A new map for one whole image needs the input of `isp_replace` to have no image open while it is
written; with back-to-back images that is not possible, which the user guide states.

### 5.5 The reset of one module (`test_reset`)

The source pauses in the middle of a line; after the drain time of the chain no beat moves. The bench holds the reset of
`isp_crop` (`typical`) for two cycles, then the source sends the start of the next image. The model resets the model of
that module at the same place of the stream. `isp_crop` loses its open image; the first module completes its open image
at the next image start of the input (E1), the modules between pass the padded pixels on, and `isp_crop` discards them
as pixels without an image start (E2); the module behind it receives the next image start while its image is open and
completes it (E1). The pulse counts of every module and the following images equal the model.

## 6. Mutations

The chain has no RTL of its own; the mutations of the modules are run by their benches. The checks of the chain bench
are shown to fire by the negative tests of section 3.3.

## 7. Additions to other parts

- `isp_pkg`: the user guide (5.1) and the roadmap name functions of `isp_pkg` for the output dimensions of the modules,
  which do not exist (only the output width of a kernel does). Two functions are added and specified there: the output
  size of a window filter along one axis (size, window, anchor, stride, border mode) and of a bin (size, factor,
  border mode), with tests in `isp_pkg_tb` and use in the chain wrapper.
- User guide: section 5 step 3 (the FIFO rule of 5.3), the procedure of 5.4 (section 4.2 or 5), and the defect map
  across images.
- Architecture: the matrix entry of ISP-STR-06 and `docs/compliance.md` with the chain test cases.
- `pr_tests.txt`: the chain `small` (the low bounds); `typical` and `reordered` run in the full tier unless short.
