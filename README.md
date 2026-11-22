# OpenISP

[![TRL 3](docs/img/trl-3.svg)](https://openspacehdl.org/trl/)

OpenISP is a suite of open image signal processing cores for spacecraft imagers, based on the Open Logic VHDL Library.
Every function of a processing chain (region of interest, pixel-level operations, 2D window filters, binning,
replacement of non-operational pixels) is a separate, generics-configured VHDL-2008 entity with valid / ready
pixel streams, so that a chain is assembled from the modules it needs, in any order. All memories and buffers use the
fault-tolerant entities of [Open Logic](https://github.com/open-logic/open-logic) (SECDED ECC, optional scrubbing),
every state machine recovers from any state, and the cores are vendor-independent.

No ECSS or CCSDS standard covers image signal processing. The reference of OpenISP is its own requirements
specification; the development follows ECSS-E-ST-20-40C.

## Status

**Version 0.1.0. Technology readiness level: TRL 3** (fully verified by simulation). Every module passes its testbench
against its Python reference model in GHDL and in QuestaSim (669 of 669 tests), with malformed streams, resets during
images, error injection into every ECC-protected memory and into the parity of the run-time parameters (`isp_crop`,
`isp_point`, `isp_conv`); the chain test connects the modules in three chains against the composition of their models.
Every module has a mutation run, and the code coverage is closed or every remaining miss is justified
([docs/coverage.md](docs/coverage.md)). The modules have not been tested on hardware and have no flight heritage; see
[what the levels mean](https://openspacehdl.org/trl/) and the steps to the next level in the
[roadmap](docs/roadmap.md#technology-readiness).

## Documentation

The documents are also published as a website: [openspacehdl.org/openisp](https://openspacehdl.org/openisp/)
(built from this repository by `tools/docs/`).

| Document | Content |
| --- | --- |
| [docs/user_guide.md](docs/user_guide.md) | Integration: sources, pixel stream, registers, building a chain, protection scope, integration constraints, conformance |
| [docs/architecture.md](docs/architecture.md) | Architecture of the suite: principles, decisions, Open Logic usage, verification, traceability matrix |
| [docs/requirements.md](docs/requirements.md) | Requirements specification: the pixel stream and the functions of the suite |
| [docs/conventions.md](docs/conventions.md) | Coding, verification and repository conventions |
| [docs/roadmap.md](docs/roadmap.md) | Technology readiness, module status and open items |
| [docs/compliance.md](docs/compliance.md) | Compliance matrix: module requirements and test cases of every core requirement (generated) |
| [docs/coverage.md](docs/coverage.md) | Code coverage of the QuestaSim regression: the results per module and the reason for every miss |
| `hdl/<module>/docs/` | Specification, architecture, verification plan and verification report of each module |

## Repository structure

```text
openisp/
|-- docs/             Top-level documentation
|-- hdl/<module>/     One folder per module: src/, tb/, docs/
|-- tb/               Verification components shared by the testbenches
|-- lint/             VSG configuration (Open Logic rules), synthesizability check
|-- tools/            Compliance matrix generator
|   `-- docs/         Documentation website (MkDocs)
|-- open-logic/       Git submodule: Open Logic (fault-tolerant entities branch)
|-- uvvm/             Git submodule: UVVM verification framework
|-- component_list.txt  Modules in dependency order
|-- compile_order.txt   Synthesis sources in compile order (generated)
|-- pr_tests.txt      Tests of the pull-request CI (VUnit patterns)
`-- run.py            VUnit regression runner
```

## Running the tests

Prerequisites: Python 3, [GHDL](https://github.com/ghdl/ghdl) on the `PATH` and the Python packages of
`requirements.txt` (VUnit, VSG).

```shell
git submodule update --init
python -m pip install -r requirements.txt
python run.py -p 4              # full regression with GHDL, 4 parallel simulations
python run.py -p 4 --subset pr_tests.txt  # the tests of the pull-request CI
python run.py "*isp_crop*"      # one module
python run.py --questa <test>   # QuestaSim
```

`run.py` compiles Open Logic into the VHDL library `olo`, the required UVVM components into their own libraries and
all OpenISP sources into the library `openisp`. `ISP_GHDL_SIM_FLAGS` passes extra flags to the GHDL simulation, for
example `--vcd=wave.vcd` for a waveform.

A change of the RTL that must keep every cycle is shown with port traces: `python run.py --port-trace` writes a VCD of
the signals at the top level of the testbench for every test, in two worktrees of the commits before and after the
change, and `python tools/trace_compare.py <tree A> <tree B>` compares them test by test.

Checks besides the regression:

```shell
python lint/lint.py                 # VSG, no errors and no warnings
python lint/synth_check.py          # synthesizability of the module top levels with GHDL
python lint/libero_synth.py --out syn fsy_max # resources and estimated timing at 125 MHz on PolarFire (Libero)
python tools/compliance.py --check  # every core requirement and module requirement traced to a test case
python run.py --compile-order       # regenerates compile_order.txt (the CI fails when it is not current)
python tools/ci_subset.py --check   # the rules of the pull-request test list pr_tests.txt
python -m mkdocs build -f tools/docs/mkdocs.yml  # documentation website, fails on broken links
python -m pytest -q tools/tests       # unit tests of the reference model
```

## Licence

OpenISP is licensed under the [PSI HDL Library License, Version 1.0](License.txt), the licence of Open Logic
(LGPL 2.1 with an exception for binaries, see [LGPL2_1.txt](LGPL2_1.txt)).
