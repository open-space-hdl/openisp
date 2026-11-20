# isp_crop: Specification

## 1. Overview

`isp_crop` selects a rectangular region of interest (ROI) of an image: it takes the pixel stream of an image of
`ImageWidth_g` x `ImageHeight_g` pixels and outputs the `RoiWidth_g` x `RoiHeight_g` pixels of the region whose top
left pixel is (X0, Y0) as an image of its own. The size of the region is set by generics. Its position is set by
generics (`RoiX_g`, `RoiY_g`) or, with `RuntimeRoi_g`, by a register that is read with every image start. The registers
of the module are on an AXI4-Lite slave (section 7).

The input of the module is an [`isp_frame_sync`](../../isp_frame_sync/docs/specification.md), which accepts any
division of the image into stream packets, completes or discards malformed images and delivers every pixel with its
position. `isp_crop` adds the selection: it forwards the pixels inside the region, discards the others and marks the
lines of the output image. The module has no memory.

### 1.1 Definitions

| Term | Definition |
| --- | --- |
| W, H | `ImageWidth_g`, `ImageHeight_g`: dimensions of the input image. |
| p(x, y) | Input pixel in column x (0 to W - 1) of line y (0 to H - 1). |
| X0, Y0 | Position of the ROI in an image: column and line of its first pixel (CRP-FN-06). |
| ROI | The pixels with X0 <= x < X0 + `RoiWidth_g` and Y0 <= y < Y0 + `RoiHeight_g`. |
| Stream packet, sequence flags, image start | As in the [requirements specification](../../../docs/requirements.md), section 2. |

## 2. Requirements

### 2.1 Interfaces

| ID | Requirement | Core requirement |
| --- | --- | --- |
| CRP-IF-01 | The module shall take pixels on a valid / ready stream (`In_Valid`, `In_Ready`, `In_Data` of `PixelBits_g` bits) with AXI4-Stream handshake semantics, the end of a stream packet on `In_Last` and the sequence flags of the packet on `In_User` (2 bits). | ISP-STR-01, ISP-STR-02 |
| CRP-IF-02 | The module shall output pixels on a valid / ready stream (`Out_Valid`, `Out_Ready`, `Out_Data` of `PixelBits_g` bits) with AXI4-Stream handshake semantics, the end of a stream packet on `Out_Last` and the sequence flags of the packet on `Out_User` (2 bits). | ISP-STR-01, ISP-STR-02 |
| CRP-IF-03 | The module shall output the status of its `isp_frame_sync`: the pulse `Err_Framing` for every error of the input stream and the level `Stat_ImageOpen` while an input image is open. | ISP-STR-08, ISP-STR-10 |
| CRP-IF-04 | The module shall have one clock `Clk` and a synchronous, high-active reset `Rst`. | ISP-GEN-01 |
| CRP-IF-05 | The module shall have an AXI4-Lite slave (`S_AxiLite_*`, 32 data bits, 8 address bits, clock `Clk`) for the registers of section 7. | ISP-CFG-03 |
| CRP-IF-06 | The module shall pulse `Err_Config` for one clock cycle for every position it rejects (CRP-ER-03). | ISP-CFG-02 |

### 2.2 Function

| ID | Requirement | Core requirement |
| --- | --- | --- |
| CRP-FN-01 | For every input image the module shall output one image of `RoiWidth_g` x `RoiHeight_g` pixels whose pixel (x, y) is the input pixel p(X0 + x, Y0 + y), unchanged, in raster order, each exactly once. | ISP-CRP-01, ISP-STR-03 |
| CRP-FN-02 | The module shall take its input through `isp_frame_sync` with the dimensions of the input image, so that the requirements of that module on the input stream (any division into packets, image start, malformed streams) hold for `isp_crop`. | ISP-STR-04, ISP-STR-08 |
| CRP-FN-03 | The module shall output every line of the output image as one stream packet: `Out_Last` with the last pixel of the line, and on every beat of the line the sequence flags "01" for the first line, "10" for the last line, "00" for the lines between and "11" for an output image of one line. | ISP-STR-05, ISP-STR-06 |
| CRP-FN-04 | The output shall not depend on the timing of the stream handshakes: any pattern of `In_Valid` and `Out_Ready` shall give the same output pixels and packets, without loss or duplication. | ISP-STR-07 |
| CRP-FN-05 | An image start may follow the last pixel of an image without a gap. | ISP-STR-07 |
| CRP-FN-06 | With `RuntimeRoi_g` false the position shall be (`RoiX_g`, `RoiY_g`). With `RuntimeRoi_g` true the module shall read the register `ROI_POS` with every image start and use that position for the whole image; a write to the register during an image shall take effect with the next image. | ISP-CRP-01, ISP-CFG-02 |

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
| CRP-ER-03 | A position read from `ROI_POS` with X + `RoiWidth_g` > W or Y + `RoiHeight_g` > H shall be rejected: the image shall be processed with the position (`RoiX_g`, `RoiY_g`) (E5). The register shall keep the value that was written. | ISP-CFG-02 |
| CRP-ER-04 | A value of `ROI_POS` whose parity bit does not match at the image start shall be rejected in the same way (E6). | ISP-FT-05 |

### 2.5 Fault tolerance

| ID | Requirement | Core requirement |
| --- | --- | --- |
| CRP-FT-01 | The selection shall use the position that `isp_frame_sync` delivers with every pixel and keep no pixel position of its own; the limits of the ROI in use shall be loaded from `ROI_POS` with every image. An upset of the datapath then disturbs at most the image in progress, and the module realigns with the next image start. | ISP-FT-04 |
| CRP-FT-03 | `ROI_POS` shall carry one parity bit over its 32 bits, set by the reset and by the writes (CRP-RG-03), and checked with every image start (CRP-ER-04). | ISP-FT-05 |
| CRP-FT-02 | After the reset, `In_Ready`, `Out_Valid`, `Err_Framing`, `Err_Config` and `Stat_ImageOpen` shall be defined, and with defined input pixels every output beat shall be free of metavalues. | ISP-FT-04 |

The module has no memory, so the requirements on memories (ISP-FT-01 to ISP-FT-03) do not apply to it. Its registers
are flip-flops; their mitigation by triple modular redundancy is a choice of the integrator in the synthesis tool
(user guide, section "Protection scope"). `ROI_POS` holds its value until it is written: its parity bit
detects an upset of one bit at the next image start, the images are then processed with the position of the generics
and `STATUS.ERR_CONFIG` tells the software to write the register again in full.

### 2.6 Partner behaviour

The partners of the input are those of `isp_frame_sync` (its specification, section 2.6). The consumer of the output
may hold `Out_Ready` low at any beat. The AXI4-Lite master is a processor or a register bridge of the system on the
clock `Clk`; it may access the registers at any time, also while images pass. A register bus in another clock domain
needs a clock crossing in the system.

## 3. Error conditions

The errors E1 to E4 of `isp_frame_sync` apply to the input stream; `Err_Framing` reports them. The module adds one
condition:

| ID | Condition | Detection | Response | Status |
| --- | --- | --- | --- | --- |
| E5 | `RuntimeRoi_g` true: the position read from `ROI_POS` with an image start places the ROI partly outside the image | Range check with the image start | The image is processed with the position of the generics | `Err_Config`, `STATUS.ERR_CONFIG` |
| E6 | `RuntimeRoi_g` true: the parity bit of `ROI_POS` does not match its value at an image start (upset of the register) | Parity check with the image start | The image is processed with the position of the generics, and so is every further image until `ROI_POS` is written in full (all four bytes); a write that keeps a byte keeps the mismatch (CRP-RG-03) | `Err_Config`, `STATUS.ERR_CONFIG` |

## 4. Configuration parameters

| Generic | Default | Range | Description |
| --- | --- | --- | --- |
| `ImageWidth_g` | none | 1 to 65536 | W: pixels per line of the input image |
| `ImageHeight_g` | none | 1 to 65536 | H: lines of the input image |
| `PixelBits_g` | none | 1 to 64 | Bits per pixel |
| `RoiWidth_g` | none | 1 to `ImageWidth_g` - `RoiX_g` | Pixels per line of the ROI and of the output image |
| `RoiHeight_g` | none | 1 to `ImageHeight_g` - `RoiY_g` | Lines of the ROI and of the output image |
| `RoiX_g` | 0 | 0 to `ImageWidth_g` - 1 | Column of the first pixel of the ROI; with `RuntimeRoi_g` the reset value of `ROI_POS` and the position used when the register holds an invalid one |
| `RoiY_g` | 0 | 0 to `ImageHeight_g` - 1 | Line of the first pixel of the ROI; with `RuntimeRoi_g` as `RoiX_g` |
| `RuntimeRoi_g` | false | false, true | Position of the ROI from the generics (false: `ROI_POS` is read only) or from the register `ROI_POS` (true) |

Output image: `RoiWidth_g` x `RoiHeight_g` pixels of `PixelBits_g` bits.

## 5. Configuration checks

| ID | Requirement | Core requirement |
| --- | --- | --- |
| CRP-CF-01 | A generic outside its range of section 4 shall stop the elaboration with a message naming the generic. | ISP-CFG-01 |
| CRP-CF-02 | The module shall be synthesizable with GHDL for the bounds of every generic. | ISP-GEN-01 |
| CRP-CF-03 | The module shall be designed for 150 MHz on the AMD Versal device of the reference systems and for 125 MHz on Microchip PolarFire; synthesis results are recorded in the verification report. | ISP-GEN-03 |

## 6. Interpretation

- Only the position of the region is configurable at run time. Its size is the size of the output image, and the
  dimensions of an image are generics of every module that follows (ISP-STR-03): a size that changes at run time
  would change the image of the whole chain behind the module.
- With `RuntimeRoi_g` false the comparisons of the selection are constants, which the synthesis tool reduces. The
  AXI4-Lite slave is present in both cases: the identification, the characteristics and the status are always
  readable. A system without a register bus leaves the slave unconnected.
- Both coordinates are in one register, so that one write changes the position as a whole.
- When `isp_frame_sync` completes a short image, the input waits for the missing pixels of the whole input image,
  not only for those of the region (its requirement FSY-PF-03).

## 7. Register map

Byte addresses of 32-bit registers on the AXI4-Lite slave. Access: RO read only, RW read and write, W1C sticky flag,
write one to clear, W1 command, write one. Reads of other addresses return 0, writes to them and to read-only
fields have no effect; every access is answered with OKAY.

| Address | Register | Bits | Field | Access | Reset | Description |
| --- | --- | --- | --- | --- | --- | --- |
| 0x00 | `ID` | 31:0 | `ID` | RO | 0x43525001 | 0x435250 (CRP) and register map version 1 |
| 0x04 | `IMAGE` | 15:0 | `WIDTH_M1` | RO | `ImageWidth_g` - 1 | Pixels per line of the input image, minus one |
| | | 31:16 | `HEIGHT_M1` | RO | `ImageHeight_g` - 1 | Lines of the input image, minus one |
| 0x08 | `ROI_SIZE` | 15:0 | `WIDTH_M1` | RO | `RoiWidth_g` - 1 | Pixels per line of the ROI, minus one |
| | | 31:16 | `HEIGHT_M1` | RO | `RoiHeight_g` - 1 | Lines of the ROI, minus one |
| 0x0C | `ROI_POS` | 15:0 | `X` | RW (RO with `RuntimeRoi_g` false) | `RoiX_g` | Column of the first pixel of the ROI |
| | | 31:16 | `Y` | RW (RO with `RuntimeRoi_g` false) | `RoiY_g` | Line of the first pixel of the ROI |
| 0x10 | `STATUS` | 0 | `IMAGE_OPEN` | RO | 0 | An input image is open (`Stat_ImageOpen`) |
| | | 8 | `ERR_FRAMING` | W1C | 0 | Set by every pulse of `Err_Framing` |
| | | 9 | `ERR_CONFIG` | W1C | 0 | Set by every pulse of `Err_Config` |
| 0x14 | `INJECT` | 0 | `ROI_POS_PARITY` | W1 | 0 | Write one: inverts the parity bit of `ROI_POS` (test of the error handling); reads as zero |

| ID | Requirement | Core requirement |
| --- | --- | --- |
| CRP-RG-01 | The AXI4-Lite slave shall implement the registers of this section with the stated addresses, fields, access types and reset values, and answer every access with OKAY. | ISP-CFG-03 |
| CRP-RG-02 | A flag of `STATUS` that is set by its event in the cycle of a write that clears it shall stay set. | ISP-CFG-03 |
| CRP-RG-03 | A write to `ROI_POS` shall change only the bytes that the write strobes select. A write of every byte that holds bits of the register shall set the parity bit for the written value; a write that keeps such a byte shall keep a parity mismatch (the parity bit changes with the parity of the written bytes against the bytes they replace), so that an upset in a kept byte is still reported, and an upset in a byte that the write replaces is reported as well, until the register is written in full (every byte that holds bits of the register) (PKG-08). | ISP-CFG-03, ISP-FT-05 |
| CRP-RG-04 | A write of one to `INJECT.ROI_POS_PARITY` shall invert the parity bit of `ROI_POS`, so that the next image start finds a mismatch. | ISP-FT-05 |
