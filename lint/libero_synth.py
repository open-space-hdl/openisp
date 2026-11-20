# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""Preliminary synthesis of OpenISP modules on PolarFire with Libero: resources and the timing estimate of the
synthesis at a target clock frequency.

For every selected configuration of lint/vivado_ooc.py the script writes a top level `isp_synth_top` (the module with
the generics of the configuration), a Libero project for the PolarFire MPF100T and a constraint file with a clock of
the target frequency on `Clk`, and runs the synthesis (Synplify Pro) in Libero. It collects the resources and the
estimated worst slack of the clock from the synthesis report. This is a pre-layout estimate: the timing after place
and route can differ. Only register-to-register paths are constrained; the ports have no input or output delays.

Usage: python lint/libero_synth.py --out DIR [--mhz MHZ] [--die DIE] [--package PKG] [name ...]
  --out      project and result directory (a short path outside the repository)
  --mhz      target clock frequency (default 150)
  --die      device (default MPF100T), --package (default FCG484), speed grade STD
Without names all configurations run, one after the other. Libero comes from LIBERO_PATH (the Designer/bin directory
of the installation) or from the PATH. Results: <out>/<name>/ (project, log, synthesis report) and
<out>/results/summary.md. Exit code 0 when every synthesis completed.
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "lint"))

from vivado_ooc import CONFIGS, declarations, entity_parts, vhdl_value  # noqa: E402


def synth_top(module, values):
    """Top level: the module with the values of the configuration as the defaults of its generics."""
    gen_text, port_text = entity_parts(module)
    generics = []
    for line in declarations(gen_text):
        m = re.match(r"^\s+(\w+_g)\s*:\s*([^;]*?)(\s*:=\s*[^;]*)?;?\s*(--.*)?$", line)
        if not m:
            continue
        name, typ, default = m.group(1), m.group(2).strip(), m.group(3)
        if name in values:
            default = " := " + vhdl_value(values[name])
        elif not default:
            raise SystemExit("generic {} of {} has no default and no value".format(name, module))
        generics.append((name, typ, default.strip()))
    ports = []
    for line in declarations(port_text):
        m = re.match(r"^\s+(\w+)\s*:\s*(in|out)\s+(.*?);?\s*(--.*)?$", line)
        if m:
            ports.append((m.group(1), m.group(2), m.group(3).rstrip(";").strip()))
    decl_g = ";\n".join("        {} : {} {}".format(n, t, d) for n, t, d in generics)
    decl_p = ";\n".join("        {} : {} {}".format(n, d, t) for n, d, t in ports)
    map_g = ",\n".join("            {} => {}".format(n, n) for n, _, _ in generics)
    map_p = ",\n".join("            {} => {}".format(n, n) for n, _, _ in ports)
    return "\n".join([
        "library ieee;",
        "    use ieee.std_logic_1164.all;",
        "    use ieee.numeric_std.all;",
        "library olo;",
        "    use olo.olo_base_pkg_math.all;",
        "    use olo.olo_ft_pkg_ecc.all;",
        "library openisp;",
        "    use openisp.isp_pkg.all;",
        "entity isp_synth_top is",
        "    generic (",
        decl_g,
        "    );",
        "    port (",
        decl_p,
        "    );",
        "end entity;",
        "architecture rtl of isp_synth_top is",
        "begin",
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


# The areas of Open Logic that OpenISP uses (the same as OLO_AREAS of run.py)
OLO_AREAS = ("base", "axi", "ft")


def olo_sources():
    """The Open Logic sources of the areas that OpenISP uses, in compile order."""
    out = []
    for line in (ROOT / "open-logic" / "compile_order.txt").read_text(encoding="utf-8").splitlines():
        rel = line.strip()
        if rel and rel.split("/")[1] in OLO_AREAS:
            out.append(ROOT / "open-logic" / rel)
    return out


def openisp_sources():
    """The synthesis sources of the library openisp in compile order (compile_order.txt)."""
    return [ROOT / ln.strip() for ln in (ROOT / "compile_order.txt").read_text(encoding="utf-8").splitlines()
            if ln.strip() and not ln.startswith("#")]


def project_tcl(name, work, top, period, die, package):
    dev = ("-family {{PolarFire}} -die {{{}}} -package {{{}}} -speed {{STD}} -die_voltage {{1.0}} "
           "-part_range {{IND}}").format(die, package)
    sdc = (work / "isp_synth.sdc").as_posix()
    lines = [
        'new_project -location "{}/prj" -name {{{}}} -hdl {{VHDL}} {} -project_description {{}} -block_mode 1 '
        '-standalone_peripheral_initialization 0 -instantiate_in_smartdesign 1 -ondemand_build_dh 1 '
        '-use_relative_path 0 -linked_files_root_dir_env {{}}'.format(work.as_posix(), name, dev),
    ]
    for src in olo_sources():
        lines.append('create_links -convert_EDN_to_HDL 0 -library {{olo}} -hdl_source "{}"'.format(src.as_posix()))
    for src in openisp_sources():
        lines.append('create_links -convert_EDN_to_HDL 0 -library {{openisp}} -hdl_source "{}"'.format(src.as_posix()))
    lines += [
        'create_links -convert_EDN_to_HDL 0 -library {{work}} -hdl_source "{}"'.format(top.as_posix()),
        "build_design_hierarchy",
        'set_root -module "isp_synth_top::work"',
        'set fh [open "{}" w]'.format(sdc),
        'puts $fh "create_clock -name {{Clk}} -period {} \\[get_ports {{Clk}}\\]"'.format(period),
        "close $fh",
        'create_links -convert_EDN_to_HDL 0 -sdc "{}"'.format(sdc),
        'organize_tool_files -tool {{SYNTHESIZE}} -file "{}" -module {{isp_synth_top::work}} '
        '-input_type {{constraint}}'.format(sdc),
        "run_tool -name {SYNTHESIZE}",
        "save_project",
        "",
    ]
    return "\n".join(lines)


def libero():
    exe = "libero" + (".exe" if os.name == "nt" else "")
    if "LIBERO_PATH" in os.environ:
        return str(Path(os.environ["LIBERO_PATH"]) / exe)
    found = shutil.which(exe)
    if not found:
        raise SystemExit("Libero not found: set LIBERO_PATH to its Designer/bin directory or put it on the PATH")
    return found


def parse_srr(srr):
    """The timing estimate and the resources of a Synplify report: (worst slack ns, estimated MHz of Clk,
    {4LUT, DFF, LSRAM, uSRAM, Math}). LUTs and DFFs include the interface logic of the RAM and Math blocks that place
    and route adds ("after P&R" in the report)."""
    text = srr.read_text(encoding="utf-8", errors="replace")

    def find(pat, default="0"):
        m = re.search(pat, text, re.M)
        return m.group(1) if m else default

    slack = find(r"^Worst slack in design:\s*(-?[0-9.]+)", "?")
    freq = find(r"^Clk\s+[0-9.]+ MHz\s+([0-9.]+) MHz", "?")
    res = {"4LUT": find(r"^Total number of LUTs after P&R:.*=\s*([0-9]+);", "?"),
           "DFF": find(r"^Total number of SLEs after P&R:.*=\s*([0-9]+);", "?"),
           "LSRAM": find(r"Total Block RAMs \(RAM1K20\)\s*:\s*([0-9]+)"),
           "uSRAM": find(r"\(RAM64X12\)\s*:\s*([0-9]+)"),
           "Math": find(r"^DSP Blocks:\s+([0-9]+) of")}
    return slack, freq, res


def run(name, out, mhz, die, package):
    module, values, _ram = CONFIGS[name]
    work = out / name
    if work.exists():
        shutil.rmtree(work)
    work.mkdir(parents=True)
    top = work / "isp_synth_top.vhd"
    top.write_text(synth_top(module, values), encoding="utf-8")
    script = work / "synthesize.tcl"
    script.write_text(project_tcl(name, work, top, "{:.3f}".format(1000.0 / mhz), die, package), encoding="utf-8")
    print("{}: synthesis for {} {} at {} MHz in {}".format(name, die, package, mhz, work), flush=True)
    log = work / "libero.log"
    with open(log, "w", encoding="utf-8") as f:
        rc = subprocess.run([libero(), "SCRIPT:" + script.as_posix(), "LOGFILE:" + log.with_suffix(".txt").as_posix()],
                            cwd=work, stdin=subprocess.DEVNULL, stdout=f, stderr=subprocess.STDOUT).returncode
    srr = sorted(work.glob("prj/synthesis/*.srr"))
    ok = rc == 0 and bool(srr)
    print("{}: {}".format(name, "completed" if ok else "FAILED (see {})".format(log)), flush=True)
    return ok, (parse_srr(srr[0]) if srr else None)


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--out", required=True)
    p.add_argument("--mhz", type=float, default=150.0)
    p.add_argument("--die", default="MPF100T")
    p.add_argument("--package", default="FCG484")
    p.add_argument("names", nargs="*")
    a = p.parse_args()
    names = a.names or list(CONFIGS)
    unknown = [n for n in names if n not in CONFIGS]
    if unknown:
        raise SystemExit("unknown configurations: " + ", ".join(unknown))
    out = Path(a.out)
    (out / "results").mkdir(parents=True, exist_ok=True)
    rows, oks = [], []
    for n in names:
        ok, parsed = run(n, out, a.mhz, a.die, a.package)
        oks.append(ok)
        if parsed:
            slack, freq, res = parsed
            rows.append("| {} | {} | {} | {} | {} | {} | {} | {} |".format(
                n, slack, freq, res["4LUT"], res["DFF"], res["LSRAM"], res["uSRAM"], res["Math"]))
        else:
            rows.append("| {} | no result | | | | | | |".format(n))
    lines = ["# OpenISP preliminary synthesis on PolarFire {} {} at {} MHz (Libero, Synplify Pro)".format(
        a.die, a.package, a.mhz), "",
        "Pre-layout estimate of the synthesis; the timing after place and route can differ.", "",
        "| Configuration | Worst slack (ns) | Estimated frequency (MHz) | 4LUT | DFF | LSRAM | uSRAM | Math |",
        "| --- | --- | --- | --- | --- | --- | --- | --- |"] + rows
    (out / "results" / "summary.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("\n".join(lines))
    sys.exit(0 if all(oks) else 1)


if __name__ == "__main__":
    main()
