# isp_point

`isp_point` is the pixel-level operation of OpenISP: it adds a signed offset to every pixel, multiplies by an unsigned
gain, shifts the product right and clamps the result between a lower and an upper threshold. The parameters are set
by generics or, as an option, by registers on an AXI4-Lite slave at run time. Its input is an
[`isp_frame_sync`](../isp_frame_sync/README.md). It has no memory.

| Document | Content |
| --- | --- |
| [Specification](docs/specification.md) | Requirements, error conditions, generics, register map |
| [Architecture](docs/architecture.md) | Blocks, ports, pipeline, parameter set, timing |

The verification plan and the verification report follow with the development of the module.
