# isp_window

`isp_window` delivers the neighbourhood of the pixels of an image: for every reference pixel one window of `WinX_g` x
`WinY_g` pixels as one vector, with the border modes valid, zero, replicate and mirror, a free anchor and a stride.
The lines above the current one are kept in ECC-protected line buffers of Open Logic. It is the front end of the
linear filter, the binning and the replacement of non-operational pixels. Its input is an
[`isp_frame_sync`](../isp_frame_sync/README.md).

| Document | Content |
| --- | --- |
| [Specification](docs/specification.md) | Requirements, error conditions, generics, border modes |
| [Architecture](docs/architecture.md) | Blocks, ports, events, line buffers, borders, timing |
| [Verification plan](docs/verification_plan.md) | Bench, configurations and sweeps, test cases, timing bounds, mutations |
| [Verification report](docs/verification_report.md) | Results, generic coverage, mutations, synthesis and timing |

## Tests

Prerequisites: those of the repository (GHDL, the Python packages of `requirements.txt`, the submodules).

```shell
python run.py -p 4 "*isp_window*"                                # all tests in all configurations
python run.py -v "*isp_window_tb.mirror5.test_static"            # one test with its log
```

| File | Content |
| --- | --- |
| `src/isp_window.vhd` | The module |
| `tb/isp_window_tb.vhd` | Testbench: the module, the shared source, sink and injection script, the counts of the `Err_Framing`, `Stat_EccSec` and `Stat_EccDed` pulses, the monitor of the control outputs and the windows, the rate checks of test_rate |
| `tb/vunit_config.py` | Configurations, sweeps, the stimulus and the injection script of every test; runs the reference model `window` of `tools/isp_model.py` |

The shared components (`tb/isp_tb_source.vhd`, `tb/isp_tb_sink.vhd`, `tb/isp_tb_inject.vhd`, `tools/isp_model.py`,
`tools/isp_tbgen.py`) are described in the [testbench components](../../docs/testbench.md).
