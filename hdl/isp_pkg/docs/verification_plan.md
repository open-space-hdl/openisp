# isp_pkg: Verification Plan

## 1. Overview

The testbench `isp_pkg_tb` evaluates the constants and functions of the package and compares them with values that
the testbench computes in another way: the widths by counting the bits of n - 1 in a loop, the image start from a
table of the eight combinations of `first` and `user` written out in the testbench, and the metavalues from a list
of every `std_logic` value. GHDL (regression) and QuestaSim (coverage at the release); VUnit with UVVM, test end
`ispTestEnd`.

## 2. Test cases

| Test | Description | Requirements |
| --- | --- | --- |
| `test_package` (TC-PKG-01) | The four flag constants against their literals; `ispPosWidth(n)` for every n from 1 to 65536 against the number of bits of n - 1 (at least 1); `ispIsImageStart` for the eight combinations of `first` and `user` and for every metavalue in `first` and in each bit of `user`; `ispConvFullBits` and `ispConvOutBits` for every pixel width 1 to 32, coefficient width 2 to 18 and number of taps 1 to 256 against p + c - 1 + log2ceil(t), with the output widths 0, 1 and 64 | PKG-01, PKG-02, PKG-03, PKG-05 |
| TC-PKG-02 (`lint/synth_check.py`) | The package is synthesised by GHDL as part of every module of TC-FSY-09 | PKG-04 |

## 3. Requirement coverage

| Requirement | Test cases | Method |
| --- | --- | --- |
| PKG-01, PKG-02, PKG-03, PKG-05 | TC-PKG-01 | Test |
| PKG-04 | TC-PKG-02 | Synthesis and review (library, use of `olo_base_pkg_math`) |
