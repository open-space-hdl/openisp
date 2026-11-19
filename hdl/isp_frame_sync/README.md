# isp_frame_sync

`isp_frame_sync` is the input side of every module of OpenISP. It takes a pixel stream in any division into
stream packets, possibly malformed, and delivers complete images of `ImageWidth_g` x `ImageHeight_g` pixels with
one stream packet per line and the position of every pixel. Images that are too short are completed with
zeros, pixels that belong to no image are discarded, and every deviation is reported. Used on its own it
normalises the stream in front of a chain. It has no memory.

| Document | Content |
| --- | --- |
| [Specification](docs/specification.md) | Requirements, error conditions, generics |
| [Architecture](docs/architecture.md) | Blocks, ports, state machine, timing |

The verification plan and the verification report follow with the development of the module.
