# isp_bin: Specification

## 1. Overview

`isp_bin` is the binning of OpenISP: it divides the image into bins of `BinX_g` x `BinY_g` pixels and outputs the sum
of the pixels of every bin as one pixel. The output image is smaller by the two factors, and its pixels are wider by
the bits that the sum needs. An average is the sum scaled by an `isp_point` behind the module.

The module is a configuration of the general 2D window filter and adds no logic of its own: a first
[`isp_filter2d`](../../isp_filter2d/docs/specification.md) adds `BinX_g` pixels along the line, a second one adds
`BinY_g` lines of the narrowed image. Both have coefficients of 1, a window of the size of the factor and a stride
of the same size, so their windows tile the image. An incomplete bin at the right or the lower edge is dropped or
completed, as the border mode says.

### 1.1 Definitions

| Term | Definition |
| --- | --- |
| W, H | `ImageWidth_g`, `ImageHeight_g`: dimensions of the input image. |
| Bin (n, m) | The pixels p'(n x `BinX_g` + i, m x `BinY_g` + j) for i = 0 to `BinX_g` - 1 and j = 0 to `BinY_g` - 1; p' is the image extended by the border mode (`isp_window`, section 6). |
| Wo, Ho | Output image. Border mode valid: Wo = floor(W / `BinX_g`), Ho = floor(H / `BinY_g`), the complete bins. Border modes zero and replicate: Wo = ceil(W / `BinX_g`), Ho = ceil(H / `BinY_g`), every bin with at least one pixel of the image. |
| P, Q | Pixel widths: P = `PixelBits_g` at the input, Q = P + log2ceil(`BinX_g` x `BinY_g`) at the output. |

## 2. Requirements

### 2.1 Interfaces

| ID | Requirement | Core requirement |
| --- | --- | --- |
| BIN-IF-01 | The module shall take pixels of P bits on a pixel stream (`In_Valid`, `In_Ready`, `In_Data`, `In_Last`, `In_User`). | ISP-STR-01, ISP-STR-02 |
| BIN-IF-02 | The module shall output pixels of Q bits on a pixel stream (`Out_Valid`, `Out_Ready`, `Out_Data`, `Out_Last`, `Out_User`). | ISP-STR-01, ISP-STR-02 |
| BIN-IF-03 | The module shall output `Err_Framing`, `Stat_ImageOpen`, `Stat_EccSec` and `Stat_EccDed` as the OR of its two filters, and pass `ErrInj_BitFlip` and `ErrInj_Valid` to the line buffers of the second filter. | ISP-STR-08, ISP-STR-10, ISP-FT-01, ISP-FT-02 |
| BIN-IF-04 | The module shall have one clock `Clk` and a synchronous, high-active reset `Rst`. | ISP-GEN-01 |

### 2.2 Function

| ID | Requirement | Core requirement |
| --- | --- | --- |
| BIN-FN-01 | For every bin (n, m) with n < Wo and m < Ho the module shall output the sum of the pixels of the bin as pixel (n, m) of the output image, without loss of precision. | ISP-BIN-01 |
| BIN-FN-02 | In the border mode valid an incomplete bin shall give no output pixel; in the border modes zero and replicate its missing pixels shall be 0 or the nearest pixel of the image. | ISP-BIN-02 |
| BIN-FN-03 | The output image shall have Wo x Ho pixels, as one stream packet per line with the sequence flags of the line. | ISP-STR-03, ISP-STR-05, ISP-STR-06 |
| BIN-FN-04 | The module shall consist of two `isp_filter2d` in series with the generics of section 4; a filter whose factor is 1 shall be left out, and with both factors 1 the module shall be an `isp_frame_sync`. The requirements of the parts on the input stream and on the completion of an image hold for the module. | ISP-GEN-02, ISP-BIN-01, ISP-STR-04, ISP-STR-07, ISP-STR-08 |

### 2.3 Throughput and latency

| ID | Requirement | Core requirement |
| --- | --- | --- |
| BIN-PF-01 | With `In_Valid` and `Out_Ready` high, the module shall hold the input for at most `BinX_g` - 1 clock cycles between the acceptance of the first pixels of two consecutive lines of an image in the border modes zero and replicate, and for no clock cycle between the first and the last pixel of an image in the border mode valid; in the border modes zero and replicate the input of an image that follows an image also waits while the vertical filter generates the virtual lines of the image before, in total at most max(0, (`BinY_g` - 1) x Wo + 2 - 2 x `BinX_g`) clock cycles. | ISP-STR-09 |
| BIN-PF-02 | In the border mode valid the interval between the starts of two consecutive images shall not exceed H x W + 16 clock cycles; in the border modes zero and replicate it shall not exceed H x (W + `BinX_g` - 1) + (`BinY_g` - 1) x Wo + 16 clock cycles. | ISP-STR-09 |

### 2.4 Error handling and fault tolerance

| ID | Requirement | Core requirement |
| --- | --- | --- |
| BIN-ER-01 | Every output image shall be complete whatever the input: Ho packets of Wo pixels. | ISP-STR-08 |
| BIN-FT-01 | An upset of a register shall disturb at most the image in progress, and the line buffers shall be ECC-protected, as specified for the parts. | ISP-FT-01, ISP-FT-04 |

### 2.5 Partner behaviour

The partners of the input are those of `isp_frame_sync`. In the border modes zero and replicate the module holds the
input for `BinX_g` - 1 cycles after every line, and an image that follows an image waits while the vertical filter
generates the `BinY_g` - 1 virtual lines of Wo pixels of the image before, at most max(0, (`BinY_g` - 1) x Wo + 2 -
2 x `BinX_g`) cycles in total (BIN-PF-01); in the border mode valid it never holds the input. The consumer of the
output may hold `Out_Ready` low at any beat.

## 3. Error conditions

The module has no error conditions of its own: E1 to E4 of `isp_frame_sync` (`Err_Framing`) and E5 of `isp_window`
(`Stat_EccDed`) apply.

## 4. Configuration parameters

| Generic | Default | Range | Description |
| --- | --- | --- | --- |
| `ImageWidth_g` | none | `BinX_g` to 65536; with `Resource_g` "BRAM" and `BinY_g` above 1, Wo at least 3 + `EccPipeline_g` | W: pixels per line of the input image |
| `ImageHeight_g` | none | `BinY_g` to 65536 | H: lines of the input image |
| `PixelBits_g` | none | 1 to 28 | P: bits per input pixel |
| `BinX_g` | 2 | 1 to 16 | Pixels of a bin along the line |
| `BinY_g` | 2 | 1 to 16 | Lines of a bin |
| `BorderMode_g` | "valid" | "valid", "zero", "replicate" | Treatment of an incomplete bin |
| `EccPipeline_g`, `Resource_g`, `RamStyle_g` | as `isp_window` | as `isp_window` | Line buffers of the second filter |

| Filter | Image | Pixel bits | Window | Anchor | Stride | Coefficients | Output bits |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Horizontal | W x H | P | `BinX_g` x 1 | 0 | `BinX_g`, 1 | `BinX_g` ones, constant | P + log2ceil(`BinX_g`) |
| Vertical | Wo x H | P + log2ceil(`BinX_g`) | 1 x `BinY_g` | 0 | 1, `BinY_g` | `BinY_g` ones, constant | Q |

Output image: Wo x Ho pixels of Q bits. The line buffers hold (`BinY_g` - 1) x Wo pixels of P + log2ceil(`BinX_g`)
bits plus check bits.

## 5. Configuration checks

| ID | Requirement | Core requirement |
| --- | --- | --- |
| BIN-CF-01 | A generic outside its range of section 4 (also the border mode mirror) shall stop the elaboration with a message naming the generic. | ISP-CFG-01 |
| BIN-CF-02 | The module shall be synthesizable with GHDL for the bounds of every numeric generic and every border mode. | ISP-GEN-01 |
| BIN-CF-03 | The default configuration shall be designed for 150 MHz on the AMD Versal device of the reference systems and for 125 MHz on Microchip PolarFire; synthesis results are recorded in the verification report. | ISP-GEN-03 |

## 6. Interpretation

- The sum along the line first: the second filter then stores lines of the narrowed image, a `BinX_g`-th of the
  line buffer that a window of `BinX_g` x `BinY_g` pixels would need.
- The mirror mode is not offered: a bin has no middle pixel to reflect at.
- Average: an `isp_point` behind the module with a shift of log2(`BinX_g` x `BinY_g`) for a bin of a power of two,
  or with the gain round(2^k / (`BinX_g` x `BinY_g`)) and the shift k otherwise. In the border mode zero an
  incomplete bin holds fewer pixels of the image, so its average is too low; replicate keeps the level.
- The two filters have the AXI4-Lite slave of their kernel; with constant coefficients it holds only read-only
  registers and is left unconnected.
