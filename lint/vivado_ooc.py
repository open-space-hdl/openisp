# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""Out-of-context implementation of OpenISP modules in Vivado: resources and timing at a target clock frequency.

For every selected configuration the script writes a top level `isp_ooc_top` (the module with the generics of the
configuration and its clock through a global clock buffer) and runs lint/vivado_ooc.tcl in Vivado: out-of-context
synthesis, placement and routing with a clock of the target frequency, then the timing summary, the utilization, the
20 worst setup paths and the logic level distribution. Only register-to-register paths are timed; the ports of the
module have no input or output delays.

Configurations (short names, also the names of the result files): see CONFIGS.

Usage: python lint/vivado_ooc.py [--out DIR] [--temp DIR] [--mhz MHZ] [--part PART] [--elaborate] [name ...]
  --out        project and result directory (default: the environment variable ISP_OOC_OUT; one of the two is
               required). Give a short path: Vivado projects need short paths on Windows
  --temp       directory of the temporary files of Vivado (default <out>/tmp)
  --mhz        target clock frequency (default 150)
  --part       device (default xcvc1902-vsva2197-2MP-e-S, the Versal AI Core device of the reference systems)
  --elaborate  RTL elaboration only; no synthesis or implementation
Without names all configurations run. The Vivado tools come from VIVADO_PATH (the Vivado installation) or from the
PATH. Results: <out>/results/<name>_timing.rpt, _util.rpt, _paths.rpt, _levels.rpt and <out>/results/summary.md.
Exit code 0 when every run completed; the timing result itself is in the summary.
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PART = "xcvc1902-vsva2197-2MP-e-S"

# name: (module, generics, the configuration contains olo_base_ram_sdp); the default configuration of every module,
# and its widest one where it differs
CONFIGS = {
    "fsy_max": ("isp_frame_sync", {"ImageWidth_g": 65536, "ImageHeight_g": 65536, "PixelBits_g": 64}, False),
}


def entity_parts(module):
    """Generic and port declarations of the entity of a module, as text."""
    src = ROOT / "hdl" / module / "src" / (module + ".vhd")
    text = src.read_text(encoding="utf-8")
    ent = re.search(r"^entity {} is\n(.*?)^end entity;".format(module), text, re.S | re.M)
    if not ent:
        raise SystemExit("entity {} not found in {}".format(module, src))
    body = ent.group(1)
    gen = re.search(r"^    generic \(\n(.*?)^    \);\n", body, re.S | re.M)
    port = re.search(r"^    port \(\n(.*?)^    \);\n", body, re.S | re.M)
    return (gen.group(1) if gen else ""), port.group(1)


def ooc_top(module, values):
    """Top level: the generics of the module with the values of the configuration as defaults, its ports with the
    clock input ClkIn through a global clock buffer."""
    gen_text, port_text = entity_parts(module)
    generics = []
    for line in gen_text.splitlines():
        m = re.match(r"^\s+(\w+_g)\s*:\s*([^;]*?)(\s*:=\s*[^;]*)?;?\s*(--.*)?$", line)
        if not m:
            continue
        name, typ, default = m.group(1), m.group(2).strip(), m.group(3)
        if name in values:
            default = " := " + str(values[name]).lower() if isinstance(values[name], bool) else \
                " := " + str(values[name])
        elif not default:
            raise SystemExit("generic {} of {} has no default and no value".format(name, module))
        generics.append((name, typ, default.strip()))
    ports = []
    for line in port_text.splitlines():
        m = re.match(r"^\s+(\w+)\s*:\s*(in|out)\s+(.*?);?\s*(--.*)?$", line)
        if m:
            ports.append((m.group(1), m.group(2), m.group(3).rstrip(";").strip()))
    if [p[0] for p in ports].count("Clk") != 1:
        raise SystemExit("module without exactly one clock port Clk")
    decl_g = ";\n".join("        {} : {} {}".format(n, t, d) for n, t, d in generics)
    decl_p = ";\n".join("        {} : {} {}".format("ClkIn" if n == "Clk" else n, d, t) for n, d, t in ports)
    map_g = ",\n".join("            {} => {}".format(n, n) for n, _, _ in generics)
    map_p = ",\n".join("            {} => {}".format(n, n) for n, _, _ in ports)
    return "\n".join([
        "library ieee;",
        "    use ieee.std_logic_1164.all;",
        "    use ieee.numeric_std.all;",
        "library unisim;",
        "    use unisim.vcomponents.all;",
        "library olo;",
        "    use olo.olo_base_pkg_math.all;",
        "    use olo.olo_ft_pkg_ecc.all;",
        "library openisp;",
        "    use openisp.isp_pkg.all;",
        "entity isp_ooc_top is",
        "    generic (",
        decl_g,
        "    );",
        "    port (",
        decl_p,
        "    );",
        "end entity;",
        "architecture rtl of isp_ooc_top is",
        "    signal Clk : std_logic;",
        "begin",
        "    i_clk_buf : BUFG",
        "        port map (",
        "            I => ClkIn,",
        "            O => Clk",
        "        );",
        "    i_dut : entity openisp.{}".format(module),
        "        generic map (",
        map_g,
        "        )",
        "        port map (",
        map_p,
        "        );",
        "end architecture;",
        "",
    ])


def vivado():
    exe = "vivado" + (".bat" if os.name == "nt" else "")
    if "VIVADO_PATH" in os.environ:
        return str(Path(os.environ["VIVADO_PATH"]) / "bin" / exe)
    found = shutil.which(exe)
    if not found:
        raise SystemExit("Vivado not found: set VIVADO_PATH to the Vivado installation or put its bin on the PATH")
    return found


def run(name, out, temp, mhz, part, elaborate):
    module, values, ram = CONFIGS[name]
    work = out / name
    work.mkdir(parents=True, exist_ok=True)
    top = work / "isp_ooc_top.vhd"
    top.write_text(ooc_top(module, values), encoding="utf-8")
    period = "{:.3f}".format(1000.0 / mhz)
    # Positional arguments: the batch wrapper of vivado splits arguments at "="
    args = [vivado(), "-mode", "batch", "-nojournal", "-log", str(work / "vivado.log"),
            "-source", str(ROOT / "lint" / "vivado_ooc.tcl"), "-tclargs",
            name, top.as_posix(), work.as_posix(), (out / "results").as_posix(), period, part,
            "elaborate" if elaborate else "implement", ROOT.as_posix(), "ram" if ram else "noram"]
    print("{}: {} at {} MHz in {}".format(name, "elaboration" if elaborate else "implementation", mhz, work),
          flush=True)
    env = dict(os.environ, TEMP=str(temp), TMP=str(temp), TMPDIR=str(temp))
    rc = subprocess.run(args, cwd=work, env=env, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL).returncode
    print("{}: {}".format(name, "completed" if rc == 0 else "FAILED (see " + str(work / "vivado.log") + ")"),
          flush=True)
    return rc == 0


def summary(out, names, mhz):
    """Collects the result lines of the runs into results/summary.md."""
    res = out / "results"
    lines = ["# OpenISP out-of-context implementation at {} MHz".format(mhz), "",
             "| Configuration | WNS (ns) | TNS (ns) | Failing endpoints | WHS (ns) | THS (ns) | LUT | FF | RAMB36 "
             "| RAMB18 | URAM | DSP |",
             "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |"]
    for n in names:
        f = res / "{}_summary.txt".format(n)
        lines.append(f.read_text(encoding="utf-8").strip() if f.exists() else
                     "| {} | no result | | | | | | | | | | |".format(n))
    (res / "summary.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("\n".join(lines))


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--out", default=os.environ.get("ISP_OOC_OUT"))
    p.add_argument("--temp")
    p.add_argument("--mhz", type=float, default=150.0)
    p.add_argument("--part", default=PART)
    p.add_argument("--elaborate", action="store_true")
    p.add_argument("names", nargs="*")
    a = p.parse_args()
    if not a.out:
        p.error("no output directory: give --out DIR or set ISP_OOC_OUT (a short path)")
    names = a.names or list(CONFIGS)
    unknown = [n for n in names if n not in CONFIGS]
    if unknown:
        raise SystemExit("unknown configurations: " + ", ".join(unknown) + " (known: " + ", ".join(CONFIGS) + ")")
    out = Path(a.out)
    (out / "results").mkdir(parents=True, exist_ok=True)
    temp = Path(a.temp) if a.temp else out / "tmp"
    temp.mkdir(parents=True, exist_ok=True)
    results = [run(n, out, temp, a.mhz, a.part, a.elaborate) for n in names]
    if not a.elaborate:
        summary(out, names, a.mhz)
    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
