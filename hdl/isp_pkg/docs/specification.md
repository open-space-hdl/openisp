# isp_pkg: Specification

## 1. Overview

`isp_pkg` holds the definitions that several OpenISP modules share: the sequence flags of the pixel stream, the width
of a pixel position, the detection of an image start, the output width of a linear kernel and the output dimensions
of a window filter and of a bin. The modules compute these values with the functions of the package, and an
integrator who builds a chain computes the generics of the next module with the same functions (user guide, section
5), so that both use one definition. Modules add their own shared definitions to it when they need them; each
addition is specified here.

## 2. Requirements

### 2.1 Function

| ID | Requirement | Core requirement |
| --- | --- | --- |
| PKG-01 | The package shall define the four sequence flags of the pixel stream as constants of 2 bits: `SeqCont_c` "00" (continuation packet), `SeqFirst_c` "01" (first packet), `SeqLast_c` "10" (last packet), `SeqOnly_c` "11" (only packet of an image). | ISP-STR-02 |
| PKG-02 | The function `ispPosWidth(n)` shall return the number of bits of an unsigned number from 0 to n - 1, at least 1: max(log2ceil(n), 1), for n from 1 to 65536. | ISP-STR-03 |
| PKG-03 | The function `ispIsImageStart(first, user)` shall return true when `first` is '1' (the first beat of a stream packet) and the flags `user` are "01" or "11", and false otherwise, also for metavalues. | ISP-STR-04 |
| PKG-05 | The function `ispConvFullBits(p, c, t)` shall return the full precision of a linear kernel, p + c - 1 + log2ceil(t), and `ispConvOutBits(p, c, t, o)` the output width: the full precision for o = 0, o otherwise; for p from 1 to 32, c from 2 to 18 and t from 1 to 256. | ISP-FLT-02 |
| PKG-06 | The function `ispWinOut(n, win, stride, border)` shall return the number of reference pixels of a window generator along an axis of n pixels with the window size win and the stride stride (specification of `isp_window`, section 1.1): (n - win) / stride + 1 rounded down for the border mode "valid" and n >= win, 0 for "valid" and n < win, and ceil(n / stride) for the other border modes; for n from 1 to 65536, win and stride from 1 to 16. | ISP-STR-03, ISP-FLT-04 |
| PKG-07 | The function `ispBinOut(n, factor, border)` shall return the number of bins of factor pixels along an axis of n pixels (specification of `isp_bin`, section 1.1): floor(n / factor) for the border mode "valid", ceil(n / factor) for "zero" and "replicate"; it is `ispWinOut(n, factor, factor, border)`. | ISP-STR-03, ISP-BIN-02 |

### 2.2 Implementation

| ID | Requirement | Core requirement |
| --- | --- | --- |
| PKG-04 | The package shall be VHDL-2008 that GHDL synthesises as part of the modules, compiled into the library `openisp`, and use `olo_base_pkg_math` of Open Logic for `log2ceil`. | ISP-GEN-01 |

## 3. Interpretation

- A metavalue in `first` or `user` gives false in `ispIsImageStart`, so that a module never starts an image on an
  undefined beat.
