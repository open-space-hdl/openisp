# isp_point: Architecture

## 1. Block diagram

![isp_point block diagram: frame sync, arithmetic, clamp and
registers](img/isp_point_arch.drawio.svg)

The frame sync (PT-1) delivers complete images. The arithmetic (PT-2) adds the offset, multiplies by the gain and
shifts; the clamp (PT-3) applies the two thresholds and holds the output pixel. The registers (PT-4) are on an
AXI4-Lite slave; the arithmetic loads the parameter set it works with at the image start.

## 2. Building blocks

| ID | Block | Function |
| --- | --- | --- |
| PT-1 | Frame sync | [`isp_frame_sync`](../../isp_frame_sync/docs/architecture.md) with `ImageWidth_g`, `ImageHeight_g` and `InBits_g`: input stream handling, `Err_Framing`, `Stat_ImageOpen`. |
| PT-2 | Arithmetic | Working parameter set, loaded with pixel (0, 0); offset adder, multiplier with `MultStages_g` register stages, shifter. |
| PT-3 | Clamp | Comparison with the two thresholds, output register. |
| PT-4 | Registers | `olo_axi_lite_slave` (8 address bits, 32 data bits) with the registers of the specification (section 7), one parity bit per parameter register. |

## 3. Ports

| Port | Direction | Width | Description |
| --- | --- | --- | --- |
| `Clk` | in | 1 | Clock |
| `Rst` | in | 1 | Synchronous reset, high-active |
| `In_Valid`, `In_Ready`, `In_Last`, `In_User` | | as `isp_frame_sync` | Input pixel stream |
| `In_Data` | in | `InBits_g` | Input stream: pixel |
| `Out_Valid` | out | 1 | Output stream: valid |
| `Out_Ready` | in | 1 | Output stream: ready |
| `Out_Data` | out | `OutBits_g` | Output stream: pixel |
| `Out_Last` | out | 1 | Output stream: last pixel of a line |
| `Out_User` | out | 2 | Output stream: sequence flags of the line |
| `S_AxiLite_*` | | 8 address bits, 32 data bits | AXI4-Lite slave of the registers, port names of `olo_axi_lite_slave` |
| `Err_Framing` | out | 1 | Pulse: error of the input stream (from PT-1) |
| `Err_Config` | out | 1 | Pulse: parameter set rejected |
| `Stat_ImageOpen` | out | 1 | Level: an input image is open (from PT-1) |

## 4. Pipeline

The pixel, `Last` and the sequence flags of PT-1 pass the stages below; the packet signals travel beside the pixel
unchanged. All stages share one enable: they advance when the output register is empty or its beat transfers. The
stages hold no state between pixels.

| Stage | Registers | Operation | Width |
| --- | --- | --- | --- |
| 1 | Sum | p + Offset | `InBits_g` + 2, signed |
| 2 to 1 + `MultStages_g` | Product | Sum x Gain; the register stages are placed by the retiming of the synthesis tool | `InBits_g` + `GainBits_g` + 2, signed |
| 2 + `MultStages_g` | Shifted value | Arithmetic shift right by Shift, 0 to `MaxShift_g`: a barrel shifter | as the product |
| 3 + `MultStages_g` | Output register | min(max(v, Low), High): two comparisons of the shifted value with the thresholds | `OutBits_g` |

With `Runtime_g` false the parameters are constants: a gain of 1 removes the multiplier, a constant shift is wiring,
an offset of 0 removes the adder, and thresholds at 0 and full scale reduce the clamp to the test of the upper bits.

## 5. Parameter set (PT-2, PT-4)

With `Runtime_g` true the arithmetic works with a working parameter set, registers of its own beside the parameter
registers of PT-4:

- The cycle that takes pixel (0, 0) from PT-1 loads the working set from the parameter registers when `CTRL.HOLD` is
  0. The pixel reaches stage 1 one cycle later, so the working set is valid for the first pixel of the image.
- In the same cycle the parity of every parameter register is compared with its parity bit. A mismatch loads the
  generics into the working set and pulses `Err_Config` (E5).
- A value of `SHIFT` above `MaxShift_g` is loaded as `MaxShift_g`.
- With `CTRL.HOLD` 1 the working set is not loaded and stays that of the image before.

The working set is loaded again with every image, so an upset of it lasts for one image. The thresholds reach the
clamp from the working set through as many register stages as the pixel passes between stage 1 and the clamp, so
that an image that follows without a gap does not change the thresholds of the last pixels of the image before.

## 6. Registers (PT-4)

`olo_axi_lite_slave` turns the AXI4-Lite accesses into single-cycle read and write strobes with an address. The
register block answers a read in the following cycle and every access with OKAY.

| Register | Implementation |
| --- | --- |
| `ID`, `IMAGE`, `PARAM` | Constants from the generics |
| `CTRL.HOLD` | One flip-flop |
| `OFFSET_LO`, `OFFSET_HI`, `GAIN`, `SHIFT`, `LOW`, `HIGH` | Flip-flops for the bits in use, with the reset values of the generics, written byte by byte with the write strobes; one parity flip-flop per register that the reset and every write set for the resulting value (`Runtime_g` true); constants otherwise |
| `STATUS` | `Stat_ImageOpen`; sticky flags set by `Err_Framing` and `Err_Config`, cleared by a write of one, the pulse wins |
| `INJECT.GAIN_PARITY` | Command: inverts the parity flip-flop of `GAIN` |

## 7. Timing and throughput

| Property | Value | Requirement |
| --- | --- | --- |
| Pixel rate | One pixel per clock cycle through PT-1 and the pipeline | PNT-PF-01 |
| Latency | 2 clock cycles in PT-1 and 3 + `MultStages_g` stages: `MultStages_g` + 5 clock cycles | PNT-PF-02 |

Paths: `Out_Ready` reaches the enable of all stages and the ready input of PT-1 through one logic level; the fanout
grows with the widths and is replicated by the synthesis tool. The longest paths are the multiplier (up to 66 x 18
bits, spread over `MultStages_g` stages) and the barrel shifter (up to seven multiplexer levels for 84 bits); a
configuration at the upper bounds of the widths uses `MultStages_g` 3 or 4.

## 8. Fault tolerance

The module has no memory. The datapath holds no state between pixels, and the working parameter set is loaded with
every image: an upset of either disturbs at most one image. The parameter registers live until they are written;
their parity bits detect an upset of one bit at the next image start, the generics then apply and `Err_Config` and
`STATUS.ERR_CONFIG` report it until the software writes the register again. Triple modular redundancy of the
flip-flops is a choice of the integrator in the synthesis tool.

## 9. Resource estimate

For 12-bit input pixels, a 16-bit gain, 12-bit output pixels and `Runtime_g` true: one multiplier of 14 x 16 bits
(one DSP block), about 450 flip-flops (frame sync, pipeline, parameter registers and working set, AXI4-Lite slave)
and about 400 LUTs. With `Runtime_g` false and a pure bit shift: about 150 flip-flops and no multiplier. Synthesis
results replace these estimates in the verification report.
