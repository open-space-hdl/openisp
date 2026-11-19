# isp_pkg: Architecture

## 1. Contents

`isp_pkg` is one VHDL package, `hdl/isp_pkg/src/isp_pkg.vhd`, in the library `openisp`. It depends on
`olo_base_pkg_math` of Open Logic (library `olo`).

| Name | Kind | Definition | Requirement |
| --- | --- | --- | --- |
| `SeqCont_c`, `SeqFirst_c`, `SeqLast_c`, `SeqOnly_c` | Constants, `std_logic_vector(1 downto 0)` | "00", "01", "10", "11" | PKG-01 |
| `ispPosWidth` | Function (`positive`) return `positive` | `maximum(log2ceil(n), 1)` | PKG-02 |
| `ispIsImageStart` | Function (`std_logic`, `std_logic_vector(1 downto 0)`) return `boolean` | `first = '1' and (user = SeqFirst_c or user = SeqOnly_c)`, compared with `=` so that a metavalue in any bit gives false | PKG-03 |

The flags "01" and "11" are the two values with bit 0 set. The function still compares both bits, so that a
metavalue in bit 1 cannot start an image.

## 2. Use

| Module | Uses |
| --- | --- |
| `isp_frame_sync` | All |
| Modules with ports of positions or counters | `ispPosWidth` |
| `isp_conv` | `ispIsImageStart` |
