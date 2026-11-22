# isp_crop: Architecture

## 1. Block diagram

![isp_crop block diagram: frame sync, position stage, selection and
registers](img/isp_crop_arch.drawio.svg)

The frame sync (CR-1) delivers complete images with the position of every pixel. The position stage (CR-2) holds one
pixel with its position and, with pixel (0, 0) of an image, loads the limits of the region of interest from the
register `ROI_POS`. The selection (CR-3) compares the position of the pixel with the limits: a pixel inside goes to
the output register, a pixel outside is dropped. The registers (CR-4) are on an AXI4-Lite slave.

## 2. Building blocks

| ID | Block | Function |
| --- | --- | --- |
| CR-1 | Frame sync | [`isp_frame_sync`](../../isp_frame_sync/docs/architecture.md) with `ImageWidth_g`, `ImageHeight_g`, `PixelBits_g`: input stream handling, `Err_Framing`, `Stat_ImageOpen`. |
| CR-2 | Position stage | Register for one pixel with its position. With `RuntimeRoi_g`: registers for the limits of the region, loaded together with pixel (0, 0); range check and `Err_Config`. |
| CR-3 | Selection | Comparison of the position with the limits; output register with `Out_Last` and `Out_User` formed from the position in the region. |
| CR-4 | Registers | `olo_axi_lite_slave` (8 address bits, 32 data bits) with the registers of the specification (section 7): identification, characteristics, `ROI_POS` with its parity bit, `STATUS`, `INJECT`. |

## 3. Ports

| Port | Direction | Width | Description |
| --- | --- | --- | --- |
| `Clk` | in | 1 | Clock |
| `Rst` | in | 1 | Synchronous reset, high-active |
| `In_Valid`, `In_Ready`, `In_Data`, `In_Last`, `In_User` | | as `isp_frame_sync` | Input pixel stream |
| `Out_Valid` | out | 1 | Output stream: valid |
| `Out_Ready` | in | 1 | Output stream: ready |
| `Out_Data` | out | `PixelBits_g` | Output stream: pixel |
| `Out_Last` | out | 1 | Output stream: last pixel of a line of the region |
| `Out_User` | out | 2 | Output stream: sequence flags of the line |
| `S_AxiLite_*` | | 8 address bits, 32 data bits | AXI4-Lite slave of the registers, port names of `olo_axi_lite_slave` |
| `Err_Framing` | out | 1 | Pulse: error of the input stream (from CR-1) |
| `Err_Config` | out | 1 | Pulse: position of the region rejected |
| `Stat_ImageOpen` | out | 1 | Level: an input image is open (from CR-1) |

The inputs of the AXI4-Lite slave default to inactive, so that a system without a register bus leaves it open.

## 4. Generics and limits of the region

The generics, defaults and ranges are those of the specification (section 4). The selection works with four limits:

| Limit | `RuntimeRoi_g` false | `RuntimeRoi_g` true |
| --- | --- | --- |
| X0, Y0 (first column, first line) | Constants `RoiX_g`, `RoiY_g` | Registers, loaded with pixel (0, 0) |
| X1, Y1 (last column, last line) | Constants `RoiX_g` + `RoiWidth_g` - 1, `RoiY_g` + `RoiHeight_g` - 1 | Registers, loaded with pixel (0, 0): X0 + `RoiWidth_g` - 1, Y0 + `RoiHeight_g` - 1 |

With `RuntimeRoi_g` false the comparisons of the selection are comparisons with constants, and `ROI_POS` reads the
generics.

## 5. Position stage (CR-2)

The stage takes a pixel from CR-1 when it is empty or its pixel leaves in the same cycle. A pixel leaves when it is
outside the region (it is dropped) or when the output register of CR-3 takes it.

With `RuntimeRoi_g` true, the cycle that loads pixel (0, 0) into the stage also loads the limits from `ROI_POS`:

- The position is valid when `ROI_POS.X` <= `ImageWidth_g` - `RoiWidth_g` and `ROI_POS.Y` <= `ImageHeight_g` -
  `RoiHeight_g`, two comparisons with constants.
- The parity of the 32 bits of `ROI_POS` is compared with its parity bit.
- A valid position with matching parity gives X0 = `ROI_POS.X`, Y0 = `ROI_POS.Y`; otherwise X0 = `RoiX_g`,
  Y0 = `RoiY_g` and a pulse on `Err_Config` (E5, E6). The register is not changed.
- X1 and Y1 are computed from the chosen X0 and Y0 in the same cycle.

The limits are registers before the comparison, so pixel (0, 0) is compared with the limits of its own image, and
they are loaded again with every image: a write to `ROI_POS` during an image takes effect with the next image, and
an upset of a limit lasts for one image (CRP-FT-01). Both coordinates are in one register, so the stage never sees a
position that is half written.

## 6. Selection (CR-3)

A pixel at (x, y) is inside the region when X0 <= x <= X1 and Y0 <= y <= Y1. The output register is loaded with a
pixel inside the region; its packet signals are functions of the position, without a counter of the output image:

| Signal | Value |
| --- | --- |
| `Out_Last` | x = X1 |
| `Out_User` | "11" when y = Y0 and Y0 = Y1; "01" when y = Y0; "10" when y = Y1; "00" otherwise |

CR-1 delivers complete images, so every line of the region and every region is complete as well (CRP-ER-01).

## 7. Registers (CR-4)

`olo_axi_lite_slave` turns the AXI4-Lite accesses into single-cycle read and write strobes with an address. The
register block answers a read in the following cycle and every access with OKAY.

| Register | Implementation |
| --- | --- |
| `ID`, `IMAGE`, `ROI_SIZE` | Constants from the generics |
| `ROI_POS` | 2 x 16 flip-flops with the reset values `RoiX_g` and `RoiY_g`, written byte by byte with the write strobes, and one parity flip-flop that the reset sets, and a write by `ispWriteParity` of `isp_pkg` (PKG-08): a write of every byte that holds bits of the register sets it for the written value, a write that keeps one of these bytes keeps a mismatch; every byte of `ROI_POS` holds bits, so a write without a strobe leaves it unchanged (`RuntimeRoi_g` true); constants otherwise |
| `INJECT.ROI_POS_PARITY` | Command: inverts the parity flip-flop |
| `STATUS.IMAGE_OPEN` | `Stat_ImageOpen` |
| `STATUS.ERR_FRAMING`, `STATUS.ERR_CONFIG` | Sticky flags: set by the pulse, cleared by a write of one; the pulse wins when both come in the same cycle (CRP-RG-02) |

The register description `hdl/isp_crop/regs/isp_crop_regs.yml` generates the VHDL package `isp_crop_regs_pkg`
(addresses, field positions, identification), the [register map](register_map.md) and the C header
`sw/isp_crop_regs.h` with `tools/regmap.py`; `tools/regmap.py --check` also compares the description with the table
of the specification.

## 8. Timing and throughput

| Property | Value | Requirement |
| --- | --- | --- |
| Pixel rate | One pixel per clock cycle through CR-1, the position stage and the output register | CRP-PF-01 |
| Latency | 4 clock cycles from the acceptance at the input to `Out_Valid`: 2 in CR-1, one in the position stage, one in the output register | CRP-PF-02 |
| Pixels outside the region | They leave the position stage without the output register, so the input keeps running while the consumer holds `Out_Ready` low, up to the next pixel of the region | CRP-PF-03 |
| Short input image | CR-1 completes the whole input image: the input waits for at most m + 3 cycles for m missing pixels of the input image | FSY-PF-03 |

Paths: `Out_Ready` reaches the enables of the output register and of the position stage and the ready input of CR-1
through one or two logic levels; `In_Ready` is a register inside CR-1. The longest path is the comparison of the
position with the four limits (up to 16 bits each) into the enable of the output register.

## 9. Fault tolerance

The module has no memory and no position counter of its own: the position of every pixel comes from CR-1, and the limits
of the region are loaded with every image. An upset of a datapath register disturbs at most the image in progress.
`ROI_POS` is a register that lives until it is written. Its parity bit detects an upset of one of its bits at the next
image start: the generics apply, `Err_Config` and `STATUS.ERR_CONFIG` report it until the software writes the register
in full (all four bytes); a write that keeps one of the bytes keeps the mismatch. The parity check lies in the cycle
that loads the limits, beside the range check. Triple modular redundancy of the flip-flops is a choice of the integrator
in the synthesis tool.

## 10. Resource estimate

Beside CR-1: the position stage (`PixelBits_g` + the two position widths), the output register (`PixelBits_g` + 4),
the AXI4-Lite slave and, with `RuntimeRoi_g`, `ROI_POS` and the four limits. About 220 flip-flops and 200 LUTs for
12-bit pixels and images up to 4096 x 4096 with `RuntimeRoi_g` true. Synthesis results replace this estimate in the
verification report.
