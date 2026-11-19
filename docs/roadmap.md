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
| `isp_window` | 2D window generator: one WinX x WinY neighbourhood per pixel of a raster stream, with border handling; the front end of every 2D stage | Phase A (requirements) done; phase B (architecture) |

The later stages (black level, defect pixel correction, flat-field correction, demosaicing, colour correction,
binning, statistics, filters) and their order are planned in the architecture document.
