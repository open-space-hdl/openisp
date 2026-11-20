# isp_chain

`isp_chain` is the chain test of OpenISP (phase G): it connects the modules as the user guide describes and verifies
the chain against the composition of their reference models, so that every connection between two modules is crossed
by a test. It has no RTL of its own. The chains are `typical` (`isp_replace`, `isp_point`, `isp_crop`, `isp_filter2d`,
`isp_bin`, `isp_point`), `small` (the same order at the low bounds of the generics) and `reordered` (`isp_bin`,
`isp_filter2d`, `isp_crop`, `isp_point`).

| Document | Content |
| --- | --- |
| [Specification](docs/specification.md) | Requirements on a chain of modules |
| [Verification plan](docs/verification_plan.md) | Chains, bench, test cases, the derivations of the timing, the FIFO and the release of run-time sets |
| [Verification report](docs/verification_report.md) | Results, measured timing, synthesis, findings |

## Tests

Prerequisites: those of the repository (GHDL, the Python packages of `requirements.txt`, the submodules).

```shell
python run.py -p 4 "*isp_chain*"                                 # all tests of the three chains
python run.py -v "*isp_chain_tb.typical.test_rate"               # one test with its log
```

| File | Content |
| --- | --- |
| `tb/isp_chain_tb.vhd` | Testbench: the modules of a chain with the generics through `isp_pkg`, the shared source and sink, a contract monitor on every connection, an AXI4-Lite decoder with one slot per module, the injection scripts of the ECC ports, the module reset script, the pulse counters, an `olo_ft_ecc_monitor`, an `olo_ft_fifo_sync` in front of the chain for the FIFO tests, and the timing checks of test_rate |
| `tb/vunit_config.py` | Chains, the pixel stream and the scripts of every test, the design values of the timing and of the FIFO; runs the composed model `chain` of `tools/isp_model.py` |
| `../../lint/isp_chain_synth.vhd` | The chains `typical` and `reordered` as one netlist each for `lint/synth_check.py` |

The shared components (`tb/isp_tb_source.vhd`, `tb/isp_tb_sink.vhd`, `tb/isp_tb_monitor.vhd`, `tb/isp_tb_inject.vhd`,
`tools/isp_model.py`, `tools/isp_tbgen.py`) are described in the [testbench components](../../docs/testbench.md).
