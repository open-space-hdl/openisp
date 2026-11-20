# OpenISP Roadmap

This page tracks the state of every module; a module is done when its verification report is written and its
regression is green.

## Technology readiness

No module is verified yet. A module reaches TRL 3 when it is fully verified by simulation (GHDL and QuestaSim, code
coverage closed or justified); TRL 4 needs the hardware test of a reference system of the family that contains it.
The [TRL page](https://openspacehdl.org/trl/) explains what the levels mean for an IP core.

## Modules

| Module | Function | Status |
| --- | --- | --- |
| `isp_pkg` | Common definitions: sequence flags, position width, image start, the output widths and dimensions of the modules | Verified (GHDL) |
| `isp_frame_sync` | Input side of every module: any division of an image into packets in, complete images with one packet per line and pixel positions out | Verified (GHDL, mutations); timing estimated on PolarFire |
| `isp_crop` | Region of interest: crops an image to a rectangle of a size set by generics, at a position set by generics or at run time | Verified (GHDL, mutations); timing estimated on PolarFire |
| `isp_point` | Pixel-level operation: offset, gain, bit shift and clamp between two thresholds, set by generics or at run time | Verified (GHDL, mutations); timing estimated on PolarFire |
| `isp_window` | Neighbourhood generator: one window per reference pixel, line buffers, border modes, anchor and stride | Verified (GHDL, mutations); timing estimated on PolarFire |
| `isp_conv` | Linear kernel: the weighted sum of a window at full precision, coefficients set by a generic or at run time | Verified (GHDL, mutations); timing estimated on PolarFire |
| `isp_filter2d` | The general 2D window filter: `isp_window` and `isp_conv` in one entity, for example an MTF filter | Verified (GHDL, mutations); timing estimated on PolarFire |
| `isp_bin` | Binning: the sum of every bin of n x m pixels, two window filters with a stride | Verified (GHDL, mutations); timing estimated on PolarFire |
| `isp_replace` | Replacement of non-operational pixels by 1D interpolation, with a defect map configurable at run time | Verified (GHDL, mutations); timing estimated on PolarFire |

All modules share the pixel stream of the [requirements specification](requirements.md), so they connect in any
order. The chain test `isp_chain` (phase G) connects them in three chains, against the composition of their reference
models: verified (GHDL).

## Open items

| Item | State |
| --- | --- |
| Release 0.1.0 | All modules through phases C to G; QuestaSim regression with code coverage on the release branch; the suite at TRL 3 |
| Marking of data errors | A pixel read from a line buffer with a double bit error is used as read and reported by `Stat_EccDed` (architecture, decision D12). A data-error sideband in the stream contract, which would mark the affected output pixels and images, is an option if a mission needs it |
| Run-time image dimensions | The dimensions are generics. Ports for the dimensions, with the generics as maxima, would land in `isp_frame_sync` and in the line buffers (`olo_ft_delay_cfg`); every module of a chain would need consistent settings |
| Defect list | The defect map of `isp_replace` has one bit per pixel. A list of the positions of the non-operational pixels needs less memory for a detector with few defects |
| Timing on Versal | The preliminary synthesis on Microchip PolarFire MPF100T at 125 MHz is recorded for every module (user guide, section 8). The out-of-context synthesis and implementation at 150 MHz on the AMD Versal device of the reference systems is open |
| Pipelined product of `isp_point` | The stages of `MultStages_g` follow the product; on PolarFire the synthesis does not take them into the multiplier, so the widest configuration reaches 80.6 MHz. A product pipelined in the RTL itself (partial products of the gain width with registers between the partial sums, or the registers of the Math blocks) would shorten the product path with any tool; a design change for the wide configurations, which are not defaults |
| Register description | Every module with registers has a description file (`hdl/<module>/regs/`) from which `tools/regmap.py` generates the VHDL package, the register map and the C header, and which it compares with the table of the specification; the modules get it with their RTL |
