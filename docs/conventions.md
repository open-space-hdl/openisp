# OpenISP Conventions

OpenISP follows the coding conventions of Open Logic and the module development process of ECSS-E-ST-20-40C. This
page lists the rules and the few OpenISP-specific additions.

## VHDL coding

- The [Open Logic coding conventions](../open-logic/doc/Conventions.md) apply in full: port names
  `<Interface>_<Signal>`, generics `_g`, constants `_c`, variables `_v`, types `_t`, FSM types `<Name>Fsm_t` with
  states `_s`, functions in `lowerCamelCase`, four spaces of indentation, no tabs, no trailing whitespace.
- Entities are named `isp_<function>` with full words (for example `isp_crop`). All OpenISP sources are compiled
  into the VHDL library `openisp`; Open Logic is compiled into the library `olo`.
- Language: VHDL-2008.
- Entities with non-trivial state use the two-process pattern of Open Logic: all registers in one `TwoProcess_r`
  record, signals `r` and `r_next`, a combinational process starting with `v := r;` and ending with
  `r_next <= v;`, a sequential process with `r <= r_next;` and the reset override at its end.
- A subprogram declared in a combinational process (`process (all)`) reads signals only through its parameters.
  Simulators differ in whether a signal that only such a subprogram reads is part of the sensitivity list; the
  process then misses its changes in one simulator and not in the other.
- A loop does not update the elements of one vector variable in place over many iterations: an elaborator follows the
  chain of partial updates recursively and can exhaust its stack. Each element is computed in a scalar and written
  once.
- A record field that is an array of arrays uses a fully constrained array type
  (`type T is array (0 to N - 1) of E`), not an index constraint on an unconstrained array type.
- Resets are synchronous and high-active. Only state registers are reset; after the reset, addresses, control
  signals and output ports are defined (no metavalues). Every module has one clock domain `Clk` unless its
  specification says otherwise.
- Every data path between blocks is a valid / ready stream (AXI4-Stream handshake semantics) or a valid-only stream
  of one-cycle events where the receiver is never slower than the source. The pixel stream (one pixel per beat,
  stream packets with sequence flags, image dimensions as generics) is defined in the
  [requirements specification](requirements.md) and is the same for every module.
- Standard functions (FIFOs, RAMs, crossings, synchronisers, arbiters, pipeline stages) are instantiated from Open
  Logic, never rewritten. FIFOs and RAMs are the fault-tolerant `olo_ft_*` entities; every crossing, reset generator
  and input synchroniser is instantiated with `SyncTmr_g => true`.
- State machines have a `when others` branch that returns to a defined recovery state; the reset leads to that state
  from any state. Counters that address a line or a frame recover from any value.
- File header: copyright line and authors, then a 1 to 2 sentence description that links to the module
  documentation. Never write "all rights reserved".
- Never use em-dashes in code, comments or documentation. Use UTF-8 only.
- VSG 3.27 with the Open Logic configuration in `lint/config` must report no errors and no warnings:
  `python lint/lint.py`. Safe automatic fixes: `python lint/lint.py --fix`.
- The design must be synthesizable in a technology-independent way: `python lint/synth_check.py` synthesises the
  module top levels with GHDL (after `python run.py --compile`) and fails on errors and inferred latches. `to_01` and
  other simulation-only functions are not used in RTL.
- `compile_order.txt` lists the synthesis sources in compile order. After adding, removing or renaming a source or
  changing the dependencies between sources, regenerate it with `python run.py --compile-order`; the CI fails when it
  is not current.

## Requirements and traceability

- No ECSS or CCSDS standard covers image signal processing. The reference of OpenISP is its own requirements
  specification `docs/requirements.md`: core requirements with IDs `ISP-<GROUP>-<NN>`, each a "shall" statement for
  the function of the core seen by its user.
- The requirement traceability matrix (architecture section 10) assigns every core requirement to the module that
  implements it, or marks it as planned or as an obligation of the user.
- Module requirements have IDs `<LAYER>-<GROUP>-<NN>` (for example `CRP-IF-01` for an interface requirement of
  `isp_crop`). The last column of a requirement table names the core requirements the requirement implements,
  or `none`.
- Every module requirement is verified by at least one test case of the verification plan, every core requirement
  in scope by the test cases of its module requirements, and every test case of a plan is run by a testbench.
  `python tools/compliance.py` writes the [compliance matrix](compliance.md); `python tools/compliance.py --check`
  fails on a gap.

## Module development process

Every module goes through seven phases:

| Phase | Output |
| --- | --- |
| A Requirements | `hdl/<module>/docs/specification.md`: requirements with IDs, each tracing to core requirements |
| B Architecture | `hdl/<module>/docs/architecture.md`: blocks, ports, state machines, data formats |
| C Verification plan | `hdl/<module>/docs/verification_plan.md`: test cases with IDs, requirement coverage |
| D RTL | `hdl/<module>/src/*.vhd` |
| E Testbenches | `hdl/<module>/tb/<entity>_th.vhd` (harness) and `<entity>_tb.vhd` (VUnit runner) |
| F Verification | Regression green, `hdl/<module>/docs/verification_report.md` |
| G Integration | Tests at the next level that cross every seam the module touches |

`hdl/<module>/README.md` links the four documents and explains how to run the tests.

## Diagrams

- Every architecture document has a block diagram; state machines and data formats have one where text alone is
  hard to follow.
- Diagrams are draw.io drawings stored as editable SVG with the drawing embedded (`<name>.drawio.svg`) in the `img/`
  folder next to the document. The SVG is the source: open it in draw.io to change it. It is exported with the light
  theme on an opaque white background, so that it reads in both colour schemes of the documentation site.
- Blocks: light blue for OpenISP logic, white with a blue outline for an OpenISP entity instantiated as a whole,
  light grey for an Open Logic entity, drawn inside the block that instantiates it. The title carries the building
  block ID of the architecture, the entity follows in grey.
- Connections: thick lines for streams and buses, thin lines for single signals. Every line is horizontal or
  vertical; a dot marks a branch, an arc marks a line that crosses another without a connection. Ports cross the
  frame of the entity, inputs on the left, outputs on the right where the layout allows.
- A diagram is at most about 1000 px wide, so that its text stays readable in the content column, and its alt text
  names the blocks it shows.

## Verification

- VUnit runs every test (`run.py`); UVVM supplies VVCs, BFMs, checks, randomisation and functional coverage.
- The harness (`_th`) contains clocks, reset, the DUT and the VVCs, the testbench (`_tb`) contains one
  `if run("<test id>") then` block per test case of the verification plan. The test IDs of the plan and the names
  in `run(...)` are identical.
- A test passes only when UVVM reports no unexpected alerts and every expected alert occurred
  (`isp_tb_pkg.ispTestEnd`). A negative test raises the stop limit with
  `increment_expected_alerts_and_stop_limit`.
- Tests observe ports and management interfaces only, never internal signals.
- Expected images come from Python reference models in `tools/`, which a module configuration runs before the
  simulation (`hdl/<module>/tb/vunit_config.py`). Tests never use the RTL, or functions of a package that the RTL
  uses, to compute expected values. Every output pixel of every frame is compared.
- Test images depend on every coordinate bit: a pattern that repeats with a short period hides addressing errors.
- GHDL is the default simulator; QuestaSim (`python run.py --questa`) is used for code coverage
  (`docs/coverage.md`). Every test passes in both simulators. QuestaSim runs at a time resolution of 1 fs,
  as GHDL.
- Every GHDL simulation gets its own copy of the option `ghdl.sim_flags`: VUnit 5.0.0.dev7 appends the generics of a
  test to the list of that option in place, so without the copy a test inherits the generics of earlier tests.
  `run.py` makes the copy and stops the run when a GHDL command does not carry exactly the generics of its
  configuration.
- Generic ranges are verified, not only declared: every value of a generic that changes the structure (widths,
  window sizes, enumerations, booleans) runs in the regression, and the bounds of every numeric range are elaborated
  and synthesised (`python lint/synth_check.py`). A value outside the declared range stops the elaboration (range
  constraint or assertion). The verification report of every module lists the declared range, the simulated and
  the synthesised values of its generics. A testbench clock follows a frequency generic of the design.
- A side effect is never obtained by calling an impure function and discarding its result: QuestaSim may remove such
  a call. Protected types offer a procedure for it.
- Negative tests inject the fault from the bench (framing errors on the input stream, single and double bit errors
  through the `ErrInj` ports of the Open Logic RAMs, at least one of them in a data bit) and expect the reaction and
  the status the specification defines.

## Continuous integration

- The workflow `CI` runs in two tiers:
  - A pull request into `develop` runs the tests of `pr_tests.txt` (`python run.py -p 4 --subset pr_tests.txt`).
  - The full regression runs on every push to `develop`, `main` and `release/*`, on pull requests into `main` and on
    a manual start of the workflow. A manual start runs the full regression on any branch, for a change that needs
    it before its merge.
- The tests of `pr_tests.txt` are a smoke test:
  - every test of every testbench, in at least one configuration;
  - at least one configuration at the low bound of every generic, and every value of a boolean or an enumeration;
  - not the high bounds of the image size (65536 pixels per line, 65536 lines) and not the long exhaustive
    configurations, which run in the full tier only.
  `python tools/ci_subset.py --check` checks the rules that a script can check, and the CI runs it before the
  tests. A new test or configuration of a module updates the list in the same pull request.
- The evidence for the merge of a module does not change: every module pull request reports the full local
  regression (`python run.py -p 4`, every test passed, none skipped) and the mutation run of its verification
  report. The CI of a pull request does not replace them.
- The other checks (VSG, compliance matrix, register maps, reference model tests, markdownlint, the compile order,
  the documentation build) run in full on every pull request.

## Git

- `develop` holds the integrated state and `main` the released state. Every module or change is developed on a
  branch `feature/<module>` or `bugfix/<topic>` from `develop` and merged through a pull request once its CI is
  green. `main` receives only release and hotfix branches.
- Releases follow semantic versioning with tags `vX.Y.Z` on `main`: 0.y.z while the core is at TRL 3, a major version
  for an incompatible change of ports, stream formats or generics, a minor version for a feature and a patch version
  for a fix.
- Commit messages: imperative subject line, body explains what and why.
