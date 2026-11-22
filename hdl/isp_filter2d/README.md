# isp_filter2d

`isp_filter2d` is the general 2D window filter of OpenISP: a pixel stream in, a pixel stream out, and between them
the weighted sum of the neighbourhood of every reference pixel. It consists of [`isp_window`](../isp_window/README.md)
and [`isp_conv`](../isp_conv/README.md) and adds no logic of its own. An MTF compensation filter is this module with
the size and the coefficients of its kernel.

| Document | Content |
| --- | --- |
| [Specification](docs/specification.md) | Requirements, generics, use as an MTF filter |
| [Architecture](docs/architecture.md) | Blocks, ports, connection, timing |
| [Verification plan](docs/verification_plan.md) | Bench, configurations, test cases, timing bounds, mutations |
| [Verification report](docs/verification_report.md) | Results, generic coverage, mutations, synthesis and timing |

The registers are those of `isp_conv` ([register map](../isp_conv/docs/register_map.md)).

## Tests

Prerequisites: those of the repository (GHDL, the Python packages of `requirements.txt`, the submodules).

```shell
python run.py -p 4 "*isp_filter2d*"                              # all tests in all configurations
python run.py -v "*isp_filter2d_tb.mtf3.test_errors"             # one test with its log
```

| File | Content |
| --- | --- |
| `src/isp_filter2d.vhd` | The module: an `isp_window` whose window stream feeds an `isp_conv` |
| `tb/isp_filter2d_tb.vhd` | Testbench: the module (or two in series for a separable kernel) with the coefficient sets as strings (`ispIntList`), the shared source and sink, the register script on the AXI4-Lite BFM of UVVM, the injection script for the line buffers, the counts of the status pulses, the monitor of the control outputs and of the output pixels, and the timing checks of test_rate |
| `tb/vunit_config.py` | Configurations, the pixel stream, the register script and the injection script of every test; runs the reference model `filter2d` of `tools/isp_model.py` (the model `window` into the kernel of the model `conv`) |
| `../../lint/isp_filter2d_synth.vhd` | Wrapper for `lint/synth_check.py`: builds the coefficient set from integer generics, which GHDL can set on the command line |

The shared components (`tb/isp_tb_source.vhd`, `tb/isp_tb_sink.vhd`, `tb/isp_tb_inject.vhd`,
`tb/isp_tb_axilite_pkg.vhd`, `tools/isp_model.py`, `tools/isp_tbgen.py`) are described in the
[testbench components](../../docs/testbench.md).
