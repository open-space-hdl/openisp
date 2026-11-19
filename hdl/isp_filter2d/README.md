# isp_filter2d

`isp_filter2d` is the general 2D window filter of OpenISP: a pixel stream in, a pixel stream out, and between them
the weighted sum of the neighbourhood of every reference pixel. It consists of [`isp_window`](../isp_window/README.md)
and [`isp_conv`](../isp_conv/README.md) and adds no logic of its own. An MTF compensation filter is this module with
the size and the coefficients of its kernel.

| Document | Content |
| --- | --- |
| [Specification](docs/specification.md) | Requirements, generics, use as an MTF filter |
| [Architecture](docs/architecture.md) | Blocks, ports, connection, timing |

The verification plan and the verification report follow with the development of the module.
