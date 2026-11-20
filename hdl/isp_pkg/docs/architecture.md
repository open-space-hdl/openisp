# isp_pkg: Architecture

## 1. Contents

`isp_pkg` is one VHDL package, `hdl/isp_pkg/src/isp_pkg.vhd`, in the library `openisp`. It depends on
`olo_base_pkg_math` of Open Logic (library `olo`).

| Name | Kind | Definition | Requirement |
| --- | --- | --- | --- |
| `SeqCont_c`, `SeqFirst_c`, `SeqLast_c`, `SeqOnly_c` | Constants, `std_logic_vector(1 downto 0)` | "00", "01", "10", "11" | PKG-01 |
| `ispPosWidth` | Function (`positive`) return `positive` | `maximum(log2ceil(n), 1)` | PKG-02 |
| `ispIsImageStart` | Function (`std_logic`, `std_logic_vector(1 downto 0)`) return `boolean` | `first = '1' and (user = SeqFirst_c or user = SeqOnly_c)`, compared with `=` so that a metavalue in any bit gives false | PKG-03 |
| `ispConvFullBits`, `ispConvOutBits` | Functions (`positive` pixel bits, coefficient bits, taps; `natural` output bits) return `positive` | p + c - 1 + `log2ceil`(t); the output width is the full precision for 0 and the given width otherwise | PKG-05 |
| `ispWinOut` | Function (`positive` n, window, stride; `string` border mode) return `natural` | "valid": 0 for n < window, (n - window) / stride + 1 otherwise; the other modes (n + stride - 1) / stride | PKG-06 |
| `ispBinOut` | Function (`positive` n, factor; `string` border mode) return `natural` | `ispWinOut(n, factor, factor, border)` | PKG-07 |
| `ispWriteParity` | Function (two `std_logic_vector(31 downto 0)` words, the old and the written one; `std_logic` parity bit; `std_logic_vector(3 downto 0)` byte strobes; `natural` bits) return `std_logic` | One loop over the four bytes: per byte that holds bits (8 x b < bits), the parity of its written and of its stored bits; all such bytes written: the parity of the written bits (0 for 0 bits); some written: the parity bit xor the parities of the written bytes and of the bytes they replace; none written: the parity bit | PKG-08 |

The flags "01" and "11" are the two values with bit 0 set. The function still compares both bits, so that a
metavalue in bit 1 cannot start an image.

`ispWriteParity` keeps the syndrome of a partial write, the parity bit xor the parity of the stored bits: a register
with a mismatch (an upset, or `INJECT`) keeps it until every byte with bits is written, and a register without one keeps
its match. Its loop unrolls into XOR trees of at most 8 bits per byte and a selection of three values by the strobes;
the modules call it once per register with the constant width of the register.

## 2. Use

| Module | Uses |
| --- | --- |
| `isp_frame_sync` | All |
| Modules with ports of positions or counters | `ispPosWidth` |
| `isp_conv` | `ispIsImageStart`, `ispConvFullBits`, `ispConvOutBits`, `ispWriteParity` |
| `isp_filter2d` | `ispConvOutBits` |
| `isp_window` | `ispWinOut` |
| `isp_bin` | `ispBinOut` |
| `isp_point`, `isp_crop` | `ispWriteParity` |
