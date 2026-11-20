# isp_window: Specification

## 1. Overview

`isp_window` delivers the neighbourhood of the pixels of an image: for every reference pixel one window of `WinX_g` x
`WinY_g` pixels as one vector. It is the front end of every function that looks at more than one pixel: the linear
filter, the binning and the replacement of non-operational pixels are a kernel behind this module.

The size of the window, the place of the reference pixel inside it (the anchor) and the distance between the
reference pixels (the stride) are generics. The pixels of a window that lie outside the image are defined by the
border mode: valid (only windows inside the image), zero, replicate or mirror. The lines above the current one are
kept in line buffers, ECC-protected delays of Open Logic of one image line each. The input of the module is an
[`isp_frame_sync`](../../isp_frame_sync/docs/specification.md).

The output is a window stream: a pixel stream whose data is a window instead of a pixel. A kernel reduces every
window to one pixel and passes the packet signals on, which gives a pixel stream again.

### 1.1 Definitions

| Term | Definition |
| --- | --- |
| W, H | `ImageWidth_g`, `ImageHeight_g`: dimensions of the input image. |
| p(x, y) | Input pixel in column x (0 to W - 1) of line y (0 to H - 1); p'(x, y) is p extended beyond the image by the border mode (section 6). |
| Ax, Ay | `AnchorX_g`, `AnchorY_g`: column and line of the reference pixel inside the window. |
| Window of (x, y) | The pixels p'(x - Ax + i, y - Ay + j) for i = 0 to `WinX_g` - 1 and j = 0 to `WinY_g` - 1. |
| Element (i, j) | The pixel in column i and line j of a window; element index k = j x `WinX_g` + i, so element 0 is the top left pixel. |
| Reference pixels | Border modes zero, replicate, mirror: x = n x `StrideX_g`, y = m x `StrideY_g` inside the image. Border mode valid: x = Ax + n x `StrideX_g`, y = Ay + m x `StrideY_g`, as long as the window lies inside the image. n and m count from 0. |
| Wo, Ho | Dimensions of the output image, the number of reference pixels per line and of lines with reference pixels. Border modes zero, replicate, mirror: Wo = ceil(W / `StrideX_g`), Ho = ceil(H / `StrideY_g`). Valid: Wo = floor((W - `WinX_g`) / `StrideX_g`) + 1, Ho = floor((H - `WinY_g`) / `StrideY_g`) + 1. |
| Rr, Rb | `WinX_g` - 1 - Ax and `WinY_g` - 1 - Ay: columns of a window right of the reference pixel and lines below it. |

## 2. Requirements

### 2.1 Interfaces

| ID | Requirement | Core requirement |
| --- | --- | --- |
| WIN-IF-01 | The module shall take pixels of `PixelBits_g` bits on a pixel stream (`In_Valid`, `In_Ready`, `In_Data`, `In_Last`, `In_User`). | ISP-STR-01, ISP-STR-02 |
| WIN-IF-02 | The module shall output one window per beat on a valid / ready stream (`Out_Valid`, `Out_Ready`, `Out_Data` of `WinX_g` x `WinY_g` x `PixelBits_g` bits) with AXI4-Stream handshake semantics; element k of the window occupies bits (k + 1) x `PixelBits_g` - 1 downto k x `PixelBits_g`. | ISP-STR-01, ISP-FLT-01 |
| WIN-IF-03 | The output stream shall carry the packets of the output image of Wo x Ho windows: `Out_Last` with the last window of every line and the sequence flags of the line on `Out_User`, as a pixel stream does. | ISP-STR-05, ISP-STR-06 |
| WIN-IF-04 | The module shall output the status of its `isp_frame_sync` (`Err_Framing`, `Stat_ImageOpen`) and pulse `Stat_EccSec` and `Stat_EccDed` for one clock cycle for a corrected single bit error and a detected double bit error of the line buffers that the window uses (WIN-FT-02). | ISP-STR-08, ISP-STR-10, ISP-FT-01 |
| WIN-IF-05 | The module shall pass `ErrInj_BitFlip` (one codeword per line buffer) and `ErrInj_Valid` to the line buffers with the semantics of Open Logic. | ISP-FT-02 |
| WIN-IF-06 | The module shall have one clock `Clk` and a synchronous, high-active reset `Rst`. | ISP-GEN-01 |

### 2.2 Function

| ID | Requirement | Core requirement |
| --- | --- | --- |
| WIN-FN-01 | For every reference pixel the module shall output the window of section 1.1 with the pixels of the input image and, for elements outside the image, the values of the border mode (section 6). | ISP-FLT-01 |
| WIN-FN-02 | The module shall output the windows of the reference pixels of section 1.1 and no others, in raster order, each exactly once: an output image of Wo x Ho windows. | ISP-FLT-01, ISP-FLT-04, ISP-STR-03 |
| WIN-FN-03 | The module shall take its input through `isp_frame_sync` with the dimensions of the input image. | ISP-STR-04, ISP-STR-08 |
| WIN-FN-04 | After the last pixel of an image the module shall output the remaining windows of the image without further input. | ISP-STR-07 |
| WIN-FN-05 | An image start may follow the last pixel of an image without a gap; the module shall hold the input as long as the remaining windows of the image before need. | ISP-STR-07 |
| WIN-FN-06 | The output shall not depend on the timing of the stream handshakes: any pattern of `In_Valid` and `Out_Ready` shall give the same windows and packets, without loss or duplication. | ISP-STR-07 |

### 2.3 Throughput and latency

| ID | Requirement | Core requirement |
| --- | --- | --- |
| WIN-PF-01 | With `In_Valid` and `Out_Ready` high, the module shall hold the input (`In_Ready` low) for at most Rr clock cycles between the acceptance of the first pixels of two consecutive lines of an image in the border modes zero, replicate and mirror, and for no clock cycle between the first and the last pixel of an image in the border mode valid; between the first pixels of the first two lines of an image the input also waits for the windows of the lower border of the image before (WIN-PF-02), Rb x (W + Rr) clock cycles at most. | ISP-STR-09 |
| WIN-PF-02 | With back-to-back input and `Out_Ready` high, the interval between the starts of two consecutive images shall not exceed (H + Rb) x (W + Rr) + 8 clock cycles in the border modes zero, replicate and mirror, and H x W + 8 clock cycles in the border mode valid: Rr cycles per line for the windows at the right border, Rb lines for the windows at the lower border, 8 cycles of registers. | ISP-STR-09 |
| WIN-PF-03 | With `Out_Ready` high, the window of the reference pixel (x, y) shall be at the output at most 6 clock cycles after the module accepted the pixel p(x + Rr, y + Rb), where that pixel is inside the image. | ISP-STR-09 |

### 2.4 Error handling

| ID | Requirement | Core requirement |
| --- | --- | --- |
| WIN-ER-01 | Every output image shall be complete whatever the input: Ho packets of Wo windows. The pixels that `isp_frame_sync` generated for missing pixels are pixels of the image like the others. | ISP-STR-08 |
| WIN-ER-02 | The image after an error shall be processed as if no error had occurred. | ISP-STR-08 |
| WIN-ER-03 | A pixel read from a line buffer with a double bit error shall be used as read. | ISP-FT-01 |

### 2.5 Fault tolerance

| ID | Requirement | Core requirement |
| --- | --- | --- |
| WIN-FT-01 | The line buffers shall be `olo_ft_delay` entities of one image line each, with one SECDED codeword per pixel; the module shall use the corrected data. With `WinY_g` = 1 there is no line buffer: the ECC status outputs stay 0 and the error injection inputs have no function. | ISP-FT-01, ISP-GEN-01 |
| WIN-FT-02 | `Stat_EccSec` and `Stat_EccDed` shall pulse once for every pixel event in which at least one line buffer that the event uses for a row of the window delivers a corrected or an uncorrectable pixel; a line buffer whose line the border rule replaces (a line above or below the image) does not count. | ISP-FT-01 |
| WIN-FT-03 | Every state machine and counter of the module shall return to a defined state from any state; an upset of a register shall disturb at most the image in progress, and the module shall realign with the next image start. | ISP-FT-04 |
| WIN-FT-04 | After the reset, `In_Ready`, `Out_Valid` and the status outputs shall be defined; with defined input pixels, every output window shall be free of metavalues: no element shall be taken from a line buffer position that the image in progress has not written. | ISP-FT-04 |

The line buffers hold a pixel for at most `WinY_g` - 1 line periods, so they need no scrubbing (ISP-FT-03 applies to
tables). The window register and the counters are flip-flops; their mitigation by triple modular redundancy is a
choice of the integrator in the synthesis tool (user guide, section "Protection scope").

### 2.6 Partner behaviour

The partners of the input are those of `isp_frame_sync` (its specification, section 2.6). The module holds the input
for Rr cycles after every line and for Rb lines after every image in the border modes zero, replicate and mirror
(WIN-PF-02); a source that cannot wait needs a FIFO or blanking of that length.

The consumer of the output is a kernel of the suite (`isp_conv`, the interpolation of `isp_replace`) or of the user.
It may hold `Out_Ready` low at any beat.

## 3. Error conditions

The errors E1 to E4 of `isp_frame_sync` apply to the input stream; `Err_Framing` reports them.

| ID | Condition | Detection | Response | Status |
| --- | --- | --- | --- | --- |
| E5 | Double bit error in a pixel read from a line buffer | ECC decoder of the line buffer | The pixel is used as read | `Stat_EccDed` |

A single bit error in a pixel read from a line buffer is corrected and reported with `Stat_EccSec`. An error in a
line buffer whose line the border rule replaces (a line above or below the image) is not reported: that pixel
does not reach a window. After power-up the line buffers can hold any content, which the first lines of the
first image read only in such rows.

## 4. Configuration parameters

| Generic | Default | Range | Description |
| --- | --- | --- | --- |
| `ImageWidth_g` | none | `WinX_g` to 65536 | W: pixels per line of the input image |
| `ImageHeight_g` | none | `WinY_g` to 65536 | H: lines of the input image |
| `PixelBits_g` | none | 1 to 32 | Bits per pixel |
| `WinX_g` | 3 | 1 to 16 | Columns of the window |
| `WinY_g` | 3 | 1 to 16 | Lines of the window; 1 means no line buffer |
| `AnchorX_g` | (`WinX_g` - 1) / 2 | 0 to `WinX_g` - 1 | Column of the reference pixel in the window |
| `AnchorY_g` | (`WinY_g` - 1) / 2 | 0 to `WinY_g` - 1 | Line of the reference pixel in the window |
| `StrideX_g` | 1 | 1 to 16 | Distance of the reference pixels in a line |
| `StrideY_g` | 1 | 1 to 16 | Distance of the lines with reference pixels |
| `BorderMode_g` | "replicate" | "valid", "zero", "replicate", "mirror" | Border mode (section 6) |
| `EccPipeline_g` | 1 | 0, 1 | Output register of the ECC decoder of every line buffer (Open Logic `EccPipeline_g`) |
| `Resource_g` | "AUTO" | "AUTO", "SRL", "BRAM" (as Open Logic, without regard to case) | Implementation of the line buffers: block RAM or shift registers (Open Logic `Resource_g`) |
| `RamStyle_g` | "auto" | Values of Open Logic | RAM implementation of the line buffers (Open Logic `RamStyle_g`) |

The line buffers hold (`WinY_g` - 1) x `ImageWidth_g` pixels of `PixelBits_g` bits plus the SECDED check bits of
every pixel.

## 5. Configuration checks

| ID | Requirement | Core requirement |
| --- | --- | --- |
| WIN-CF-01 | A generic outside its range of section 4 shall stop the elaboration with a message naming the generic. | ISP-CFG-01 |
| WIN-CF-02 | The border mode mirror with a window of more than one column whose anchor is not its middle column (`WinX_g` odd and `AnchorX_g` = (`WinX_g` - 1) / 2), or the same for the lines, shall stop the elaboration with a message. | ISP-CFG-01 |
| WIN-CF-03 | The module shall be synthesizable with GHDL for the bounds of every numeric generic and every value of `BorderMode_g`. | ISP-GEN-01 |
| WIN-CF-04 | The default configuration shall be designed for 150 MHz on the FPGA families of the reference systems; synthesis results are recorded in the verification report. | ISP-GEN-03 |
| WIN-CF-05 | With `Resource_g` "BRAM" and `WinY_g` above 1, an `ImageWidth_g` below 3 + `EccPipeline_g` shall stop the elaboration with a message naming `ImageWidth_g` (the block RAM delay of Open Logic needs a delay of at least 3). | ISP-CFG-01 |

## 6. Interpretation

The border modes extend the input image beyond its borders:

| Mode | Value of p'(x, y) outside the image |
| --- | --- |
| valid | Not used: only windows without pixels outside the image are output. |
| zero | 0 |
| replicate | p(clamp(x, 0, W - 1), clamp(y, 0, H - 1)): the nearest pixel of the image. |
| mirror | p(r(x, W), r(y, H)) with r(c, N) = -c for c < 0 and 2 x (N - 1) - c for c > N - 1: reflection at the outermost pixel, which is not repeated (d c b \| a b c d \| c b a). |

- A window is never larger than the image (ranges of `ImageWidth_g` and `ImageHeight_g`), so a reflection never
  leaves the image.
- The mirror mode needs the reflected pixels at the time a window is output. That holds for a window with its
  reference pixel in the middle; other anchors would need pixels that have not arrived yet (WIN-CF-02).
- Binning uses the anchor 0 and a stride equal to the window size: the windows then tile the image. In the border
  mode valid an incomplete window at the right or the lower edge is not output; in the modes zero and replicate it
  is completed.
- With a stride above 1 the module still takes every input pixel; only the windows of the reference pixels are
  output.
- The input stage of `isp_frame_sync` takes up to two pixels while the module holds its input for the right
  border, so the hold cycles of a line can fall after the first pixels of the next line: WIN-PF-01 counts them
  between the first pixels of two lines, and the latency of WIN-PF-03 leaves room for these two pixels.
- For the same reason the input stage takes the first pixels of an image while the module still generates the
  virtual lines of the image before. These hold cycles fall between the first pixels of the first two lines of the
  image, and the first interval between two image starts after an idle module is shorter than the period of
  WIN-PF-02.
