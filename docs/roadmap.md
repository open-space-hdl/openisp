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
| `isp_frame_sync` | Input side of every module: any division of an image into packets in, complete images with one packet per line and pixel positions out | Phase B (architecture) |
| `isp_crop` | Region of interest: crops an image to a rectangle of a size set by generics, at a position set by generics or at run time | Phase B (architecture) |
| `isp_point` | Pixel-level operation: offset, gain, bit shift and clamp between two thresholds, set by generics or at run time | Phase B (architecture) |
| `isp_window` | Neighbourhood generator: one window per pixel, line buffers, border modes, stride | Planned |
| `isp_conv`, `isp_filter2d` | Linear kernel on a window; the general 2D window filter (for example an MTF filter) with coefficients configurable at run time | Planned |
| `isp_bin` | Binning: two 1D window filters with a stride | Planned |
| `isp_replace` | Replacement of non-operational pixels by 1D interpolation, with a defect map configurable at run time | Planned |

All modules share the pixel stream of the [requirements specification](requirements.md), so they connect in any
order.
