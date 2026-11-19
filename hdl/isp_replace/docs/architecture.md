# isp_replace: Architecture

## 1. Block diagram

![isp_replace block diagram: frame sync, map lookup, window, interpolation and
registers](img/isp_replace_arch.drawio.svg)

The frame sync (RP-1) delivers complete images with the position of every pixel. The map lookup (RP-2) reads the
defect map in step with the pixels and attaches to every pixel its mark. The window (RP-3) delivers every pixel
with its G neighbours on each side, all with their marks. The interpolation (RP-4) passes an operational pixel and
replaces a non-operational one. The registers (RP-5) are on an AXI4-Lite slave; through them the software writes
the defect map.

## 2. Building blocks

| ID | Block | Function |
| --- | --- | --- |
| RP-1 | Frame sync | [`isp_frame_sync`](../../isp_frame_sync/docs/architecture.md): input stream handling, position of every pixel, `Err_Framing`, `Stat_ImageOpen`. |
| RP-2 | Map lookup | Defect map in `olo_ft_ram_sdp_scrub` (H x ceil(W / 32) words of 32 bits); word counter, current word, selection of the mark of every pixel (section 5). |
| RP-3 | Window | [`isp_window`](../../isp_window/docs/architecture.md) with a window of 2 x G + 1 columns and one line, the anchor in the middle, the border mode zero and pixels of `PixelBits_g` + 1 bits: the pixel and its "operational" flag. No line buffer. |
| RP-4 | Interpolation | Search for the nearest operational pixel on each side, weighted sum, division by the distance, output register (section 6). |
| RP-5 | Registers | `olo_axi_lite_slave` (8 address bits, 32 data bits) with the registers of the specification (section 7); write port of the defect map, clear sequence. |

## 3. Ports

| Port | Direction | Width | Description |
| --- | --- | --- | --- |
| `Clk` | in | 1 | Clock |
| `Rst` | in | 1 | Synchronous reset, high-active |
| `In_Valid`, `In_Ready`, `In_Data`, `In_Last`, `In_User` | | as `isp_frame_sync` | Input pixel stream |
| `Out_Valid`, `Out_Ready`, `Out_Data`, `Out_Last`, `Out_User` | | pixel stream, `PixelBits_g` | Output pixel stream |
| `S_AxiLite_*` | | 8 address bits, 32 data bits | AXI4-Lite slave of the registers, port names of `olo_axi_lite_slave` |
| `Err_Framing` | out | 1 | Pulse: error of the input stream (from RP-1) |
| `Stat_ImageOpen` | out | 1 | Level: an input image is open (from RP-1) |
| `Stat_Unreplaced` | out | 1 | Pulse: a non-operational pixel was not replaced |
| `Stat_EccSec`, `Stat_EccDed` | out | 1 | Pulse: a read of the defect map corrected a single bit error, detected a double bit error |
| `ErrInj_BitFlip` | in | 39 | Flip pattern for the next write of the defect map (codeword of a 32-bit word) |
| `ErrInj_Valid` | in | 1 | Latches the flip pattern |
| `Scrub_Enable` | in | 1 | Scrubber enable (default '1') |
| `Scrub_EccSec`, `Scrub_EccDed`, `Scrub_PassDone`, `Scrub_Overrun` | out | 1 | Scrubber status of Open Logic |

## 4. The mark as part of the pixel

RP-2 turns the mark into an "operational" flag, the inverse of the mark, and puts it beside the pixel. The window
RP-3 treats the pair as a pixel of `PixelBits_g` + 1 bits and knows nothing of its meaning. With the border mode
zero, a place of the window outside the image holds the pixel 0 with the flag 0: it is not operational. The left and
the right border of the image therefore need no case of their own in the interpolation (RPL-FN-02).

RP-3 contains a frame sync of its own. RP-1 and RP-2 deliver complete images, so it only acts after an upset between
the blocks; its `Err_Framing` joins that of RP-1, so that such an upset is reported.

## 5. Map lookup (RP-2)

The defect map is read in the order of the pixels. Every line has its own words, so the address of the word is a
counter that counts up through the image: by one after every 32 pixels of a line and at the end of every line. It
returns to 0 with pixel (0, 0).

- The lookup holds the word of the current pixels and the two words after it in a queue of three words: when a word
  comes in use, the read of the word two places after it starts. Two words ahead cover the read latency of the RAM
  and of its ECC decoder (`RamRdLatency_g` + `EccPipeline_g`, at most 5 cycles) also when the last word of a line
  holds a single pixel: two lines take at least 2 x (3 x G + 1) cycles.
- The read-ahead stops at the last word of the image. Pixel (0, 0) starts the reads of words 0, 1 and 2 and waits
  for word 0, so that a map written between two images applies to the whole next image (RPL-FN-04).
- The reads of an image start in the cycle in which pixel (0, 0) reaches the lookup; reads of the image before
  that are still under way are dropped when they arrive. A word that arrives with no read pending is dropped as
  well; this cannot happen without an upset of the counter, since every read-valid stage of the RAM clears with the
  reset, and is a defence against such an upset (RPL-FT-02). A pixel waits in the lookup only for the first word of
  an image.
- When no word can come for a pixel (only after an upset of the counters), the pixel passes as operational until
  the next image start realigns the lookup (RPL-FT-02).
- The RAM has max(2, H x ceil(W / 32)) words, as `olo_ft_ram_sdp_scrub` needs at least 2; the extra word of a map of
  one word is not used.
- The read port of the RAM is busy once in 32 pixels; the scrubber uses the other cycles (RPL-FT-01).
- The write port belongs to RP-5: a write of `MAP_DATA`, or the clear sequence. The datapath never writes.
- The error flags of a read travel with the word through the queue; `Stat_EccSec` and `Stat_EccDed` pulse when
  the word comes in use, with the first pixel of the word (RPL-IF-04). A word read ahead and dropped by a reset
  reports nothing. A word with a double error is used as read (E6).

## 6. Interpolation (RP-4)

The window holds the pixels x - G to x + G of a line with their flags; the middle element is the pixel (x, y) to
output.

| Stage | Operation |
| --- | --- |
| 1 | Two priority searches over the flags: dl, the distance of the nearest operational pixel on the left, and dr on the right, each 1 to G or none; the two pixels L and R are selected by them. |
| 2 | N = L x dr + R x dl + floor(d / 2) with d = dl + dr: two multiplications of a pixel with a number of at most three bits, built from shifts and adders. |
| 3 | Q = floor(N / d) by a multiplication with a constant: N x ceil(2^K / d) / 2^K with K = `PixelBits_g` + 8, the constant from a table of the 13 possible divisors 2 to 14. |
| 4 | Output register: the pixel itself when it is operational or when neither side has an operational pixel (E5; `Stat_Unreplaced` pulses in the cycle after the pixel left the output); L or R when only one side has one; Q otherwise. |

The division in stage 3 is exact: for a divisor d of at most 14 and a numerator below 2^(`PixelBits_g` + 4), the
error of the rounded constant, at most d - 1 parts in 2^K per unit of the numerator, stays below one unit of the
quotient. The verification checks it for every divisor against the reference model.

`Out_Last` and `Out_User` of the window stream travel beside the pixel through the four stages. All stages share one
enable: they advance when the output register is empty or its beat transfers.

## 7. Registers (RP-5)

| Register | Implementation |
| --- | --- |
| `ID`, `IMAGE`, `PARAM`, `MAP_LINE`, `MAP_WORDS` | Constants from the generics |
| `MAP_ADDR` | 32-bit counter; written by the software, counted up by every write of `MAP_DATA` that changes the map |
| `MAP_DATA` | Write strobe of the RAM with the address `MAP_ADDR`; no effect during a clear or with an address outside the map |
| `CTRL.CLEAR` | Starts the clear sequence: a counter writes 0 to every word, one per clock cycle; `STATUS.BUSY` is high meanwhile |
| `STATUS` | `Stat_ImageOpen`, the busy flag, and sticky flags set by `Err_Framing`, `Stat_Unreplaced` and the error flags of the reads and of the scrubber; cleared by a write of one, the event wins |

Open Logic does not initialise the RAM (its codewords cannot carry initial values); whether a device starts with
zeros depends on the device. The software therefore clears the map with `CTRL.CLEAR` or writes it completely
after power-up. The simulation model of the RAM starts with zeros, which are valid codewords of an empty map;
the tests clear or write the map before they use it. The reset does not touch the RAM; a reset during a clear
ends the clear, and the software repeats the command.

## 8. Timing and throughput

| Property | Value | Requirement |
| --- | --- | --- |
| Pixel rate | One pixel per clock cycle within a line; the input waits for the G virtual columns of the window after every line, which the buffers between the input and the window (the two frame syncs and the lookup register) shift into the next line; in line 0 it waits for word 0 of the map instead, `RamRdLatency_g` + `EccPipeline_g` + 1 cycles after an idle module, max(G, `RamRdLatency_g` + `EccPipeline_g` + 1) after an image, whose last G virtual columns run beside the wait | RPL-PF-01 |
| Image period | H x (W + G) + max(0, `RamRdLatency_g` + `EccPipeline_g` + 1 - G) cycles: the window generates G virtual columns after every line, and the wait for word 0 adds the part that does not run beside the virtual columns of the image before; the first interval after an idle module is H x W + (H - 1) x G + `RamRdLatency_g` + `EccPipeline_g` + 1 | RPL-PF-02 |
| Latency | 2 clock cycles in RP-1, 1 in the lookup, 3 in the window, 4 in the interpolation: 10 clock cycles after the pixel G columns to the right; up to 2 more for a pixel taken while the input was held; up to `RamRdLatency_g` + `EccPipeline_g` + 1 more for the first pixels of an image | RPL-PF-03 |

Paths: the priority searches over at most seven flags and the selection of L and R (stage 1), and the
multiplication with the constant in stage 3, at most 28 x 32 bits, which the synthesis tool maps to DSP blocks
with their registers.

## 9. Fault tolerance

| Element | Protection |
| --- | --- |
| Defect map | SECDED per word in `olo_ft_ram_sdp_scrub`, scrubbed in the cycles without a read; a double error is reported and stays until the word is written |
| Word counter, current word, window register, interpolation | Flip-flops; the counter restarts with every image, an upset changes pixels of the image in progress |
| `MAP_ADDR`, clear sequence | Flip-flops; an upset during a map update writes a word to a wrong place, which the software finds only by writing the map again |

Beside the defect map, the module has no register that holds a parameter for longer than an image: `CTRL.CLEAR` is a
command, `MAP_ADDR` a pointer that the software sets for every map update, and the scrubber is enabled by a port.
The parity of long-lived registers (ISP-FT-05) therefore has nothing to protect here; the map itself has its ECC.

Triple modular redundancy of the flip-flops is a choice of the integrator in the synthesis tool.

## 10. Resource estimate

For 12-bit pixels, G = 2 and an image of 2048 x 1024 pixels: a defect map of 65536 words (2.6 Mbit with check
bits, about 72 block RAMs of 36 kbit), one or two DSP blocks for the division, and about 700 flip-flops and 700 LUTs
(two frame syncs, the window of five pixels, the interpolation, the AXI4-Lite slave). Synthesis results replace these
estimates in the verification report.
