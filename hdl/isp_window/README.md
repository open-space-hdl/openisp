# isp_window

`isp_window` is the 2D window generator of OpenISP: it takes a raster pixel stream and delivers, for every pixel, its
`WinX_g` x `WinY_g` neighbourhood as one flattened vector with the position of the centre pixel, with the border
modes valid, zero, replicate and mirror. It is the front end of every 2D stage of OpenISP. The previous lines are kept
in an ECC-protected line memory of Open Logic.

| Document | Content |
| --- | --- |
| [Specification](docs/specification.md) | Requirements, error conditions, generics, border modes |

The architecture, the verification plan and the verification report follow with the development of the module.
