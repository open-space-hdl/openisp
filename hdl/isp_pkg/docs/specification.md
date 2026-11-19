# isp_pkg: Specification

## 1. Overview

`isp_pkg` holds the definitions that several OpenISP modules share: the sequence flags of the pixel stream, the width
of a pixel position and the detection of an image start. Modules add their own shared definitions (for example the
output dimensions of a window generator) to it when they need them; each addition is specified here.

## 2. Requirements

### 2.1 Function

| ID | Requirement | Core requirement |
| --- | --- | --- |
| PKG-01 | The package shall define the four sequence flags of the pixel stream as constants of 2 bits: `SeqCont_c` "00" (continuation packet), `SeqFirst_c` "01" (first packet), `SeqLast_c` "10" (last packet), `SeqOnly_c` "11" (only packet of an image). | ISP-STR-02 |
| PKG-02 | The function `ispPosWidth(n)` shall return the number of bits of an unsigned number from 0 to n - 1, at least 1: max(log2ceil(n), 1), for n from 1 to 65536. | ISP-STR-03 |
| PKG-03 | The function `ispIsImageStart(first, user)` shall return true when `first` is '1' (the first beat of a stream packet) and the flags `user` are "01" or "11", and false otherwise, also for metavalues. | ISP-STR-04 |

### 2.2 Implementation

| ID | Requirement | Core requirement |
| --- | --- | --- |
| PKG-04 | The package shall be VHDL-2008 that GHDL synthesises as part of the modules, compiled into the library `openisp`, and use `olo_base_pkg_math` of Open Logic for `log2ceil`. | ISP-GEN-01 |

## 3. Interpretation

- A metavalue in `first` or `user` gives false in `ispIsImageStart`, so that a module never starts an image on an
  undefined beat.
