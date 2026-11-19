# isp_crop: Specification

## 1. Overview

`isp_crop` selects a rectangular region of interest (ROI) of an image: it takes the pixel stream of an image of
`ImageWidth_g` x `ImageHeight_g` pixels and outputs the `RoiWidth_g` x `RoiHeight_g` pixels of the region whose top
left pixel is (`RoiX_g`, `RoiY_g`) as an image of its own. The position and the size of the region are generics. The
module has no memory: it counts the pixels of the input image, forwards those inside the region and discards the
others.

It is the smallest module of the suite and implements the pixel stream of the
[requirements specification](../../../docs/requirements.md) (section 3.1) completely: any division of the input
image into stream packets, one packet per line at the output, and the handling of streams that deviate from the
dimensions.

### 1.1 Definitions

| Term | Definition |
| --- | --- |
| W, H | `ImageWidth_g`, `ImageHeight_g`: dimensions of the input image. |
| p(x, y) | Input pixel in column x (0 to W - 1) of line y (0 to H - 1); pixel number n = y x W + x in the order of arrival. |
| ROI | The pixels with `RoiX_g` <= x < `RoiX_g` + `RoiWidth_g` and `RoiY_g` <= y < `RoiY_g` + `RoiHeight_g`. |
| Stream packet, sequence flags, image start | As in the requirements specification, section 2. |
| Image open | From an accepted image start until pixel W x H - 1 has been taken, from the input or as a missing pixel (section 3). |

## 2. Requirements

### 2.1 Interfaces

| ID | Requirement | Core requirement |
| --- | --- | --- |
| CRP-IF-01 | The module shall take pixels on a valid / ready stream (`In_Valid`, `In_Ready`, `In_Data` of `PixelBits_g` bits) with AXI4-Stream handshake semantics, the end of a stream packet on `In_Last` and the sequence flags of the packet on `In_User` (2 bits). | ISP-STR-01, ISP-STR-02 |
| CRP-IF-02 | The module shall output pixels on a valid / ready stream (`Out_Valid`, `Out_Ready`, `Out_Data` of `PixelBits_g` bits) with AXI4-Stream handshake semantics, the end of a stream packet on `Out_Last` and the sequence flags of the packet on `Out_User` (2 bits). | ISP-STR-01, ISP-STR-02 |
| CRP-IF-03 | The module shall pulse `Err_Framing` for one clock cycle for every error of section 3. | ISP-STR-08 |
| CRP-IF-04 | The module shall have one clock `Clk` and a synchronous, high-active reset `Rst`. | ISP-GEN-01 |

### 2.2 Function

| ID | Requirement | Core requirement |
| --- | --- | --- |
| CRP-FN-01 | For every input image the module shall output one image of `RoiWidth_g` x `RoiHeight_g` pixels whose pixel (x, y) is the input pixel p(`RoiX_g` + x, `RoiY_g` + y), unchanged, in raster order, each exactly once. | ISP-CRP-01, ISP-STR-03 |
| CRP-FN-02 | The module shall start an image with every image start and locate the pixels by counting from it; the division of the input image into stream packets shall not change the output. | ISP-STR-04, ISP-STR-08 |
| CRP-FN-03 | The module shall output every line of the output image as one stream packet: `Out_Last` with the last pixel of the line, and on every beat of the line the sequence flags "01" for the first line, "10" for the last line, "00" for the lines between and "11" for an output image of one line. | ISP-STR-05, ISP-STR-06 |
| CRP-FN-04 | The output shall not depend on the timing of the stream handshakes: any pattern of `In_Valid` and `Out_Ready` shall give the same output pixels and packets, without loss or duplication. | ISP-STR-07 |
| CRP-FN-05 | An image start may follow the last pixel of an image without a gap. | ISP-STR-07 |
| CRP-FN-06 | After the reset, the module shall discard input pixels up to the first image start and then process that image. | ISP-STR-08, ISP-FT-04 |

### 2.3 Throughput and latency

| ID | Requirement | Core requirement |
| --- | --- | --- |
| CRP-PF-01 | With `In_Valid` and `Out_Ready` high, the module shall accept one pixel per clock cycle, also across the lines and from one image to the next. | ISP-STR-09 |
| CRP-PF-02 | With `Out_Ready` high, a pixel of the ROI shall be at the output at most 2 clock cycles after the module accepted it. | ISP-STR-09 |
| CRP-PF-03 | Pixels outside the ROI shall not wait for the consumer: while the output waits for `Out_Ready`, the module shall continue to accept input pixels up to the next pixel of the ROI. | ISP-STR-07 |

### 2.4 Error handling

| ID | Requirement | Core requirement |
| --- | --- | --- |
| CRP-ER-01 | An image start while an image is open shall complete the open image: its missing pixels shall be taken as pixels of value 0, so that the output image is complete; the new image shall then start with the pixel of the image start (E1). | ISP-STR-08 |
| CRP-ER-02 | Pixels while no image is open, other than an image start, shall be discarded (E2). | ISP-STR-08 |
| CRP-ER-03 | Pixel W x H - 1 of an image that is not the last beat of a stream packet with the sequence flags "10" or "11" shall end the image all the same (E3); a stream packet with the sequence flags "10" or "11" that ends before pixel W x H - 1 shall not end the image (E4). | ISP-STR-08 |
| CRP-ER-04 | Every output image shall be complete whatever the input: `RoiHeight_g` packets of `RoiWidth_g` pixels with the sequence flags of CRP-FN-03. | ISP-STR-08 |
| CRP-ER-05 | The image after an error shall be processed as if no error had occurred. | ISP-STR-08 |

### 2.5 Fault tolerance

| ID | Requirement | Core requirement |
| --- | --- | --- |
| CRP-FT-01 | Every state machine and counter of the module shall return to a defined state from any state; an upset of a register shall disturb at most the image in progress, and the module shall realign with the next image start. | ISP-FT-04 |
| CRP-FT-02 | After the reset, `In_Ready`, `Out_Valid` and `Err_Framing` shall be defined, and with defined input pixels every output beat shall be free of metavalues. | ISP-FT-04 |

The module has no memory, so the requirements on memories (ISP-FT-01 to ISP-FT-03) do not apply to it. Its counters
and registers are flip-flops; their mitigation by triple modular redundancy is a choice of the integrator in the
synthesis tool (user guide, section "Protection scope").

### 2.6 Partner behaviour

The input comes from a source outside the suite or from another module of the suite.

- A source outside the suite, for example the receiving end of a packet link, delivers an image as stream packets
  whose boundaries follow the packets of the link, not the lines of the image. It marks the first and the last packet
  of an image with the sequence flags. After a fault of the link a packet can be missing, so that an image is too
  short, or the first packet can be missing, so that pixels arrive without an image start (section 3).
- A module of the suite delivers one packet per line and only complete images.

Both may pause at any beat and may send images back to back. The consumer of the output may hold `Out_Ready` low at
any beat.

| ID | Requirement | Core requirement |
| --- | --- | --- |
| CRP-PB-01 | The module shall accept `In_Valid` low at any beat and stream packets of any length from one pixel upwards, also packets that span several lines or a whole image. | ISP-STR-04, ISP-STR-07 |

## 3. Error conditions

The first beat after the reset and every beat after a beat with `In_Last` is the first beat of a stream packet. The
sequence flags are evaluated at the first beat of a packet for the image start and at pixel W x H - 1 for the end of
the image; an image start is evaluated before every other condition of its pixel.

| ID | Condition | Detection | Response | Status |
| --- | --- | --- | --- | --- |
| E1 | Image start while an image is open (the image is too short) | Image state | The input waits; the pixels n to W x H - 1 of the open image are taken as 0, the ROI pixels among them are output; then the new image starts with the waiting pixel | `Err_Framing` |
| E2 | Pixel that is not an image start while no image is open (after a complete image or after the reset) | Image state | Pixel discarded | `Err_Framing`, once per run of discarded pixels |
| E3 | Pixel W x H - 1 without `In_Last`, or in a packet with the sequence flags "01" or "00" | Pixel count | The image ends with this pixel; further pixels are E2 | `Err_Framing` |
| E4 | `In_Last` in a packet with the sequence flags "10" or "11" on a pixel before W x H - 1 | Pixel count | None: the image continues with the next packet (or ends by E1) | `Err_Framing` |

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

Output image: `RoiWidth_g` x `RoiHeight_g` pixels of `PixelBits_g` bits. A ROI equal to the input image makes the
module a stream normaliser: it turns any division into packets into one packet per line and completes or discards
malformed images.

## 5. Configuration checks

| ID | Requirement | Core requirement |
| --- | --- | --- |
| CRP-CF-01 | A generic outside its range of section 4 shall stop the elaboration with a message naming the generic. | ISP-CFG-01 |
| CRP-CF-02 | The module shall be synthesizable with GHDL for the bounds of every generic. | ISP-GEN-01 |
| CRP-CF-03 | The module shall be designed for 150 MHz on the FPGA families of the reference systems; synthesis results are recorded in the verification report. | ISP-GEN-03 |

## 6. Interpretation

- The pixel count decides where an image ends; the image start decides where it begins. The sequence flags "10" and
  "11" at the end of an image and `In_Last` are checked against the count, but never move the end of an image: after
  a lost packet the count is the only reference that keeps the following lines in their columns.
- An image that is too short is completed with zeros when the next image start arrives, not earlier: the module
  cannot tell a pause of the source from a lost packet. An image whose rest never arrives and that no image start
  follows stays open.
- The sequence flags of the beats after the first beat of a packet are not evaluated, except with pixel W x H - 1.
