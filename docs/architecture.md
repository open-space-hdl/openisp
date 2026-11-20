# OpenISP Architecture

This document describes the architecture of the OpenISP suite as a whole: its scope, the principles that every
module follows, the stream that connects the modules, the use of Open Logic, the verification architecture and the
traceability of the [requirements specification](requirements.md). The design of every module is described in its
own documents in `hdl/<module>/docs/`.

## 1 Purpose, scope and references

### In scope

OpenISP is a suite of image processing modules for the instruments of spacecraft. A module performs one function on
a stream of pixels; a processing chain is a series of modules that the integrator selects and orders. The suite
covers:

- the input side of every module: images in any division into stream packets, malformed streams (`isp_frame_sync`);
- the selection of a region of interest (`isp_crop`);
- pixel-level operations: offset, gain, bit shift, clamp (`isp_point`);
- the neighbourhood of every pixel with border handling (`isp_window`) and linear filters on it (`isp_conv`,
  `isp_filter2d`), for example the compensation of the modulation transfer function (MTF);
- binning (`isp_bin`);
- the replacement of non-operational pixels by interpolation (`isp_replace`).

### Out of scope

- The interface to a detector (timing, readout, serial links) and the transfer of images over a packet link: the
  modules see images as stream packets, for example the data fields of segmented CCSDS Space Packets that a packet
  core has unpacked.
- Colour processing (demosaicing, colour correction), statistics and compression; the compression of the images is
  the task of OpenCompact behind a chain.
- Image dimensions that change at run time: the dimensions are generics of every module.

### Target technology

Technology-independent VHDL-2008, synthesisable by GHDL, built on the fault-tolerant entities of Open Logic. The
default configuration of every module is designed for 150 MHz on the FPGA families of the reference systems of the
family (AMD Versal, Microchip PolarFire).

### References

| Reference | Title | Use |
| --- | --- | --- |
| [Requirements specification](requirements.md) | OpenISP requirements specification | The reference of the suite in place of a standard (section 10) |
| ECSS-E-ST-20-40C | Space engineering: ASIC, FPGA and IP core engineering | Development process |
| CCSDS 133.0-B-2 | Space Packet Protocol | Meaning of the sequence flags of the pixel stream (4.1.3.4.2.2) |
| AMBA AXI4-Stream, AXI4-Lite | Arm protocol specifications | Handshake of the pixel stream, register interface |
| Open Logic | VHDL library, fork open-space-hdl/open-logic-ft | Line buffers, tables, pipeline stages, AXI4-Lite slave |

### Conventions

Coding, verification and repository rules: [conventions](conventions.md). Requirement IDs: core requirements
`ISP-<GROUP>-<NN>`, module requirements `<LAYER>-<GROUP>-<NN>`.

## 2 Functional overview

An instrument delivers images; OpenISP corrects and reduces them before they are compressed or sent to the ground.
A typical chain:

![Example chain of OpenISP modules: replacement of non-operational pixels, offset and gain, region of interest, MTF
filter, binning and bit shift](img/isp_chain.drawio.svg)

1. `isp_replace` replaces the non-operational pixels that the defect map marks.
2. `isp_point` subtracts the dark level and applies the gain.
3. `isp_crop` selects the region of interest.
4. `isp_filter2d` compensates the MTF with a kernel whose coefficients can be replaced in operation.
5. `isp_bin` adds the pixels of every bin.
6. `isp_point` scales the sums to the pixel width of the compressor.

The order is free: every module consumes and produces the same pixel stream (section 6). The image dimensions
change where a module crops, bins or filters in the border mode valid; each such module states its output dimensions
as functions of its generics.

## 3 Design drivers

| Driver | Consequence |
| --- | --- |
| Images arrive in packets of a link, not in lines | Every input accepts any division into packets; every output delivers one packet per line |
| Packets get lost on a link; registers and counters suffer upsets | The pixel count from the image start decides where an image ends; every module completes or discards and realigns with the next image start |
| A mission changes some parameters in orbit | Region position, offset, gain, shift, thresholds, filter coefficients and the defect map are registers; image dimensions and structure are generics |
| Radiation | Every memory is an ECC-protected Open Logic entity; long-lived registers carry a parity bit; the rest relies on the TMR of the synthesis tool |
| One pixel per clock cycle at 150 MHz | Pipelined datapaths, no multi-cycle operation per pixel; waits only at the image borders |
| Reuse | A specific function is a configuration of a general module (the MTF filter of `isp_filter2d`, the binning of two filters) |

## 4 Design goals

1. Connectable: the output of any module is a legal input of any other.
2. General: few modules, each configured by generics, instead of one module per function.
3. Robust: a malformed stream or an upset disturbs at most the image in progress.
4. Verifiable: every requirement traces to a test case; expected images come from a reference model independent of
   the RTL.
5. Vendor-independent and built on Open Logic.

## 5 Design principles

- One clock domain per module (`Clk`, synchronous high-active `Rst`); a register bus or a source in another clock
  domain is connected by the system.
- Valid / ready handshake with back-pressure everywhere; one pixel per beat.
- Image dimensions, pixel widths and window sizes are generics with checked ranges; run-time parameters are
  registers taken at the image start.
- Memories are Open Logic ft entities (SECDED, optional scrubbing); state machines have a `when others` recovery;
  counters restart with every image. All other logic relies on the TMR of the synthesis tool
  ([user guide](user_guide.md), section "Protection scope").
- Standard functions come from Open Logic and are not rewritten.

## 6 Architecture overview

### Pixel stream

The pixel stream is the interface between the modules (requirements specification, section 3.1):

| Signal | Width | Meaning |
| --- | --- | --- |
| `Valid`, `Ready` | 1 | AXI4-Stream handshake |
| `Data` | pixel width of the stream | One unsigned pixel per beat, raster order |
| `Last` | 1 | Last beat of a stream packet |
| `User` | 2 | Sequence flags of the packet on every beat: "01" first, "00" continuation, "10" last, "11" only packet of an image |

At an input an image may arrive in any division into packets; the first beat of a packet with the flags "01" or "11"
starts an image. At an output every line is one packet: "01" for the first line, "00" between, "10" for the last
line, "11" for an image of one line. The dimensions of the image are generics, and the pixel count from the image
start, not the packets, decides where an image ends: an image that is too short is completed with zeros when the next
image starts, pixels that belong to no image are discarded, and every deviation pulses `Err_Framing`.

### Window stream

Between `isp_window` and a kernel (`isp_conv`, the interpolation of `isp_replace`) the data of a beat is a window
of `WinX_g` x `WinY_g` pixels instead of one pixel, element 0 the top left pixel, row by row. The packets are those
of the output image of the window generator, so the kernel outputs a pixel stream without logic of its own for the
packets.

### Registers

A module with run-time parameters has an AXI4-Lite slave (32 data bits) in its clock domain. Every register map
starts with an identification register (three characters of the module and the version of the map), the build-time
characteristics and a status register with sticky error flags. Run-time parameters are taken at the image start;
`CTRL.HOLD` lets the software change several of them for the same image. A parameter register carries a parity bit:
an upset is found at the next image start, the module then uses the generics and reports `Err_Config`.

### Status

| Output | Kind | Modules |
| --- | --- | --- |
| `Err_Framing` | Pulse | Every module with an `isp_frame_sync` |
| `Stat_ImageOpen` | Level | Every module with an `isp_frame_sync` |
| `Err_Config` | Pulse | Modules with parameter registers |
| `Stat_EccSec`, `Stat_EccDed` | Pulse | Modules with line buffers or a table |
| `Stat_Unreplaced` | Pulse | `isp_replace` |

### Architecture decisions

| ID | Decision | Reason |
| --- | --- | --- |
| D1 | Image dimensions are generics of every module | One configuration per sensor mode; counters and line buffers sized at build time; run-time dimensions would need consistent settings along the chain |
| D2 | The sequence flags of the packets on two user bits | The framing of the link (CCSDS Space Packets) reaches the modules unchanged |
| D3 | Any division into packets at an input, one packet per line at an output | Inputs take the packets of a link; outputs are a normal form that every module accepts |
| D4 | The pixel count decides the end of an image; short images are completed, excess pixels discarded | The count keeps the lines in their columns after a lost packet; outputs are always complete images |
| D5 | One input module, `isp_frame_sync`, for every module | The stream rules are implemented and verified once |
| D6 | Registers on an AXI4-Lite slave per module, taken at the image start, with `CTRL.HOLD` | No image is processed with a mixed parameter set |
| D7 | A parity bit per long-lived register | An upset of a register is found at the next image start instead of changing every image |
| D8 | Filters and binning deliver sums at full precision; `isp_point` scales | One scaling stage for every sum; no loss of precision between the stages |
| D9 | Line buffers are `olo_ft_delay` entities of one line each, one codeword per pixel | The delay counts pixels, not cycles; the decoder depth does not grow with the window |
| D10 | Binning is two window filters, first along the line | The line buffers hold the narrowed image |
| D11 | The defect map has one bit per pixel, its own words per line | Read in step with the pixels by a counter; a list of positions is a later option for detectors with few defects |
| D12 | A pixel read with a double bit error is used as read and reported by a status pulse, not marked in the stream | The stream contract has no data-error sideband; it is an option if a mission needs per-image marking |

### Clock and reset

Every module has one clock and a synchronous, high-active reset. The reset leads to the state that waits for an image
start; the defect map of `isp_replace` keeps its content.

### Single event effects

The modules protect their memories with the SECDED code of the Open Logic ft entities: the line buffers of
`isp_window` and the defect map of `isp_replace`, which is also scrubbed. Long-lived registers carry a parity bit.
State machines recover through their `when others` branch, counters restart with every image start, and every other
register relies on the TMR of the synthesis tool ([user guide](user_guide.md), section "Protection scope").

## 7 Building blocks

| Module | Function | Uses |
| --- | --- | --- |
| [`isp_frame_sync`](../hdl/isp_frame_sync/README.md) | Input side of every module; stream normaliser | `olo_base_pl_stage` |
| [`isp_crop`](../hdl/isp_crop/README.md) | Region of interest | `isp_frame_sync`, `olo_axi_lite_slave` |
| [`isp_point`](../hdl/isp_point/README.md) | Offset, gain, shift, clamp | `isp_frame_sync`, `olo_axi_lite_slave` |
| [`isp_window`](../hdl/isp_window/README.md) | Neighbourhood of every reference pixel | `isp_frame_sync`, `olo_ft_delay` |
| [`isp_conv`](../hdl/isp_conv/README.md) | Linear kernel on a window | `olo_axi_lite_slave` |
| [`isp_filter2d`](../hdl/isp_filter2d/README.md) | General 2D window filter | `isp_window`, `isp_conv` |
| [`isp_bin`](../hdl/isp_bin/README.md) | Binning | two `isp_filter2d` |
| [`isp_replace`](../hdl/isp_replace/README.md) | Replacement of non-operational pixels | `isp_frame_sync`, `isp_window`, `olo_ft_ram_sdp_scrub`, `olo_axi_lite_slave` |

A package `isp_pkg` holds the common types (the coefficient vector) and the functions that give the output
dimensions and pixel widths of the modules for the generics of the module behind.

## 8 Open Logic usage

| Open Logic entity | Used by | Purpose |
| --- | --- | --- |
| `olo_ft_delay` | `isp_window` | Line buffers, one codeword per pixel |
| `olo_ft_ram_sdp_scrub` | `isp_replace` | Defect map, ECC per word, scrubbing |
| `olo_base_pl_stage` | `isp_frame_sync` | Input register stage with a registered ready |
| `olo_axi_lite_slave` | `isp_crop`, `isp_point`, `isp_conv`, `isp_replace` | Register interface |

Every memory of the suite is one of the two ft entities. `olo_base_pl_stage` and `olo_axi_lite_slave` hold no
memory. At system level, `olo_ft_fifo_sync` in front of a chain absorbs the waits of the modules for a source that
cannot be stalled, and `olo_ft_ecc_monitor` collects the ECC status pulses.

### Gaps in Open Logic

None found: the suite needs no new or changed Open Logic entity.

## 9 Verification architecture

### Framework

VUnit runs every test (`run.py`), UVVM supplies the checks, logs, randomisation and the AXI4-Lite BFM. GHDL is the
simulator of the regression and of the CI; QuestaSim runs the release regression with code coverage. Every test
passes in both.

### Benches

- A Python reference model (`tools/isp_model.py`) computes the output of every module from its input image,
  independent of the RTL. The configuration of a module (`hdl/<module>/tb/vunit_config.py`) runs it before the
  simulation and writes the stimulus and the expected output of every test as files.
- A pixel stream source (`tb/isp_tb_source.vhd`) reads the stimulus, drives the input with random gaps and with
  directives (reset, synchronisation); a pixel stream sink (`tb/isp_tb_sink.vhd`) takes the output with random
  stalls and compares every beat with the expected output.
- The testbench of a module adds the checks of its status outputs, its timing and its registers. Tests observe ports
  and the AXI4-Lite interface only.
- Test images are random or depend on every coordinate bit, so that an addressing fault changes the output.

### Rules

- Every requirement of a module specification has a test case; every checker and error path has a negative test;
  ECC is tested through the `ErrInj` ports, with at least one data bit.
- Every value of a generic that changes the structure is simulated, the bounds of every numeric range are simulated
  in configurations of small size, and `lint/synth_check.py` synthesises the bounds with GHDL.
- The sink of every unit test checks the output contract of the pixel stream (sequence flags in order, one packet
  per line, constant flags within a packet, the number of lines), so that every module shows at unit level that
  its output is a legal input.
- Phase G: the chain test (`hdl/isp_chain`) connects the modules in three chains, the chain of section 2, the same
  order at the low bounds of the generics and another order, and compares them with the composition of the
  reference models; a contract monitor on every connection, so that every connection between modules is crossed by
  a test.
- Phase F of every module ends with an out-of-context synthesis and timing run of its default configuration at
  150 MHz (Vivado, Versal device of the reference systems).

## 10 Requirement traceability matrix

Every core requirement has an owner module, the module whose requirements implement it first. "Also involved" lists
the other modules with requirements that trace to it. "First verified at" names the level at which it is fully
checked:

- "Unit": in the testbench of the owner and of every involved module;
- "Chain": in the integration test of section 9, after the unit tests of every module;
- "Synthesis": by the GHDL synthesis of `lint/synth_check.py` at the bounds of the generics;
- "Timing": by an out-of-context synthesis and timing run of the default configuration of every module at
  150 MHz with Vivado on the Versal device of the reference systems, recorded in the verification report of the
  module. A simulation does not show timing.

The [compliance matrix](compliance.md), generated from this table, the module specifications and the verification
plans, lists the module requirements and test cases of every core requirement.

| Core requirement | Title | Owner | Also involved | First verified at |
| --- | --- | --- | --- | --- |
| ISP-STR-01 | AXI4-Stream handshake | `isp_frame_sync` | every module | Unit |
| ISP-STR-02 | Raster order, packets, sequence flags | `isp_frame_sync` | every module | Unit |
| ISP-STR-03 | Dimensions and pixel width by generics | `isp_crop` | `isp_point`, `isp_window`, `isp_filter2d`, `isp_bin`, `isp_replace` | Unit |
| ISP-STR-04 | Any division into packets | `isp_frame_sync` | every module with a frame sync | Unit |
| ISP-STR-05 | One packet per line at the output | `isp_frame_sync` | every module | Unit |
| ISP-STR-06 | Output is a legal input | `isp_frame_sync` | every module | Chain |
| ISP-STR-07 | Back-pressure and gaps, images back to back | `isp_frame_sync` | every module | Unit |
| ISP-STR-08 | Pixel count, malformed streams | `isp_frame_sync` | every module with a frame sync | Unit |
| ISP-STR-09 | One pixel per clock cycle | `isp_frame_sync` | every module | Unit |
| ISP-STR-10 | Status of an open image | `isp_frame_sync` | every module with a frame sync | Unit |
| ISP-CFG-01 | Structure by generics with checked ranges | `isp_frame_sync` | every module | Unit |
| ISP-CFG-02 | Run-time parameters as registers | `isp_crop` | `isp_point`, `isp_conv`, `isp_replace` | Unit |
| ISP-CFG-03 | AXI4-Lite slave per module with registers | `isp_crop` | `isp_point`, `isp_conv`, `isp_filter2d`, `isp_replace` | Unit |
| ISP-CRP-01 | Region of interest | `isp_crop` | | Unit |
| ISP-PNT-01 | Offset, gain, shift, clamp | `isp_point` | | Unit |
| ISP-PNT-02 | Parameters by generics or at run time | `isp_point` | | Unit |
| ISP-FLT-01 | Window with border modes | `isp_window` | `isp_filter2d` | Unit |
| ISP-FLT-02 | Linear filter at full precision | `isp_conv` | `isp_filter2d` | Unit |
| ISP-FLT-03 | Window size by generics, coefficients at run time | `isp_conv` | `isp_filter2d` | Unit |
| ISP-FLT-04 | Stride | `isp_window` | `isp_filter2d` | Unit |
| ISP-BIN-01 | Binning as a configuration of the filter | `isp_bin` | | Unit |
| ISP-BIN-02 | Incomplete bins by the border mode | `isp_bin` | | Unit |
| ISP-RPL-01 | Replacement by interpolation in the line | `isp_replace` | | Unit |
| ISP-RPL-02 | Defect map of one bit per pixel | `isp_replace` | | Unit |
| ISP-RPL-03 | Largest distance by a generic | `isp_replace` | | Unit |
| ISP-FT-01 | Memories with SECDED and status | `isp_window` | `isp_filter2d`, `isp_bin`, `isp_replace` | Unit |
| ISP-FT-02 | Error injection | `isp_window` | `isp_filter2d`, `isp_bin`, `isp_replace` | Unit |
| ISP-FT-03 | Scrubbing of long-lived tables | `isp_replace` | | Unit |
| ISP-FT-04 | Recovery from any state | `isp_frame_sync` | every module | Unit |
| ISP-FT-05 | Parity of long-lived registers | `isp_crop` | `isp_point`, `isp_conv`, `isp_filter2d` | Unit |
| ISP-GEN-01 | VHDL-2008, GHDL synthesis, Open Logic | `isp_frame_sync` | every module | Synthesis |
| ISP-GEN-02 | Specific functions as configurations | `isp_filter2d` | `isp_bin`, `isp_replace` | Unit |
| ISP-GEN-03 | 150 MHz | `isp_frame_sync` | every module | Timing |

## 11 Development plan

Every module goes through the phases of the [conventions](conventions.md): requirements (A), architecture (B),
verification plan (C), RTL (D), testbenches (E), verification (F) and integration (G). The modules are developed in
the order of their dependencies:

| Step | Modules | Content |
| --- | --- | --- |
| 1 | `isp_frame_sync` | Shared bench components (source, sink, reference model, `isp_pkg`) |
| 2 | `isp_crop`, `isp_point` | Register interface with parity and `CTRL.HOLD` |
| 3 | `isp_window`, `isp_conv`, `isp_filter2d` | Line buffers, borders, kernels |
| 4 | `isp_bin`, `isp_replace` | Configurations of the filter, defect map |
| 5 | Chain | Integration test of section 2 |
| 6 | Release 0.1.0 | QuestaSim regression with code coverage; the suite at TRL 3 (fully verified by simulation; the 150 MHz target shown by the timing runs, not by the simulation) |

The [roadmap](roadmap.md) tracks the state of every module.
