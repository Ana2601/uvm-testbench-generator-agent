"""Run a verification plan against a design and score the testbench it produces."""
from __future__ import annotations

import json
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from . import emit_icarus, emit_uvm, lec, mutate, sim
from .plan import validate
from .rtl import interface


def run_plan(plan: dict, design_dir: Path, work: Path, rtl: Path | None = None) -> dict:
    """Emit the Icarus testbench and run it on the design. Returns structured feedback."""
    rtl = rtl or design_dir / "rtl" / f"{design_dir.name}.sv"
    try:
        ports = interface(rtl, plan.get("dut", design_dir.name), plan.get("params"))
    except (RuntimeError, KeyError) as e:
        return {"status": "PLAN_ERROR", "problems": [f"cannot elaborate DUT with these params: {e}"]}
    problems = validate(plan, ports)
    if problems:
        return {"status": "PLAN_ERROR", "problems": problems}
    work.mkdir(parents=True, exist_ok=True)
    tb = work / "tb.sv"
    tb.write_text(emit_icarus.emit(plan, ports))
    res = sim.icarus(tb, rtl, work, plan)
    res["tb"] = str(tb)
    return res


def mutation_score(plan: dict, design_dir: Path, work: Path, workers: int = 6) -> dict:
    rtl = design_dir / "rtl" / f"{design_dir.name}.sv"
    top = plan["dut"]
    ports = interface(rtl, top, plan.get("params"))
    work.mkdir(parents=True, exist_ok=True)
    tb = work / "tb.sv"
    tb.write_text(emit_icarus.emit(plan, ports))
    ms = mutate.mutants(rtl.read_text())

    def one(m):
        d = work / "mutants" / f"m{m.id:02d}"
        src = mutate.write(m, d, top)
        r = sim.icarus(tb, src, d, plan, timeout=120)
        st = r["status"]
        kind = ("stillborn" if st == "COMPILE_ERROR" else "killed" if st != "PASS" else "survived")
        return m, kind, src, d

    with ThreadPoolExecutor(workers) as ex:
        rows = list(ex.map(one, ms))

    # classify survivors: provably equivalent mutants can never be killed
    # (checked at reduced parameter widths when lec.json says so: arithmetic stays tractable)
    cfg = lec.config(design_dir)
    params = {**plan.get("params", {}), **cfg.get("params", {})}
    out = []
    for m, kind, src, d in rows:
        row = {"id": m.id, "line": m.line, "op": m.label, "after": m.after}
        if kind == "survived":
            eq = lec.equivalent(rtl, src, top, params, plan["clock"], plan["reset"]["port"],
                                plan["reset"]["active"], cfg.get("compare", {}), d / "lec")
            kind = "equivalent" if eq == "EQUIVALENT" else "survived"
            row["lec"] = eq.lower()
        row["result"] = kind
        out.append(row)
    k = sum(r["result"] == "killed" for r in out)
    s = sum(r["result"] == "survived" for r in out)
    return {
        "mutants": len(out), "killed": k, "survived": s,
        "equivalent": sum(r["result"] == "equivalent" for r in out),
        "stillborn": sum(r["result"] == "stillborn" for r in out),
        "score_pct": round(100 * k / (k + s), 1) if k + s else 100.0,
        "survivors": [r for r in out if r["result"] == "survived"],
        "detail": out,
    }


def write_uvm(plan: dict, design_dir: Path, out: Path) -> list[Path]:
    rtl = design_dir / "rtl" / f"{design_dir.name}.sv"
    ports = interface(rtl, plan["dut"], plan.get("params"))
    out.mkdir(parents=True, exist_ok=True)
    files = emit_uvm.emit(plan, ports)
    for n, t in files.items():
        (out / n).write_text(t)
    return [out / n for n in emit_uvm.file_order(plan["dut"])]


def run_uvm(plan: dict, design_dir: Path, out: Path) -> dict:
    files = write_uvm(plan, design_dir, out / "uvm")
    return sim.verilator_uvm(files, design_dir / "rtl" / f"{design_dir.name}.sv", out / "uvm_build", plan)


def dumps(x) -> str:
    return json.dumps(x, indent=1)
