# isp_conv: Specification

## 1. Overview

`isp_conv` is the linear kernel of OpenISP: it takes the windows that `isp_window` delivers, multiplies every pixel of
a window by a signed coefficient and outputs the sum as one pixel. The sum has its full precision; a negative sum
becomes 0, because pixels are unsigned. Scaling the sum, for example to the pixel width of the input, is the task of
an `isp_point` behind the filter.

The size of the window is set by generics. The coefficients are set by a generic or, with `RuntimeCoef_g`, by
registers on an AXI4-Lite slave (section 7). Together with `isp_window` the module forms the general 2D window filter
`isp_filter2d`. It has no memory.

### 1.1 Definitions

| Term | Definition |
| --- | --- |
| T | `WinX_g` x `WinY_g`: number of elements of a window (taps). |
| e(k) | Element k of the input window (unsigned, `PixelBits_g` bits), k = 0 to T - 1, element 0 the top left pixel, row by row. |
| c(k) | Coefficient of element k: signed number of `CoefBits_g` bits. |
| S | Sum over k of c(k) x e(k). |
| Full precision | F = `PixelBits_g` + `CoefBits_g` - 1 + log2ceil(T) bits: every sum that is not negative fits. |
| q | Output pixel: 0 for S < 0, otherwise min(S, 2^B - 1) with B = F for `OutBits_g` = 0 and B = `OutBits_g` otherwise. |
| Coefficient set | The T coefficients together. |
| Window stream, image start | The output stream of `isp_window`: a pixel stream whose data is a window; the image start is the first beat of a stream packet with the sequence flags "01" or "11". |

## 2. Requirements

### 2.1 Interfaces

| ID | Requirement | Core requirement |
| --- | --- | --- |
| CNV-IF-01 | The module shall take windows on a window stream (`In_Valid`, `In_Ready`, `In_Data` of T x `PixelBits_g` bits, `In_Last`, `In_User`); element k occupies bits (k + 1) x `PixelBits_g` - 1 downto k x `PixelBits_g`. | ISP-STR-01, ISP-FLT-02 |
| CNV-IF-02 | The module shall output pixels of B bits on a pixel stream (`Out_Valid`, `Out_Ready`, `Out_Data`, `Out_Last`, `Out_User`). | ISP-STR-01, ISP-STR-02 |
| CNV-IF-03 | The module shall have an AXI4-Lite slave (`S_AxiLite_*`, 32 data bits, 12 address bits, clock `Clk`) for the registers of section 7. | ISP-CFG-03 |
| CNV-IF-04 | The module shall pulse `Err_Config` for one clock cycle for every coefficient set it rejects (CNV-ER-01). | ISP-FT-05 |
| CNV-IF-05 | The module shall have one clock `Clk` and a synchronous, high-active reset `Rst`. | ISP-GEN-01 |

### 2.2 Function

| ID | Requirement | Core requirement |
| --- | --- | --- |
| CNV-FN-01 | For every window the module shall output the pixel q of section 1.1, with the coefficient set of the image. | ISP-FLT-02 |
| CNV-FN-02 | The module shall output `In_Last` and `In_User` of a window with its pixel, so that the output is the pixel stream of the image that the window stream carries. | ISP-STR-05, ISP-STR-06 |
| CNV-FN-03 | With `RuntimeCoef_g` false the coefficient set shall be the generic `Coef_g`. | ISP-FLT-03 |
| CNV-FN-04 | With `RuntimeCoef_g` true the module shall take the coefficient set from the registers with every image start at which `CTRL.HOLD` is 0 and use it for the whole image; at an image start with `CTRL.HOLD` 1 the coefficient set of the image before shall stay. | ISP-FLT-03, ISP-CFG-02 |
| CNV-FN-05 | The output shall not depend on the timing of the stream handshakes, and an image start may follow the last window of an image without a gap. | ISP-STR-07 |

### 2.3 Throughput and latency

| ID | Requirement | Core requirement |
| --- | --- | --- |
| CNV-PF-01 | With `In_Valid` and `Out_Ready` high, the module shall accept one window per clock cycle. | ISP-STR-09 |
| CNV-PF-02 | With `Out_Ready` high, the pixel of a window shall be at the output at most log2ceil(T) + 3 clock cycles after the module accepted the window. | ISP-STR-09 |

### 2.4 Error handling

| ID | Requirement | Core requirement |
| --- | --- | --- |
| CNV-ER-01 | A coefficient set with a register whose parity bit does not match at the image start shall be rejected: the image shall be processed with the coefficient set of the generic (E1). | ISP-FT-05 |

### 2.5 Fault tolerance

| ID | Requirement | Core requirement |
| --- | --- | --- |
| CNV-FT-01 | The coefficient set in use shall be loaded with every image start (CNV-FN-04), and the datapath shall keep no state between windows, so that an upset of the datapath disturbs at most the image in progress. | ISP-FT-04 |
| CNV-FT-02 | Every coefficient register shall carry one parity bit over its bits, set by the reset and by every write, and checked with every image start at which the registers are taken (CNV-ER-01). | ISP-FT-05 |
| CNV-FT-03 | After the reset, `In_Ready`, `Out_Valid` and `Err_Config` shall be defined, and with defined input windows every output beat shall be free of metavalues. | ISP-FT-04 |

The module has no memory, so the requirements on memories (ISP-FT-01 to ISP-FT-03) do not apply to it.

### 2.6 Partner behaviour

The source of the windows is `isp_window`: it delivers complete images, one packet per line, and may pause at any
beat. The module therefore does not check the stream; it finds the image start from the packets alone. The consumer
of the output may hold `Out_Ready` low at any beat. The AXI4-Lite master is a processor or a register bridge of the
system on the clock `Clk`; a register bus in another clock domain needs a clock crossing in the system.

## 3. Error conditions

| ID | Condition | Detection | Response | Status |
| --- | --- | --- | --- | --- |
| E1 | `RuntimeCoef_g` true: the parity bit of a coefficient register does not match its value at an image start with `CTRL.HOLD` 0 (upset of the register) | Parity check with the image start | The image is processed with the coefficient set of the generic, and so is every further image until the register is written | `Err_Config`, `STATUS.ERR_CONFIG` |

## 4. Configuration parameters

| Generic | Default | Range | Description |
| --- | --- | --- | --- |
| `PixelBits_g` | none | 1 to 32 | Bits per pixel of the window |
| `WinX_g` | 3 | 1 to 16 | Columns of the window |
| `WinY_g` | 3 | 1 to 16 | Lines of the window |
| `CoefBits_g` | 16 | 2 to 18 | Bits of a coefficient, with its sign |
| `Coef_g` | none | T values of -2^(`CoefBits_g` - 1) to 2^(`CoefBits_g` - 1) - 1 | Coefficient set (vector of integers of `isp_pkg`, element 0 for the top left pixel, row by row); with `RuntimeCoef_g` the reset values of the coefficient registers |
| `RuntimeCoef_g` | false | false, true | Coefficient set from the generic (false: the coefficient registers are read only) or from the registers (true) |
| `OutBits_g` | 0 | 0 (full precision) or 1 to 64 | Bits per output pixel; a smaller width than the full precision saturates |

Output pixel width: B of section 1.1; the function `ispConvOutBits` of `isp_pkg` gives the full precision for the
generics of the module behind.

## 5. Configuration checks

| ID | Requirement | Core requirement |
| --- | --- | --- |
| CNV-CF-01 | A generic outside its range of section 4 (also a `Coef_g` with another number of values than T) shall stop the elaboration with a message naming the generic. | ISP-CFG-01 |
| CNV-CF-02 | The module shall be synthesizable with GHDL for the bounds of every numeric generic and both values of `RuntimeCoef_g`. | ISP-GEN-01 |
| CNV-CF-03 | The default configuration shall be designed for 150 MHz on the FPGA families of the reference systems; synthesis results are recorded in the verification report. | ISP-GEN-03 |

## 6. Interpretation

- Coefficient k weighs element k of the window: the module computes a correlation. A convolution kernel is given
  mirrored in both directions; for the symmetric kernels of an MTF compensation the two are the same.
- The sum is not divided or shifted. A kernel with a gain of 2^n (coefficients that add up to 2^n) is brought back to
  the pixel range by an `isp_point` with a shift of n behind the filter.
- `CTRL.HOLD` makes a change of several coefficients take effect together: the software sets it, writes the
  coefficients and clears it.

## 7. Register map

Byte addresses of 32-bit registers on the AXI4-Lite slave. Access: RO read only, RW read and write, W1C sticky flag,
write one to clear, W1 command, write one, W write only (the argument of a command). Reads of other addresses
return 0, writes to them and to read-only fields have no effect; every access is answered with OKAY. With
`RuntimeCoef_g` false the coefficient registers are read only and show the generic.

| Address | Register | Bits | Field | Access | Reset | Description |
| --- | --- | --- | --- | --- | --- | --- |
| 0x000 | `ID` | 31:0 | `ID` | RO | 0x434E5601 | 0x434E56 (CNV) and register map version 1 |
| 0x004 | `PARAM` | 4:0 | `WIN_X` | RO | `WinX_g` | Columns of the window |
| | | 12:8 | `WIN_Y` | RO | `WinY_g` | Lines of the window |
| | | 20:16 | `COEF_BITS` | RO | `CoefBits_g` | Bits of a coefficient |
| | | 29:24 | `PIXEL_BITS` | RO | `PixelBits_g` | Bits per pixel of the window |
| 0x008 | `CTRL` | 0 | `HOLD` | RW | 0 | 1: the image starts do not take the coefficient registers |
| 0x00C | `STATUS` | 9 | `ERR_CONFIG` | W1C | 0 | Set by every pulse of `Err_Config` |
| 0x010 | `INJECT` | 0 | `PARITY` | W1 | 0 | Write one: inverts the parity bit of `COEF[INDEX]` (test of the error handling); reads as zero |
| | | 15:8 | `INDEX` | W | 0 | Coefficient whose parity bit a write of `PARITY` inverts; an index of T or above has no effect; reads as zero |
| 0x100 + 4 x k | `COEF[k]`, k = 0 to T - 1 | 17:0 | `COEF` | RW | `Coef_g`(k) | Coefficient of element k (two's complement, `CoefBits_g` bits); reads sign-extended to 32 bits |

| ID | Requirement | Core requirement |
| --- | --- | --- |
| CNV-RG-01 | The AXI4-Lite slave shall implement the registers of this section with the stated addresses, fields, access types and reset values, and answer every access with OKAY. | ISP-CFG-03 |
| CNV-RG-02 | A flag of `STATUS` that is set by its event in the cycle of a write that clears it shall stay set. | ISP-CFG-03 |
| CNV-RG-03 | A write to a coefficient register shall change only the bytes that the write strobes select, and set the parity bit for the resulting value. | ISP-CFG-03, ISP-FT-05 |
| CNV-RG-04 | A write of one to `INJECT.PARITY` shall invert the parity bit of `COEF[INDEX]` of the same write, so that the next image start that takes the registers finds a mismatch. | ISP-FT-05 |
