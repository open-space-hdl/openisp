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
| `M <n>` | stimulus | Set the marker output of the source to n (phases of a timing test) |
| `R <n>` | both | Stimulus: wait until the sink has received n beats, then request a reset of the module for two cycles. Expected file: the sink holds `Out_Ready` low until the reset, then continues; its contract checker starts again |

A reset entry is placed where the result does not depend on the timing: the n beats are produced by the input sent
before it, and no error event lies among the beats that the reset may still find in the module.

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
| `M_Valid`, `M_Ready`, `M_Data`, `M_Last`, `M_User` | out, in | Pixel stream to the module; `M_Data` is `'X'` while `M_Valid` is low |
| `SinkCount` | in | Beats received by the sink (for `W` and `R`) |
| `Probe` | in | Status output of the module checked by `P` |
| `RstReq` | out | Reset request (`R`) |
| `Hold` | out | Hold of the sink (`H`) |
| `Marker` | out | Marker (`M`) |
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
| `Count` | out | Beats received |
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
  count of the model (generics of the test);
- a monitor that checks the control outputs of the module for metavalues in every cycle after the first reset;
- the timing checks of its verification plan, by the markers of the source;
- for modules with registers, the AXI4-Lite master of UVVM (`bitvis_vip_axilite`).

The test ends when the source is done, the sink has received every expected beat and a drain time has passed without
an extra beat.
