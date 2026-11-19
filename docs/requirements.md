# OpenISP: Requirements Specification

## 1. Purpose and scope

No ECSS or CCSDS standard covers the image signal processing of a spacecraft imager. This specification is the
reference of OpenISP in place of a standard: it states, as core requirements, what the cores provide to their user.
The architecture document (section 10) assigns every core requirement to the module that implements it, and every
module requirement names the core requirements it implements; `tools/compliance.py` traces them to the test cases.
The development follows ECSS-E-ST-20-40C.

This issue covers the pixel stream common to all stages and the 2D neighbourhood (window) generator, the front end of
every 2D stage. The later stages (black level, defect pixel correction, flat-field correction, demosaicing, colour
correction, binning, statistics, filters) add their core requirements when they are specified.

## 2. Definitions

| Term | Definition |
| --- | --- |
| Frame | A raster image of W x H pixels: H lines from top to bottom, each of W pixels from left to right. |
| Pixel p(x, y) | The pixel in column x (0 to W - 1, left to right) of line y (0 to H - 1, top to bottom). |
| Pixel stream | A valid / ready stream with AXI4-Stream handshake semantics that carries one pixel per beat in raster order. |
| Window | The WinX x WinY neighbourhood of a centre pixel p(x, y): the pixels p(x + i, y + j) for i = -Rx to Rx and j = -Ry to Ry, with Rx = (WinX - 1) / 2 and Ry = (WinY - 1) / 2. |
| Border pixel | A pixel of a window outside the frame (x + i or y + j outside the frame); its value is defined by the border mode. |
| Stage | A module of OpenISP that consumes and / or produces pixel streams. |

## 3. Requirements

### 3.1 Pixel stream (STR)

| ID | Requirement |
| --- | --- |
| ISP-STR-01 | Every stage shall exchange pixels on pixel streams with AXI4-Stream handshake semantics: a beat transfers when valid and ready are high in the same clock cycle; the source keeps the beat stable until it transfers. |
| ISP-STR-02 | A pixel stream shall carry the frame structure with the beats: start of frame (`User(0)`, `TUSER(0)`) with the first pixel of a frame, end of line (`Last`, `TLAST`) with the last pixel of every line and end of frame (`User(1)`, `TUSER(1)`) with the last pixel of a frame. |
| ISP-STR-03 | The line width of a frame shall be configurable at run time up to a maximum set at synthesis, and take effect with the start of a frame; the number of lines of a frame shall be given by its end of frame. |
| ISP-STR-04 | Every stage shall accept back-pressure on its output at any beat without loss, duplication or change of pixels, and shall not require a gap between frames. |
| ISP-STR-05 | Every stage shall detect a frame structure that deviates from its configuration (line too short or too long, missing or early start or end of frame, line width outside its range), report every deviation on a status output, deliver only well-formed frames on its outputs and process the next well-formed frame correctly. |

### 3.2 2D window generation (WIN)

| ID | Requirement |
| --- | --- |
| ISP-WIN-01 | The core shall deliver, for every pixel of a frame, its window of WinX x WinY pixels, with odd window sizes set at synthesis, on a pixel stream that keeps the frame structure. |
| ISP-WIN-02 | The core shall offer the border modes valid (only windows without border pixels, the output frame is smaller), zero (border pixels are 0), replicate (the nearest pixel of the frame) and mirror (reflection at the outermost pixel, which is not repeated), selected at synthesis. |
| ISP-WIN-03 | With every window, the core shall deliver the position of its centre pixel in the frame (column, line, first and last line, first and last column). |
| ISP-WIN-04 | The core shall complete a frame after its end of frame without further input. |
| ISP-WIN-05 | The core shall transfer one pixel per clock cycle within a line, with a bounded overhead per line and per frame. |

### 3.3 Fault tolerance (FT)

| ID | Requirement |
| --- | --- |
| ISP-FT-01 | Every memory shall be protected by a SECDED code: single bit errors are corrected on every read, double bit errors detected; each correction and detection shall be reported on a status output. |
| ISP-FT-02 | Every memory shall offer the error injection of Open Logic (`ErrInj_BitFlip`, `ErrInj_Valid`) for the test of the error handling in the system. |
| ISP-FT-03 | The memories shall optionally be scrubbed in idle cycles, with the scrubber status of Open Logic. |
| ISP-FT-04 | Output data that contains a pixel read with an uncorrectable error shall be marked. |
| ISP-FT-05 | Every state machine and counter shall return to a defined state from any state, so that an upset of a register disturbs at most the frame in progress; after the reset, control outputs, addresses and status outputs shall be defined (no metavalues). |

### 3.4 Implementation (GEN)

| ID | Requirement |
| --- | --- |
| ISP-GEN-01 | The cores shall be technology-independent VHDL-2008 that GHDL can synthesise, built on Open Logic (fault-tolerant `olo_ft_*` memories), with vendor-specific parts in separate adapter modules. |
| ISP-GEN-02 | Every stage shall be configured by generics with declared ranges; values outside a range shall stop the elaboration with a message. |
| ISP-GEN-03 | The default configuration of every stage shall be designed for a clock of 150 MHz on the FPGA families of the family's reference systems. |
