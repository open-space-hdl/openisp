# OpenISP: Requirements Specification

## 1. Purpose and scope

No ECSS or CCSDS standard covers the image signal processing of a spacecraft instrument. This specification is the
reference of OpenISP in place of a standard: it states, as core requirements, what the suite provides to its user.
The architecture document (section 10) assigns every core requirement to the module that implements it, and every
module requirement names the core requirements it implements; `tools/compliance.py` traces them to the test cases.
The development follows ECSS-E-ST-20-40C.

OpenISP is a suite of image processing modules. Every module consumes and produces the same pixel stream, so that the
output of any module connects to the input of any other. The detector interface is outside the suite: the modules
see images that arrive as stream packets, for example the unpacked data fields of segmented CCSDS Space Packets.

This issue covers the pixel stream, the configuration, the fault tolerance and the implementation rules common to all
modules, and the functions region of interest, pixel-level operation, 2D window filter, binning and replacement of
non-operational pixels.

## 2. Definitions

| Term | Definition |
| --- | --- |
| Image | A raster of W x H pixels: H lines from top to bottom, each of W pixels from left to right. W and H are set by generics. |
| Pixel p(x, y) | The pixel in column x (0 to W - 1) of line y (0 to H - 1); an unsigned number. |
| Pixel stream | A valid / ready stream with AXI4-Stream handshake semantics that carries one pixel per beat in raster order: `Valid`, `Ready`, `Data`, `Last`, `User`. |
| Stream packet | The beats up to and including a beat with `Last`. An image is carried by one or more stream packets. |
| Sequence flags | The two bits `User(1:0)` of a stream packet, with the meaning of the Sequence Flags of a Space Packet (CCSDS 133.0-B-2, 4.1.3.4.2.2): "01" first packet of an image, "00" continuation packet, "10" last packet, "11" the only packet of an image. |
| Image start | The first beat of a stream packet with the sequence flags "01" or "11". |
| Module | An entity of OpenISP with at least one pixel stream. |

## 3. Requirements

### 3.1 Pixel stream (STR)

| ID | Requirement |
| --- | --- |
| ISP-STR-01 | Every module shall exchange pixels on pixel streams with AXI4-Stream handshake semantics: a beat transfers when valid and ready are high in the same clock cycle; the source keeps the beat stable until it transfers. |
| ISP-STR-02 | A pixel stream shall carry the pixels of an image in raster order, one pixel per beat, in one or more stream packets; the sequence flags of a packet shall be valid with each of its beats. |
| ISP-STR-03 | The dimensions of the input image and the pixel width of every module shall be set by generics; a module whose output image differs in its dimensions or pixel width shall state them as functions of its generics. |
| ISP-STR-04 | A module shall accept an image in any division into stream packets (the packet boundaries need not coincide with the lines) and start an image with every image start. |
| ISP-STR-05 | A module shall output every image as one stream packet per line, with the sequence flags "01" for the first line, "10" for the last line, "00" for the lines between and "11" for an image of one line. |
| ISP-STR-06 | The output pixel stream of every module shall meet the requirements on an input pixel stream, so that modules connect in any order where the dimensions and the pixel width match. |
| ISP-STR-07 | Every module shall accept back-pressure on its output and gaps of valid on its input at any beat without loss, duplication or change of pixels, and shall not require a gap between images. |
| ISP-STR-08 | Every module shall locate the pixels of an image by counting from the image start. It shall detect a stream that deviates from its dimensions (an image start before the image is complete, pixels after a complete image without an image start, an image that does not end with the last beat of a packet with the sequence flags "10" or "11"), report every deviation on a status output, output only complete images (missing input pixels taken as 0, excess input pixels discarded) and process the next image correctly. |
| ISP-STR-09 | Every module shall accept one pixel per clock cycle within an image. |
| ISP-STR-10 | Every module shall show on a status output while an input image is open (started and not complete), so that a supervisor can detect an image whose rest never arrives. |

### 3.2 Configuration (CFG)

| ID | Requirement |
| --- | --- |
| ISP-CFG-01 | The structure of a module (image dimensions, pixel widths, sizes of windows and regions) shall be set by generics with declared ranges; a value outside a range shall stop the elaboration with a message. |
| ISP-CFG-02 | Parameters that change during a mission (the map of non-operational pixels, the coefficients of a filter, the position of a region of interest, the values of a pixel-level operation) shall be configurable at run time through registers, with reset values from generics, and shall take effect at an image start. |
| ISP-CFG-03 | Every module with registers shall have an AXI4-Lite slave for them, and its register map shall also hold an identification of the module, its build-time characteristics and its status. |

### 3.3 Region of interest (CRP)

| ID | Requirement |
| --- | --- |
| ISP-CRP-01 | The suite shall provide the selection of a rectangular region of interest of an image, with its size set by generics and its position set by generics or, as an option, at run time; the region shall be the output image. |

### 3.4 Pixel-level operation (PNT)

| ID | Requirement |
| --- | --- |
| ISP-PNT-01 | The suite shall provide a pixel-level operation that adds a signed offset to every pixel, multiplies the sum by an unsigned gain, shifts the product right and clamps the result between a lower and an upper threshold. |
| ISP-PNT-02 | The offset, the gain, the shift and the two thresholds shall be set by generics or at run time. |

### 3.5 2D window filter (FLT)

| ID | Requirement |
| --- | --- |
| ISP-FLT-01 | The suite shall deliver, for every pixel of an image, its neighbourhood (window) of a size set by generics, with the border modes valid (only windows inside the image), zero, replicate and mirror for the pixels of a window outside the image. |
| ISP-FLT-02 | The suite shall provide a linear filter on the window: the sum of the pixels of the window, each multiplied by a signed coefficient, at full precision, with negative sums set to 0. |
| ISP-FLT-03 | The size of the window shall be set by generics; the coefficients shall be set by generics or at run time. |
| ISP-FLT-04 | The window filter shall be able to deliver only every n-th window of a line and every m-th line (stride), set by generics. |

### 3.6 Binning (BIN)

| ID | Requirement |
| --- | --- |
| ISP-BIN-01 | The suite shall provide binning: the sum of the pixels of every bin of n x m pixels, with n and m set by generics, as a configuration of the 2D window filter. |
| ISP-BIN-02 | An incomplete bin at the right or the lower edge of the image shall be dropped (border mode valid) or completed with border pixels (the other border modes), selected by a generic. |

### 3.7 Replacement of non-operational pixels (RPL)

| ID | Requirement |
| --- | --- |
| ISP-RPL-01 | The suite shall replace every non-operational pixel by an interpolation between the nearest operational pixels of the same line. |
| ISP-RPL-02 | The non-operational pixels shall be marked by a defect map of one bit per pixel that is written at run time and marks no pixel after the configuration of the device. |
| ISP-RPL-03 | The largest distance to an operational pixel that the interpolation uses shall be set by a generic. |

### 3.8 Fault tolerance (FT)

| ID | Requirement |
| --- | --- |
| ISP-FT-01 | Every memory (line buffers, tables, FIFOs) shall be a fault-tolerant entity of Open Logic with a SECDED code: single bit errors are corrected on every read, double bit errors detected; each correction and detection shall be reported on a status output. |
| ISP-FT-02 | Every memory shall offer the error injection of Open Logic for the test of the error handling in the system. |
| ISP-FT-03 | Tables that hold their content longer than an image (run-time parameters) shall be scrubbed. |
| ISP-FT-04 | Every state machine and counter shall return to a defined state from any state: an upset of a register shall disturb at most the image in progress, and every module shall realign with the next image start. After the reset, control outputs and status outputs shall be defined (no metavalues). |
| ISP-FT-05 | A configuration register that holds its value longer than an image shall carry a parity bit, checked when the value is taken at an image start: a write of every byte that holds bits of the register sets the parity bit for the written value; a write that keeps one of these bytes keeps a parity mismatch. A mismatch shall be reported, and the image shall be processed with the values of the generics. The register map shall offer the injection of a parity error for the test of this error handling. |

### 3.9 Implementation (GEN)

| ID | Requirement |
| --- | --- |
| ISP-GEN-01 | The modules shall be technology-independent VHDL-2008 that GHDL can synthesise, built on Open Logic, with vendor-specific parts in separate adapter modules. |
| ISP-GEN-02 | A specific function shall be a configuration of a general module wherever one covers it. |
| ISP-GEN-03 | The default configuration of every module shall be designed for a clock of 125 MHz on Microchip PolarFire. |
| ISP-GEN-04 | The default configuration of every module shall be designed for a clock of 150 MHz on the AMD Versal device of the family's reference systems. |
