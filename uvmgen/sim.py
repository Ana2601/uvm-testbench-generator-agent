"""Compile and run generated testbenches; turn the logs into structured feedback."""
from __future__ import annotations

import re
from pathlib import Path

from .rtl import run

ROOT = Path(__file__).resolve().parent.parent
UVM_SRC = Path(__import__("os").environ.get("UVM_HOME", ROOT / "third_party" / "uvm-core" / "src"))


def parse(log: str, plan: dict) -> dict:
    cov = {m.group(1): int(m.group(2)) for m in re.finditer(r"^COVER (\S+) (\d+)", log, re.M)}
    m = re.search(r"CHECKS (\d+) ERRORS (\d+)", log)
    mism = re.findall(r"^.*MISMATCH.*$", log, re.M)
    names = [c["name"] for c in plan["coverage"]]
    hit = [n for n in names if cov.get(n, 0) > 0]
    return {
        "status": "PASS" if re.search(r"^\s*(UVM_INFO.*)?PASS\b", log, re.M) and m and m.group(2) == "0" else "FAIL",
        "checks": int(m.group(1)) if m else 0,
        "errors": int(m.group(2)) if m else None,
        "first_mismatches": [x.strip() for x in mism[:12]],
        "coverage": {n: cov.get(n, 0) for n in names},
        "coverage_pct": round(100 * len(hit) / len(names), 1) if names else 100.0,
        "holes": [n for n in names if cov.get(n, 0) == 0],
    }


def icarus(tb: Path, rtl: Path, work: Path, plan: dict, timeout: int = 300) -> dict:
    work.mkdir(parents=True, exist_ok=True)
    exe = work / "simv.vvp"
    rc, log = run(["iverilog", "-g2012", "-o", str(exe), "-s", "tb", str(tb), str(rtl)], work, 120)
    if rc:
        errs = [l for l in log.splitlines() if "error" in l.lower() or "sorry" in l.lower()]
        return {"status": "COMPILE_ERROR", "log": "\n".join(errs[:25]) or log[-2500:]}
    rc, log = run(["vvp", "-n", str(exe)], work, timeout)
    if rc == 124:
        return {"status": "TIMEOUT", "log": log[-1500:]}
    res = parse(log, plan)
    res["sim"] = "icarus"
    return res


def verilator_uvm(files: list[Path], rtl: Path, work: Path, plan: dict, timeout: int = 1800) -> dict:
    """Build and run the UVM testbench on Verilator (UVM 2020 / IEEE 1800.2, no DPI)."""
    work.mkdir(parents=True, exist_ok=True)
    if not (UVM_SRC / "uvm_pkg.sv").exists():
        return {"status": "SKIPPED", "log": f"UVM library not found at {UVM_SRC} (make uvm-lib)"}
    obj = work / "obj_uvm"
    cmd = ["verilator", "--binary", "--timing", "-j", "8", "--Mdir", str(obj), "-o", "simv",
           "--timescale", "1ns/1ps", "+define+UVM_NO_DPI", f"+incdir+{UVM_SRC}", f"+incdir+{files[0].parent}",
           "--top-module", "tb_top", "-MAKEFLAGS", "OPT_FAST=-O0 OPT_SLOW=-O0 OPT_GLOBAL=-O0",
           str(UVM_SRC / "uvm_pkg.sv"), *map(str, files), str(rtl)]
    rc, log = run(cmd, work, timeout)
    if rc:
        errs = [l for l in log.splitlines() if l.startswith("%Error")]
        return {"status": "COMPILE_ERROR", "log": "\n".join(errs[:25]) or log[-2500:]}
    rc, log = run([str(obj / "simv")], work, timeout)
    (work / "uvm_run.log").write_text(log)
    res = parse(log, plan)
    fatal = re.search(r"UVM_(ERROR|FATAL)\s*:\s*(\d+)", log)
    res["uvm_report"] = {k: int(v) for k, v in re.findall(r"^(UVM_\w+)\s*:\s*(\d+)\s*$", log, re.M)}
    if fatal and int(fatal.group(2)) > 0 and res["status"] == "PASS":
        res["status"] = "FAIL"
    res["sim"] = "verilator-uvm"
    return res
