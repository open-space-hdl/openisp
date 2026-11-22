# isp_pkg

`isp_pkg` holds the definitions that several OpenISP modules share: the sequence flags of the pixel stream, the width
of a pixel position and the detection of an image start.

| Document | Content |
| --- | --- |
| [Specification](docs/specification.md) | Requirements |
| [Architecture](docs/architecture.md) | Contents of the package |
| [Verification plan](docs/verification_plan.md) | Test cases |
| [Verification report](docs/verification_report.md) | Results |

## Tests

```shell
python run.py "*isp_pkg*"
```

| File | Content |
| --- | --- |
| `src/isp_pkg.vhd` | The package |
| `tb/isp_pkg_tb.vhd` | Testbench: the constants and functions against values computed in another way |
