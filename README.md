# OpenISP

OpenISP is a suite of open image signal processing cores for spacecraft imagers, based on the Open Logic VHDL Library.
Every stage of a pixel pipeline (border-aware 2D neighbourhoods, defect pixel correction, flat-field correction,
filters, demosaicing and others) is developed as a separate, generics-configured VHDL-2008 entity with valid / ready
pixel streams, so that a processing chain is assembled from the stages it needs. All memories and buffers use the
fault-tolerant entities of [Open Logic](https://github.com/open-logic/open-logic) (SECDED ECC, optional scrubbing),
every state machine recovers from any state, and the cores are vendor-independent.

No ECSS or CCSDS standard covers image signal processing. The reference of OpenISP is its own requirements
specification; the development follows ECSS-E-ST-20-40C.

## Status

**In development.** No module is verified yet. The first module is the 2D window generator, the front end of every
later 2D stage. The [roadmap](docs/roadmap.md) lists the modules and their state.

## Documentation

The documents are also published as a website: [openspacehdl.org/openisp](https://openspacehdl.org/openisp/)
(built from this repository by `tools/docs/`).

| Document | Content |
| --- | --- |
| [docs/conventions.md](docs/conventions.md) | Coding, verification and repository conventions |
| [docs/roadmap.md](docs/roadmap.md) | Technology readiness, module status and open items |
| [docs/compliance.md](docs/compliance.md) | Compliance matrix: module requirements and test cases of every core requirement (generated) |
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
`-- run.py            VUnit regression runner
```

## Running the tests

Prerequisites: Python 3, [GHDL](https://github.com/ghdl/ghdl) on the `PATH` and the Python packages of
`requirements.txt` (VUnit, VSG).

```shell
git submodule update --init
python -m pip install -r requirements.txt
python run.py -p 4              # full regression with GHDL, 4 parallel simulations
python run.py "*isp_window*"    # one module
python run.py --questa <test>   # QuestaSim
```

`run.py` compiles Open Logic into the VHDL library `olo`, the required UVVM components into their own libraries and
all OpenISP sources into the library `openisp`. `ISP_GHDL_SIM_FLAGS` passes extra flags to the GHDL simulation, for
example `--vcd=wave.vcd` for a waveform.

Checks besides the regression:

```shell
python lint/lint.py                 # VSG, no errors and no warnings
python lint/synth_check.py          # synthesizability of the module top levels with GHDL
python tools/compliance.py --check  # every core requirement and module requirement traced to a test case
python run.py --compile-order       # regenerates compile_order.txt (the CI fails when it is not current)
python -m mkdocs build -f tools/docs/mkdocs.yml  # documentation website, fails on broken links
```

## Licence

OpenISP is licensed under the [PSI HDL Library License, Version 1.0](License.txt), the licence of Open Logic
(LGPL 2.1 with an exception for binaries, see [LGPL2_1.txt](LGPL2_1.txt)).
