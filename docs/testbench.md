# OpenISP Testbench Components

The testbenches of all modules share a reference model, a stimulus generator, a pixel stream source and a pixel
stream sink. This page describes them; the verification plan of every module names the parts it uses and the checks
it adds.

## 1. Flow

1. `run.py` loads the configuration of every module (`hdl/<module>/tb/vunit_config.py`). For every test and
   configuration it generates the input images and their division into packets (`tools/isp_tbgen.py`), computes the
   expected output with the reference model (`tools/isp_model.py`) and writes two files to
   `vunit_out/vectors/<module>/<configuration>/`: `<test>.stim` (stimulus) and `<test>.exp` (expected output). Their
   paths are generics of the testbench.
2. The source reads the stimulus and drives the input of the module; the sink takes the output and compares it with
   the expected file.
3. The testbench of the module adds the checks of its status outputs, its timing and its registers, and ends the test
   with `ispTestEnd`, which fails on any unexpected alert and on any expected alert that did not occur.

Every random choice (images, packet lengths, gaps, stalls) comes from a seed per module, configuration and test, so
that a failing test repeats exactly.

## 2. Reference model

`tools/isp_model.py` holds one function per module. Each takes the input beats (pixel, `Last`, sequence flags) or
the input images and the generics, and returns the output beats with their sideband and the expected events. The
functions are written from the specifications and share no code or table with the RTL; where a specification leaves
a choice to the architecture (for example the order of the operations of an interpolation), the model follows the
specification and the RTL has to match it.

Test images are random over the full pixel range, or depend on every bit of the pixel position, so that an
addressing fault changes the output.

## 3. Files

Text files, one entry per line, numbers in hexadecimal for data and sidebands and in decimal otherwise.

| Entry | File | Meaning |
| --- | --- | --- |
| `B <data> <last> <user> [<side>]` | both | One beat: data, `Last` (0, 1), sequence flags (0 to 3, bit 1 = `User(1)`); in the expected file the sideband that the sink compares |
| `G <n>` | stimulus | n cycles without a beat (a pause of the source) |
| `W <n>` | stimulus | Wait until the sink has received n beats in total |
| `T <n>` | stimulus | Wait n cycles |
| `P <value>` | stimulus | Check the probe input of the source (a status output of the module) against the value |
| `H <0, 1>` | stimulus | Hold the sink (`Out_Ready` low) or release it |
| `M <n>` | stimulus | Set the marker output of the source to n (phases of a timing test, register accesses) |
| `K <n>` | stimulus | Wait until the register script has acknowledged marker n (section 7) |
| `R <n> <mode> <cycles>` | stimulus | Wait until the sink has compared n beats, then request a reset of the module for the given number of cycles (1 or more). Mode 0 (held): the sink has held `Out_Ready` low since beat n. Mode 1 (running): the sink keeps taking beats with its random stalls, so the reset falls while beats transfer |
| `R <mode>` | expected | Mode 0: after the beats before it, the sink holds `Out_Ready` low until the reset. Mode 1: the sink takes the beats that arrive until the reset without comparing them (their number depends on the timing). In both modes the comparison and the contract checker start again after the reset |

A reset entry is placed where the result does not depend on the timing: the n beats are produced by the input sent
before it, all input before it can enter the module while the sink takes at most n beats, and no error event lies
among the beats that the reset may still find in the module.

## 4. Source (`tb/isp_tb_source.vhd`)

| Generic | Meaning |
| --- | --- |
| `Width_g` | Width of `M_Data` (a pixel, or a window for a kernel) |
| `StimFile_g` | Path of the stimulus file |
| `GapPct_g` | Probability in percent of a pause of 1 to 4 cycles before a beat |
| `Seed_g` | Seed of the pauses |
| `ProbeWidth_g` | Width of the probe input |

| Port | Direction | Meaning |
| --- | --- | --- |
| `Clk` | in | Clock of the module |
| `M_Valid`, `M_Ready`, `M_Data`, `M_Last`, `M_User` | out, in | Pixel stream to the module; `M_Data`, `M_Last` and `M_User` are `'X'` while `M_Valid` is low, so that a module that samples them without a beat puts metavalues into its state |
| `SinkCount` | in | Beats compared by the sink (for `W` and `R`) |
| `Probe` | in | Status output of the module checked by `P` |
| `RstReq` | out | Reset request (`R`), high for the cycles of the entry |
| `Hold` | out | Hold of the sink (`H`) |
| `Marker` | out | Marker (`M`) |
| `Ack` | in | Last marker whose register accesses are done (`K`) |
| `Done` | out | The stimulus file is at its end |

The source reads the next entry only after the beat before has been transferred. A `P` entry that does not match
raises an error alert.

## 5. Sink (`tb/isp_tb_sink.vhd`)

| Generic | Meaning |
| --- | --- |
| `Width_g`, `SideWidth_g` | Widths of `S_Data` and of the compared sideband |
| `ExpFile_g` | Path of the expected file |
| `StallPct_g`, `Seed_g` | Probability in percent of a stall of 1 to 4 cycles before a beat; its seed |
| `OutWidth_g`, `OutHeight_g` | Dimensions of the output image, for the contract checker |
| `Contract_g` | The contract checker is active (false only for a stream that is not a pixel stream by design) |

| Port | Direction | Meaning |
| --- | --- | --- |
| `Clk`, `Rst` | in | Clock and reset of the module (`Rst` ends an `R` entry) |
| `S_Valid`, `S_Ready`, `S_Data`, `S_Last`, `S_User`, `S_Side` | in, out | Output of the module |
| `Hold` | in | Holds `S_Ready` low |
| `Count` | out | Beats compared (beats taken during a running reset are not counted) |
| `Done` | out | Every expected beat has been received |

Checks:

- Every beat equals the next `B` entry in data, `Last`, flags and sideband; a beat after the last entry is an error.
  The first difference raises an error alert with the beat number, the expected and the received values.
- The contract checker verifies the output contract of the pixel stream, independent of the expected file: `Last` on
  every `OutWidth_g`-th beat of an image and on no other; the flags constant within a packet; the first packet of an
  image with "01" ("11" when `OutHeight_g` is 1), the following with "00" and the last with "10"; exactly
  `OutHeight_g` packets per image, after which the next packet starts an image. A reset (`R` entry) restarts it.

## 6. Testbench of a module

Every testbench instantiates the module, one source, one sink and a clock. It adds:

- a counter of the cycles in which each error or status pulse is high, compared at the end of the test with the
  count of the model (generics of the test); every pulse output is active in at least one test, and the counts of two
  outputs that a wiring mistake could exchange differ in at least one test;
- probes of `Stat_ImageOpen` (`P` entries): the malformed input streams of `tools/isp_tbgen.py` begin with an image
  cut after half of its pixels and a probe while it is open (`open_image_probe`, from a random generator of its
  own), so that the port is checked at 1 as well as at 0;
- a monitor that checks the control outputs of the module for metavalues in every cycle after the first reset;
- the timing checks of its verification plan, by the markers of the source;
- for modules with registers, the register script (section 7).

The test ends when the source is done, the sink has received every expected beat and a drain time has passed without
an extra beat. The drain time is a tolerance derived from the design:

| Term | Cycles | Reason |
| --- | --- | --- |
| Latency of the module | L | From the last input beat to the last output beat; the verification plan of the module states it (2 for `isp_frame_sync`) |
| Longest stall of the sink | 4 | The sink stalls at most 4 cycles before a beat |
| Output register | 1 | A beat that the module loads in the last cycle of the stall |
| Margin | 16 | Covers a module that is wrong by more than a few cycles; an extra beat later than that would come from input the source never sent |

The drain time is L + 21 cycles; a beat in it after the last expected beat is an error.

A watchdog (`test_runner_watchdog` of VUnit) ends a test that does not end, for example because the module stops
delivering beats: its time is 1 ms plus 0.5 µs per entry of the stimulus and the expected file (`watchdog_us` of
`tools/isp_tbgen.py`), more than ten times what an entry takes with gaps, stalls and pauses.

## 7. Register script

A module with registers gets a third file per test, `<test>.regs`, with its register accesses. The procedure
`ispRegsRun` of `tb/isp_tb_axilite_pkg.vhd` executes it in the main process of the testbench with the AXI4-Lite BFM
of UVVM (`bitvis_vip_axilite`), one access after the other, so that no access overtakes another.

| Entry | Meaning |
| --- | --- |
| `<m> W <address> <data> [<strobes>]` | When the source sets marker m: write the data (hexadecimal) with the byte strobes (hexadecimal, default all) |
| `<m> C <address> <data>` | When the source sets marker m: read and compare with the data (hexadecimal); a difference is an error alert |

The accesses of one marker run in the order of the file; when they are done, the procedure sets the acknowledge to m.
The source waits for it with `K m` before its next beat, so a register access falls between two known beats of the
stream. The markers of the register script start at 100, so that they do not collide with the markers of a timing
test. A test that needs an access at a cycle the script cannot express (for example a clear that coincides with an
event) drives the BFM itself.

## 8. Injection script

A module with ECC-protected memories gets an injection script per test, `<test>.inj`. The entity
`tb/isp_tb_inject.vhd` executes it beside the source and drives the error injection ports of the module and, where
the module has a scrubber, its enable.

| Entry | Meaning |
| --- | --- |
| `<m> J <pattern>` | When the source sets marker m: `ErrInj_BitFlip` = pattern (hexadecimal) with `ErrInj_Valid` for one cycle; the pattern applies to the next write of the memory |
| `<m> S <0 or 1>` | When the source sets marker m: `Scrub_Enable` = 0 or 1 |

When the entries of a marker are done, the entity sets its acknowledge to m, and the source waits for it with `K m`,
as for the register script. A testbench with a register script and an injection script gives the source the larger
of the two acknowledges; the markers of both scripts are distinct and increase through the test, so `K m` waits for
the script that owns marker m. The source pauses before an injection until every pixel it sent has passed the memory
(`T` with the drain time of the module), so the next write of the memory is the one the model expects.

## 9. Timing file

A rate test gets a timing file, `<test>.tim`, from the model: one line per output beat with the index of the input
beat that completes it (counted from 0 over the accepted beats of the test), or -1 for a beat that the module
completes without a new input pixel (the right and the lower border). The testbench records the cycle of every
accepted input beat and checks, for every output beat with an index, the cycles from the acceptance of that input
beat to the output against the design values of the verification plan.
