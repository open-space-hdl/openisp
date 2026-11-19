# isp_filter2d: Specification

## 1. Overview

`isp_filter2d` is the general 2D window filter of OpenISP: a pixel stream in, a pixel stream out, and between them
the weighted sum of the neighbourhood of every reference pixel. It consists of two modules and adds no logic of its
own: [`isp_window`](../../isp_window/docs/specification.md) forms the windows with their borders, anchor and stride,
and [`isp_conv`](../../isp_conv/docs/specification.md) multiplies them with the coefficients and adds.

A specific filter is a configuration of this module. An MTF compensation filter is `isp_filter2d` with the size and
the coefficients of its kernel; the binning `isp_bin` consists of two instances with kernels of ones and a stride.

### 1.1 Definitions

The definitions of `isp_window` (W, H, p', anchor Ax and Ay, reference pixels, output image Wo x Ho) and of `isp_conv`
(T, coefficient c, full precision F, output width B) apply. c(i, j) is the coefficient of column i and line j of the
window, element k = j x `WinX_g` + i of the coefficient set.

## 2. Requirements

### 2.1 Interfaces

| ID | Requirement | Core requirement |
| --- | --- | --- |
| FLT-IF-01 | The module shall take pixels of `PixelBits_g` bits on a pixel stream (`In_Valid`, `In_Ready`, `In_Data`, `In_Last`, `In_User`). | ISP-STR-01, ISP-STR-02 |
| FLT-IF-02 | The module shall output pixels of B bits on a pixel stream (`Out_Valid`, `Out_Ready`, `Out_Data`, `Out_Last`, `Out_User`). | ISP-STR-01, ISP-STR-02 |
| FLT-IF-03 | The module shall have the AXI4-Lite slave of its `isp_conv` (`S_AxiLite_*`, 32 data bits, 12 address bits) with the register map of that module. | ISP-CFG-03 |
| FLT-IF-04 | The module shall output the status of its two parts: `Err_Framing`, `Stat_ImageOpen`, `Stat_EccSec` and `Stat_EccDed` of `isp_window`, `Err_Config` of `isp_conv`; and pass `ErrInj_BitFlip` and `ErrInj_Valid` to `isp_window`. | ISP-STR-08, ISP-STR-10, ISP-FT-01, ISP-FT-02, ISP-FT-05 |
| FLT-IF-05 | The module shall have one clock `Clk` and a synchronous, high-active reset `Rst`. | ISP-GEN-01 |

### 2.2 Function

| ID | Requirement | Core requirement |
| --- | --- | --- |
| FLT-FN-01 | For every reference pixel (x, y) the module shall output the pixel min(max(S, 0), 2^B - 1) with S the sum over i = 0 to `WinX_g` - 1 and j = 0 to `WinY_g` - 1 of c(i, j) x p'(x - Ax + i, y - Ay + j). | ISP-FLT-01, ISP-FLT-02 |
| FLT-FN-02 | The output image shall have Wo x Ho pixels, in raster order of the reference pixels, as one stream packet per line with the sequence flags of the line. | ISP-FLT-04, ISP-STR-03, ISP-STR-05, ISP-STR-06 |
| FLT-FN-03 | The module shall consist of an `isp_window` and an `isp_conv` with the generics of section 4, the window stream of the first connected to the second, so that the requirements of both modules hold for it (input stream, borders, stride, completion of an image; coefficient set, registers). | ISP-GEN-02, ISP-FLT-03, ISP-STR-04, ISP-STR-07, ISP-STR-08 |

### 2.3 Throughput and latency

| ID | Requirement | Core requirement |
| --- | --- | --- |
| FLT-PF-01 | Within a line, with `In_Valid` and `Out_Ready` high, the module shall accept one pixel per clock cycle, and its image period shall be that of `isp_window` (WIN-PF-02). | ISP-STR-09 |
| FLT-PF-02 | With `Out_Ready` high, the output pixel of the reference pixel (x, y) shall be at the output at most log2ceil(T) + 9 clock cycles after the module accepted the pixel p(x + Rr, y + Rb), where that pixel is inside the image. | ISP-STR-09 |

### 2.4 Error handling and fault tolerance

| ID | Requirement | Core requirement |
| --- | --- | --- |
| FLT-ER-01 | Every output image shall be complete whatever the input: Ho packets of Wo pixels. | ISP-STR-08 |
| FLT-FT-01 | An upset of a register shall disturb at most the image in progress; the line buffers shall be ECC-protected and the coefficient registers parity-protected, as specified for the two parts. | ISP-FT-01, ISP-FT-04, ISP-FT-05 |

### 2.5 Partner behaviour

The partners of the input are those of `isp_frame_sync`, with the waiting times of `isp_window` at the right and the
lower border (its specification, section 2.6). The consumer of the output may hold `Out_Ready` low at any beat; a
typical consumer is an `isp_point` that scales the sums. The AXI4-Lite master is that of `isp_conv`.

## 3. Error conditions

The module has no error conditions of its own: E1 to E4 of `isp_frame_sync` (`Err_Framing`), E5 of `isp_window`
(`Stat_EccDed`) and E1 of `isp_conv` (`Err_Config`) apply.

## 4. Configuration parameters

| Generic | Default | Range | Passed to |
| --- | --- | --- | --- |
| `ImageWidth_g`, `ImageHeight_g` | none | as `isp_window` | `isp_window` |
| `PixelBits_g` | none | 1 to 32 | both |
| `WinX_g`, `WinY_g` | 3 | 1 to 16 | both |
| `AnchorX_g`, `AnchorY_g` | middle of the window | as `isp_window` | `isp_window` |
| `StrideX_g`, `StrideY_g` | 1 | 1 to 16 | `isp_window` |
| `BorderMode_g` | "replicate" | "valid", "zero", "replicate", "mirror" | `isp_window` |
| `EccPipeline_g`, `Resource_g`, `RamStyle_g` | as `isp_window` | as `isp_window` | `isp_window` |
| `CoefBits_g` | 16 | 2 to 18 | `isp_conv` |
| `Coef_g` | none | as `isp_conv` | `isp_conv` |
| `RuntimeCoef_g` | false | false, true | `isp_conv` |
| `OutBits_g` | 0 | 0 (full precision) or 1 to 64 | `isp_conv` |

Output image: Wo x Ho pixels of B bits (specifications of `isp_window` and `isp_conv`, sections 1.1); functions of
`isp_pkg` give Wo, Ho and the full precision for the generics of the module behind.

## 5. Configuration checks

| ID | Requirement | Core requirement |
| --- | --- | --- |
| FLT-CF-01 | A generic outside its range shall stop the elaboration with the message of the part that it belongs to. | ISP-CFG-01 |
| FLT-CF-02 | The module shall be synthesizable with GHDL in its default configuration, with a stride, with every border mode and with both values of `RuntimeCoef_g`. | ISP-GEN-01 |
| FLT-CF-03 | The default configuration shall be designed for 150 MHz on the FPGA families of the reference systems; synthesis results are recorded in the verification report. | ISP-GEN-03 |

## 6. Interpretation

- MTF compensation: the kernel of the filter is designed outside the FPGA from the modulation transfer function of
  the instrument. Its coefficients are scaled by 2^n and rounded to integers of `CoefBits_g` bits; with the border
  mode replicate or mirror the output image has the size of the input image. An `isp_point` behind the filter shifts
  the sums right by n and clamps them to the pixel range. With `RuntimeCoef_g` the kernel is replaced in operation;
  its size stays that of the generics.
- A separable kernel can be built from two instances, one of 1 x `WinY_g` and one of `WinX_g` x 1 elements, with
  fewer multipliers than the full window needs.
