# isp_conv: Architecture

## 1. Block diagram

![isp_conv block diagram: multipliers, adder tree, limiter and
registers](img/isp_conv_arch.drawio.svg)

A window enters the multipliers (CV-1), one per element, each with its coefficient. The adder tree (CV-2) adds the
products in pairs, level by level. The limiter (CV-3) sets a negative sum to 0, saturates it where the output is
narrower than the full precision, and holds the output pixel. The registers (CV-4) are on an AXI4-Lite slave; the
multipliers load the coefficient set they work with at the image start.

## 2. Building blocks

| ID | Block | Function |
| --- | --- | --- |
| CV-1 | Multipliers | Input register for the window; working coefficient set, loaded with the image start; T multipliers of `PixelBits_g` x `CoefBits_g` bits with a register. |
| CV-2 | Adder tree | log2ceil(T) levels of signed adders, a register after every level. |
| CV-3 | Limiter | 0 for a negative sum, saturation to `OutBits_g`, output register. |
| CV-4 | Registers | `olo_axi_lite_slave` (12 address bits, 32 data bits) with the registers of the specification (section 7), one parity bit per coefficient register. |

## 3. Ports

| Port | Direction | Width | Description |
| --- | --- | --- | --- |
| `Clk` | in | 1 | Clock |
| `Rst` | in | 1 | Synchronous reset, high-active |
| `In_Valid` | in | 1 | Window stream: valid |
| `In_Ready` | out | 1 | Window stream: ready |
| `In_Data` | in | T x `PixelBits_g` | Window stream: window |
| `In_Last` | in | 1 | Window stream: last window of a line |
| `In_User` | in | 2 | Window stream: sequence flags of the line |
| `Out_Valid` | out | 1 | Output stream: valid |
| `Out_Ready` | in | 1 | Output stream: ready |
| `Out_Data` | out | B (specification, section 1.1) | Output stream: pixel |
| `Out_Last` | out | 1 | Output stream: last pixel of a line |
| `Out_User` | out | 2 | Output stream: sequence flags of the line |
| `S_AxiLite_*` | | 12 address bits, 32 data bits | AXI4-Lite slave of the registers, port names of `olo_axi_lite_slave` |
| `Err_Config` | out | 1 | Pulse: coefficient set rejected |

## 4. Pipeline

The window, `Last` and the sequence flags pass the stages below; the packet signals travel beside the data
unchanged. All stages share one enable: they advance when the output register is empty or its beat transfers. The
stages hold no state between windows.

| Stage | Registers | Operation | Width |
| --- | --- | --- | --- |
| 1 | Window | Input register; detection of the image start | T x `PixelBits_g` |
| 2 | Products | c(k) x e(k) for every element | `PixelBits_g` + `CoefBits_g`, signed |
| 3 to 2 + log2ceil(T) | Partial sums | Pairwise addition, one level per stage; the width grows by one bit per level | up to F + 1, signed |
| 3 + log2ceil(T) | Output register | 0 for a negative sum, saturation to B bits | B |

`In_Ready` is the common enable, so the module adds no register to the ready path; in `isp_filter2d` the window
register of `isp_window` is the source and its ready path ends at the input stage of the frame sync.

With `RuntimeCoef_g` false the coefficients are constants: the synthesis tool turns the multipliers into shifts and
adders, removes those of the coefficients 0 and reduces those of the coefficients 1 and -1 to wires. A kernel of
ones, as the binning uses it, is an adder tree only.

## 5. Coefficient set (CV-1, CV-4)

With `RuntimeCoef_g` true the multipliers work with a working coefficient set, registers of their own beside the
coefficient registers of CV-4:

- The module marks the first beat of every stream packet (after the reset and after every beat with `In_Last`). A
  first beat with the sequence flags "01" or "11" is the image start.
- The cycle that takes the window of the image start into stage 1 loads the working set from the coefficient
  registers when `CTRL.HOLD` is 0. The window reaches the multipliers one cycle later, so the working set is valid
  for the first window of the image.
- In the same cycle the parity of every coefficient register is compared with its parity bit. A mismatch in any of
  them loads the generic into the working set and pulses `Err_Config` (E1).
- With `CTRL.HOLD` 1 the working set is not loaded and stays that of the image before.

The working set is loaded again with every image, so an upset of it lasts for one image.

## 6. Registers (CV-4)

`olo_axi_lite_slave` turns the AXI4-Lite accesses into single-cycle read and write strobes with an address. The
register block answers a read in the following cycle and every access with OKAY.

| Register | Implementation |
| --- | --- |
| `ID`, `PARAM` | Constants from the generics |
| `CTRL.HOLD` | One flip-flop |
| `COEF[k]` | `CoefBits_g` flip-flops with the reset value `Coef_g`(k), written byte by byte with the write strobes; one parity flip-flop per register that the reset and every write set for the resulting value (`RuntimeCoef_g` true); constants otherwise |
| `STATUS.ERR_CONFIG` | Sticky flag set by `Err_Config`, cleared by a write of one, the pulse wins |
| `INJECT.COEF0_PARITY` | Command: inverts the parity flip-flop of `COEF[0]` |

The read multiplexer of the coefficients has T inputs; the read data is registered behind it.

## 7. Timing and throughput

| Property | Value | Requirement |
| --- | --- | --- |
| Window rate | One window per clock cycle | CNV-PF-01 |
| Latency | 3 + log2ceil(T) stages: 6 clock cycles for 3 x 3, 8 for 5 x 5, 10 for 9 x 9 | CNV-PF-02 |

Paths: one multiplier of at most 32 x 18 bits between two registers, one adder of at most F + 1 bits per level, and
the common enable with a fanout that grows with T, replicated by the synthesis tool.

## 8. Fault tolerance

The module has no memory. The datapath holds no state between windows, and the working coefficient set is loaded
with every image: an upset of either disturbs at most one image. The coefficient registers live until they are
written; their parity bits detect an upset of one bit at the next image start, the generic then applies and
`Err_Config` and `STATUS.ERR_CONFIG` report it until the software writes the register again. Triple modular
redundancy of the flip-flops is a choice of the integrator in the synthesis tool.

## 9. Resource estimate

| Configuration | Multipliers | Flip-flops | Remarks |
| --- | --- | --- | --- |
| 3 x 3, 12-bit pixels, 16-bit coefficients, run-time | 9 | about 1100 | 2 x 9 x 17 coefficient and parity bits, window, products, tree |
| 5 x 5, 12-bit pixels, 16-bit coefficients, run-time | 25 | about 2900 | |
| 5 x 5, 12-bit pixels, constant coefficients | none or few | about 1300 | Shifts and adders in LUTs |
| 1 x 4, 12-bit pixels, ones (binning) | none | about 150 | Adder tree only |
| 16 x 16 (largest), 12-bit pixels, 16-bit coefficients, run-time | 256 | about 27000 | 2 x 256 x 17 coefficient and parity bits (8700), window 3100, products 7200, adder tree of eight levels 7700; a read multiplexer of 256 inputs for the coefficients |
| 16 x 16, 12-bit pixels, constant coefficients | none or few | about 18000 | Shifts and adders in LUTs; the cost depends on the coefficients |

Synthesis results replace these estimates in the verification report.
