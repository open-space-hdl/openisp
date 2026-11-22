# Changelog

The notable changes of OpenISP. The versions follow semantic versioning: 0.y.z while the core is at TRL 3, a major
version for an incompatible change of ports, stream formats or generics, a minor version for a feature and a patch
version for a fix.

## [Unreleased]

## [0.1.0] - 2026-11-21

The first release: eight modules and the shared package, each through the phases A to G, verified by simulation.

### Added

- `isp_pkg`: sequence flags, position width, image start, the output widths and dimensions of the modules, the parity
  bit of a register write (fail-safe partial writes).
- `isp_frame_sync`: the input side of every module: any division of an image into packets in, complete images with
  one packet per line and pixel positions out; malformed streams completed or discarded and reported.
- `isp_crop`: region of interest, its position by generics or at run time (register with parity).
- `isp_point`: offset, gain, bit shift and clamp between two thresholds, by generics or at run time (`CTRL.HOLD`,
  parity of every register).
- `isp_window`: the neighbourhood generator: line buffers with SECDED ECC, border modes, anchor and stride.
- `isp_conv`: the linear kernel at full precision, coefficients by a generic or at run time.
- `isp_filter2d`: `isp_window` and `isp_conv` in one entity, for example an MTF filter.
- `isp_bin`: binning as two window filters with a stride.
- `isp_replace`: replacement of non-operational pixels by 1D interpolation, with a scrubbed defect map of one bit per
  pixel configurable at run time.
- The chain test `isp_chain` (phase G): three chains of the modules against the composition of their reference models.
- Verification: VUnit and UVVM testbenches with a Python reference model for every module, mutation runs of every
  module, the code coverage of the QuestaSim regression (`docs/coverage.md`), the compliance matrix, the register map
  generator, the port traces of `run.py --port-trace` and `tools/trace_compare.py`, the pull-request test tier of the
  CI.
- Timing: the preliminary synthesis of every configuration on PolarFire MPF100T at 125 MHz (`lint/libero_synth.py`).
- Repository skeleton: VUnit regression runner, VSG lint, synthesis check, compliance matrix generator, CI and
  documentation workflows, Open Logic 4.8.0-ft.2 and UVVM as submodules.
