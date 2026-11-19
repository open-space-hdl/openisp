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
