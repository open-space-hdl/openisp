# isp_window: Specification

## 1. Overview

`isp_window` is the 2D window generator of OpenISP and the front end of every 2D stage (convolution, median,
morphology, defect pixel correction, demosaicing, non-maximum suppression). It takes a raster pixel stream and
delivers, for every pixel, its neighbourhood of `WinX_g` x `WinY_g` pixels as one flattened vector, together with the
position of the centre pixel. The pixels of a window that lie outside the frame are defined by the border mode
(`BorderMode_g`): valid (only windows inside the frame), zero, replicate or mirror. After the end of a frame the
generator delivers the remaining windows of the bottom border itself, without further input.

The generator keeps the `WinY_g` - 1 previous pixels of every column in one line memory of ECC-protected simple
dual-port RAMs of Open Logic (`olo_ft_ram_sdp`, optionally with the scrubber `olo_ft_ram_sdp_scrub`), one word of
(`WinY_g` - 1) x `PixelBits_g` bits per column. The size of the window, the pixel width, the maximum line width, the
border mode and the memory options are generics; the line width of a frame is an input that takes effect with the
start of the frame. A Bayer mosaic is a monochrome raster at this level: the generator treats every pixel alike, and
the position outputs give the colour phase to the following stage.

### 1.1 Definitions

| Term | Definition |
| --- | --- |
| W, H | Line width (pixels per line) and number of lines of the frame in progress. W is the value of `Cfg_LineWidth` at the start of the frame, H follows from the end of frame. |
| p(x, y) | Input pixel in column x (0 to W - 1) of line y (0 to H - 1). |
| Rx, Ry | Window radii: Rx = (`WinX_g` - 1) / 2, Ry = (`WinY_g` - 1) / 2. |
| Window of (x, y) | The pixels p'(x + i, y + j) for i = -Rx to Rx and j = -Ry to Ry, where p' is p extended beyond the frame by the border mode (section 6). |
| Element (i, j) | The pixel p'(x + i, y + j) of a window; element index k = (j + Ry) x `WinX_g` + (i + Rx). |
| Border modes | Valid, zero, replicate, mirror (section 6). "Border modes" without "valid" means zero, replicate and mirror, which keep the frame size. |
| Drain | The windows that the generator outputs after the last pixel they depend on has arrived and no further input is needed: Rx windows at the end of every line and Ry lines at the end of a frame (border modes). |
| Frame open | From the accepted start of frame up to the end of the frame (end of frame, or an error that ends the frame, section 3). |

## 2. Requirements

### 2.1 Interfaces

| ID | Requirement | Core requirement |
| --- | --- | --- |
| WIN-IF-01 | The generator shall take pixels on a valid / ready stream (`In_Valid`, `In_Ready`, `In_Data` of `PixelBits_g` bits) with AXI4-Stream handshake semantics, the end of line on `In_Last` and the start and end of frame on `In_User(0)` and `In_User(1)`. | ISP-STR-01, ISP-STR-02 |
| WIN-IF-02 | The generator shall output one window per beat on a valid / ready stream (`Out_Valid`, `Out_Ready`, `Out_Data` of `WinX_g` x `WinY_g` x `PixelBits_g` bits) with AXI4-Stream handshake semantics; element k of the window occupies bits (k + 1) x `PixelBits_g` - 1 downto k x `PixelBits_g` (element 0 is the top left pixel, the centre pixel is element (`WinX_g` x `WinY_g` - 1) / 2). | ISP-STR-01, ISP-WIN-01 |
| WIN-IF-03 | The output stream shall carry the frame structure of the output frame with its windows: start of frame on `Out_User(0)`, end of line on `Out_Last` and end of frame on `Out_User(1)`, so that a further stage connects to the output as to a pixel stream. | ISP-STR-02, ISP-WIN-01 |
| WIN-IF-04 | With every window the generator shall output the column and the line of its centre pixel in the input frame (`Out_PosX`, unsigned, log2ceil(`MaxLineWidth_g`) bits; `Out_PosY`, unsigned, max(log2ceil(`MaxFrameHeight_g`), 1) bits) and four flags for a centre in the first line, last line, first column and last column of the output frame (`Out_Border`). | ISP-WIN-03 |
| WIN-IF-05 | The generator shall take the line width as an input (`Cfg_LineWidth`, unsigned, log2ceil(`MaxLineWidth_g` + 1) bits). | ISP-STR-03 |
| WIN-IF-06 | The generator shall pulse a status output for one clock cycle for every error of section 3, one output per error class: line width (`Err_LineWidth`), line length (`Err_LineLength`) and frame structure (`Err_Framing`). | ISP-STR-05 |
| WIN-IF-07 | The generator shall have one clock `Clk` and a synchronous, high-active reset `Rst`. | ISP-GEN-01 |

### 2.2 Function

| ID | Requirement | Core requirement |
| --- | --- | --- |
| WIN-FN-01 | For every centre of the output frame, the generator shall output the window of section 1.1 with the pixels of the input frame and, for elements outside the frame, the values of the border mode (section 6). | ISP-WIN-01, ISP-WIN-02 |
| WIN-FN-02 | In the border modes, the output frame shall have W x H windows, one per input pixel; in the valid mode, (W - 2Rx) x (H - 2Ry) windows, those of the centres with Rx <= x <= W - 1 - Rx and Ry <= y <= H - 1 - Ry. | ISP-WIN-01, ISP-WIN-02 |
| WIN-FN-03 | The generator shall output the windows of a frame in raster order of their centres, each exactly once. | ISP-WIN-01 |
| WIN-FN-04 | The generator shall sample `Cfg_LineWidth` with the start of frame; a change during a frame shall take effect with the next frame. | ISP-STR-03 |
| WIN-FN-05 | After the end of frame, the generator shall output the remaining windows of the frame (the drain of the last Ry lines in the border modes) without further input, also when no further frame follows. | ISP-WIN-04 |
| WIN-FN-06 | The start of frame of the next frame may follow the end of frame without a gap; the generator shall hold `In_Ready` low as long as the drain of the previous frame needs. | ISP-STR-04 |
| WIN-FN-07 | The output shall not depend on the timing of the stream handshakes: any pattern of `In_Valid` and `Out_Ready` shall give the same output windows, flags and frame structure, without loss or duplication. | ISP-STR-04 |
| WIN-FN-08 | `Out_PosX` and `Out_PosY` shall give the coordinates (x, y) of the centre in the input frame, also in the valid mode (where the first window has the centre (Rx, Ry)). | ISP-WIN-03 |
| WIN-FN-09 | After the reset, the generator shall discard input pixels up to the first start of frame and then process that frame. | ISP-STR-05, ISP-FT-05 |

### 2.3 Throughput and latency

| ID | Requirement | Core requirement |
| --- | --- | --- |
| WIN-PF-01 | Within a line, with `In_Valid` and `Out_Ready` high, the generator shall accept one pixel per clock cycle. | ISP-WIN-05 |
| WIN-PF-02 | For frames with W >= 32, back-to-back input and `Out_Ready` high, the interval between the starts of two consecutive frames shall not exceed (H + Ry) x (W + Rx) + `RamRdLatency_g` + `EccPipeline_g` + 8 clock cycles in the border modes and H x W + 8 clock cycles in the valid mode. The terms: H x W input pixels; Rx cycles per line for the windows of the right border; Ry lines of W + Rx cycles for the drain of the bottom border; once per frame the read latency of the line memory and its ECC decoder, which the drain waits for; at most 8 cycles of fixed registers between the input and the output. Narrower frames shall be processed correctly at a lower rate. | ISP-WIN-05 |
| WIN-PF-03 | Outside the drains, with `Out_Ready` high, the generator shall output the window of (x, y) at most 8 clock cycles after it accepted the pixel p(x + Rx, y + Ry). | ISP-WIN-05 |

### 2.4 Error handling

| ID | Requirement | Core requirement |
| --- | --- | --- |
| WIN-ER-01 | A `Cfg_LineWidth` outside `WinX_g` to `MaxLineWidth_g` at the start of frame shall discard the frame (E1 of section 3). | ISP-STR-05 |
| WIN-ER-02 | A line that ends before W pixels shall be completed with pixels of value 0 to W pixels (E2). | ISP-STR-05 |
| WIN-ER-03 | A line without end of line on pixel W - 1 shall end with pixel W - 1; the further pixels of the line shall be discarded (E3). | ISP-STR-05 |
| WIN-ER-04 | A start of frame while a frame is open shall end the open frame and start a new frame with this pixel (E4). | ISP-STR-05 |
| WIN-ER-05 | Pixels while no frame is open, other than a start of frame, shall be discarded (E5). | ISP-STR-05 |
| WIN-ER-06 | A frame of more than `MaxFrameHeight_g` lines shall end after line `MaxFrameHeight_g` - 1 (E6). | ISP-STR-05 |
| WIN-ER-07 | In the valid mode, a frame of fewer than `WinY_g` lines shall give no output frame (E7). | ISP-STR-05 |
| WIN-ER-08 | Every output frame shall be well-formed whatever the input: one start of frame, lines of the same width, each with one end of line, one end of frame. | ISP-STR-05 |
| WIN-ER-09 | The frame after an error shall be processed as if no error had occurred. | ISP-STR-05 |

### 2.5 Fault tolerance

| ID | Requirement | Core requirement |
| --- | --- | --- |
| WIN-FT-01 | The line memory shall consist of `olo_ft_ram_sdp` (`Scrubber_g` false) or `olo_ft_ram_sdp_scrub` (`Scrubber_g` true) entities whose SECDED codewords cover the word of a column; the generator shall use the corrected read data. With `WinY_g` = 1 there is no line memory: the ECC and scrubber status outputs stay 0 and the error injection inputs are ignored. | ISP-FT-01, ISP-GEN-01 |
| WIN-FT-02 | The generator shall pulse `Stat_EccSec` and `Stat_EccDed` for one clock cycle for every read of the line memory with a corrected single error or a detected double error in at least one of its codewords. | ISP-FT-01 |
| WIN-FT-03 | The generator shall pass `ErrInj_BitFlip` and `ErrInj_Valid` to the codewords of the line memory with the semantics of Open Logic (the bits of the codewords flipped in the next write). | ISP-FT-02 |
| WIN-FT-04 | With `Scrubber_g` true, the line memory shall be scrubbed in idle cycles of its read port with the period `ScrubPeriod_g`, and the generator shall output the scrubber status of Open Logic (`Scrub_Enable` input, `Scrub_EccSec`, `Scrub_EccDed`, `Scrub_PassDone`, `Scrub_Overrun`). | ISP-FT-03 |
| WIN-FT-05 | The generator shall set `Out_EccDed` with every window that contains a pixel from a read of the line memory with a detected double error. | ISP-FT-04 |
| WIN-FT-06 | Every state machine and counter of the generator shall return to a defined state from any state; an upset of a register shall disturb at most the frame in progress, and the next frame shall be processed correctly. | ISP-FT-05 |
| WIN-FT-07 | After the reset, `In_Ready`, `Out_Valid`, the error and status outputs and the addresses of the line memory shall be defined; with defined input pixels, every output window shall be free of metavalues (no element is taken from a memory word that the frame has not written). | ISP-FT-05 |

The line memory is the only storage the generator protects itself. The window shift register, the counters and the
other control registers are flip-flops without ECC; an upset in them falls under WIN-FT-06 and disturbs at most the
frame in progress. Their mitigation by triple modular redundancy is a choice of the integrator in the synthesis tool
and not part of the core (user guide, section "Protection scope").

### 2.6 Partner behaviour

The input of the generator comes from one of two kinds of source:

- A sensor interface adapter: it delivers pixels at the pace of the sensor, with blanking between lines and frames,
  and cannot always wait. The generator holds `In_Ready` low for at most Rx cycles after a line and for the drain of
  Ry lines after a frame (WIN-PF-02); a FIFO in front of the generator that absorbs these stalls is an obligation of
  the integrator (user guide), sized from the blanking of the sensor.
- Another OpenISP stage or a DMA: back-pressure at any beat, gaps of `In_Valid` at any beat, frames back to back
  (WIN-FN-06, WIN-FN-07).

Both kinds may deliver malformed frames after a transmission or sensor fault (section 3). The output goes to a 2D
stage of OpenISP or to a user stage, which may hold `Out_Ready` low at any beat.

| ID | Requirement | Core requirement |
| --- | --- | --- |
| WIN-PB-01 | The generator shall accept `In_Valid` low at any beat, also within a line and between lines. | ISP-STR-01 |

## 3. Error conditions

An end of line ends a line at the earliest of: the pixel with `In_Last`, the pixel with the end of frame, pixel
W - 1. A start of frame (`In_User(0)`) is evaluated before every other condition of its pixel.

| ID | Condition | Detection | Response | Status |
| --- | --- | --- | --- | --- |
| E1 | `Cfg_LineWidth` < `WinX_g` or > `MaxLineWidth_g` at the start of frame | Range check with the start of frame | The frame is discarded: no output, input pixels discarded up to and including the end of frame, or up to the next start of frame, without further status | `Err_LineWidth` |
| E2 | Short line: `In_Last` or the end of frame on pixel x < W - 1 | Column count | The line is completed with pixels of value 0 to W pixels; the end of frame, if present, ends the frame after the line | `Err_LineLength` |
| E3 | Long line: pixel W - 1 without `In_Last` | Column count | Pixel W - 1 ends the line; if it carries the end of frame, the frame ends; otherwise the following pixels are discarded up to and including the next pixel with `In_Last` or the end of frame (which ends the frame), and a start of frame among them is handled as E4 | `Err_LineLength` |
| E4 | Start of frame while a frame is open | Frame state | The open frame ends with its last complete line; a started line is completed as in E2; the drain of the open frame follows; then the new frame starts with this pixel | `Err_Framing`; `Err_LineLength` for a started line |
| E5 | Pixel without start of frame while no frame is open | Frame state | Pixel discarded | `Err_Framing`, once per sequence of discarded pixels |
| E6 | Line `MaxFrameHeight_g` starts (more lines than `MaxFrameHeight_g`) | Line count | The frame ends after line `MaxFrameHeight_g` - 1; the following pixels are discarded as in E5 without a further status | `Err_Framing` |
| E7 | Valid mode: end of frame with H < `WinY_g` | Line count | No output frame | `Err_Framing` |
| E8 | Double bit error in a read of the line memory | ECC decoder | The window is output with the uncorrected data and marked | `Stat_EccDed`, `Out_EccDed` |

A single bit error in a read of the line memory is corrected and reported with `Stat_EccSec`; it is not an error of
the frame.

## 4. Configuration parameters

| Generic | Default | Range | Description |
| --- | --- | --- | --- |
| `WinX_g` | 3 | 1 to 9, odd | Window width (columns) |
| `WinY_g` | 3 | 1 to 9, odd | Window height (lines); 1 means no line memory |
| `PixelBits_g` | 12 | 1 to 32 | Bits per pixel |
| `MaxLineWidth_g` | 2048 | max(`WinX_g`, 2) to 16384 | Largest line width; depth of the line memory |
| `MaxFrameHeight_g` | 2048 | 1 to 65536 | Largest number of lines of a frame; width of `Out_PosY` |
| `BorderMode_g` | "replicate" | "valid", "zero", "replicate", "mirror" | Border mode (section 6) |
| `RamRdLatency_g` | 1 | 1 to 3 | Read latency of the line memory (Open Logic `RamRdLatency_g`) |
| `EccPipeline_g` | 0 | 0 to 2 | Pipeline stages of the ECC decoder (Open Logic `EccPipeline_g`) |
| `RamStyle_g` | "auto" | Values of Open Logic | Implementation of the line memory (Open Logic `RamStyle_g`) |
| `Scrubber_g` | false | false, true | Scrubber of the line memory |
| `ScrubClkHz_g` | 150.0e6 | Range of Open Logic | Clock frequency for the scrub period (`Scrubber_g` true) |
| `ScrubPeriod_g` | 0.0 | Range of Open Logic | Time for one scrub pass over the line memory; 0.0 scrubs in every idle read cycle |

The widths of the ports follow from the generics: `In_Data` `PixelBits_g` bits, `Out_Data` `WinX_g` x `WinY_g` x
`PixelBits_g` bits, `Cfg_LineWidth` log2ceil(`MaxLineWidth_g` + 1) bits, `Out_PosX` log2ceil(`MaxLineWidth_g`) bits,
`Out_PosY` max(log2ceil(`MaxFrameHeight_g`), 1) bits.

The line memory holds `MaxLineWidth_g` words of (`WinY_g` - 1) x `PixelBits_g` data bits plus the SECDED check bits of
its codewords; the partition of a word into codewords is part of the architecture.
The data written to it lives for at most `WinY_g` - 1 line periods before it is overwritten, so an accumulation of two
upsets in one word is unlikely without scrubbing; the scrubber matters for long gaps between frames and is off by
default. It uses only idle cycles of the read port, which within a line is busy in every cycle.

## 5. Configuration checks

| ID | Requirement | Core requirement |
| --- | --- | --- |
| WIN-CF-01 | A generic outside its range of section 4 (also an even `WinX_g` or `WinY_g` and an unknown `BorderMode_g`) shall stop the elaboration with a message naming the generic. | ISP-GEN-02 |
| WIN-CF-02 | The generator shall be synthesizable with GHDL for the bounds of every numeric generic and every value of `BorderMode_g`, `Scrubber_g`, `RamRdLatency_g` and `EccPipeline_g`. | ISP-GEN-01 |
| WIN-CF-03 | The default configuration shall be designed for 150 MHz on the FPGA families of the reference systems; synthesis results are recorded in the verification report. | ISP-GEN-03 |

## 6. Interpretation

The border modes extend the input frame beyond its borders. For a coordinate c of a frame dimension N (x with N = W,
or y with N = H):

| Mode | Value of p'(x, y) outside the frame |
| --- | --- |
| valid | Not used: only windows without border pixels are output (WIN-FN-02). |
| zero | 0 |
| replicate | p(clamp(x, 0, W - 1), clamp(y, 0, H - 1)): the nearest pixel of the frame. |
| mirror | p(m(x, W), m(y, H)) with m(c, N) = clamp(r(c, N), 0, N - 1), r(c, N) = -c for c < 0 and 2(N - 1) - c for c > N - 1: reflection at the outermost pixel, which is not repeated (d c b \| a b c d \| c b a). |

Horizontally the clamp of the mirror mode never applies, as W >= `WinX_g` >= Rx + 1. Vertically it applies only for
frames of at most Ry lines: their missing lines repeat the outermost line.

The first and last line and column flags (WIN-IF-04) refer to the output frame: in the valid mode the first column
flag is set for the centre x = Rx.
