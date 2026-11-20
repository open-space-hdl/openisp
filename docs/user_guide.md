# OpenISP User Guide

This guide is for the integrator of OpenISP modules: how to compile them, how the pixel stream between them works,
how to program their registers and what the system around them has to provide. The function of every module, its
generics, ports and register map are in its specification (`hdl/<module>/docs/specification.md`).

## 1. Sources

The modules are VHDL-2008. Compile Open Logic (submodule `open-logic`, the areas `base`, `axi` and `ft`) into the
library `olo` and the OpenISP sources into the library `openisp`, in the order of `compile_order.txt`. The modules
have no vendor-specific parts.

| Module | Top-level entity | Function |
| --- | --- | --- |
| `isp_frame_sync` | `isp_frame_sync` | Input side of every module; stream normaliser on its own |
| `isp_crop` | `isp_crop` | Region of interest |
| `isp_point` | `isp_point` | Offset, gain, bit shift, clamp |
| `isp_window` | `isp_window` | Neighbourhood of every reference pixel (window stream) |
| `isp_conv` | `isp_conv` | Linear kernel on a window stream |
| `isp_filter2d` | `isp_filter2d` | General 2D window filter, for example an MTF filter |
| `isp_bin` | `isp_bin` | Binning |
| `isp_replace` | `isp_replace` | Replacement of non-operational pixels |

## 2. The pixel stream

### 2.1 Signals

Every module has a pixel stream at its input (`In_*`) and at its output (`Out_*`), except `isp_window` (window
stream at the output) and `isp_conv` (window stream at the input).

| Signal | Width | Meaning |
| --- | --- | --- |
| `Valid`, `Ready` | 1 | AXI4-Stream handshake: a beat transfers when both are high |
| `Data` | pixel width | One unsigned pixel per beat, in raster order |
| `Last` | 1 | Last beat of a stream packet |
| `User` | 2 | Sequence flags of the packet, valid with every beat: "01" first packet of an image, "00" continuation, "10" last packet, "11" the only packet of an image |

The sequence flags have the meaning of the Sequence Flags of a CCSDS Space Packet (CCSDS 133.0-B-2, 4.1.3.4.2.2): a
source that unpacks the data fields of segmented Space Packets passes the flags of every packet with its pixels.

### 2.2 Packets at an input and at an output

At an input an image may arrive in any division into packets; the boundaries need not be line ends. The first beat
of a packet with the flags "01" or "11" starts an image; the module counts the pixels from there with the image
dimensions of its generics.

At an output every line is one packet: "01" for the first line, "00" for the lines between, "10" for the last line,
"11" for an image of one line. This output is a legal input of every module.

Example: an image of 4 x 3 pixels in two packets of 7 and 5 pixels.

| Input packet | Pixels | `User` | Output packet | Pixels | `User` |
| --- | --- | --- | --- | --- | --- |
| 1 | p(0,0) to p(2,1) | "01" | 1 | p(0,0) to p(3,0) | "01" |
| 2 | p(3,1) to p(3,2) | "10" | 2 | p(0,1) to p(3,1) | "00" |
| | | | 3 | p(0,2) to p(3,2) | "10" |

### 2.3 Malformed streams

The pixel count, not the packets, decides where an image ends:

| Input | Response | Status |
| --- | --- | --- |
| An image start before the open image is complete (a lost packet) | The open image is completed with pixels of value 0, then the new image starts | `Err_Framing` |
| Pixels without an image start while no image is open | Discarded | `Err_Framing`, once per run |
| The last pixel of an image without `Last` or in a packet with the flags "01" or "00" | The image ends all the same | `Err_Framing` |
| `Last` with the flags "10" or "11" before the last pixel | The image continues | `Err_Framing` |

Every output image is complete. An image whose rest never arrives stays open until the next image start;
`Stat_ImageOpen` shows it, so that a supervisor can apply a timeout of its own.

### 2.4 Waiting times

A module accepts one pixel per clock cycle within a line. It holds its input in these cases:

| Case | Module | Wait |
| --- | --- | --- |
| Completion of a short image | every module with a frame sync | One cycle per missing pixel, when the next image starts |
| Right border of every line | `isp_window`, `isp_filter2d` (border modes zero, replicate, mirror) | `WinX_g` - 1 - `AnchorX_g` cycles |
| Right border of every line | `isp_bin` (border modes zero, replicate) | `BinX_g` - 1 cycles |
| Right border of every line | `isp_replace` | `MaxGap_g` cycles; between the first pixels of lines 0 and 1 of an image the wait for word 0 of the defect map: `RamRdLatency_g` + `EccPipeline_g` + 2 cycles after an idle input, max(`MaxGap_g`, `RamRdLatency_g` + `EccPipeline_g` + 2) after an image (RPL-PF-01). With the defaults (`RamRdLatency_g` 2, `EccPipeline_g` 1) 5 cycles, which a clock of 125 MHz on PolarFire needs; with `RamRdLatency_g` 1 and `EccPipeline_g` 0 3 cycles. Within a line the read path adds no hold |
| Lower border of every image | `isp_window`, `isp_filter2d` (border modes zero, replicate, mirror) | `WinY_g` - 1 - `AnchorY_g` lines of the image width |
| Lower border of every image | `isp_bin` (border modes zero, replicate) | At most max(0, (`BinY_g` - 1) x Wo + 2 - 2 x `BinX_g`) cycles, taken by the next image (BIN-PF-01; Wo = ceil(W / `BinX_g`)) |
| Output stalled | every module | Until the consumer takes the output |

The frame sync of a module takes three more pixels after the last pixel of a line before its input holds (its output
register and the two entries of its input stage). The holds for the right border of a line therefore come at the
start of the next line at the input, and those of the last line of an image at the start of the next image.

## 3. Clocks and reset

Every module has one clock `Clk` and a synchronous, high-active reset `Rst`. The reset leads to the state that waits
for an image start: an image in progress is lost, and the next image start begins a new one. The reset does not
change the defect map of `isp_replace`; the command `CTRL.CLEAR` does.

## 4. Registers

### 4.1 Interface

`isp_crop`, `isp_point`, `isp_conv` (and `isp_filter2d` through it) and `isp_replace` have an AXI4-Lite slave
(`S_AxiLite_*`, 32 data bits, the port names of Open Logic `olo_axi_lite_slave`) in the clock domain of the module.
A register bus in another clock domain needs a clock crossing in the system. Every access is answered with OKAY;
reads of unused addresses return 0. A module whose registers are not needed leaves the slave unconnected: its inputs
default to inactive.

The register map of a module is generated from its register description (`hdl/<module>/regs/<module>_regs.yml`) by
`tools/regmap.py`: the page "Register map" of the module, the VHDL package `<module>_regs_pkg` and the C header
`sw/<module>_regs.h` with the addresses, the field positions and masks and the identification for the software.

Every register map starts with the same registers:

| Register | Content |
| --- | --- |
| `ID` | Three characters of the module and the version of the register map, for example 0x43525001 for `isp_crop` |
| Characteristics | The generics that the software needs (image dimensions, widths, sizes) |
| `STATUS` | `IMAGE_OPEN` and sticky error flags, cleared by writing one |

### 4.2 Run-time parameters

The run-time parameters (the position of the region of `isp_crop`, the parameter set of `isp_point`, the
coefficients of `isp_conv`) are taken from the registers with every image start. A write takes effect with the next
image. To change several registers for the same image:

1. Write 1 to `CTRL.HOLD`: the next image starts keep the parameters in use.
2. Write the registers.
3. Write 0 to `CTRL.HOLD`: the next image start takes all of them.

Without `CTRL.HOLD`, an image start between two writes takes a mixed set for one image. `isp_crop` has its position
in one register and needs no `CTRL.HOLD`.

In a chain every module takes its set at its own image start, when pixel (0, 0) of the image reaches it, and these
starts come later from module to module. To give one image the new sets of several modules:

1. Write 1 to `CTRL.HOLD` of every module whose set changes, and write the new sets.
2. In the window below, write 0 to every `CTRL.HOLD` and write `ROI_POS` of `isp_crop`; every write ends before the
   window ends.

Every module then has image k open at the release and takes the new set at its start of image k + 1. The software
times the release from the image start at the chain input (the frame start of the source). The image start reaches
module j S_j cycles after it, the sum of the delays of the modules before j:

| Module | Delay of the image start |
| --- | --- |
| `isp_point` | Its latency, `MultStages_g` + 5 (PNT-PF-02) |
| `isp_replace` | `MaxGap_g` pixels and its latency, 13 + `RamRdLatency_g` + `EccPipeline_g` (RPL-PF-03) |
| `isp_crop` | `RoiY_g` lines, `RoiX_g` pixels and its latency, 4 (CRP-PF-02) |
| `isp_window`, `isp_filter2d` | Rb lines, Rr pixels (`WinY_g` - 1 lines and `WinX_g` - 1 pixels in the border mode valid) and the latency, 6 (WIN-PF-03) or log2ceil(T) + 9 (FLT-PF-02) |
| `isp_bin` | `BinY_g` - 1 lines, `BinX_g` - 1 pixels and its latency, 16 + log2ceil(`BinX_g`) + log2ceil(`BinY_g`) with both filters, 8 + log2ceil of the factor with one |

A line is the line period at the chain input (W plus the holds per line, section 2.4; line 0 can be longer: the wait for
word 0 of `isp_replace`), a pixel one cycle. With S_first and S_last the delays to the first and the last module whose
set changes and P the image period, the window is S_last < t < S_first + P after the image start. A window that holds in
every case is narrower than the true one at both ends: its start takes S_last with the latency bounds of the
specifications (the table), its end S_first with the pixel and line delays of the table only, without the latencies.
When S_last - S_first is not shorter than P (a region near the lower edge of the image, large windows), back-to-back
images leave no window: the source pauses after an image, the release comes S_last after its start, and the next image
starts after the writes. A release at another time can give one image the old set in the first modules and the new one
in the last.

Example: `isp_replace` (40 x 20 pixels, `MaxGap_g` 2, `RamRdLatency_g` 1, `EccPipeline_g` 0), `isp_point`, `isp_crop`
(32 x 16 at (4, 2)), a 3 x 3 `isp_filter2d`, a 2 x 2 `isp_bin` and `isp_point`, with run-time sets in both `isp_point`,
`isp_crop` and `isp_filter2d`: line period 42, line 0 one cycle longer (the wait for word 0 of the defect map, 3
cycles), P = 841, S_last = 16 + 1 + 7 + 92 + 56 + 61 = 233 with the latency bounds, S_first = 2 (the `MaxGap_g` pixels
of `isp_replace`) without them; the window is 233 < t < 843 cycles after the image start. It lies inside the window of
the design values of the module plans (230 < t < 853). Without a window: 5 x 3 pixels of 1 bit through `isp_replace`
(`MaxGap_g` 2, `RamRdLatency_g` 1, `EccPipeline_g` 0), `isp_point`, `isp_crop` (3 x 3 at (1, 0)), a 3 x 3 `isp_filter2d`
and a 3 x 3 `isp_bin` to `isp_point`: P = 22, S_last = 85. The source stops after an image, the release comes at least
85 cycles after its start, and the next image starts after the writes.

### 4.3 Parity of the parameter registers

Every parameter register carries a parity bit, set with every write. At the image start the module checks it; after
an upset the image is processed with the values of the generics, `Err_Config` pulses and `STATUS.ERR_CONFIG` is set,
and so for every further image until the register is written again. The software therefore:

- reads `STATUS` after every image or periodically,
- writes the parameter registers again when `ERR_CONFIG` is set, then clears the flag.

The register `INJECT` inverts the parity bit of a parameter register, so that the system can test this path.

### 4.4 Defect map of `isp_replace`

The defect map has one bit per pixel, 1 for a non-operational pixel, in words of 32 bits; every line has its own
`MAP_LINE` words. The software writes it word by word: `MAP_ADDR` with the first address, then `MAP_DATA` once per
word, which counts `MAP_ADDR` up. `CTRL.CLEAR` writes 0 to every word (`STATUS.BUSY` meanwhile). A map written while
images pass applies to an image in part: the module reads the words in step with the pixels, not at the image start.
A new map for one whole image is written while no image is open at the input of `isp_replace`; with back-to-back
images the source pauses between two images for the writes. The map is protected by its
ECC and scrubbed; `STATUS.ECC_DED` reports a word that the software has to write again. Open Logic does not
initialise the RAM of the map: after power-up the software issues `CTRL.CLEAR` or writes every word before the
first image, and clears the `STATUS` flags that the scrubber set for the content before.

## 5. Building a chain

1. Choose the modules and their order; the output dimensions and pixel width of every module are the input generics
   of the next (the specification of every module states them; the functions of `isp_pkg` compute them as the
   modules do: `ispWinOut` the dimensions behind a window filter, `ispBinOut` behind a binning, `ispConvOutBits` the
   width behind a kernel).
2. Scale the sums of filters and binning with an `isp_point` behind them: a kernel whose coefficients add up to 2^n
   is followed by a shift of n; the average of a bin of n pixels is a shift of log2(n), or the gain round(2^k / n)
   with the shift k when n is not a power of two.
3. Put an `olo_ft_fifo_sync` in front of the chain when the source cannot wait. For a source of W pixels per line at one
   per cycle with a line blanking L and an image blanking F: let r_y be the hold cycles of the chain input between the
   first pixels of lines y and y + 1 (section 2.4: the holds of the first module, plus the waits of a module behind it
   that the modules between do not take; `isp_crop` takes them with the pixels outside its region, a binning with its
   idle output cycles), D_-1 = 0 and D_y = max(0, D_(y-1) + r_y - L). Then `Depth_g` >= max over the lines of D_(y-1) +
   r_y, plus 4, and F >= D_(H-2) + r_(H-1) + 1, so that every image finds the FIFO empty; when the source is faster than
   the chain over an image, no depth suffices. Example: `isp_replace` with `MaxGap_g` 2, `RamRdLatency_g` 1 and
   `EccPipeline_g` 0 first (r_0 = 3, the wait for word 0 of the defect map, r_y = 2 for y >= 1), H = 20, L = 1:
   `Depth_g` 26 and F >= 23. The plain sum of the waits of all modules overestimates: in that
   example the lower border of a filter behind `isp_crop` is taken by the pixels outside the region.
4. Collect the ECC status pulses of the modules in an `olo_ft_ecc_monitor` and the error pulses in a status
   register of the system.

An MTF compensation filter is an `isp_filter2d` with the size of the kernel as `WinX_g` and `WinY_g`, the kernel
scaled by 2^n and rounded as `Coef_g`, the border mode replicate or mirror (the output keeps the image size), and an
`isp_point` with the shift n behind it. With `RuntimeCoef_g` the kernel is replaced in operation.

## 6. Protection scope

The modules are designed for radiation environments together with the triple modular redundancy (TMR) of the
synthesis tool, like the Open Logic ft entities they are built on. They protect the parts in the first rows
themselves and rely on TMR for all other logic:

| Part | Protection | Indication and test |
| --- | --- | --- |
| Line buffers of `isp_window` (also in `isp_filter2d`, `isp_bin`, `isp_replace`) and the defect map of `isp_replace` | SECDED ECC of the Open Logic ft entities: a single error is corrected, a double error is detected; the pixel or the word is used as read. Only the line buffers whose pixels reach a window report: the rows that the border rule replaces do not count, so the content of the line buffers after power-up is never reported. The defect map is scrubbed | `Stat_EccSec`, `Stat_EccDed`, `STATUS.ECC_SEC` and `ECC_DED` of `isp_replace`; error injection through the `ErrInj` ports |
| Parameter registers of `isp_crop`, `isp_point` and `isp_conv` | A parity bit per register, checked at every image start; the generics apply after an upset | `Err_Config`, `STATUS.ERR_CONFIG`; error injection through the register `INJECT` |
| Clock domain crossings and reset synchronisers | None needed: every module has one clock domain | none |
| State machines and counters | Recovery state through the `when others` branch and the reset; the counters restart with every image start | `Err_Framing` for the image in progress |
| All other logic: registers of the control and data paths, counters, pipeline registers, window registers | TMR of the synthesis tool (for example `syn_radhardlevel` = `tmr` with Synplify, or the equivalent setting of the tool chain). The modules add no protection of their own for this logic; without TMR, an upset in it is not covered | synthesis report |

The integrator:

- enables the TMR of the synthesis tool for the modules and the logic around them,
- checks in the synthesis report that TMR was applied and that no register-based storage meant to be protected by
  TMR was inferred as a RAM primitive,
- requests safe state machines, so that synthesis keeps the `when others` branches (AMD Vivado: property
  `FSM_SAFE_STATE` = `default_state` on the state registers; Synplify: attribute `syn_encoding` = `safe`),
- protects the configuration memory of SRAM-based FPGAs by scrubbing; this is part of the FPGA design, not of the
  modules.

The ECC and parity paths are verified in simulation by error injection. Whether the protection as a whole meets the
requirements of a mission is shown by a radiation test with the modules in operation (TRL 5).

## 7. Integration constraints

| Constraint | Reason |
| --- | --- |
| TMR of the synthesis tool enabled for the modules | The modules protect their line buffers, the defect map and their parameter registers themselves and rely on TMR for all other logic (section 6) |
| A source that cannot wait has a FIFO in front of the chain, or blanking between lines and images, that covers the waits of section 2.4 (section 5, step 3) | The modules hold their input at the image borders and while they complete a short image |
| After a lost packet the input waits as long as the lost data would have taken; the source has blanking per image of at least the largest loss to be tolerated, or the clock of the modules is faster than the pixel rate | A source at one pixel per clock cycle without blanking never catches up after a loss; with enough blanking the chain recovers within one image |
| A packet protocol behind a chain whose data field is smaller than a line (W x pixel width bits; 65536 octets for a Space Packet) has a segmenting stage | Every output line is one packet |
| The register bus is in the clock domain of the module, or the system provides a clock crossing | The AXI4-Lite slaves have no crossing of their own |
| The software reacts to `STATUS.ERR_CONFIG` by writing the parameter registers again | An upset of a parameter register persists until it is written (section 4.3) |
| The defect map is written between images where an image must not see a partial update | The map is read in step with the pixels (section 4.4) |
| After power-up the software clears the defect map (`CTRL.CLEAR`) or writes it completely before the first image, and repeats `CTRL.CLEAR` after a reset during a clear | The content of the RAM after configuration depends on the device; Open Logic does not initialise it |
| A chain is reset together with its source, or between images | A reset inside a first or only packet of an image makes the rest of that packet an image start: one wrong image with `Err_Framing`, the next one correct (`isp_frame_sync` specification, section 6) |
| A module of a chain is reset alone only between two packets of its output (between two lines) | A reset inside a packet cuts it: the module behind continues the packet with the next image, ends the image at its pixel count and discards the rest (`Err_Framing` twice), so that image is lost behind the reset module (CHN-FN-03) |

## 8. Resources and performance

Every module accepts one pixel per clock cycle within a line; the default configurations are designed for 150 MHz.
The timing is shown by an out-of-context synthesis and timing run of the default configuration of every module on
the AMD Versal device of the reference systems, not by the simulation; runs on Microchip PolarFire are a later
option. The architecture document of every module estimates its resources; the verification reports record the synthesis
results.

## 9. Conformance

The reference of OpenISP is its [requirements specification](requirements.md). The
[architecture](architecture.md) (section 10) assigns every core requirement to a module, and the
[compliance matrix](compliance.md) lists the module requirements and the test cases of every core requirement with
its status.

| Group | Core requirements | Implemented by |
| --- | --- | --- |
| Pixel stream | ISP-STR-01 to ISP-STR-10 | `isp_frame_sync` in every module; the output side of every module |
| Configuration | ISP-CFG-01 to ISP-CFG-03 | Every module (generics); `isp_crop`, `isp_point`, `isp_conv`, `isp_replace` (registers) |
| Region of interest | ISP-CRP-01 | `isp_crop` |
| Pixel-level operation | ISP-PNT-01, ISP-PNT-02 | `isp_point` |
| 2D window filter | ISP-FLT-01 to ISP-FLT-04 | `isp_window`, `isp_conv`, `isp_filter2d` |
| Binning | ISP-BIN-01, ISP-BIN-02 | `isp_bin` |
| Replacement of non-operational pixels | ISP-RPL-01 to ISP-RPL-03 | `isp_replace` |
| Fault tolerance | ISP-FT-01 to ISP-FT-05 | Modules with memories and parameter registers; every module for ISP-FT-04 |
| Implementation | ISP-GEN-01 to ISP-GEN-03 | Every module; ISP-GEN-01 is shown by the GHDL synthesis check, ISP-GEN-03 by the timing runs of section 8, not by simulation |

The status column of the compliance matrix shows which of them are verified; a module is complete when its
verification report is written and every requirement has a passing test case.
