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

The verification plan and the verification report follow with the development of the module.
