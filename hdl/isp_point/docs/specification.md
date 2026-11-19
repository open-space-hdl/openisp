# isp_point: Specification

## 1. Overview

`isp_point` is the pixel-level operation of OpenISP. It changes every pixel on its own, without its neighbours: it
adds a signed offset, multiplies the sum by an unsigned gain, shifts the product right and clamps the result between
a lower and an upper threshold. With these four steps it covers the bit shift that scales the sums of a filter or of
the binning, a global gain and offset correction, the reduction of the pixel width and thresholds.

The five parameters are set by generics or, with `Runtime_g`, by registers on an AXI4-Lite slave (section 7). The
input of the module is an [`isp_frame_sync`](../../isp_frame_sync/docs/specification.md). The image keeps its
dimensions; the pixel width changes from `InBits_g` to `OutBits_g`. The module has no memory.

### 1.1 Definitions

| Term | Definition |
| --- | --- |
| p, q | Input pixel (unsigned, `InBits_g` bits) and output pixel (unsigned, `OutBits_g` bits). |
| Offset | Signed number of `InBits_g` + 1 bits. |
| Gain | Unsigned number of `GainBits_g` bits. |
| Shift | Number of bit positions, 0 to `MaxShift_g`. |
| Low, High | Thresholds: unsigned numbers of `OutBits_g` bits. |
| v | floor((p + Offset) x Gain / 2^Shift): the shift is arithmetic and drops the lower bits without rounding. |
| Operation | q = min(max(v, Low), High). |
| Parameter set | Offset, Gain, Shift, Low and High together. |

## 2. Requirements

### 2.1 Interfaces

| ID | Requirement | Core requirement |
| --- | --- | --- |
| PNT-IF-01 | The module shall take pixels of `InBits_g` bits on a pixel stream (`In_Valid`, `In_Ready`, `In_Data`, `In_Last`, `In_User`). | ISP-STR-01, ISP-STR-02 |
| PNT-IF-02 | The module shall output pixels of `OutBits_g` bits on a pixel stream (`Out_Valid`, `Out_Ready`, `Out_Data`, `Out_Last`, `Out_User`). | ISP-STR-01, ISP-STR-02 |
| PNT-IF-03 | The module shall have an AXI4-Lite slave (`S_AxiLite_*`, 32 data bits, 8 address bits, clock `Clk`) for the registers of section 7. | ISP-CFG-03 |
| PNT-IF-04 | The module shall output the status of its `isp_frame_sync` (`Err_Framing`, `Stat_ImageOpen`) and pulse `Err_Config` for one clock cycle for every parameter set it rejects (PNT-ER-03). | ISP-STR-08, ISP-STR-10, ISP-FT-05 |
| PNT-IF-05 | The module shall have one clock `Clk` and a synchronous, high-active reset `Rst`. | ISP-GEN-01 |

### 2.2 Function

| ID | Requirement | Core requirement |
| --- | --- | --- |
| PNT-FN-01 | For every pixel p of an image the module shall output the pixel q of the operation of section 1.1 at the same position, with the parameter set of the image. | ISP-PNT-01, ISP-STR-03 |
| PNT-FN-02 | The module shall take its input through `isp_frame_sync` with the dimensions of the image and output the image with the same dimensions as one stream packet per line with the sequence flags of the line. | ISP-STR-04, ISP-STR-05, ISP-STR-06, ISP-STR-08 |
| PNT-FN-03 | With `Runtime_g` false the parameter set shall be the generics `Offset_g`, `Gain_g`, `Shift_g`, `Low_g` and `High_g`. | ISP-PNT-02 |
| PNT-FN-04 | With `Runtime_g` true the module shall take the parameter set from the registers with every image start at which `CTRL.HOLD` is 0 and use it for the whole image; at an image start with `CTRL.HOLD` 1 the parameter set of the image before shall stay. | ISP-PNT-02, ISP-CFG-02 |
| PNT-FN-05 | A value of the register `SHIFT` above `MaxShift_g` shall be taken as `MaxShift_g`. | ISP-PNT-02 |
| PNT-FN-06 | The output shall not depend on the timing of the stream handshakes, and an image start may follow the last pixel of an image without a gap. | ISP-STR-07 |

### 2.3 Throughput and latency

| ID | Requirement | Core requirement |
| --- | --- | --- |
| PNT-PF-01 | With `In_Valid` and `Out_Ready` high, the module shall accept one pixel per clock cycle, also across the lines and from one image to the next. | ISP-STR-09 |
| PNT-PF-02 | With `Out_Ready` high, a pixel shall be at the output at most `MultStages_g` + 5 clock cycles after the module accepted it. | ISP-STR-09 |

### 2.4 Error handling

| ID | Requirement | Core requirement |
| --- | --- | --- |
| PNT-ER-01 | Every output image shall be complete whatever the input; the pixels that `isp_frame_sync` generated for missing pixels pass the operation like the others. | ISP-STR-08 |
| PNT-ER-02 | The image after an error shall be processed as if no error had occurred. | ISP-STR-08 |
| PNT-ER-03 | A parameter set with a register whose parity bit does not match at the image start shall be rejected: the image shall be processed with the parameter set of the generics (E5). | ISP-FT-05 |

### 2.5 Fault tolerance

| ID | Requirement | Core requirement |
| --- | --- | --- |
| PNT-FT-01 | The parameter set in use shall be loaded with every image start (PNT-FN-04), and the datapath shall keep no state between pixels, so that an upset of the datapath disturbs at most the image in progress. | ISP-FT-04 |
| PNT-FT-02 | Every parameter register shall carry one parity bit over its bits, set by the reset and by every write, and checked with every image start at which the registers are taken (PNT-ER-03). | ISP-FT-05 |
| PNT-FT-03 | After the reset, `In_Ready`, `Out_Valid`, `Err_Framing`, `Err_Config` and `Stat_ImageOpen` shall be defined, and with defined input pixels every output beat shall be free of metavalues. | ISP-FT-04 |

The module has no memory, so the requirements on memories (ISP-FT-01 to ISP-FT-03) do not apply to it.

### 2.6 Partner behaviour

The partners of the input are those of `isp_frame_sync` (its specification, section 2.6); a typical source is a
filter or the binning, whose sums the module scales. The consumer of the output may hold `Out_Ready` low at any beat.
The AXI4-Lite master is a processor or a register bridge of the system on the clock `Clk`; it may access the
registers at any time. A register bus in another clock domain needs a clock crossing in the system.

## 3. Error conditions

The errors E1 to E4 of `isp_frame_sync` apply to the input stream; `Err_Framing` reports them.

| ID | Condition | Detection | Response | Status |
| --- | --- | --- | --- | --- |
| E5 | `Runtime_g` true: the parity bit of a parameter register does not match its value at an image start with `CTRL.HOLD` 0 (upset of the register) | Parity check with the image start | The image is processed with the parameter set of the generics, and so is every further image until the register is written | `Err_Config`, `STATUS.ERR_CONFIG` |

## 4. Configuration parameters

| Generic | Default | Range | Description |
| --- | --- | --- | --- |
| `ImageWidth_g` | none | 1 to 65536 | Pixels per line |
| `ImageHeight_g` | none | 1 to 65536 | Lines per image |
| `InBits_g` | none | 1 to 64 | Bits per input pixel |
| `OutBits_g` | none | 1 to 32 | Bits per output pixel |
| `GainBits_g` | 16 | 1 to 18 | Bits of the gain |
| `MaxShift_g` | `InBits_g` + `GainBits_g` | 0 to `InBits_g` + `GainBits_g` + 1 | Largest shift |
| `Offset_g` | 0 | Range of the offset, within -2^31 to 2^31 - 1 | Offset; with `Runtime_g` the reset value of `OFFSET` |
| `Gain_g` | 1 | 0 to 2^`GainBits_g` - 1 | Gain; with `Runtime_g` the reset value of `GAIN` |
| `Shift_g` | 0 | 0 to `MaxShift_g` | Shift; with `Runtime_g` the reset value of `SHIFT` |
| `Low_g` | 0 | 0 to 2^`OutBits_g` - 1, within 0 to 2^31 - 1 | Lower threshold; with `Runtime_g` the reset value of `LOW` |
| `High_g` | -1 | -1 (full scale, 2^`OutBits_g` - 1) or as `Low_g` | Upper threshold; with `Runtime_g` the reset value of `HIGH` |
| `Runtime_g` | false | false, true | Parameter set from the generics (false: the parameter registers are read only) or from the registers (true) |
| `MultStages_g` | 2 | 1 to 4 | Register stages of the multiplier |

Output image: `ImageWidth_g` x `ImageHeight_g` pixels of `OutBits_g` bits. With the defaults the module passes the
pixels and limits them to the output width.

Typical settings: a bit shift is `Gain_g` 1 with `Shift_g`; the average of a bin of n pixels is `Shift_g` =
log2(n) for a power of two, otherwise `Gain_g` = round(2^k / n) with `Shift_g` = k; a dark level is a negative
`Offset_g`.

## 5. Configuration checks

| ID | Requirement | Core requirement |
| --- | --- | --- |
| PNT-CF-01 | A generic outside its range of section 4 shall stop the elaboration with a message naming the generic. | ISP-CFG-01 |
| PNT-CF-02 | The module shall be synthesizable with GHDL for the bounds of every numeric generic and both values of `Runtime_g`. | ISP-GEN-01 |
| PNT-CF-03 | The default configuration shall be designed for 150 MHz on the FPGA families of the reference systems; synthesis results are recorded in the verification report. | ISP-GEN-03 |

## 6. Interpretation

- The sum p + Offset can be negative. The product and the shifted value then are negative as well (the shift keeps
  the sign), and the lower threshold, which is never negative, replaces them.
- The thresholds are applied in the order of section 1.1: first the lower, then the upper one. A lower threshold above
  the upper one therefore gives the upper threshold for every pixel.
- The limit of the output width needs no step of its own: the upper threshold is at most 2^`OutBits_g` - 1.
- `CTRL.HOLD` makes a change of several registers take effect together: the software sets it, writes the registers
  and clears it. Without it, an image start between two writes takes a mixed parameter set for one image.
- The shift does not round. A rounded shift by s is the same operation with an offset: the software adds 2^(s - 1) /
  Gain to the offset where that is a whole number.

## 7. Register map

Byte addresses of 32-bit registers on the AXI4-Lite slave. Access: RO read only, RW read and write, W1C sticky flag,
write one to clear, W1 command, write one. Reads of other addresses return 0, writes to them and to read-only
fields have no effect; every access is answered with OKAY. With `Runtime_g` false the registers from `OFFSET_LO` to
`HIGH` are read only and show the generics.

| Address | Register | Bits | Field | Access | Reset | Description |
| --- | --- | --- | --- | --- | --- | --- |
| 0x00 | `ID` | 31:0 | `ID` | RO | 0x504E5401 | 0x504E54 (PNT) and register map version 1 |
| 0x04 | `IMAGE` | 15:0 | `WIDTH_M1` | RO | `ImageWidth_g` - 1 | Pixels per line, minus one |
| | | 31:16 | `HEIGHT_M1` | RO | `ImageHeight_g` - 1 | Lines per image, minus one |
| 0x08 | `PARAM` | 6:0 | `IN_BITS` | RO | `InBits_g` | Bits per input pixel |
| | | 13:8 | `OUT_BITS` | RO | `OutBits_g` | Bits per output pixel |
| | | 20:16 | `GAIN_BITS` | RO | `GainBits_g` | Bits of the gain |
| | | 30:24 | `MAX_SHIFT` | RO | `MaxShift_g` | Largest shift |
| 0x0C | `CTRL` | 0 | `HOLD` | RW | 0 | 1: the image starts do not take the parameter registers |
| 0x10 | `STATUS` | 0 | `IMAGE_OPEN` | RO | 0 | An input image is open (`Stat_ImageOpen`) |
| | | 8 | `ERR_FRAMING` | W1C | 0 | Set by every pulse of `Err_Framing` |
| | | 9 | `ERR_CONFIG` | W1C | 0 | Set by every pulse of `Err_Config` |
| 0x14 | `INJECT` | 0 | `GAIN_PARITY` | W1 | 0 | Write one: inverts the parity bit of `GAIN` (test of the error handling); reads as zero |
| 0x18 | `OFFSET_LO` | 31:0 | `OFFSET` | RW | `Offset_g` | Bits 31:0 of the offset (two's complement) |
| 0x1C | `OFFSET_HI` | 31:0 | `OFFSET` | RW | Sign of `Offset_g` | Bits 63:32 of the offset; the bits above `InBits_g` are not used |
| 0x20 | `GAIN` | 17:0 | `GAIN` | RW | `Gain_g` | Gain; the bits above `GainBits_g` - 1 are not used |
| 0x24 | `SHIFT` | 6:0 | `SHIFT` | RW | `Shift_g` | Shift |
| 0x28 | `LOW` | 31:0 | `LOW` | RW | `Low_g` | Lower threshold; the bits above `OutBits_g` - 1 are not used |
| 0x2C | `HIGH` | 31:0 | `HIGH` | RW | `High_g` | Upper threshold; the bits above `OutBits_g` - 1 are not used |

| ID | Requirement | Core requirement |
| --- | --- | --- |
| PNT-RG-01 | The AXI4-Lite slave shall implement the registers of this section with the stated addresses, fields, access types and reset values, and answer every access with OKAY. | ISP-CFG-03 |
| PNT-RG-02 | A flag of `STATUS` that is set by its event in the cycle of a write that clears it shall stay set. | ISP-CFG-03 |
| PNT-RG-03 | A write to a parameter register shall change only the bytes that the write strobes select, and set the parity bit for the resulting value. | ISP-CFG-03, ISP-FT-05 |
| PNT-RG-04 | A write of one to `INJECT.GAIN_PARITY` shall invert the parity bit of `GAIN`, so that the next image start that takes the registers finds a mismatch. | ISP-FT-05 |
