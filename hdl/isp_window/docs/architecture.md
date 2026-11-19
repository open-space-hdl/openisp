# isp_window: Architecture

## 1. Block diagram

![isp_window block diagram: frame sync, event control, line buffers, window register and
output](img/isp_window_arch.drawio.svg)

The frame sync (WN-1) delivers complete images with the position of every pixel. The event control (WN-2) turns
every pixel into a pixel event and adds the events that the borders need. In a pixel event, the line buffers (WN-3)
deliver the pixels of the same column in the `WinY_g` - 1 lines above; with the new pixel they form a column of
`WinY_g` pixels. The window register (WN-4) selects the rows for the upper and lower border, shifts the column in and
handles the left and right border. The output (WN-5) marks the windows of the reference pixels as valid and forms
the packets of the output image.

## 2. Building blocks

| ID | Block | Function |
| --- | --- | --- |
| WN-1 | Frame sync | [`isp_frame_sync`](../../isp_frame_sync/docs/architecture.md) with `ImageWidth_g`, `ImageHeight_g`, `PixelBits_g`: input stream handling, position of every pixel, `Err_Framing`, `Stat_ImageOpen`. |
| WN-2 | Event control | Event state machine (section 5), counters of the virtual columns and lines, row select of the line. |
| WN-3 | Line buffers | `WinY_g` - 1 `olo_ft_delay` in a chain, each `PixelBits_g` wide with a delay of `ImageWidth_g` (section 6). |
| WN-4 | Window register | Row select for the upper and lower border, `WinX_g` columns of `WinY_g` pixels, loads for the left and right border (section 7). |
| WN-5 | Output | `Out_Valid`, `Out_Last`, `Out_User` from the position of the event (section 8); the window register is `Out_Data`. |

## 3. Ports

| Port | Direction | Width | Description |
| --- | --- | --- | --- |
| `Clk` | in | 1 | Clock |
| `Rst` | in | 1 | Synchronous reset, high-active |
| `In_Valid`, `In_Ready`, `In_Data`, `In_Last`, `In_User` | | as `isp_frame_sync` | Input pixel stream |
| `Out_Valid` | out | 1 | Window stream: valid |
| `Out_Ready` | in | 1 | Window stream: ready |
| `Out_Data` | out | `WinX_g` x `WinY_g` x `PixelBits_g` | Window stream: window, element k in bits (k + 1) x `PixelBits_g` - 1 downto k x `PixelBits_g` |
| `Out_Last` | out | 1 | Window stream: last window of a line of the output image |
| `Out_User` | out | 2 | Window stream: sequence flags of the line |
| `Err_Framing` | out | 1 | Pulse: error of the input stream (from WN-1) |
| `Stat_ImageOpen` | out | 1 | Level: an input image is open (from WN-1) |
| `Stat_EccSec` | out | 1 | Pulse: a line buffer corrected a single bit error |
| `Stat_EccDed` | out | 1 | Pulse: a line buffer detected a double bit error |
| `ErrInj_BitFlip` | in | max(`WinY_g` - 1, 1) x eccCodewordWidth(`PixelBits_g`) | Flip pattern, codeword of line buffer t in bits t x C - 1 downto (t - 1) x C (C the codeword width, t from 1) |
| `ErrInj_Valid` | in | 1 | Latches the flip pattern for the next pixel event |

## 4. Derived constants

| Constant | Value | Meaning |
| --- | --- | --- |
| Ax, Ay | `AnchorX_g`, `AnchorY_g` | Reference pixel in the window |
| Rr, Rb | `WinX_g` - 1 - Ax, `WinY_g` - 1 - Ay | Columns right of the reference pixel, lines below it |
| X0, Y0 | 0 in the border modes zero, replicate, mirror; Ax, Ay in the border mode valid | First reference pixel |
| Wo, Ho | Specification, section 1.1 | Output image |
| XL, YL | X0 + (Wo - 1) x `StrideX_g`, Y0 + (Ho - 1) x `StrideY_g` | Last reference pixel of a line, last line with reference pixels |

## 5. Events (WN-2)

The datapath advances by column events, at most one per clock cycle. Every event shifts one column into the window
register.

| Event | Source | Line buffers | When |
| --- | --- | --- | --- |
| PIX | A pixel from WN-1, at its position (xe, ye) | Shift by one pixel | Every pixel of the image |
| HCOL | Virtual column xe = W to W + Rr - 1 | No shift | After the last pixel of every line, border modes zero, replicate, mirror |
| VPIX | Virtual pixel of value 0 at (xe, ye), ye = H to H + Rb - 1 | Shift by one pixel | Rb virtual lines after the last line, each followed by its HCOL events; border modes zero, replicate, mirror |

An event at (xe, ye) completes the window of the pixel (xe - Rr, ye - Rb): its last column and its last line have
arrived. In the border mode valid there are only PIX events.

| State | Events | Next state |
| --- | --- | --- |
| `Pix_s` | PIX for every pixel that WN-1 delivers | `HCol_s` after the last pixel of a line (Rr > 0, border modes); otherwise `VPix_s` after the last pixel of the image (Rb > 0, border modes) |
| `HCol_s` | Rr HCOL; the input waits | `Pix_s`; `VPix_s` after the last line of the image or within the virtual lines |
| `VPix_s` | W VPIX; the input waits | `HCol_s` (Rr > 0); `Pix_s` after the last virtual line |

For PIX events the position is the one WN-1 delivers; the module counts only the virtual columns and lines itself.
The reset and the `when others` branch lead to `Pix_s`, and pixel (0, 0) of WN-1 restarts the counters: an upset of
the state or of a counter disturbs the image in progress only (WIN-FT-03).

An event waits while the window register holds a window that the consumer has not taken (`Out_Valid` high and
`Out_Ready` low); a PIX event also waits for a pixel of WN-1.

## 6. Line buffers (WN-3)

The line buffers are `WinY_g` - 1 instances of `olo_ft_delay` in a chain: the input of the first is the pixel of the
event, the input of every other is the output of the one before. All have the width `PixelBits_g`, the delay
`ImageWidth_g`, `RstState_g` true and the event as `In_Valid` (PIX and VPIX). In an event at (xe, ye) the output of
delay t (t = 1 to `WinY_g` - 1) is the pixel of column xe in line ye - t; with the pixel of the event (t = 0) these
are the `WinY_g` pixels of the column.

- Every pixel is its own SECDED codeword, so the decoder depth does not grow with the window, a double error touches
  one pixel, and the same structure serves every window height.
- A line has exactly W shifts (PIX or VPIX), whatever the timing of the input: the delay counts pixels, not clock
  cycles.
- The error flags of the delays are sampled in the event: `Stat_EccSec` and `Stat_EccDed` are the OR over the
  delays that the row selection of the event uses (WIN-FT-02). The delays above the first lines of an image hold the
  image before, or after power-up whatever the RAM holds; their data never reaches a window, and neither do their
  flags.
- `EccPipeline_g` 1 (default) registers the corrected output of every delay, so that the path from one delay to the
  encoder of the next and to the window register starts at a register.

| Configuration | Line buffer data | With check bits |
| --- | --- | --- |
| 3 x 3, 12 bits, 2048 pixels per line | 49 kbit | 74 kbit (2 x 2048 x 18) |
| 5 x 5, 16 bits, 4096 pixels per line | 262 kbit | 360 kbit (4 x 4096 x 22) |
| 1 x 9, any | none | none |

## 7. Window register and borders (WN-4)

### 7.1 Upper and lower border

Row j of the window of an event in line ye is the pixel of line ye - (`WinY_g` - 1) + j, the output of delay
`WinY_g` - 1 - j. A row outside the image takes its value from the border mode: 0, or the delay that holds the line
which the replicate or mirror rule names. That line is always one of the `WinY_g` lines of the column (the mirror
mode has its reference pixel in the middle, WIN-CF-02), and always a line of the image in progress (WIN-FT-04).

The selection depends on the line only: on ye up to `WinY_g` - 2 for the upper border and on the number of the
virtual line for the lower border. The event control sets a row select vector at the start of every line from a
constant table; every column passes `WinY_g` multiplexers of at most `WinY_g` + 1 inputs.

### 7.2 Left and right border

The window register holds `WinX_g` columns; every event shifts it by one column and writes the new column into the
last one. `Out_Data` is the register itself. The border modes act on what is loaded:

| Mode | First events of a line (left border) | HCOL events (right border) |
| --- | --- | --- |
| valid | Nothing | None |
| zero | The event of column 0 clears the other columns | The new column is 0 |
| replicate | The event of column 0 loads its column into all columns | The new column is a copy of the last one |
| mirror | The event of column k (1 to Ax) also loads its column into the column 2k places before the last | HCOL m (1 to Rr) loads the column 2m - 1 places before the last, which holds column W - 1 - m |

`BorderMode_g` is a generic, so only the multiplexers of the selected mode exist.

## 8. Output (WN-5)

The window of an event at (xe, ye) is valid when its pixel (x, y) = (xe - Rr, ye - Rb) is a reference pixel:
X0 <= x <= XL with (x - X0) a multiple of `StrideX_g`, and the same for y. Two small counters, restarted with X0 and
Y0, follow the stride. The packet signals come from the position, without a counter of the output image:

| Signal | Value |
| --- | --- |
| `Out_Last` | x = XL |
| `Out_User` | "11" when y = Y0 and Y0 = YL; "01" when y = Y0; "10" when y = YL; "00" otherwise |

## 9. Timing and throughput

| Property | Value | Requirement |
| --- | --- | --- |
| Pixel rate | One event per clock cycle; within a line every event is a PIX event; the input waits for the Rr HCOL events of every line, which the input stage of WN-1 shifts by up to two pixels into the next line | WIN-PF-01 |
| Image period | (H + Rb) x (W + Rr) events in the border modes zero, replicate, mirror, H x W in the border mode valid, plus the registers of WN-1 at the image boundary | WIN-PF-02 |
| Latency | 2 clock cycles in WN-1, one for the event into the window register: 3 clock cycles; up to 2 more for a pixel that WN-1 took while the module held its input: at most 5 clock cycles | WIN-PF-03 |

Paths: from the output registers of the delays through the row select and the border multiplexer of a column into
the window register (two to three LUT levels for windows up to 9 lines); `Out_Ready` to the enable of the window
register, the delays and the ready input of WN-1 through one logic level, with a fanout of the window size that the
synthesis tool replicates.

## 10. Fault tolerance

| Element | Protection |
| --- | --- |
| Line buffers | SECDED per pixel in `olo_ft_delay`; a pixel lives for at most `WinY_g` - 1 lines |
| Window register, output signals | Flip-flops; an upset changes windows of the image in progress |
| Event state machine, counters | `when others` to `Pix_s`, restart with pixel (0, 0) of every image |

Triple modular redundancy of the flip-flops is a choice of the integrator in the synthesis tool.

## 11. Resource estimate

Beside the line buffers and WN-1: the window register of `WinX_g` x `WinY_g` x `PixelBits_g` flip-flops and the row
and border multiplexers. About 250 flip-flops and 250 LUTs for 3 x 3 windows of 12-bit pixels, about 900 flip-flops
and 900 LUTs for 5 x 5 windows of 16-bit pixels. Synthesis results replace these estimates in the verification
report.
