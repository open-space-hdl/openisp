# isp_chain: Specification

## 1. Overview

`isp_chain` is the integration test of OpenISP (phase G): chains of modules, connected as the user guide describes
(section 5), simulated end to end, so that every connection between two modules is crossed by a test. It adds no
module to the suite. The chains are built in the testbench and in a synthesis wrapper from the modules as they are;
every generic of a module behind another one follows from the generics of the one before.

The chain test closes the core requirement ISP-STR-06 (the output of every module is a legal input), whose
verification level in the matrix of the architecture is "Chain", and verifies the claims of the user guide on chains:
the waiting times of section 2.4 and their combination, the run-time parameters of section 4.2 across several
modules, and the steps of section 5.

### 1.1 Chains

| Chain | Modules in the order of the stream | Purpose |
| --- | --- | --- |
| `typical` | `isp_replace` -> `isp_point` -> `isp_crop` -> `isp_filter2d` -> `isp_bin` -> `isp_point` | The chain of the architecture (section 2): replacement, dark level and gain, region, MTF filter, binning, scaling |
| `reordered` | `isp_bin` -> `isp_filter2d` -> `isp_crop` -> `isp_point` | Another order: the binning before the filter, the border modes zero and mirror, line buffers on block RAM |
| `small` | The modules of `typical` at the low bounds of their generics | 1-bit pixels, an image as large as the window and as the bin, `EccPipeline_g` 0, shift registers |

## 2. Requirements

The requirements of the chain test restate core requirements and claims of the user guide at chain level; they add no
behaviour to a module.

| ID | Requirement | Core requirement |
| --- | --- | --- |
| CHN-FN-01 | Every chain shall output, for every input stream, the composition of the outputs of its modules: the output of each module is the input of the next. | ISP-STR-06, ISP-GEN-02 |
| CHN-FN-02 | The stream between two modules of a chain shall meet the requirements on an input stream (sequence flags, one packet per line, the dimensions of the next module) for every input stream of the chain, also malformed ones and after a reset of a module of the chain. | ISP-STR-06, ISP-STR-08 |
| CHN-FN-03 | Only the first module of a chain shall report `Err_Framing` for a malformed input stream; the modules behind it receive complete images. A module behind a module that was reset alone shall report the image cut by that reset as its frame sync specifies and output complete images. | ISP-STR-06, ISP-STR-08 |
| CHN-FN-04 | The generics of every module of a chain behind the first shall follow from the generics of the module before with the functions of `isp_pkg` (user guide 5.1). | ISP-STR-03, ISP-GEN-02 |
| CHN-IF-01 | The registers of every module of a chain shall be accessible through its own AXI4-Lite slave; the procedure of the user guide (4.2, 5) shall give one image the new parameter sets of every module. | ISP-CFG-03 |
| CHN-IF-02 | The ECC status pulses of the modules of a chain, collected in an `olo_ft_ecc_monitor` (user guide 5.4), shall be counted there as the modules report them. | ISP-FT-01, ISP-FT-02 |
| CHN-PF-01 | With `In_Valid` and `Out_Ready` high, a chain shall accept one pixel per clock cycle within an image, apart from the waits of its modules that reach its input; the image period and the latency shall be those that the derivations of the modules give for the chain (verification plan, section 5). | ISP-STR-09 |
| CHN-PF-02 | An `olo_ft_fifo_sync` in front of a chain with the depth that the rule of the user guide (5.3) gives for the chain and the blanking of the source shall never overflow. | ISP-STR-09 |
| CHN-CF-01 | The chains `typical` and `reordered` shall be synthesizable with GHDL as one netlist, without latches. | ISP-GEN-01 |

## 3. Configuration

The generics of the chains are fixed in the testbench and in the synthesis wrapper (verification plan, section 2).
