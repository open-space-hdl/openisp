# isp_conv: Verification Report

## 1. Test results

Run on 2026-11-19 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM (commit 4f1e13b), Open Logic 4.8.0-ft.2:
`python run.py -p 4`, 425 of 425 tests passed (122 of them `isp_conv`), 0 skipped.
QuestaSim runs with the release regression (with and without code coverage).

The write decode with one address compare per coefficient and the parity of a write from the parities of its bytes
(architecture, section 6) keep every cycle: in all 122 tests of the module, the 29 signals at the ports of the module
(the reset, the input and output streams, the AXI4-Lite channels and `Err_Config`) are identical in every time step
between commit ac061ff (before the change) and commit dbcce6e, and the generated stimuli and expected outputs of every
configuration are unchanged (488 files). The test bench, the model and the shared bench sources are the same in both
commits.
`python run.py -p 4` on 2026-11-20 on commit 1a42dba, 668 of 668 tests passed (122 of them `isp_conv`), 0 skipped;
`lint/synth_check.py` (TC-CNV-11) passed.

`In_Ready` from a copy of the valid flag of the output register (architecture, section 4) keeps every cycle: in every
test of `isp_conv_tb` (122, the 29 signals at the ports of the module, `In_Ready` among them) and of the benches of
`isp_filter2d` (32), `isp_bin` (97) and the chain (21) (the signals at the top level of the bench), the traces are
identical in every time step between commit 572dbd7 (before the change) and commit 76f82e0, 272 tests in all.
`python run.py -p 4` on 2026-11-20 on commit 3ca7d40 (with develop 0b4d974), 668 of 668 tests passed (122 of them
`isp_conv`), 0 skipped; `lint/synth_check.py` (TC-CNV-11) passed.

The parity bit of a write after PKG-08 (`ispWriteParity` of `isp_pkg`: a write that keeps a byte with bits of the
register keeps a mismatch; architecture, section 6) came with the partial writes of test_parity: `python run.py -p 4` on
2026-11-20 on commit e9116a7 (with develop fbc18fd), 669 of 669 tests passed (122 of them `isp_conv`), 0 skipped;
`lint/synth_check.py` (TC-CNV-11) passed.

| Test | Configurations | Passed |
| --- | --- | --- |
| `test_static` (TC-CNV-01) | 42 (with the sweeps) | 42 |
| `test_runtime` (TC-CNV-02) | 10 | 10 |
| `test_hold` (TC-CNV-03) | 4 | 4 |
| `test_parity` (TC-CNV-04) | 42 (with the sweeps) | 42 |
| `test_registers` (TC-CNV-05) | 6 | 6 |
| `test_flag_coincidence` (TC-CNV-06) | 1 | 1 |
| `test_exhaustive` (TC-CNV-07) | 2 | 2 |
| `test_packets` (TC-CNV-08) | 6 | 6 |
| `test_reset` (TC-CNV-09) | 6 | 6 |
| `test_rate` (TC-CNV-10) | 3 | 3 |
| TC-CNV-11 (`lint/synth_check.py`) | 8 configurations synthesise without latches; 10 generics out of range stop the elaboration with a message naming the generic | 18 |
| TC-CNV-12 (`lint/libero_synth.py`) | 4 configurations (section 5) | 4 of 4 synthesised |

## 2. Summary

Every output pixel of every test equals the reference model, which computes the sum in unbounded integers, with and
without gaps of the source and stalls of the sink; the contract checker of the sink found the output contract in every
test with well-formed window streams.

- The arithmetic: the MTF kernels 3 x 3 (gain 16) and 5 x 5, the sum of four ones of the binning, every window size
  n x (17 - n), every depth of the adder tree (0 to 8 levels, with a full and a partly filled last level), the
  smallest configuration (1-bit pixels, 2-bit coefficients, 1-bit output) and the widest (16 x 16 windows of 32-bit
  pixels with 18-bit coefficients and a 64-bit output), the coefficient bounds -2^17 and 2^17 - 1. Every image
  contains the windows of largest and of zero elements, of the largest and of the most negative sum, and a window of
  nonzero elements whose sum is exactly 0. `test_exhaustive` ran every coefficient pair of 3-bit coefficients (64
  sets) as a run-time set over an image of every pair of 3-bit elements, at the full precision and saturated to 3
  bits: 8192 pixels, each equal to the model.
- The output width: the full precision (`OutBits_g` 0) and the saturation below it (1, 3, 12 bits), at it (F = 52)
  and above it (64 bits).
- Run-time sets: random sets, the sets of both bounds, a set with the sign of every coefficient changed, every
  coefficient read back sign-extended; a set written during an image applies from the next image.
- `CTRL.HOLD`: a set written over two images is not taken while `HOLD` is 1 and is taken as a whole after it; a
  register of bad parity is neither taken nor reported while `HOLD` is 1.
- Parity: the injection into each coefficient register in turn (for more than 16 coefficients the first, the last and
  eight random ones) makes every image use the generic with one `Err_Config` until the register is written; the
  injection into `CTRL` with `CTRL.HOLD` 1 makes every image start take the held set with one `Err_Config` until
  `CTRL` is written; two injections in one set, a second injection that restores the parity, an index of T or above,
  an injection without the strobe of byte 0 and injections with `RuntimeCoef_g` false have no effect beyond the model.
  Partial writes (PKG-08): after an injection, a write that keeps a byte with bits of the register and a write of
  only bytes without bits keep the mismatch (the next images use the generic with `Err_Config`), a write of every
  byte with bits clears it, and a partial write without a mismatch is taken (one random coefficient per
  configuration; both kinds of write where `CoefBits_g` is above 8).
- Registers: identification, the window and the widths, the reset values of all coefficients (the generic,
  sign-extended), every single byte strobe on the first, the middle and the last coefficient, read-only registers,
  the gaps, the address above the last coefficient and the end of the address space, the sticky flag. Every access
  was answered with OKAY.
- Packets: a "01" packet after "00" packets, single-window packets, `In_Last` on every beat, other flags on the later
  beats of a packet, images back to back: the set changes only at an image start.
- Resets idle, held and running, of one and two cycles, in the middle of an image and between the image start and the
  first output pixel: the registers hold the generic again and the next images are correct.
- The control outputs carry no metavalue after the first reset, no output pixel carries a metavalue, and `Out_Valid`
  and `Err_Config` are 0 after every reset.

Measured timing (test_rate) and coincidence (test_flag_coincidence):

| Quantity | Bound | Design value | Measured |
| --- | --- | --- | --- |
| Throughput (CNV-PF-01) | One window per cycle | One per cycle | `In_Ready` high for every window of three images back to back, for T = 9, 25 and 256 |
| Latency (CNV-PF-02) | 3 + log2ceil(T) cycles | 3 + log2ceil(T) | 7, 8 and 11 cycles for T = 9, 25 and 256, for each of the 288 pixels |
| Clear of the flag in the cycle of its event (CNV-RG-02) | The flag stays set | The event wins | `ERR_CONFIG`: 12 steps, with the clear from two cycles before to nine cycles after the pulse |

## 3. Generic ranges

| Generic | Declared range | Simulated | Synthesised |
| --- | --- | --- | --- |
| `PixelBits_g` | 1 to 32 | 1, 3, 6, 8, 12, 16, 31, 32 | 1, 12, 32; 33 stops the elaboration |
| `WinX_g`, `WinY_g` | 1 to 16 | every value | 1, 3, 4, 5, 16; 17 stops the elaboration |
| `CoefBits_g` | 2 to 18 | 2, 3, 6, 8, 16, 17, 18 | 2, 16, 18; 1 and 19 stop the elaboration |
| `Coef_g` | T values of -2^(`CoefBits_g` - 1) to 2^(`CoefBits_g` - 1) - 1 | both bounds of 18-bit coefficients, 0, 1, -1, the MTF kernels, random sets of every simulated width | both bounds; T - 1 and T + 1 values and a value beyond either bound stop the elaboration |
| `RuntimeCoef_g` | false, true | both | both |
| `OutBits_g` | 0, 1 to 64 | 0, 1, 3, 12, 52 (F), 64 | 0, 1, 12, 64; 65 stops the elaboration |

## 4. Mutations

Run on 2026-11-19 on commit acb925d in a worktree of its own (`git diff --quiet` before and after every mutant), with
the 24 tests of the configurations `mtf3`, `mtf5_const`, `ones4`, `exhaustive`, `exhaustive_sat` and `rate_3`,
test_static of `taps_5` and `taps_33` and test_registers of `wide`. Every mutant of the plan (section 6) fails at
least one test, and the tests that fail include those the plan expects.

The mutation run was repeated on 2026-11-20 on commit dbcce6e, the write decode with one address compare per
coefficient and the parity of a write from the parities of its bytes (architecture, section 6), with the same 24 tests,
four mutants of the write decode and two of the byte parities. Every one of the 19 mutants failed at least one test.
The write with byte enables merged into zeros and the parity of a kept byte taken from the write data are killed by
test_registers of `mtf3` and `wide`, which write with random strobes (CNV-RG-03).

The mutation run was repeated again on 2026-11-20 on commit 76f82e0, `In_Ready` from a copy of the output valid flag
(architecture, section 4), with the same 24 tests and two mutants of the copy. Every one of the 21 mutants fails at
least one test. The two mutants of the copy are killed by every test with stalls of the sink (20 and 17 tests); the plan
first named TC-CNV-10 for them as well, which runs without stalls and cannot see the ready path, and was corrected.

The mutation run was repeated on 2026-11-20 on commit 2189d17, the parity bit of a write from `ispWriteParity` of
`isp_pkg` (PKG-08), with the same 24 tests; the table shows that run, and the sources of the module are the same at
e9116a7. The two mutants of the byte parities now change the function, and three mutants of PKG-08 came with it: a write
that keeps a byte with bits sets the parity bit for the resulting value (the rule before PKG-08), a write of every byte
with bits keeps the syndrome, and a write of only bytes without bits sets the parity bit. Every one of the 24 mutants
fails at least one test; the three mutants of PKG-08 are killed by test_parity.

| Mutation | Result | Failing tests |
| --- | --- | --- |
| None (reference) | passes (24 tests) |  |
| A negative sum not set to 0 (wraps) | killed by 19 of 24 tests | test_exhaustive, test_flag_coincidence, test_hold, test_packets, test_parity, test_rate, test_registers, test_reset, test_runtime, test_static |
| No saturation below the full precision (truncation) | killed by 6 of 24 tests | test_exhaustive, test_packets, test_parity, test_registers, test_reset, test_static |
| An element multiplied as a signed number (its top bit as sign) | killed by 24 of 24 tests | test_exhaustive, test_flag_coincidence, test_hold, test_packets, test_parity, test_rate, test_registers, test_reset, test_runtime, test_static |
| The last product dropped when a level of the adder tree has an odd count | killed by 12 of 24 tests | test_flag_coincidence, test_hold, test_packets, test_parity, test_rate, test_registers, test_reset, test_runtime, test_static |
| The working set loaded at the first beat of every packet, not only at the image start | killed by 7 of 24 tests | test_flag_coincidence, test_hold, test_packets, test_parity, test_registers, test_runtime |
| CTRL.HOLD without effect | killed by 2 of 24 tests | test_hold, test_parity |
| No parity check of the coefficients | killed by 5 of 24 tests | test_flag_coincidence, test_hold, test_parity, test_registers |
| No parity check of CTRL | killed by 1 of 24 tests | test_parity |
| No Err_Config pulse | killed by 5 of 24 tests | test_flag_coincidence, test_hold, test_parity, test_registers |
| INJECT.INDEX ignored (always coefficient 0) | killed by 1 of 24 tests | test_parity |
| A coefficient read back without sign extension | killed by 6 of 24 tests | test_registers, test_reset, test_runtime |
| Out_Last one stage early | killed by 24 of 24 tests | test_exhaustive, test_flag_coincidence, test_hold, test_packets, test_parity, test_rate, test_registers, test_reset, test_runtime, test_static |
| A stage that does not wait for the common enable (the adder tree advances in every cycle) | killed by 20 of 24 tests | test_hold, test_packets, test_parity, test_registers, test_reset, test_runtime, test_static |
| A coefficient write that lands in the coefficient after its address | killed by 9 of 24 tests | test_exhaustive, test_hold, test_packets, test_parity, test_registers, test_reset, test_runtime |
| The parity bit of a coefficient not set by its write | killed by 8 of 24 tests | test_exhaustive, test_hold, test_packets, test_parity, test_registers, test_reset, test_runtime |
| A write with byte enables merged into zeros instead of the stored coefficient | killed by 3 of 24 tests | test_parity, test_registers |
| In_Ready from a copy of the output valid flag stuck at 0 (always ready) | killed by 20 of 24 tests | test_hold, test_packets, test_parity, test_registers, test_reset, test_runtime, test_static |
| The copy of the output valid flag one advance late | killed by 17 of 24 tests | test_hold, test_packets, test_parity, test_registers, test_reset, test_runtime, test_static |
| INJECT.PARITY flips the parity bit of every coefficient | killed by 1 of 24 tests | test_parity |
| The parity of a kept byte taken from the write data | killed by 2 of 24 tests | test_parity, test_registers |
| The parity of a written byte taken from the stored bits | killed by 8 of 24 tests | test_exhaustive, test_hold, test_packets, test_parity, test_registers, test_reset, test_runtime |
| A write that keeps a byte with bits sets the parity for the resulting value (the re-seal before PKG-08) | killed by 1 of 24 tests | test_parity |
| A write of every byte with bits keeps the syndrome | killed by 2 of 24 tests | test_hold, test_parity |
| A write of only bytes without bits sets the parity for the stored value | killed by 1 of 24 tests | test_parity |

## 5. Synthesis and timing

TC-CNV-12 (`lint/libero_synth.py`), the preliminary synthesis on PolarFire MPF100T (Libero, Synplify Pro, speed grade
STD) with a clock of 125 MHz, on commit 4c1744f (the RTL of develop 06a41e5). The results are pre-layout estimates, not
a timing closure and not on the reference device. The out-of-context run at 150 MHz on the Versal device of the
reference systems is open (roadmap).

| Configuration | Estimate (MHz) | Slack (ns) | 4LUT | DFF | LSRAM | Math | Worst path (logic levels) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `cnv_mtf3`: 3 x 3, 12-bit pixels, 16-bit run-time coefficients (the MTF filter) | 177.1 | 2.354 | 1094 | 1043 | 0 | 9 | the image-start load of the working set (4) |
| `cnv_mtf5`: 5 x 5, 12-bit pixels, 16-bit run-time coefficients (the MTF filter) | 149.8 | 1.327 | 2835 | 2457 | 0 | 25 | a coefficient -> the parity check of the set -> the enable of the working set (8) |
| `cnv_max`: 16 x 16, 12-bit pixels, 16-bit run-time coefficients (the largest) | 112.1 | -0.919 | 25660 | 33174 | 0 | 256 | the register address -> the read multiplexer of 256 coefficients -> the read data (17) |
| `cnv_bin4`: 1 x 4 ones, 12-bit pixels (the binning) | 274.9 | 4.362 | 106 | 215 | 0 | 0 | the flags of the adder pipeline (2) |

The MTF filters and the binning meet 125 MHz in the estimate (sections 5.1 to 5.3). `cnv_max`, the largest window at run
time and not a default, reaches 112.1 MHz (section 5.1, user guide, section 8).

The GHDL synthesis of TC-CNV-11 shows that the module is synthesisable at the bounds of its generics with both values
of `RuntimeCoef_g`, without latches; it gives no timing.

### 5.1 The register write

The preliminary synthesis on PolarFire MPF100T (Libero, Synplify Pro) with a clock of 125 MHz, pre-layout estimates,
not a timing closure and not on the reference device, found the write of a coefficient register on the worst path of
every configuration with run-time coefficients: the index of the register computed from the address, the stored
coefficient selected among all T for the merge of the written bytes, the parity of the merged word and the write
enables decoded again. The write now compares the address with each register by itself (one compare per
coefficient), and the parity of a write comes from the parities of the bytes (the write data for a written byte, the
stored bits for a kept one), so that the byte merge feeds only the register:

| Configuration | Before (MHz, 4LUT) | One compare per coefficient, the parity of the merged word | With the parity from the bytes (the design) | Worst path of the design |
| --- | --- | --- | --- | --- |
| `cnv_mtf3` (3 x 3) | 132.3, 1093 | 180.3, 1187 | 178.8, 1061 | the image-start load of the working set (4 logic levels) |
| `cnv_mtf5` (5 x 5) | 124.4, 2792 | 160.9, 3196 | 156.2, 2758 | a coefficient -> the working set (8) |
| `cnv_max` (16 x 16) | 79.4, 21930 | 118.0, 29122 | 116.2, 24507 | the register address -> the read data, the read multiplexer of 256 coefficients (16) |

`cnv_max`, the largest configuration and not a default, stays below 125 MHz: its worst path is the read multiplexer of
the 256 coefficient registers, which answers a read in the cycle after it (CV-4). A register stage there would add a
cycle to every register read; the configuration is recorded instead.

### 5.2 The ready path

In `isp_filter2d` 5 x 5 mirror (`flt_mtf5`) `In_Ready` of the module was the condition of the common enable of the
stages, a net with 890 loads, and the window and its frame sync decided their events and the data of the line buffers
from it. Once the window computed its decisions without the selection of the event position, that path limited
`flt_mtf5`: 115.1 MHz (122.2 MHz before the window change, with the window path). `In_Ready` now comes from a copy of
the valid flag of the output register (architecture, section 4):

| Configuration | Before (MHz, 4LUT) | With the copy (MHz, 4LUT) | Worst path with the copy |
| --- | --- | --- | --- |
| `flt_mtf5` (`isp_filter2d` 5 x 5 mirror) | 115.1, 4765 | 146.0, 4741 | the window state -> the row select register (7 logic levels) |
| `cnv_mtf3` | 178.8, 1061 | 177.2, 1056 | the image-start load of the working set (4) |
| `cnv_mtf5` | 156.2, 2758 | 155.6, 2787 | a coefficient -> the working set (8) |
| `win_mirror5` | 139.5, 2329 | 139.5, 2329 | the state -> the row select register (8) |

The worst paths of `cnv_mtf3` and `cnv_mtf5` are those before the change and do not contain the copy; the LUT counts
differ slightly, so the mapping differs; the estimates differ by less than 1 % and stay above 125 MHz.

### 5.3 The parity of a partial write

The parity bit of a write after PKG-08 (`ispWriteParity` of `isp_pkg`) needs, for every coefficient register, the parity
of the written and of the stored bits of each byte and a selection by the strobes among the parity of the written value,
the kept syndrome and the old parity bit. Preliminary synthesis on PolarFire MPF100T (Libero, Synplify Pro) with a clock
of 125 MHz, pre-layout estimates, not a timing closure and not on the reference device, on develop fbc18fd and on commit
e9116a7:

| Configuration | Develop fbc18fd (MHz, 4LUT) | With PKG-08 (MHz, 4LUT) | Worst path with PKG-08 |
| --- | --- | --- | --- |
| `cnv_mtf3` | 177.2, 1056 | 177.1, 1094 | the image-start load of the working set (4 logic levels), as on develop |
| `cnv_mtf5` | 155.6, 2787 | 149.8, 2835 | a coefficient -> its parity -> the parity check of the set at the image start -> the enable of the working set (8), as on develop with another coefficient |
| `cnv_max` | 114.2, 24511 | 112.1, 25660 | the register address -> the read data, the read multiplexer of 256 coefficients (17; 15 on develop) |

The parity of the writes costs 38, 48 and 1149 4LUT (3.6 %, 1.7 % and 4.7 %), in `cnv_max` about 4.5 4LUT per
coefficient register. It feeds only the parity registers, and no worst path ends there. The estimate of `cnv_mtf5` is
5.8 MHz (3.7 %) lower on the same path and stays above 125 MHz; `cnv_max`, not a default, stays below 125 MHz on the
read multiplexer (section 5.1).

## 6. Requirement coverage

| Requirement | Test cases | Status |
| --- | --- | --- |
| CNV-IF-01, CNV-IF-02 | TC-CNV-01 to 10 | Passed |
| CNV-IF-03 | TC-CNV-05 | Passed |
| CNV-IF-04 | TC-CNV-04 | Passed |
| CNV-IF-05 | TC-CNV-09 and review (one clock, the reset sampled in the clocked process only) | Passed |
| CNV-FN-01 | TC-CNV-01, 02, 07 | Passed |
| CNV-FN-02 | TC-CNV-01, 08 | Passed |
| CNV-FN-03 | TC-CNV-01 | Passed |
| CNV-FN-04 | TC-CNV-02, 03, 08 | Passed |
| CNV-FN-05 | TC-CNV-01, 08 | Passed |
| CNV-PF-01, CNV-PF-02 | TC-CNV-10 | Passed |
| CNV-ER-01, CNV-ER-02 | TC-CNV-04 | Passed |
| CNV-FT-01 | TC-CNV-04, 09 and review: the stages hold no state between windows; the working set is loaded with every image start | Passed |
| CNV-FT-02 | TC-CNV-04 | Passed |
| CNV-FT-03 | TC-CNV-09 and the monitor of every test | Passed |
| CNV-RG-01 | TC-CNV-02, 05 | Passed |
| CNV-RG-03 | TC-CNV-02, 04, 05 | Passed |
| CNV-RG-02 | TC-CNV-05, 06 | Passed |
| CNV-RG-04 | TC-CNV-04 | Passed |
| CNV-CF-01, CNV-CF-02 | TC-CNV-11 | Passed |
| CNV-CF-03 | TC-CNV-12 | Open (section 5) |

## 7. Findings

| Finding | Correction |
| --- | --- |
| The synthesis check with a `Coef_g` of T - 1 values stopped with an index error in the function that builds the coefficient set of the generic, before the check of CNV-CF-01 could name the generic | The function fills the missing values with 0, so that the elaboration reaches the check and stops with its message |
| `test_static` sent one image as a single packet with the flags "11", which `isp_window` never delivers; the contract checker of the sink rejected it. `test_reset` resumed the interrupted image after the reset, which a window stream does not do either, since `isp_window` is reset with the module and restarts at an image start | `test_static` sends window streams of one packet per line (the other packet shapes stay in `test_packets`, with the checker off); `test_reset` stops the window stream at the reset and sends the next image; the plan states it. No change of the RTL |
| `lint/vivado_ooc.py` read one declaration per line and wrote generic values as plain text: the port `Out_Data` of `isp_conv` continues on a second line, and `Coef_g` is a vector | The script joins continued declarations and writes lists as named aggregates; the top levels of the earlier configurations are unchanged, byte for byte |
| The preliminary synthesis at 125 MHz on PolarFire MPF100T found the write of a coefficient register on the worst path of every configuration with run-time coefficients (`cnv_mtf5` 124.4 MHz, `cnv_max` 79.4 MHz, in `isp_filter2d` 108.0 MHz): the register selected by an index computed from the address for the merge of the written bytes and the parity | One address compare per coefficient and the parity of a write from the parities of its bytes (architecture, section 6; section 5.1): `cnv_mtf3` 178.8 MHz, `cnv_mtf5` 156.2 MHz, with fewer LUT than before; no cycle changes (section 1); four mutants of the write decode (plan, section 6) |
| A write with byte strobes set the parity bit for the resulting value. An upset in a byte that the write kept, for example while `CTRL.HOLD` is 1 and the registers are not checked, therefore became a valid word with the next partial write: masked, not detected (found in review) | The parity bit of a write follows PKG-08 (`ispWriteParity` of `isp_pkg`): a write of every byte that holds bits of the register sets it for the written value, a write that keeps such a byte keeps a mismatch, so that the error is reported until the register is written in full; CNV-RG-03, the error table, the user guide (4.3: the software writes every byte with bits after `ERR_CONFIG`); test_parity: an injection, then a partial write and a write of only bytes without bits, then the images with the generics, a full write that clears it, and a partial write without a mismatch |
