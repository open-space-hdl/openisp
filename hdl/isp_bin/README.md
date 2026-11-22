# isp_bin

`isp_bin` is the binning of OpenISP: it outputs the sum of the pixels of every bin of `BinX_g` x `BinY_g` pixels as
one pixel. It consists of two [`isp_filter2d`](../isp_filter2d/README.md) in series, one that adds along the line
and one that adds lines of the narrowed image, and adds no logic of its own. An incomplete bin at the edge is
dropped or completed, as the border mode says.

| Document | Content |
| --- | --- |
| [Specification](docs/specification.md) | Requirements, generics, configuration of the two filters |
| [Architecture](docs/architecture.md) | Blocks, ports, connection, timing |
| [Verification plan](docs/verification_plan.md) | Bench, configurations, test cases, timing bounds, mutations |
| [Verification report](docs/verification_report.md) | Results, generic coverage, mutations, synthesis and timing |

## Tests

Prerequisites: those of the repository (GHDL, the Python packages of `requirements.txt`, the submodules).

```shell
python run.py -p 4 "*isp_bin*"                                   # all tests in all configurations
python run.py -v "*isp_bin_tb.rate_tall.test_rate"               # one test with its log
```

| File | Content |
| --- | --- |
| `src/isp_bin.vhd` | The module: the horizontal and the vertical `isp_filter2d` with coefficients of 1, a filter of factor 1 left out, the frame sync alone for 1 x 1 |
| `tb/isp_bin_tb.vhd` | Testbench: the module, the shared source and sink, the injection script for the line buffers of the vertical filter, the counts of the status pulses, the monitor of the control outputs and of the output pixels, and the timing checks of test_rate |
| `tb/vunit_config.py` | Configurations, the pixel stream and the injection script of every test; runs the reference model `bin_model` of `tools/isp_model.py` (the definition of a bin, and the two filters in series for the pulse counts, `Stat_ImageOpen`, the timing and the injection) |

The shared components (`tb/isp_tb_source.vhd`, `tb/isp_tb_sink.vhd`, `tb/isp_tb_inject.vhd`, `tools/isp_model.py`,
`tools/isp_tbgen.py`) are described in the [testbench components](../../docs/testbench.md).
