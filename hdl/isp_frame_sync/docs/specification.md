# isp_frame_sync: Specification

## 1. Overview

`isp_frame_sync` is the input side of every module of OpenISP. It takes a pixel stream as a source delivers it, in
any division into stream packets and possibly malformed, and delivers the pixel stream of the suite in its normal
form: complete images of `ImageWidth_g` x `ImageHeight_g` pixels, one stream packet per line, with the position of
every pixel. It implements the requirements of the
[requirements specification](../../../docs/requirements.md) on input streams and on malformed streams once, for all
modules: a module instantiates it at its input and adds only its own function.

Used on its own it is a stream normaliser: in front of a chain it turns the packets of a link into lines, completes
images that are too short and discards pixels that belong to no image.

The module has no memory. It counts the pixels from every image start; the count decides where an image ends.

### 1.1 Definitions

| Term | Definition |
| --- | --- |
| W, H | `ImageWidth_g`, `ImageHeight_g`: dimensions of the image. |
| Pixel n | The n-th pixel of an image in the order of arrival, n = 0 with the image start; its position is x = n mod W, y = n / W. |
| Stream packet, sequence flags, image start | As in the requirements specification, section 2. |
| Image open | From an accepted image start until pixel W x H - 1 has been output, taken from the input or generated as a missing pixel (section 3). |
| Missing pixel | A pixel of an open image that the input does not deliver before the next image start; it is generated with the value 0. |

## 2. Requirements

### 2.1 Interfaces

| ID | Requirement | Core requirement |
| --- | --- | --- |
| FSY-IF-01 | The module shall take pixels on a valid / ready stream (`In_Valid`, `In_Ready`, `In_Data` of `PixelBits_g` bits) with AXI4-Stream handshake semantics, the end of a stream packet on `In_Last` and the sequence flags of the packet on `In_User` (2 bits). | ISP-STR-01, ISP-STR-02 |
| FSY-IF-02 | The module shall output pixels on a valid / ready stream (`Out_Valid`, `Out_Ready`, `Out_Data` of `PixelBits_g` bits) with AXI4-Stream handshake semantics, the end of a stream packet on `Out_Last` and the sequence flags of the packet on `Out_User` (2 bits). | ISP-STR-01, ISP-STR-02 |
| FSY-IF-03 | With every output pixel the module shall output its position: the column on `Out_PosX` (unsigned, max(log2ceil(W), 1) bits) and the line on `Out_PosY` (unsigned, max(log2ceil(H), 1) bits). | ISP-STR-08 |
| FSY-IF-04 | The module shall pulse `Err_Framing` for one clock cycle for every error of section 3. | ISP-STR-08 |
| FSY-IF-05 | The module shall hold `Stat_ImageOpen` high while an image is open. | ISP-STR-10 |
| FSY-IF-06 | The module shall have one clock `Clk` and a synchronous, high-active reset `Rst`. | ISP-GEN-01 |

### 2.2 Function

| ID | Requirement | Core requirement |
| --- | --- | --- |
| FSY-FN-01 | For every image start the module shall output one image of W x H pixels whose pixel n is pixel n of the input image, unchanged, in raster order, each exactly once. | ISP-STR-08 |
| FSY-FN-02 | The module shall start an image with every image start and locate the pixels by counting from it; the division of the input image into stream packets shall not change the output. | ISP-STR-04, ISP-STR-08 |
| FSY-FN-03 | The module shall output every line as one stream packet: `Out_Last` with pixel x = W - 1, and on every beat of the line the sequence flags "01" for the first line, "10" for the last line, "00" for the lines between and "11" for an image of one line. | ISP-STR-05, ISP-STR-06 |
| FSY-FN-04 | The output shall not depend on the timing of the stream handshakes: any pattern of `In_Valid` and `Out_Ready` shall give the same output pixels, positions and packets, without loss or duplication. | ISP-STR-07 |
| FSY-FN-05 | An image start may follow the last pixel of an image without a gap. | ISP-STR-07 |
| FSY-FN-06 | After the reset, the module shall discard input pixels up to the first image start and then process that image. | ISP-STR-08, ISP-FT-04 |

### 2.3 Throughput and latency

| ID | Requirement | Core requirement |
| --- | --- | --- |
| FSY-PF-01 | With `In_Valid` and `Out_Ready` high, the module shall accept one pixel per clock cycle, also across the lines and from one image to the next. | ISP-STR-09 |
| FSY-PF-02 | With `Out_Ready` high, a pixel shall be at the output at most 2 clock cycles after the module accepted it. | ISP-STR-09 |
| FSY-PF-03 | With `Out_Ready` high, the module shall generate missing pixels at one per clock cycle: after an image start that finds m pixels of the open image missing, the module shall accept the pixel of the image start at most m + 4 clock cycles after it was offered. | ISP-STR-08 |
| FSY-PF-04 | The module shall discard pixels that belong to no image at one per clock cycle, whatever `Out_Ready`. | ISP-STR-07 |

### 2.4 Error handling

| ID | Requirement | Core requirement |
| --- | --- | --- |
| FSY-ER-01 | An image start while an image is open shall complete the open image with missing pixels of value 0; the new image shall then start with the pixel of the image start (E1). | ISP-STR-08 |
| FSY-ER-02 | Pixels while no image is open, other than an image start, shall be discarded (E2). | ISP-STR-08 |
| FSY-ER-03 | Pixel W x H - 1 of an image that is not the last beat of a stream packet with the sequence flags "10" or "11" shall end the image all the same (E3). | ISP-STR-08 |
| FSY-ER-04 | A stream packet with the sequence flags "10" or "11" that ends before pixel W x H - 1 shall not end the image (E4). | ISP-STR-08 |
| FSY-ER-05 | Every output image shall be complete whatever the input: H packets of W pixels with the sequence flags of FSY-FN-03. | ISP-STR-08 |
| FSY-ER-06 | The image after an error shall be processed as if no error had occurred. | ISP-STR-08 |

### 2.5 Fault tolerance

| ID | Requirement | Core requirement |
| --- | --- | --- |
| FSY-FT-01 | Every state machine and counter of the module shall return to a defined state from any state; an upset of a register shall disturb at most the image in progress, and the module shall realign with the next image start. | ISP-FT-04 |
| FSY-FT-02 | After the reset, `In_Ready`, `Out_Valid`, `Err_Framing` and `Stat_ImageOpen` shall be defined, and with defined input pixels every output beat shall be free of metavalues. | ISP-FT-04 |

The module has no memory, so the requirements on memories (ISP-FT-01 to ISP-FT-03) do not apply to it. Its counters
and registers are flip-flops; their mitigation by triple modular redundancy is a choice of the integrator in the
synthesis tool (user guide, section "Protection scope").

### 2.6 Partner behaviour

The input comes from a source outside the suite or from a module of the suite.

- A source outside the suite, for example the receiving end of a packet link, delivers an image as stream packets
  whose boundaries follow the packets of the link, not the lines of the image, and marks the first and the last
  packet of an image with the sequence flags. After a fault of the link a packet can be missing, so that an image is
  too short, or the first packet can be missing, so that pixels arrive without an image start (section 3).
- A module of the suite delivers one packet per line and only complete images. Its stream deviates only after an
  upset in that module.

Both may pause at any beat and may send images back to back. The consumer of the output may hold `Out_Ready` low at
any beat. A packet of the output is one line, W x `PixelBits_g` bits: a packet protocol behind a chain whose data
field is smaller (65536 octets for a Space Packet) needs a segmenting stage.

While the module generates missing pixels, the input waits (FSY-PF-03). A source that cannot wait needs a FIFO in
front of the chain; if that FIFO overflows during the wait, the following image is short as well and is completed in
the same way, until a pause of the source lets the chain catch up.

| ID | Requirement | Core requirement |
| --- | --- | --- |
| FSY-PB-01 | The module shall accept `In_Valid` low at any beat and stream packets of any length from one pixel upwards, also packets that span several lines or a whole image. | ISP-STR-04, ISP-STR-07 |

## 3. Error conditions

The first beat after the reset and every beat after a beat with `In_Last` is the first beat of a stream packet. The
sequence flags are evaluated at the first beat of a packet for the image start and at pixel W x H - 1 for the end of
the image; an image start is evaluated before every other condition of its pixel.

| ID | Condition | Detection | Response | Status |
| --- | --- | --- | --- | --- |
| E1 | Image start while an image is open (the image is too short) | Image state | The input waits; the pixels n to W x H - 1 of the open image are output as missing pixels; then the new image starts with the waiting pixel | `Err_Framing` |
| E2 | Pixel that is not an image start while no image is open (after a complete image or after the reset) | Image state | Pixel discarded | `Err_Framing`, once per run of discarded pixels |
| E3 | Pixel W x H - 1 without `In_Last`, or in a packet with the sequence flags "01" or "00" | Pixel count | The image ends with this pixel; further pixels are E2 | `Err_Framing` |
| E4 | `In_Last` in a packet with the sequence flags "10" or "11" on a pixel before W x H - 1 | Pixel count | None: the image continues with the next packet (or ends by E1) | `Err_Framing` |

## 4. Configuration parameters

| Generic | Default | Range | Description |
| --- | --- | --- | --- |
| `ImageWidth_g` | none | 1 to 65536 | W: pixels per line |
| `ImageHeight_g` | none | 1 to 65536 | H: lines per image |
| `PixelBits_g` | none | 1 to 32 | Bits per pixel |

## 5. Configuration checks

| ID | Requirement | Core requirement |
| --- | --- | --- |
| FSY-CF-01 | A generic outside its range of section 4 shall stop the elaboration with a message naming the generic. | ISP-CFG-01 |
| FSY-CF-02 | The module shall be synthesizable with GHDL for the bounds of every generic. | ISP-GEN-01 |
| FSY-CF-03 | The module shall be designed for 150 MHz on the FPGA families of the reference systems; synthesis results are recorded in the verification report. | ISP-GEN-03 |

## 6. Interpretation

- The pixel count decides where an image ends; the image start decides where it begins. The sequence flags "10" and
  "11" at the end of an image and `In_Last` are checked against the count, but never move the end of an image: after
  a lost packet the count is the only reference that keeps the following lines in their columns.
- An image that is too short is completed when the next image start arrives, not earlier: the module cannot tell a
  pause of the source from a lost packet. An image whose rest never arrives and that no image start follows stays
  open; `Stat_ImageOpen` lets a supervisor outside the module detect it.
- The sequence flags of the beats after the first beat of a packet are not evaluated, except with pixel W x H - 1.
