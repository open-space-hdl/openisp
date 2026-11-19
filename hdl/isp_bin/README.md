# isp_bin

`isp_bin` is the binning of OpenISP: it outputs the sum of the pixels of every bin of `BinX_g` x `BinY_g` pixels as
one pixel. It consists of two [`isp_filter2d`](../isp_filter2d/README.md) in series, one that adds along the line
and one that adds lines of the narrowed image, and adds no logic of its own. An incomplete bin at the edge is
dropped or completed, as the border mode says.

| Document | Content |
| --- | --- |
| [Specification](docs/specification.md) | Requirements, generics, configuration of the two filters |
| [Architecture](docs/architecture.md) | Blocks, ports, connection, timing |

The verification plan and the verification report follow with the development of the module.
