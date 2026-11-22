# isp_replace: Specification

## 1. Overview

`isp_replace` replaces the non-operational pixels of an image. A defect map with one bit per pixel marks them; every
marked pixel is replaced by an interpolation between the nearest operational pixels to its left and to its right in
the same line. All other pixels pass unchanged.

The defect map is a table in an ECC-protected, scrubbed RAM of Open Logic that the software writes through an
AXI4-Lite slave (section 7). Open Logic does not initialise this RAM, so the software clears the map with
`CTRL.CLEAR` or writes it completely after power-up. The largest distance at which the interpolation looks for
an operational pixel is the generic `MaxGap_g`.

The module is built from the general parts of the suite: an
[`isp_frame_sync`](../../isp_frame_sync/docs/specification.md) at the input, an
[`isp_window`](../../isp_window/docs/specification.md) of one line that delivers every pixel with its neighbours
and their marks, and an interpolation kernel behind it.

### 1.1 Definitions

| Term | Definition |
| --- | --- |
| W, H | `ImageWidth_g`, `ImageHeight_g`: dimensions of the image. |
| p(x, y), q(x, y) | Input and output pixel in column x of line y (unsigned, `PixelBits_g` bits). |
| G | `MaxGap_g`: the largest distance, in pixels, to an operational pixel that the interpolation uses. |
| Defect map | H x Wl words of 32 bits, Wl = ceil(W / 32) words per line. The mark of pixel (x, y) is bit x mod 32 of word y x Wl + x / 32 (integer division); 1 marks the pixel as non-operational. The bits of the last word of a line beyond column W - 1 have no meaning. |
| Operational pixel | A pixel inside the image whose mark is 0. |
| dl, dr | For a non-operational pixel (x, y): the distance to the nearest operational pixel of line y on its left (x - dl) and on its right (x + dr), each at most G; "none" when there is no operational pixel within G on that side. |
| Replacement | Both found: q = floor((p(x - dl, y) x dr + p(x + dr, y) x dl + floor((dl + dr) / 2)) / (dl + dr)), the linear interpolation at the place of the pixel, rounded to the nearest. One found: the value of that pixel. None found: q = p. |

## 2. Requirements

### 2.1 Interfaces

| ID | Requirement | Core requirement |
| --- | --- | --- |
| RPL-IF-01 | The module shall take pixels of `PixelBits_g` bits on a pixel stream (`In_Valid`, `In_Ready`, `In_Data`, `In_Last`, `In_User`). | ISP-STR-01, ISP-STR-02 |
| RPL-IF-02 | The module shall output pixels of `PixelBits_g` bits on a pixel stream (`Out_Valid`, `Out_Ready`, `Out_Data`, `Out_Last`, `Out_User`). | ISP-STR-01, ISP-STR-02 |
| RPL-IF-03 | The module shall have an AXI4-Lite slave (`S_AxiLite_*`, 32 data bits, 8 address bits, clock `Clk`) for the registers of section 7. | ISP-CFG-03 |
| RPL-IF-04 | The module shall output the status of its `isp_frame_sync` (`Err_Framing`, `Stat_ImageOpen`), pulse `Stat_Unreplaced` for one clock cycle for every non-operational pixel that it cannot replace, after the pixel left the output (a pixel lost by a reset reports nothing), and pulse `Stat_EccSec` and `Stat_EccDed` for a corrected single bit error and a detected double bit error of a word of the defect map that the image uses, when the word comes in use; a word read ahead and not used reports nothing. | ISP-STR-08, ISP-STR-10, ISP-FT-01 |
| RPL-IF-05 | The module shall pass `ErrInj_BitFlip` and `ErrInj_Valid` to the RAM of the defect map with the semantics of Open Logic, and output the scrubber status of Open Logic (`Scrub_Enable` input, `Scrub_EccSec`, `Scrub_EccDed`, `Scrub_PassDone`, `Scrub_Overrun`). | ISP-FT-02, ISP-FT-03 |
| RPL-IF-06 | The module shall have one clock `Clk` and a synchronous, high-active reset `Rst`. | ISP-GEN-01 |

### 2.2 Function

| ID | Requirement | Core requirement |
| --- | --- | --- |
| RPL-FN-01 | For every operational pixel the module shall output q = p, for every non-operational pixel the replacement of section 1.1, at the same position. | ISP-RPL-01, ISP-RPL-03 |
| RPL-FN-02 | The module shall use only pixels of the same line and of the same image for a replacement; a pixel outside the image is not an operational pixel. | ISP-RPL-01 |
| RPL-FN-03 | The module shall take its input through `isp_frame_sync` with the dimensions of the image and output the image with the same dimensions as one stream packet per line with the sequence flags of the line. | ISP-STR-03, ISP-STR-04, ISP-STR-05, ISP-STR-06, ISP-STR-08 |
| RPL-FN-04 | A write to the defect map that completes before the module accepts the first pixel of an image shall apply to the whole image. A write that completes during an image shall apply in that image at the latest from the third word after the word of the last pixel the module accepted. | ISP-RPL-02, ISP-CFG-02 |
| RPL-FN-05 | The defect map shall mark no pixel after the command `CTRL.CLEAR`; the reset `Rst` shall not change it. | ISP-RPL-02 |
| RPL-FN-06 | The output shall not depend on the timing of the stream handshakes, and an image start may follow the last pixel of an image without a gap. | ISP-STR-07 |
| RPL-FN-07 | The module shall be built from `isp_frame_sync`, `isp_window` (one line of 2 x G + 1 pixels, each with its mark, border mode zero) and an interpolation kernel. | ISP-GEN-02 |

### 2.3 Throughput and latency

| ID | Requirement | Core requirement |
| --- | --- | --- |
| RPL-PF-01 | With `In_Valid` and `Out_Ready` high, the module shall hold the input (`In_Ready` low) for at most G clock cycles between the acceptance of the first pixels of two consecutive lines of an image; between the first pixels of lines 0 and 1 the input waits for word 0 of the defect map instead, max(G, `RamRdLatency_g` + `EccPipeline_g` + 2) clock cycles at most. | ISP-STR-09 |
| RPL-PF-02 | With back-to-back input and `Out_Ready` high, the interval between the starts of two consecutive images shall not exceed H x (W + G) + `RamRdLatency_g` + `EccPipeline_g` + 16 clock cycles. | ISP-STR-09 |
| RPL-PF-03 | With `Out_Ready` high, the pixel q(x, y) shall be at the output at most 13 + `RamRdLatency_g` + `EccPipeline_g` clock cycles after the module accepted the pixel p(x + G, y), where that pixel is inside the image. | ISP-STR-09 |

### 2.4 Error handling

| ID | Requirement | Core requirement |
| --- | --- | --- |
| RPL-ER-01 | Every output image shall be complete whatever the input; the pixels that `isp_frame_sync` generated for missing pixels are pixels of the image like the others. | ISP-STR-08 |
| RPL-ER-02 | A non-operational pixel without an operational pixel within G on either side shall be output unchanged and reported (E5). | ISP-RPL-03 |
| RPL-ER-03 | A word of the defect map read with a double bit error shall be used as read and reported (E6). | ISP-FT-01 |
| RPL-ER-04 | A write to `MAP_DATA` during a clear of the map or with `MAP_ADDR` outside the map shall change neither the map nor `MAP_ADDR`. | ISP-CFG-03 |

### 2.5 Fault tolerance

| ID | Requirement | Core requirement |
| --- | --- | --- |
| RPL-FT-01 | The defect map shall be in an `olo_ft_ram_sdp_scrub` with one SECDED codeword per word; the module shall use the corrected data, and the scrubber shall correct the words in the cycles in which the datapath does not read. | ISP-FT-01, ISP-FT-03 |
| RPL-FT-02 | Every state machine and counter of the module shall return to a defined state from any state; an upset of a register shall disturb at most the image in progress, and the module shall realign with the next image start. | ISP-FT-04 |
| RPL-FT-03 | After the reset, `In_Ready`, `Out_Valid` and the status outputs shall be defined, and with defined input pixels every output beat shall be free of metavalues. | ISP-FT-04 |

The module has no configuration register that outlives an image beside the defect map, which is protected by its
ECC (ISP-FT-05 does not apply to `MAP_ADDR`, a pointer of the software). The window register, the counters and the
interpolation are flip-flops; their mitigation by triple modular redundancy is a choice of the integrator in the
synthesis tool (user guide, section "Protection scope").

### 2.6 Partner behaviour

The partners of the input are those of `isp_frame_sync`; the module holds the input for G cycles after every line.
The consumer of the output may hold `Out_Ready` low at any beat. The AXI4-Lite master is a processor or a register
bridge of the system on the clock `Clk`; a register bus in another clock domain needs a clock crossing in the system.

The software writes the defect map word by word. A map that is written while images pass applies to an image in
part; the software writes it between images where that matters, or accepts one image with a mixed map. After
power-up it clears the map with `CTRL.CLEAR` or writes every word before the first image, since the content of
the RAM after configuration depends on the device; it repeats `CTRL.CLEAR` after a reset during a clear, which
ends the clear.

## 3. Error conditions

The errors E1 to E4 of `isp_frame_sync` apply to the input stream; `Err_Framing` reports them.

| ID | Condition | Detection | Response | Status |
| --- | --- | --- | --- | --- |
| E5 | A non-operational pixel has no operational pixel within G on its left and on its right (the middle of a group of more than 2 x G neighbours, or of a shorter group at the border of the image) | Interpolation kernel | The pixel is output unchanged | `Stat_Unreplaced`, `STATUS.UNREPLACED` |
| E6 | Double bit error in a word of the defect map | ECC decoder of the RAM | The word is used as read; it stays so until the software writes the word or clears the map | `Stat_EccDed`, `STATUS.ECC_DED` |

A single bit error in a word of the defect map is corrected and reported with `Stat_EccSec`; the scrubber writes
the corrected word back. The read errors of a word are reported when the word comes in use; a word that the
lookup read ahead and a reset dropped reports nothing. The scrubber reports the errors of every word on its own
outputs, also of the content of the RAM after power-up until the software clears or writes the map.

## 4. Configuration parameters

| Generic | Default | Range | Description |
| --- | --- | --- | --- |
| `ImageWidth_g` | none | 2 x `MaxGap_g` + 1 to 65536 | W: pixels per line |
| `ImageHeight_g` | none | 1 to 65536 | H: lines per image |
| `PixelBits_g` | none | 1 to 24 | Bits per pixel |
| `MaxGap_g` | 2 | 1 to 7 | G: largest distance to an operational pixel used for a replacement |
| `RamRdLatency_g` | 2 | 1 to 3 | Read latency of the RAM of the defect map (Open Logic `RamRdLatency_g`) |
| `EccPipeline_g` | 1 | 0 to 2 | Pipeline stages of its ECC decoder (Open Logic `EccPipeline_g`) |
| `RamStyle_g` | "auto" | Values of Open Logic | Implementation of the RAM (Open Logic `RamStyle_g`) |
| `ClkFreqHz_g` | 150.0e6 | 1000.0 to 2.14748e11 when `ScrubPeriod_g` is above 0.0 (the pacer of Open Logic divides the clock to a tick of 1 kHz; `olo_base_strobe_gen` checks FreqClkHz_g / FreqStrobeHz_g <= 214748000.0, so 214748000 x 1000 Hz); any value with `ScrubPeriod_g` 0.0 | Clock frequency, for the scrub period |
| `ScrubPeriod_g` | 0.0 | 0.0, or 0.001 to 1073741.823 s, rounded to whole milliseconds (the pacer of Open Logic counts the period in milliseconds, at most 2^30 - 1) | Time for one scrub pass over the defect map; 0.0 scrubs in every free cycle |

Output image: `ImageWidth_g` x `ImageHeight_g` pixels of `PixelBits_g` bits. The defect map holds H x ceil(W / 32)
words of 32 bits plus 7 check bits each: about 2.6 Mbit for an image of 2048 x 1024 pixels.

A group of up to G neighbouring non-operational pixels of a line is interpolated completely from both sides. A
longer group is still replaced at its two ends, from one side or from both, as far as an operational pixel lies
within G; the pixels in its middle stay unchanged (E5).

## 5. Configuration checks

| ID | Requirement | Core requirement |
| --- | --- | --- |
| RPL-CF-01 | A generic outside its range of section 4 shall stop the elaboration with a message naming the generic. | ISP-CFG-01 |
| RPL-CF-02 | The module shall be synthesizable with GHDL for the bounds of every numeric generic. | ISP-GEN-01 |
| RPL-CF-03 | The default configuration shall be designed for 125 MHz on Microchip PolarFire; synthesis results are recorded in the verification report. The target of 150 MHz on the AMD Versal device of the reference systems (ISP-GEN-04) is open. | ISP-GEN-03 |

## 6. Interpretation

- The interpolation is linear between the two operational pixels that enclose a group of non-operational pixels,
  whatever the length of the group: for a single non-operational pixel it is the mean of its two neighbours.
- At the left and the right border of the image a non-operational pixel has an operational pixel on one side only
  and takes its value.
- Each line has its own words of the defect map, so the software addresses the word of a pixel without a division
  by the image width.
- The module reads the map ahead of the pixels within an image (RPL-FN-04), but not across the start of an image:
  a map that the software completes between two images applies to the whole next image. The first pixel of an
  image waits for its word, which adds the read latency of the map to the image period and to the latency of
  the first pixels (RPL-PF-02, RPL-PF-03).
- `MAP_ADDR` keeps all 32 bits, so that an address outside the map stays outside and a write to it has no effect
  (RPL-ER-04).
- The map is a table of one bit per pixel. A list of the positions of the non-operational pixels would need less
  memory for a detector with few defects; the register interface of this module leaves room for it in a later
  version.

## 7. Register map

Byte addresses of 32-bit registers on the AXI4-Lite slave. Access: RO read only, RW read and write, WO write only,
W1C sticky flag, write one to clear, W1 command, write one. Reads of other addresses and of write-only registers
return 0, writes to other addresses and to read-only fields have no effect; every access is answered with OKAY.

| Address | Register | Bits | Field | Access | Reset | Description |
| --- | --- | --- | --- | --- | --- | --- |
| 0x00 | `ID` | 31:0 | `ID` | RO | 0x52504C01 | 0x52504C (RPL) and register map version 1 |
| 0x04 | `IMAGE` | 15:0 | `WIDTH_M1` | RO | `ImageWidth_g` - 1 | Pixels per line, minus one |
| | | 31:16 | `HEIGHT_M1` | RO | `ImageHeight_g` - 1 | Lines per image, minus one |
| 0x08 | `PARAM` | 3:0 | `MAX_GAP` | RO | `MaxGap_g` | G |
| | | 12:8 | `PIXEL_BITS` | RO | `PixelBits_g` | Bits per pixel |
| 0x0C | `MAP_LINE` | 15:0 | `WORDS` | RO | ceil(W / 32) | Words of the defect map per line |
| 0x10 | `MAP_WORDS` | 31:0 | `WORDS` | RO | H x ceil(W / 32) | Words of the defect map |
| 0x14 | `CTRL` | 0 | `CLEAR` | W1 | 0 | Write one: writes 0 to every word of the defect map; reads as zero |
| 0x18 | `STATUS` | 0 | `IMAGE_OPEN` | RO | 0 | An input image is open (`Stat_ImageOpen`) |
| | | 1 | `BUSY` | RO | 0 | A clear of the defect map is in progress |
| | | 8 | `ERR_FRAMING` | W1C | 0 | Set by every pulse of `Err_Framing` |
| | | 10 | `UNREPLACED` | W1C | 0 | Set by every pulse of `Stat_Unreplaced` |
| | | 16 | `ECC_SEC` | W1C | 0 | Set by every corrected single bit error of the defect map (read or scrubber) |
| | | 17 | `ECC_DED` | W1C | 0 | Set by every detected double bit error of the defect map (read or scrubber) |
| 0x1C | `MAP_ADDR` | 31:0 | `ADDR` | RW | 0 | Address of the word that the next write to `MAP_DATA` changes; it counts up by one with every such write; all 32 bits are stored and read back |
| 0x20 | `MAP_DATA` | 31:0 | `DATA` | WO | - | Writes the word `MAP_ADDR` of the defect map |

| ID | Requirement | Core requirement |
| --- | --- | --- |
| RPL-RG-01 | The AXI4-Lite slave shall implement the registers of this section with the stated addresses, fields, access types and reset values, and answer every access with OKAY. | ISP-CFG-03 |
| RPL-RG-02 | A flag of `STATUS` that is set by its event in the cycle of a write that clears it shall stay set. | ISP-CFG-03 |
| RPL-RG-03 | A write to `MAP_DATA` shall write all 32 bits of the word `MAP_ADDR` and then increase `MAP_ADDR` by one. | ISP-RPL-02 |
| RPL-RG-04 | `CTRL.CLEAR` shall write 0 to every word of the defect map, with `STATUS.BUSY` high from the command to the last word; a `CTRL.CLEAR` while `STATUS.BUSY` is high shall have no effect. | ISP-RPL-02 |
