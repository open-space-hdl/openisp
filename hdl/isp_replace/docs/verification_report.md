# isp_replace: Verification Report

## 1. Test results

Run on 2026-11-19 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM (commit 4f1e13b), Open Logic 4.8.0-ft.2:
`python run.py -p 4`, 509 of 509 tests passed (84 of them `isp_replace`), 0 skipped.
QuestaSim runs with the release regression (with and without code coverage).

The status-output audit added a probe of `Stat_ImageOpen` and a read of `STATUS` while an image is open
(test_input_stream, test_registers) and the exact count of `Scrub_EccDed` (test_scrub): `python run.py -p 4` on
2026-11-20 on commit 399d8b9, 542 of 542 tests passed (84 of them `isp_replace`), 0 skipped.

| Test | Configurations | Passed |
| --- | --- | --- |
| `test_static` (TC-RPL-01) | 27 (with the sweeps) | 27 |
| `test_input_stream` (TC-RPL-02) | 8 | 8 |
| `test_map_update` (TC-RPL-03) | 8 | 8 |
| `test_clear` (TC-RPL-04) | 1 | 1 |
| `test_ecc` (TC-RPL-05) | 8 | 8 |
| `test_scrub` (TC-RPL-06) | 10 | 10 |
| `test_registers` (TC-RPL-07) | 8 | 8 |
| `test_flag_coincidence` (TC-RPL-08) | 1 | 1 |
| `test_exhaustive` (TC-RPL-09) | 2 | 2 |
| `test_reset` (TC-RPL-10) | 8 | 8 |
| `test_rate` (TC-RPL-11) | 3 | 3 |
| TC-RPL-12 (`lint/synth_check.py`) | 7 configurations synthesise without latches; 13 generics out of range stop the elaboration with a message naming the generic | 20 |
| TC-RPL-13 (`lint/vivado_ooc.py`) | Section 5 | Not run |
| TC-RPL-14 (review) | Section 6 | Passed |

## 2. Summary

Every output pixel of every test equals the reference model, which computes the replacement from the definitions of
the specification with the defect map read as the architecture reads it, with and without gaps of the source and
stalls of the sink; the contract checker of the sink found the output contract in every test. No test relies on the
initial content of the RAM: every test that depends on the map clears it with `CTRL.CLEAR` or writes it completely
first. The simulation model of the RAM of Open Logic starts with zeros, which are valid codewords of an empty map.

- Replacement: random maps with isolated defects, groups of 2 to 2 x G and longer, groups at both borders of a line
  and lines without an operational pixel, with random bits beyond the last pixel of every line, five images per map
  in different divisions into packets; every G from 1 to 7; pixels of 1 to 24 bits; images of one line, of one map
  word, of 65536 pixels per line and of 65536 lines. `test_exhaustive` ran every pair of 4-bit values with every pair
  of distances (dl, dr) of 1 to 7 for G = 7, the one-sided and the unreplaced pixels of a group of 15 at the right
  border: 30720 pixels, each equal to the model; `exhaustive_p6` did the same for every pair of 6-bit values (491520
  pixels), a width at which a division constant one bit shorter would fail.
- Map lookup: every combination of `RamRdLatency_g` and `EccPipeline_g` with a line of 33 pixels, whose last word
  holds one pixel; maps with a partial last word per line (`g2`, `w33`) and with whole words (`w64`).
- Map updates: words 0, 1, 2 and the last word written between two images apply to the whole next image; words from
  the third after the word of the last accepted pixel on, written during an image, apply in that image; `MAP_ADDR`
  outside the map (the number of words, 0xFFFFFFFF): a write of `MAP_DATA` changes neither the map nor `MAP_ADDR`,
  which reads back all 32 bits.
- `CTRL.CLEAR`: `STATUS.BUSY` high during the clear; `MAP_DATA` without effect during the clear; a second
  `CTRL.CLEAR` does not restart it (`STATUS.BUSY` low after the end of the first clear and before the end of a
  restarted one); the next image unchanged; a map written before a reset applies after it.
- ECC: single errors on a data bit, a Hamming parity bit and the overall parity bit (corrected, one `Stat_EccSec` per
  image that uses the word), a double error on two data bits, one of them the mark of a pixel (the word used as read,
  one `Stat_EccDed` per image), the sticky flags, a new write that ends the reports; a single error on a word that
  pixel (0, 0) reads ahead and a reset while word 0 is in use: no report, and one report in the next image.
- Scrubber: single and double errors injected with the scrubber off, then the scrubber on without images: one
  `Scrub_EccSec` per corrected word, `Scrub_EccDed` once per pass for the double error in the last word of the map (the
  exact count of the plan, section 5), `Scrub_PassDone`; an image after it reports only the double error; images with
  the scrubber running. With the pacer (one tick per clock cycle at `ClkFreqHz_g` 1000): 10 passes in 3000 cycles with a
  period of 300 cycles, no overrun; a period shorter than a pass pulses `Scrub_Overrun`.
- `Stat_ImageOpen` is 1 while an image is open (an image cut after half of its pixels) and 0 after complete images.
- Registers: identification, dimensions, parameters, the words of the map, `STATUS.IMAGE_OPEN` during an image, the
  reset values, every single byte strobe on `MAP_ADDR`, a write of `MAP_DATA` with the strobe of byte 0 only (all 32
  bits written), read-only and write-only registers, unused addresses, every flag of `STATUS` set by its event, kept by
  a write of 0 and by a write without the strobe of its byte, cleared by a write of 1. Every access was answered with
  OKAY.
- Resets idle, held and running, of one and two cycles, during a line, while the window outputs the virtual columns
  of a line, and between two images: the registers return to their reset values, the map stays, the next images are
  correct. A reset of one cycle swept over the cycles of the map reads of pixel (0, 0), with the next image right
  after it: the next image is correct for every step, also with a read latency of 5. A held reset that drops an
  unreplaced pixel waiting in the output register: no `Stat_Unreplaced` for it.
- The control and status outputs carry no metavalue after the first reset, no output pixel carries a metavalue, and
  `Out_Valid`, the pulses and the scrubber status are 0 after every reset.

Measured timing (test_rate) and coincidence (test_flag_coincidence), with Lat = `RamRdLatency_g` + `EccPipeline_g`:

| Quantity | Bound | Design value | Measured |
| --- | --- | --- | --- |
| Hold cycles between the first pixels of two lines (RPL-PF-01) | G; lines 0 and 1: max(G, Lat + 1) | G; lines 0 and 1: Lat + 1 after an idle module, max(G, Lat + 1) after an image | `rate_g2`, `rate_g7`, `rate_w33` (G = 2, 7, 1; Lat = 1, 3, 5): exactly the design values, G per line; lines 0 and 1: 2, 4, 6 after the idle module and 2, 7, 6 after an image |
| Image period (RPL-PF-02) | H x (W + G) + Lat + 16 | H x (W + G) + max(0, Lat + 1 - G); the first interval after an idle module H x W + (H - 1) x G + Lat + 1 | Exactly the design values: 252 and 252, 129 and 132, 209 and 209 cycles (first interval and the further ones) |
| Latency (RPL-PF-03) | 13 + Lat | 10; up to 12 after a hold; up to 11 + Lat for the first pixels of an image | 10 to 12, 10, 10 to 16 cycles (16 = 11 + Lat for the first pixels of an image with Lat = 5) |
| Clear of a flag in the cycle of its event (RPL-RG-02) | The flag stays set | The event wins | `ERR_FRAMING` and `UNREPLACED`: 12 steps each, with the clear before, in and after the cycle of the pulse |

## 3. Generic ranges

| Generic | Declared range | Simulated | Synthesised |
| --- | --- | --- | --- |
| `ImageWidth_g` | 2 x `MaxGap_g` + 1 to 65536 | 3 and 15 (2 x G + 1), 9 to 33 (the gap sweep), 10, 20, 33, 40, 64, 100, 120, 65536 | 3, 15, 2048, 65536; 2 x G and 65537 stop the elaboration |
| `ImageHeight_g` | 1 to 65536 | 1, 2, 3, 4, 5, 6, 40, 256, 4096, 65536 | 1, 1024, 65536; 65537 stops the elaboration |
| `PixelBits_g` | 1 to 24 | 1, 4, 6, 8, 10, 12, 24 | 1, 12, 24; 25 stops the elaboration |
| `MaxGap_g` | 1 to 7 | every value | 1, 2, 7; 0 and 8 stop the elaboration |
| `RamRdLatency_g` | 1 to 3 | every value, crossed with every `EccPipeline_g` | 1, 2, 3; 4 stops the elaboration |
| `EccPipeline_g` | 0 to 2 | every value | 0, 1, 2; 3 stops the elaboration |
| `RamStyle_g` | values of Open Logic | the default (an attribute for the synthesis tool only) | the default |
| `ClkFreqHz_g`, `ScrubPeriod_g` | 1000.0 to 2.14748e11 when paced; 0.0, or 0.001 to 1073741.823 s | 150 MHz free running (0.0); 1000 Hz with 300 ms and 5 ms | 150 MHz with 0.0, 1 ms and 1073741.823 s; 1 ms at 1000 Hz and at 2.14748e11 Hz; a negative period, 0.0005 and 1073741.824 s, 999 Hz and 2.14748001e11 Hz stop the elaboration |

## 4. Mutations

Run on 2026-11-19 on commit a1eceec in a worktree of its own (`git diff --quiet` before and after every mutant), with
14 tests: the 7 of `g2` (every test but the flag sweeps), test_static and test_map_update of `w33`, test_exhaustive of
`exhaustive` and of `exhaustive_p6`, test_clear and test_static of `clear`, and test_static of `one_word`. Every one
of the 16 mutants of the plan (section 6) fails at least one test, and the tests that fail include those the plan
expects. A mutant that changes several places of the source carries all of them in one run.

A first run on 6431301 kept two mutants alive, both equivalent for the tests of that commit (section 7): the border
mode mirror, which the plan now replaces by the window that carries the mark instead of the operational flag, and the
division constant one bit shorter, which the configuration `exhaustive_p6` now kills.

The mutation run was repeated on 2026-11-20 on commit 399d8b9 after the status-output audit (section 7), with the same
14 tests and the three mutants of the audit; the table shows that run. Every one of the 19 mutants fails at least one
test. The read-ahead across the image start is no longer killed by test_scrub: that test wrote its double error into a
random word, in `g2` word 0, which the mutant reads before the injection; the double error is now in the last word of
the map (plan, section 5). test_map_update, the test the plan names, kills it as before.

| Mutation | Result | Failing tests |
| --- | --- | --- |
| None (reference) | passes (14 tests) | - |
| The weights of the interpolation swapped (L x dl + R x dr) | killed by 9 of 14 tests | test_clear, test_ecc, test_exhaustive, test_input_stream, test_map_update, test_scrub, test_static |
| No rounding term | killed by 13 of 14 tests | test_clear, test_ecc, test_exhaustive, test_input_stream, test_map_update, test_registers, test_reset, test_scrub, test_static |
| The search one place too far (G + 1) | killed by 14 of 14 tests | test_clear, test_ecc, test_exhaustive, test_input_stream, test_map_update, test_registers, test_reset, test_scrub, test_static |
| A place outside the image taken as operational (the window carries the mark instead of the operational flag, so that the zero border reads as operational) | killed by 14 of 14 tests | test_clear, test_ecc, test_exhaustive, test_input_stream, test_map_update, test_registers, test_reset, test_scrub, test_static |
| A one-sided replacement from the wrong side | killed by 14 of 14 tests | test_clear, test_ecc, test_exhaustive, test_input_stream, test_map_update, test_registers, test_reset, test_scrub, test_static |
| An unreplaced pixel output as 0 and not reported | killed by 14 of 14 tests | test_clear, test_ecc, test_exhaustive, test_input_stream, test_map_update, test_registers, test_reset, test_scrub, test_static |
| The division constant one bit shorter (K = PixelBits_g + 7) | killed by 1 of 14 tests | test_exhaustive |
| The read-ahead across the image start (words 0 and 1 read at the end of the image before) | killed by 9 of 14 tests | test_clear, test_map_update, test_registers, test_reset, test_static |
| No new word at the first pixel of a line (the word counter not advanced at the end of a line) | killed by 12 of 14 tests | test_clear, test_ecc, test_exhaustive, test_input_stream, test_map_update, test_reset, test_scrub, test_static |
| MAP_ADDR cut to the width of the map address | killed by 3 of 14 tests | test_map_update, test_registers |
| MAP_ADDR counted up by a write without effect | killed by 3 of 14 tests | test_clear, test_map_update |
| A CTRL.CLEAR during a clear restarts it | killed by 1 of 14 tests | test_clear |
| A word with a double error replaced by zeros instead of used as read | killed by 3 of 14 tests | test_ecc, test_registers, test_scrub |
| Stat_Unreplaced pulsed when the pixel enters the output register (not when it leaves the module) | killed by 1 of 14 tests | test_reset |
| No Stat_EccSec pulse with a read | killed by 2 of 14 tests | test_ecc, test_registers |
| The error flags of a word reported when it is read, not when it comes in use | killed by 1 of 14 tests | test_ecc |
| Stat_ImageOpen tied to 0 | killed by 1 of 14 tests | test_input_stream |
| STATUS.IMAGE_OPEN tied to 0 | killed by 1 of 14 tests | test_registers |
| Scrub_EccSec and Scrub_EccDed exchanged | killed by 1 of 14 tests | test_scrub |

## 5. Synthesis and timing

Not run yet: TC-RPL-13 runs out-of-context synthesis and implementation at 150 MHz on the device of the Timing level
(architecture of the suite, section 10); the run is open (roadmap). The script `lint/vivado_ooc.py` is ready with the
configurations `rpl_default` (2048 x 1024 pixels of 12 bits, G = 2, a map of 65536 words) and `rpl_g7` (24-bit pixels, G
= 7).

The GHDL synthesis of TC-RPL-12 shows that the module is synthesisable at the bounds of its generics, with the
scrubber free running and paced, without latches; the netlist of the default configuration holds the map as a RAM of
65536 words and the divisors as a table of 16 constants. It gives no timing.

## 6. Requirement coverage

| Requirement | Test cases | Status |
| --- | --- | --- |
| RPL-IF-01, RPL-IF-02 | TC-RPL-01 to 11 | Passed |
| RPL-IF-03 | TC-RPL-07 | Passed |
| RPL-IF-04 | TC-RPL-01, 02, 05 | Passed |
| RPL-IF-05 | TC-RPL-05, 06 | Passed |
| RPL-IF-06 | TC-RPL-10 | Passed |
| RPL-FN-01 | TC-RPL-01, 09 and review TC-RPL-14 | Passed |
| RPL-FN-02, RPL-FN-03 | TC-RPL-01, 02 | Passed |
| RPL-FN-04 | TC-RPL-03 | Passed |
| RPL-FN-05 | TC-RPL-01, 04 | Passed |
| RPL-FN-06 | TC-RPL-01 (configurations with and without gaps and stalls) | Passed |
| RPL-FN-07 | TC-RPL-14 (review): the RTL instantiates `isp_frame_sync`, the map lookup, `isp_window` (`WinX_g` = 2 x G + 1, `WinY_g` = 1, anchor G, border mode zero, pixels of `PixelBits_g` + 1 bits with the operational flag) and the interpolation | Passed |
| RPL-PF-01, RPL-PF-02, RPL-PF-03 | TC-RPL-11 | Passed |
| RPL-ER-01 | TC-RPL-02 | Passed |
| RPL-ER-02 | TC-RPL-01, 09 | Passed |
| RPL-ER-03 | TC-RPL-05 | Passed |
| RPL-ER-04 | TC-RPL-03, 04 | Passed |
| RPL-FT-01 | TC-RPL-05, 06 | Passed |
| RPL-FT-02 | TC-RPL-10 and review TC-RPL-14: `when others` of the lookup leads to `Run_s`; the reads restart with every pixel (0, 0); a word without a pending read is dropped; a pixel for which no word can come passes as operational until the next image start; the division constant: ceil(2^K / d) for K = `PixelBits_g` + 8 and d = 2 to 14 has an error below one unit of the quotient for every numerator below 2^(`PixelBits_g` + 4), since N x (d - 1) < 2^K | Passed |
| RPL-FT-03 | TC-RPL-10 and the monitor of every test | Passed |
| RPL-RG-01, RPL-RG-03 | TC-RPL-03, 07 | Passed |
| RPL-RG-02 | TC-RPL-07, 08 | Passed |
| RPL-RG-04 | TC-RPL-04 | Passed |
| RPL-CF-01, RPL-CF-02 | TC-RPL-12 | Passed |
| RPL-CF-03 | TC-RPL-13 | Open (section 5) |

## 7. Findings

| Finding | Correction |
| --- | --- |
| The derivation of the plan expected G + Lat + 1 hold cycles between the first pixels of lines 0 and 1 and an image period of H x (W + G) + Lat + 1. The rate test measured less (for example 7 instead of 11 holds and 132 instead of 136 cycles with G = 7 and Lat = 3). A trace of the handshakes showed the cause: after an image, the wait for word 0 of the next image runs beside the G virtual columns of the last line of the image before, which the buffers between the input and the window move into the next image; after an idle module the wait stands alone. The RTL is right | The specification (RPL-PF-01), the architecture and the plan state the exact values: Lat + 1 holds after an idle module, max(G, Lat + 1) after an image; the period H x (W + G) + max(0, Lat + 1 - G), the first interval after an idle module H x W + (H - 1) x G + Lat + 1. The bench checks these values exactly |
| `Stat_Unreplaced` pulsed when an unreplaced pixel entered the output register. A reset that drops pixels in the pipeline made the count depend on the stage the dropped pixel had reached; the count of `test_reset` differed from the model by one in two configurations | `Stat_Unreplaced` pulses in the cycle after the pixel left the output, so a pixel lost by a reset reports nothing (RPL-IF-04); the model counts the delivered pixels |
| The first runs stopped in every test of `g2` with a range error of the counter of pending reads, which ran below 0. The first explanation, a read issued during the reset that returned after it, was wrong: every read-valid stage of `olo_ft_ram_sdp_scrub` clears with the reset. A trace of every event of the read valid showed the cause: when a read of the scrubber returns, the read valid rises to '1' and falls back to '0' within the same simulation time (the mask of the scrubber reads takes effect one delta cycle later), and the combinational process of the lookup saw the '1' in that delta cycle with no read pending. At every clock edge the read valid is '0', so the glitch never reached a register; the RTL is right | The guard that drops a word with no read pending stays, as the defence against an upset of the counter (RPL-FT-02) that it is; it also keeps the counter in its range in the delta cycle of the glitch. `test_reset` sweeps a reset of one cycle over the cycles of the map reads of pixel (0, 0); with a read latency of 5 the reset met a read in four steps, with 0, 1 and 2 reads under way, and the next image was correct every time |
| The flag sweeps ran first in `g2`, with gaps of the source and stalls of the sink; the pulse moved by more than one cycle per step and missed the coincidence | The sweeps run in the configuration `flags` without gaps and stalls |
| The plan asked for a scrub period of 2 µs; the pacer of Open Logic has a granularity of 1 ms | The bench sets `ClkFreqHz_g` to 1000, so that a millisecond of the pacer is one clock cycle, with periods of 300 and 5 ms |
| The plan listed the mutant "the map lookup takes the uncorrected word"; Open Logic delivers only the corrected word, so the mutant cannot be written in the module | Replaced by "a word with a double error replaced by zeros instead of used as read" (E6), and the mutant of the E1 rule added |
| A model that rebuilt the line for every pixel took minutes for 65536 pixels per line | The model looks only at the places up to the pixel G to the right, which have all arrived |
| `test_reset` placed its running reset at random. In a running reset the sink takes a random number of the dropped beats before the reset, so a dropped unreplaced pixel could leave the module and report: the count of `Stat_Unreplaced` differed from the model by one in two configurations | The running reset is placed where no dropped pixel is unreplaced; the held resets need no such care, since no dropped beat leaves the module |
| The first mutation run (6431301) kept the mutant of the border mode mirror alive. It is equivalent: a place outside the image then reaches only a pixel that the search on the other side finds nearer, and the interpolation of a pixel with itself is that pixel; the border mode replicate is equivalent as well | The mutant of a place outside taken as operational is the window that carries the mark instead of the operational flag, so that the zero border reads as operational |
| The first mutation run also kept the division constant one bit shorter alive: with 4-bit pixels it gives the right quotient for every reachable numerator. A model of the division over every width from 1 to 24 bits shows that K = P + 8 is exact and that K = P + 7 fails only at 5, 6, 9, 17, 18 and 21 bits (for d = 13, values near the top) | The configuration `exhaustive_p6` runs every pair of 6-bit values with every pair of distances |
| The audit of the status outputs of every module (after the mutation run of `isp_filter2d`) found three gaps in this bench: `Stat_ImageOpen` probed only after complete images, where it is 0; `STATUS.IMAGE_OPEN` never read as 1; `Scrub_EccDed` checked only as at least one pulse, not against the count of the design | test_input_stream probes `Stat_ImageOpen` while an image is open; test_registers reads `STATUS` while an image is open; test_scrub checks `Scrub_EccDed` exactly, one pulse per pass for the word with the double error, which is now the last word of the map, and the bench switches the scrubber off only at the end of a pass (derivation in the plan, section 5). The mutants `Stat_ImageOpen` tied to 0, `STATUS.IMAGE_OPEN` tied to 0 and the exchange of `Scrub_EccSec` and `Scrub_EccDed` are killed (section 4). No change of the RTL |
| The audit of the configuration checks found the ranges of `ClkFreqHz_g` and `ScrubPeriod_g` stated as "range of Open Logic" and unchecked in the module: the scrubber of Open Logic checks 1000.0 Hz and 1 ms with messages that name its own generics, treats a negative period as free running, and the divider of the period fails above 2^30 - 1 ms with an integer overflow in `log2ceil` (Open Logic states 2^31 - 1 ms) | The specification states the ranges (the period rounded to whole milliseconds), the module checks both and passes the scrubber in-range values only; negatives for a negative, a too short and a too long period and a too low and a too high clock, and the bounds synthesised (TC-RPL-12). The bench is unchanged |
