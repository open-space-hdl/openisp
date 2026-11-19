# isp_crop: Specification

## 1. Overview

`isp_crop` selects a rectangular region of interest (ROI) of an image: it takes the pixel stream of an image of
`ImageWidth_g` x `ImageHeight_g` pixels and outputs the `RoiWidth_g` x `RoiHeight_g` pixels of the region whose top
left pixel is (`RoiX_g`, `RoiY_g`) as an image of its own. The position and the size of the region are generics.

The input of the module is an [`isp_frame_sync`](../../isp_frame_sync/docs/specification.md), which accepts any
division of the image into stream packets, completes or discards malformed images and delivers every pixel with its
position. `isp_crop` adds the selection: it forwards the pixels inside the region, discards the others and marks the
lines of the output image. The module has no memory.

### 1.1 Definitions

| Term | Definition |
| --- | --- |
| W, H | `ImageWidth_g`, `ImageHeight_g`: dimensions of the input image. |
| p(x, y) | Input pixel in column x (0 to W - 1) of line y (0 to H - 1). |
| ROI | The pixels with `RoiX_g` <= x < `RoiX_g` + `RoiWidth_g` and `RoiY_g` <= y < `RoiY_g` + `RoiHeight_g`. |
| Stream packet, sequence flags, image start | As in the [requirements specification](../../../docs/requirements.md), section 2. |

## 2. Requirements

### 2.1 Interfaces

| ID | Requirement | Core requirement |
| --- | --- | --- |
| CRP-IF-01 | The module shall take pixels on a valid / ready stream (`In_Valid`, `In_Ready`, `In_Data` of `PixelBits_g` bits) with AXI4-Stream handshake semantics, the end of a stream packet on `In_Last` and the sequence flags of the packet on `In_User` (2 bits). | ISP-STR-01, ISP-STR-02 |
| CRP-IF-02 | The module shall output pixels on a valid / ready stream (`Out_Valid`, `Out_Ready`, `Out_Data` of `PixelBits_g` bits) with AXI4-Stream handshake semantics, the end of a stream packet on `Out_Last` and the sequence flags of the packet on `Out_User` (2 bits). | ISP-STR-01, ISP-STR-02 |
| CRP-IF-03 | The module shall output the status of its `isp_frame_sync`: the pulse `Err_Framing` for every error of the input stream and the level `Stat_ImageOpen` while an input image is open. | ISP-STR-08, ISP-STR-10 |
| CRP-IF-04 | The module shall have one clock `Clk` and a synchronous, high-active reset `Rst`. | ISP-GEN-01 |

### 2.2 Function

| ID | Requirement | Core requirement |
| --- | --- | --- |
| CRP-FN-01 | For every input image the module shall output one image of `RoiWidth_g` x `RoiHeight_g` pixels whose pixel (x, y) is the input pixel p(`RoiX_g` + x, `RoiY_g` + y), unchanged, in raster order, each exactly once. | ISP-CRP-01, ISP-STR-03 |
| CRP-FN-02 | The module shall take its input through `isp_frame_sync` with the dimensions of the input image, so that the requirements of that module on the input stream (any division into packets, image start, malformed streams) hold for `isp_crop`. | ISP-STR-04, ISP-STR-08 |
| CRP-FN-03 | The module shall output every line of the output image as one stream packet: `Out_Last` with the last pixel of the line, and on every beat of the line the sequence flags "01" for the first line, "10" for the last line, "00" for the lines between and "11" for an output image of one line. | ISP-STR-05, ISP-STR-06 |
| CRP-FN-04 | The output shall not depend on the timing of the stream handshakes: any pattern of `In_Valid` and `Out_Ready` shall give the same output pixels and packets, without loss or duplication. | ISP-STR-07 |
| CRP-FN-05 | An image start may follow the last pixel of an image without a gap. | ISP-STR-07 |

### 2.3 Throughput and latency

| ID | Requirement | Core requirement |
| --- | --- | --- |
| CRP-PF-01 | With `In_Valid` and `Out_Ready` high, the module shall accept one pixel per clock cycle, also across the lines and from one image to the next. | ISP-STR-09 |
| CRP-PF-02 | With `Out_Ready` high, a pixel of the ROI shall be at the output at most 4 clock cycles after the module accepted it. | ISP-STR-09 |
| CRP-PF-03 | Pixels outside the ROI shall not wait for the consumer: while the output waits for `Out_Ready`, the module shall continue to accept input pixels up to the next pixel of the ROI. | ISP-STR-07 |

### 2.4 Error handling

| ID | Requirement | Core requirement |
| --- | --- | --- |
| CRP-ER-01 | Every output image shall be complete whatever the input: `RoiHeight_g` packets of `RoiWidth_g` pixels with the sequence flags of CRP-FN-03. The ROI pixels of an input image that `isp_frame_sync` completed are the pixels it delivered (value 0 for missing pixels). | ISP-STR-08 |
| CRP-ER-02 | The image after an error of the input stream shall be processed as if no error had occurred. | ISP-STR-08 |

### 2.5 Fault tolerance

| ID | Requirement | Core requirement |
| --- | --- | --- |
| CRP-FT-01 | The selection shall use the position that `isp_frame_sync` delivers with every pixel and keep no position of its own, so that an upset disturbs at most the image in progress and the module realigns with the next image start. | ISP-FT-04 |
| CRP-FT-02 | After the reset, `In_Ready`, `Out_Valid`, `Err_Framing` and `Stat_ImageOpen` shall be defined, and with defined input pixels every output beat shall be free of metavalues. | ISP-FT-04 |

The module has no memory, so the requirements on memories (ISP-FT-01 to ISP-FT-03) do not apply to it. Its registers
are flip-flops; their mitigation by triple modular redundancy is a choice of the integrator in the synthesis tool
(user guide, section "Protection scope").

### 2.6 Partner behaviour

The partners of the input are those of `isp_frame_sync` (its specification, section 2.6). The consumer of the output
may hold `Out_Ready` low at any beat.

## 3. Error conditions

The module has no error conditions of its own. The errors E1 to E4 of `isp_frame_sync` apply to its input stream;
`Err_Framing` reports them.

## 4. Configuration parameters

| Generic | Default | Range | Description |
| --- | --- | --- | --- |
| `ImageWidth_g` | none | 1 to 65536 | W: pixels per line of the input image |
| `ImageHeight_g` | none | 1 to 65536 | H: lines of the input image |
| `PixelBits_g` | none | 1 to 32 | Bits per pixel |
| `RoiX_g` | 0 | 0 to `ImageWidth_g` - 1 | Column of the first pixel of the ROI |
| `RoiY_g` | 0 | 0 to `ImageHeight_g` - 1 | Line of the first pixel of the ROI |
| `RoiWidth_g` | none | 1 to `ImageWidth_g` - `RoiX_g` | Pixels per line of the ROI and of the output image |
| `RoiHeight_g` | none | 1 to `ImageHeight_g` - `RoiY_g` | Lines of the ROI and of the output image |

Output image: `RoiWidth_g` x `RoiHeight_g` pixels of `PixelBits_g` bits.

## 5. Configuration checks

| ID | Requirement | Core requirement |
| --- | --- | --- |
| CRP-CF-01 | A generic outside its range of section 4 shall stop the elaboration with a message naming the generic. | ISP-CFG-01 |
| CRP-CF-02 | The module shall be synthesizable with GHDL for the bounds of every generic. | ISP-GEN-01 |
| CRP-CF-03 | The module shall be designed for 150 MHz on the FPGA families of the reference systems; synthesis results are recorded in the verification report. | ISP-GEN-03 |

## 6. Interpretation

- The region is static. A region set at run time is a later extension: configuration ports with defaults from the
  generics, effective at an image start (ISP-CFG-02).
- When `isp_frame_sync` completes a short image, the input waits for the missing pixels of the whole input image,
  not only for those of the region (its requirement FSY-PF-03).
