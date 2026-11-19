# isp_replace

`isp_replace` replaces the non-operational pixels of an image: a defect map with one bit per pixel marks them, and
every marked pixel is replaced by an interpolation between the nearest operational pixels of the same line. The
defect map is an ECC-protected, scrubbed table that the software writes through an AXI4-Lite slave. The module is
built from [`isp_frame_sync`](../isp_frame_sync/README.md), an [`isp_window`](../isp_window/README.md) of one line
and an interpolation kernel.

| Document | Content |
| --- | --- |
| [Specification](docs/specification.md) | Requirements, error conditions, generics, register map |
| [Architecture](docs/architecture.md) | Blocks, ports, map lookup, interpolation, timing |

The verification plan and the verification report follow with the development of the module.
