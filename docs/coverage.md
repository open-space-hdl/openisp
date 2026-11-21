# OpenISP: Code Coverage

## 1. Method

The code coverage of the OpenISP sources is measured with QuestaSim Pro Microchip Edition 2024.3 over the complete
regression of `run.py`, the same test set that GHDL runs in CI, at a time resolution of 1 fs:

```shell
python run.py --questa --coverage -p 1
```

The sources of `hdl/<module>/src` are compiled with `+cover=sbcef`: statements, branches, conditions, expressions
(focused expression coverage) and state machines. Open Logic, UVVM and the testbenches (`hdl/<module>/tb`, `tb/`) are
not instrumented; Open Logic is verified by its own regression. `run.py` merges the coverage of all tests into
`coverage/coverage.ucdb` and writes the reports `coverage/coverage_report.txt` (details per instance) and
`coverage/coverage_byfile.txt`. The numbers below are per source file: an item is covered when any instance of the
file in any test covers it. The sources carry no coverage pragmas.

Closure rules:

- Statements, branches, state machine states and transitions: every item is covered by a test or listed with its
  justification in section 4.
- Conditions and expressions: every miss is reviewed. A miss that a stimulus at the ports of a module can reach is
  closed by a test (section 3); a remaining miss is listed with its justification in section 4.
- A test that changes after the run of the complete regression runs again in QuestaSim with code coverage from the
  same source tree, and its coverage database is merged with that of the complete run (`vcover merge`).

## 2. Result

Two runs, both on the HDL of release 0.1.0 (the sources `hdl/<module>/src` of commit b50efd1):

- The complete regression on 2026-11-21 on commit b50efd1: 669 of 669 tests passed, 0 skipped.
- The 76 tests that the coverage closure changed (section 3), on 2026-11-21 on commit 92a444e: 76 of 76 passed, 0
  skipped. They are test_parity (42 configurations) and test_registers (6) of `isp_conv`, test_parity (5) and
  test_registers (4) of `isp_crop`, test_registers (9) of `isp_point`, and test_clear (1) and test_registers (9) of
  `isp_replace`.

Between the two commits `git diff b50efd1 92a444e -- 'hdl/*/src/*'` is empty and no VHDL file of the testbenches
changed; the generated stimuli and expected outputs of the other 593 tests are byte-identical, so their results of
the first run apply to commit 92a444e. The numbers below are the merge of the coverage databases of the two runs.
Numbers are covered/total bins per file; bold marks a metric with misses.

| File | Statements | Branches | FSM States | FSM Transitions | Conditions | Expressions |
| --- | --- | --- | --- | --- | --- | --- |
| `isp_bin/src/isp_bin.vhd` | 19/19 |  |  |  |  | 4/4 |
| `isp_conv/src/isp_conv.vhd` | **112/113** | **53/54** |  |  | **21/24** | 2/2 |
| `isp_crop/src/isp_crop.vhd` | 86/86 | 57/57 |  |  | **8/10** | 13/13 |
| `isp_frame_sync/src/isp_frame_sync.vhd` | **75/78** | **52/53** |  |  | 6/6 | 6/6 |
| `isp_pkg/src/isp_pkg.vhd` | **25/26** | **14/15** |  |  |  | 9/9 |
| `isp_point/src/isp_point.vhd` | 165/165 | 81/81 |  |  | **12/15** | 6/6 |
| `isp_replace/src/isp_replace.vhd` | **207/211** | **95/99** |  |  | **23/27** | **17/18** |
| `isp_window/src/isp_window.vhd` | **156/157** | **102/104** | 3/3 | 6/6 | **19/21** | 17/17 |
| Total | 845/855 (98.8 %) | 454/463 (98.1 %) | 3/3 (100.0 %) | 6/6 (100.0 %) | 89/103 (86.4 %) | 74/75 (98.7 %) |

`isp_filter2d.vhd` (instances of `isp_window` and `isp_conv` and the checks of the generics) and the register packages
(`isp_<module>_regs_pkg.vhd`, constants) have no items to cover. Every remaining miss is listed in section 4: seven
conditions whose first term is a generic, and items that no stimulus can reach (three of them `when others` branches).

QuestaSim extracts the state machine of `isp_window` (states `Pix_s`, `HCol_s`, `VPix_s`): 3 of 3 states and 6 of 6
transitions are covered. It extracts no state machine for `isp_frame_sync` (`State`) and for the map lookup of
`isp_replace` (`LkState`). For these two, the branch of every state and every assignment of a next state are covered.
The hits below count executions of the combinational process, several per clock cycle with the evaluations in delta
cycles: they show that every assignment executes, not how often a transition occurs. A test observes each transition
at the ports.

| State machine | `when` branch of each state (hits) | Assignments of a next state (hits) | Transitions observed at the ports |
| --- | --- | --- | --- |
| `isp_frame_sync`, `State` | `Idle_s` (line 231): 724057; `Image_s` (264): 23437911; `Pad_s` (292): 501645; `when others` (305): 0, section 4 | `Image_s` from `Idle_s` (251): 13959; `Pad_s` from `Image_s` (269): 15855; `Idle_s` from `Image_s` (281): 23823; `Idle_s` from `Pad_s` (299): 1031 | test_images (TC-FSY-01): complete images back to back, from the image start to the last pixel; test_short_images (TC-FSY-02): short images completed with pixels of 0 at their positions, followed by the next image |
| `isp_replace`, `LkState` | `Run_s` (line 501): 8573608; `Start_s` (533): 15177; `when others` (540): 0, section 4 | `Start_s` from `Run_s` (505): 4096; `Run_s` from `Start_s` (537): 3638 | test_rate (TC-RPL-11): pixel (0, 0) waits for word 0 of the map, the measured wait of the image start |

## 3. Gaps found and closed

The run of the complete regression showed register accesses that a stimulus at the ports can make but that no test
made. Each was closed by an extended test; no RTL changed. Each check that a mutant can fail has a new mutant in the
mutation run of its module (verification report of the module, section 4).

| Gap | Resolution |
| --- | --- |
| `isp_conv.vhd:357`: a write of `CTRL` without the strobe of byte 0 | test_registers writes `CTRL` with the strobes 0xE: `HOLD` is unchanged |
| `isp_conv.vhd:365`: an injection without the strobe of byte 1 | test_parity writes `INJECT` with the index 1 in byte 1 and the strobe of byte 0 alone: the index is 0, coefficient 0 loses its parity, and the write of coefficient 0 restores it |
| `isp_conv.vhd:379`: a write above the last coefficient | test_registers writes the address above the last coefficient: no coefficient changes. No mutant of this bound can fail at the ports, because the compare of the address with each coefficient register decides the write; in the read path (line 430) the bound is needed for the index range |
| `isp_conv.vhd:430`: a read between two coefficient registers, at an address that is not a multiple of 4 | test_registers reads the three addresses above a coefficient that is not 0: 0. The AXI4-Lite slave passes the read address unchanged and ignores the address bits 1:0 of a write (user guide, section 4.1): a write at such an address acts on the coefficient at the aligned address, which the test reads back. test_registers of `isp_crop`, `isp_point` and `isp_replace` reads `ID` + 2: 0 |
| `isp_crop.vhd:359`: a write of `INJECT` with bit 0 clear | test_parity writes `INJECT` with 0 after a write of `ROI_POS`: the next image uses the written position |
| `isp_point.vhd:468`: a write of `CTRL` without the strobe of byte 0 | test_registers writes `CTRL` with the strobes 0xE: `HOLD` is unchanged |
| `isp_replace.vhd:707`: a write of `CTRL` with `CLEAR` 0, and a write of `CLEAR` without the strobe of byte 0 | test_clear makes both after a map that marks pixel (1, 0): `STATUS.BUSY` stays low, and the pixel, at the maximum between two neighbours of 0, is replaced by 0 in the next image |

## 4. Remaining misses

### 4.1 Conditions on a generic

A condition whose first term is a generic of the module cannot score the row where that generic is false. In an
instance with the generic false the condition is constant, and QuestaSim removes it: the coverage database of a single
test of such a configuration has no item for the line (for example `isp_point_tb.defaults.test_registers` has none for
lines 417, 420 and 480 of `isp_point.vhd`, `isp_point_tb.runtime.test_registers` has all three). In an instance with
the generic true the term is constant true. Both values of every such generic are simulated.

| Location | Row not covered | Configurations with the generic false |
| --- | --- | --- |
| `isp_conv/src/isp_conv.vhd:331`, `:334` | `RuntimeCoef_g` false | 16 configurations of `isp_conv_tb` (38 tests: `mtf5_const`, `ones4`, `taps_<T>` for T from 1 to 256); both instances in every test of `isp_bin`; 5 configurations of `isp_filter2d_tb` (8 tests); the chain `reordered` |
| `isp_crop/src/isp_crop.vhd:304`, `:359` | `RuntimeRoi_g` false | 6 configurations of `isp_crop_tb` (16 tests: `w8_h6_static`, `w8_h6_static_bp`, `w8_h6_line`, `w8_h6_column`, `w33_h9_rate`, `w1_h65536`); the chain `reordered` |
| `isp_point/src/isp_point.vhd:417`, `:420`, `:480` | `Runtime_g` false | 9 configurations of `isp_point_tb` (27 tests: `shift`, `dark_gain`, `clamp`, `neutral`, `w65536_h1`, `w1_h65536`, `w1_h4`, `generic_bounds`, `defaults`); the chain `reordered` |

### 4.2 Items that cannot be reached

| Location | Item not covered | Justification |
| --- | --- | --- |
| `isp_conv/src/isp_conv.vhd:119`, `:120` | Branch and statement: the coefficient beyond the length of `Coef_g` in the function `genCoefs` | The branch runs only for a `Coef_g` with fewer than `WinX_g` x `WinY_g` values. The check of CNV-CF-01 (the concurrent assertion of line 214) stops a simulation of such a configuration at time 0, after the elaboration has computed the coefficient set with this branch, and the synthesis at the elaboration; no test of the regression can therefore have such a `Coef_g`. The branch lets the elaboration reach the check and its message. TC-CNV-11 (`lint/synth_check.py`) elaborates a `Coef_g` of T - 1 values and stops with the message. |
| `isp_conv/src/isp_conv.vhd:474` | Condition term `K_v >= 0` false | The condition has no source text: QuestaSim reports it at the last line of the file with the bounds of the loop of lines 370 to 374 over the coefficients (T - 1: 8, 24 and 4 in the instances of 9, 25 and 5 coefficients). `K_v` is a `natural` (line 276); the upper term is covered both ways (an `INJECT.INDEX` of T or above in test_parity). |
| `isp_pkg/src/isp_pkg.vhd:130`, `:131` | Branch and statement: `ispWinOut` for the border mode "valid" with n < win | Every call from the design has n >= win: `isp_window` checks `ImageWidth_g >= WinX_g` and `ImageHeight_g >= WinY_g` (lines 249 and 252), `isp_bin` calls `ispBinOut(ImageWidth_g, BinX_g, ...)` (line 90) and checks `ImageWidth_g >= BinX_g` (line 125), the window of `isp_replace` has the width `maximum(ImageWidth_g, WinX_c)` and the height 1. test_dimensions of `isp_pkg_tb` checks the result 0 for n < win in both simulators: 1920 rows of its table have the border mode "valid" and n < win (every win from 2 to 16), and 120 more reach the branch through `ispBinOut`. The calls of the testbench, which is compiled without coverage, are not counted: in the coverage database of test_dimensions alone every line of `isp_pkg.vhd` has 0 hits, also the lines 129 to 135 of `ispWinOut`, although the test calls the function 51456 times. |
| `isp_frame_sync/src/isp_frame_sync.vhd:305` to `:308` | Branch `when others` and its three statements | `State_t` has the values `Idle_s`, `Image_s` and `Pad_s`, each with its own choice (lines 231, 264 and 292). `when others` covers no value of the type: it is the recovery from an upset of the state register ([conventions](conventions.md)). |
| `isp_window/src/isp_window.vhd:464`, `:465` | Branch `when others` and its statement | As in `isp_frame_sync`: `State_t` has the values `Pix_s`, `HCol_s` and `VPix_s`, each with its own choice (lines 400, 422 and 441). |
| `isp_window/src/isp_window.vhd:537` | Branch: none of the border modes in the state `HCol_s` | Both transitions to `HCol_s` (lines 412 and 449) require virtual columns (`VCols_c > 0`), and the border mode "valid" has none (`virtual`, lines 102 to 110). In `HCol_s` the border mode is therefore "zero", "replicate" or "mirror" (check of line 276), and one branch of the three is taken. |
| `isp_window/src/isp_window.vhd:167` | Condition term `ye - Map_v > WinY_g - 1` true | `rowSelect` is called for the lines ye from 0 to H - 1 + V (V virtual lines below the image, `VLines_c` = `WinY_g` - 1 - `AnchorY_g`; `nextRowSel`, lines 182 to 198). With `Map_v >= 0`, ye - `Map_v` is `WinY_g` - 1 - j for a line of the image; ye for the upper border of "replicate", which is less than `WinY_g` - 1 - j; at most V for its lower border; less than ye for the upper border of "mirror"; at most 2V - (`WinY_g` - 1) + j = j for its lower border, since "mirror" requires the centred anchor (line 282). The modes "zero" and "valid" give `Map_v` = -1, which the first term catches. The term is the guard for a line that is not in the line buffers. |
| `isp_window/src/isp_window.vhd:573` | Condition term `m < W_c` false | m runs from 1 to `AnchorX_g`, and `AnchorX_g` <= `WinX_g` - 1 < `ImageWidth_g` (checks of lines 264 and 249). |
| `isp_replace/src/isp_replace.vhd:482`, `:483` | Branch and statement: a map word of a dropped read-ahead (`Discard` > 0) | `Discard` grows only at an image start, by the reads in flight (line 508). `isp_frame_sync` delivers complete images, from pixel (0, 0) to the last pixel. A pixel passes only when its word is in the queue (lines 514 and 525) or when no read is in flight (lines 519 and 527); the reads run in address order up to the last word of the image (line 565) and return in order. When the first pixel of the last word passes, every read has therefore returned, and none starts until the next image start; after a reset no read is in flight either (lines 814 to 818). The branch drops the reads that an image start abandons after an upset of the lookup counters (RPL-FT-02). |
| `isp_replace/src/isp_replace.vhd:512`, `:527` to `:529` | Branches: a pixel within a word without a word in the queue (the fallback of line 527 and the case where none of the three conditions holds), their two statements and the two terms of the condition of line 527 | Both need the state `Run_s`, a pixel that is not the first of its word, and an empty queue. The queue loses a word only when it holds two or more (line 514) and is emptied only by an image start (line 506, followed by `Start_s`) or a reset; `Start_s` returns to `Run_s` only with a word in the queue (line 534). After a reset the first pixel of `isp_frame_sync` is pixel (0, 0), the image start. In `Run_s` the queue therefore holds at least one word for every pixel that is not an image start; the fallback lets the pixels of an image pass after an upset of the queue counter (RPL-FT-02). The same fallback for the first pixel of a word (line 519) has hits: they come from evaluations of the combinational process in delta cycles, in which the registers of the lookup already hold their new values and the outputs of `isp_frame_sync` do not yet. A check of the conditions of lines 482, 512, 519, 527 and 534 at every clock edge over the 89 tests of `isp_replace` and the 21 tests of `isp_chain` found none of them true. |
| `isp_replace/src/isp_replace.vhd:534` | Condition term `Fs_Valid = '1'` false | `Start_s` is entered with a valid pixel (0, 0) that is not taken (line 505, `Fs_Ready` low), and the output register of `isp_frame_sync` holds a pixel until it is taken (`isp_frame_sync.vhd`, lines 219 to 221). `Fs_Valid` is therefore high in every cycle of `Start_s`. |
| `isp_replace/src/isp_replace.vhd:540`, `:541` | Branch `when others` and its statement | `LkState_t` has the values `Run_s` and `Start_s`, each with its own choice (lines 501 and 533). |
| `isp_replace/src/isp_replace.vhd:751`, `:800` | Condition term and expression term `Win_Framing` = '1' | The internal `isp_window` (line 369) receives one beat for every beat that the lookup takes from `isp_frame_sync`, in order and with its end-of-packet and sequence flags, and has the same image size as the internal `isp_frame_sync` (line 305). `isp_frame_sync` delivers only complete images with one packet per line, so the frame sync of the window finds no malformed stream. |

## 5. Reproduction

```shell
python run.py --questa --coverage -p 1
vcover report -byfile -details -zeros -codeAll coverage/coverage.ucdb
```

The second command lists every item that is not covered, per file. A follow-up of changed tests runs them alone
(`python run.py --questa --coverage -p 1 --subset <file>`, one test per line) from the same source tree and merges its
database with that of the complete run:

```shell
vcover merge -suppress 6854 -out merged.ucdb complete.ucdb follow_up.ucdb
```

The tests of the follow-up have the names of their first run; vcover keeps one test record per name (message 6854,
which concerns the test records, not the coverage counts).
