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
| `isp_pkg` | Common types and functions: coefficient vector, output dimensions and pixel widths of the modules | Planned (with the first RTL) |
| `isp_frame_sync` | Input side of every module: any division of an image into packets in, complete images with one packet per line and pixel positions out | Phase B (architecture) |
| `isp_crop` | Region of interest: crops an image to a rectangle of a size set by generics, at a position set by generics or at run time | Phase B (architecture) |
| `isp_point` | Pixel-level operation: offset, gain, bit shift and clamp between two thresholds, set by generics or at run time | Phase B (architecture) |
| `isp_window` | Neighbourhood generator: one window per reference pixel, line buffers, border modes, anchor and stride | Phase B (architecture) |
| `isp_conv` | Linear kernel: the weighted sum of a window at full precision, coefficients set by a generic or at run time | Phase B (architecture) |
| `isp_filter2d` | The general 2D window filter: `isp_window` and `isp_conv` in one entity, for example an MTF filter | Phase B (architecture) |
| `isp_bin` | Binning: the sum of every bin of n x m pixels, two window filters with a stride | Phase B (architecture) |
| `isp_replace` | Replacement of non-operational pixels by 1D interpolation, with a defect map configurable at run time | Phase B (architecture) |

All modules share the pixel stream of the [requirements specification](requirements.md), so they connect in any
order.

## Open items

| Item | State |
| --- | --- |
| Release 0.1.0 | All modules through phases C to G; QuestaSim regression with code coverage on the release branch; the suite at TRL 3 |
| Marking of data errors | A pixel read from a line buffer with a double bit error is used as read and reported by `Stat_EccDed` (architecture, decision D12). A data-error sideband in the stream contract, which would mark the affected output pixels and images, is an option if a mission needs it |
| Run-time image dimensions | The dimensions are generics. Ports for the dimensions, with the generics as maxima, would land in `isp_frame_sync` and in the line buffers (`olo_ft_delay_cfg`); every module of a chain would need consistent settings |
| Defect list | The defect map of `isp_replace` has one bit per pixel. A list of the positions of the non-operational pixels needs less memory for a detector with few defects |
| Timing on PolarFire | The timing of every module is shown by an out-of-context run on the AMD Versal device of the reference systems. Runs on Microchip PolarFire are a later option |
| Register description | The register maps are tables in the module specifications. A description file per module with a generator of the VHDL package, the documentation and a C header follows with the RTL |
