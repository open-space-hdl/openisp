# isp_conv

`isp_conv` is the linear kernel of OpenISP: it multiplies every pixel of a window of `isp_window` by a signed
coefficient and outputs the sum as one pixel, at full precision and with negative sums set to 0. The size of the
window is set by generics; the coefficients are set by a generic or, as an option, by registers on an AXI4-Lite
slave at run time. It has no memory.

| Document | Content |
| --- | --- |
| [Specification](docs/specification.md) | Requirements, error conditions, generics, register map |
| [Architecture](docs/architecture.md) | Blocks, ports, pipeline, coefficient set, timing |

The verification plan and the verification report follow with the development of the module.
