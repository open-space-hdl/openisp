# isp_crop

`isp_crop` selects a rectangular region of interest of an image: it takes the pixel stream of an image of
`ImageWidth_g` x `ImageHeight_g` pixels and outputs a region of `RoiWidth_g` x `RoiHeight_g` pixels as an image of
its own. The position of the region is set by generics or, as an option, by configuration ports at run time. Its
input is an [`isp_frame_sync`](../isp_frame_sync/README.md). It has no memory.

| Document | Content |
| --- | --- |
| [Specification](docs/specification.md) | Requirements, error conditions, generics |

The architecture, the verification plan and the verification report follow with the development of the module.
