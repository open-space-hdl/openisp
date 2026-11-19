# isp_crop

`isp_crop` selects a rectangular region of interest of an image: it takes the pixel stream of an image of
`ImageWidth_g` x `ImageHeight_g` pixels and outputs the region set by `RoiX_g`, `RoiY_g`, `RoiWidth_g` and
`RoiHeight_g` as an image of its own. It has no memory. With a region equal to the image it normalises a stream: any
division into packets becomes one packet per line, and malformed images are completed or discarded.

| Document | Content |
| --- | --- |
| [Specification](docs/specification.md) | Requirements, error conditions, generics |

The architecture, the verification plan and the verification report follow with the development of the module.
