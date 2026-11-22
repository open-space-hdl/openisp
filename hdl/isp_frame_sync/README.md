# isp_frame_sync

`isp_frame_sync` is the input side of every module of OpenISP. It takes a pixel stream in any division into
stream packets, possibly malformed, and delivers complete images of `ImageWidth_g` x `ImageHeight_g` pixels with
one stream packet per line and the position of every pixel. Images that are too short are completed with
zeros, pixels that belong to no image are discarded, and every deviation is reported. Used on its own it
normalises the stream in front of a chain. It has no memory.

| Document | Content |
| --- | --- |
| [Specification](docs/specification.md) | Requirements, error conditions, generics |
| [Architecture](docs/architecture.md) | Blocks, ports, state machine, timing |
| [Verification plan](docs/verification_plan.md) | Bench, configurations, test cases, timing bounds, mutations |
| [Verification report](docs/verification_report.md) | Results, generic coverage, mutations, synthesis and timing |

## Tests

Prerequisites: those of the repository (GHDL, the Python packages of `requirements.txt`, the submodules).

```shell
python run.py -p 4 "*isp_frame_sync*"            # all tests in all configurations
python run.py -v "*isp_frame_sync_tb.w5_h4_p12.test_reset"   # one test with its log
```

| File | Content |
| --- | --- |
| `src/isp_frame_sync.vhd` | The module |
| `tb/isp_frame_sync_tb.vhd` | Testbench: the module, the shared source and sink, the count of the `Err_Framing` pulses, the monitor of the control outputs, the timing checks of test_rate |
| `tb/vunit_config.py` | Configurations and the stimulus of every test; runs the reference model `frame_sync` of `tools/isp_model.py` |

The shared components (`tb/isp_tb_source.vhd`, `tb/isp_tb_sink.vhd`, `tools/isp_model.py`, `tools/isp_tbgen.py`)
are described in the [testbench components](../../docs/testbench.md).
