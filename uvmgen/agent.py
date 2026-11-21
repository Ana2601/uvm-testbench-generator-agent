"""The testbench-generation loop.

    RTL + spec ──> model writes a verification plan (reference model, stimulus, coverage)
                          │ run_plan
                          v
       emit Icarus TB ─> compile ─> simulate on the DUT ─> mismatches / coverage holes
                          │ (if it passes)
                          v
       mutation analysis: inject one bug at a time, re-run; survivors = blind spots
                          │
                          v
       model: fix its plan, close holes, or report_dut_bug when the DUT breaks the spec
                          │ finish
                          v
       final: UVM testbench from the same plan (+ optional run on Verilator)

The spec is the source of truth. When the reference model and the DUT disagree,
the model must decide - from the spec - which one is wrong. It may never bend the
reference model to match the DUT.
"""
from __future__ import annotations

import json
import time
from dataclasses import dataclass, field
from pathlib import Path

from . import evaluate
from .prompts import system_prompt, task_prompt
from .rtl import interface

TOOLS = [
    {
        "name": "run_plan",
        "description": (
            "Generate the testbench from a verification plan and run it on the DUT with Icarus "
            "Verilog. Returns PLAN_ERROR (schema problems), COMPILE_ERROR (your SystemVerilog), "
            "FAIL (first mismatches between the reference model and the DUT, with inputs), or "
            "PASS. Always returns coverage per point. On PASS it also runs mutation analysis and "
            "lists the injected bugs your testbench did NOT catch."),
        "input_schema": {
            "type": "object",
            "properties": {
                "plan_json": {"type": "string", "description": "The complete plan as a JSON document."},
                "note": {"type": "string", "description": "What changed since the previous plan, and why."},
            },
            "required": ["plan_json", "note"],
            "additionalProperties": False,
        },
        "strict": True,
    },
    {
        "name": "report_dut_bug",
        "description": (
            "Report that the DUT violates its specification. Use only when a mismatch persists "
            "after you have checked that your reference model follows the spec exactly. Keep "
            "the reference model faithful to the spec afterwards."),
        "input_schema": {
            "type": "object",
            "properties": {
                "title": {"type": "string"},
                "spec_clause": {"type": "string", "description": "The sentence of the spec that is violated."},
                "evidence": {"type": "string", "description": "Cycle, inputs, expected vs observed."},
            },
            "required": ["title", "spec_clause", "evidence"],
            "additionalProperties": False,
        },
        "strict": True,
    },
    {
        "name": "finish",
        "description": "Stop: the testbench is final. Summarise what it verifies and any known gaps.",
        "input_schema": {
            "type": "object",
            "properties": {"summary": {"type": "string"}},
            "required": ["summary"],
            "additionalProperties": False,
        },
        "strict": True,
    },
]


@dataclass
class Generator:
    design: Path
    backend: object
    out: Path
    max_runs: int = 8
    run_uvm: bool = False
    log: callable = print
    runs: list = field(default_factory=list)
    bugs: list = field(default_factory=list)

    def run(self) -> dict:
        name = self.design.name
        rtl = self.design / "rtl" / f"{name}.sv"
        ports = interface(rtl, name)
        system = system_prompt()
        messages: list = [{"role": "user", "content": task_prompt(self.design, ports)}]
        self.best = None                       # last plan that compiled and ran
        summary = None
        turns = 0
        while len(self.runs) < self.max_runs and turns < self.max_runs * 3:
            turns += 1
            turn = self.backend.step(system, messages, TOOLS)
            messages.append({"role": "assistant", "content": turn.raw_content if turn.raw_content is not None
                             else _blocks(turn)})
            if turn.text:
                self.log(f"[{name}] model: {turn.text.strip()[:500]}")
            if not turn.tool_calls:
                break
            results = []
            for c in turn.tool_calls:
                out, done = self._dispatch(c)
                results.append({"type": "tool_result", "tool_use_id": c["id"], "content": json.dumps(out, indent=1)})
                if done:
                    summary = c["input"].get("summary", "")
            messages.append({"role": "user", "content": results})
            if summary is not None:
                break
        return self._finalise(summary)

    # ------------------------------------------------------------------ #
    def _dispatch(self, c: dict) -> tuple[dict, bool]:
        name, inp = c["name"], c["input"]
        if name == "finish":
            return {"ok": True}, True
        if name == "report_dut_bug":
            self.bugs.append({k: inp.get(k, "") for k in ("title", "spec_clause", "evidence")})
            self.log(f"[{self.design.name}] DUT BUG REPORTED: {inp.get('title')}")
            return {"recorded": True, "bugs_reported": len(self.bugs)}, False
        if name != "run_plan":
            return {"error": f"unknown tool {name}"}, False
        if len(self.runs) >= self.max_runs:
            return {"error": "run budget exhausted; call finish"}, False
        n = len(self.runs) + 1
        try:
            plan = json.loads(inp["plan_json"])
        except json.JSONDecodeError as e:
            return {"status": "PLAN_ERROR", "problems": [f"plan_json is not valid JSON: {e}"]}, False
        t0 = time.time()
        work = self.out / "work" / f"run{n:02d}"
        res = evaluate.run_plan(plan, self.design, work)
        if res["status"] == "PASS":
            mut = evaluate.mutation_score(plan, self.design, work)
            res["mutation"] = {k: v for k, v in mut.items() if k != "detail"}
            res["mutation"]["survivors"] = mut["survivors"][:12]
        if res["status"] in ("PASS", "FAIL"):
            self.best = {"plan": plan, "result": res, "run": n}
        rec = {"run": n, "note": inp.get("note", ""), "status": res["status"],
               "checks": res.get("checks"), "errors": res.get("errors"),
               "coverage_pct": res.get("coverage_pct"),
               "mutation_pct": res.get("mutation", {}).get("score_pct"),
               "seconds": round(time.time() - t0, 1)}
        self.runs.append(rec)
        self.log(f"[{self.design.name}] run {n}: {res['status']:13s} checks={rec['checks']} errors={rec['errors']} "
                 f"coverage={rec['coverage_pct']}% mutation={rec['mutation_pct']}%  ({rec['seconds']}s)")
        res.pop("tb", None)
        res["runs_left"] = self.max_runs - n
        return res, False

    def _finalise(self, summary: str | None) -> dict:
        name = self.design.name
        rep = {"design": name, "runs": self.runs, "bugs": self.bugs, "summary": summary}
        if self.best:
            plan, res = self.best["plan"], self.best["result"]
            self.out.mkdir(parents=True, exist_ok=True)
            (self.out / "plan.json").write_text(json.dumps(plan, indent=2) + "\n")
            (self.out / "tb_icarus.sv").write_text(Path(self.out / "work" / f"run{self.best['run']:02d}" / "tb.sv").read_text())
            evaluate.write_uvm(plan, self.design, self.out / "uvm")
            rep["final"] = {"run": self.best["run"], "status": res["status"], "checks": res.get("checks"),
                            "coverage_pct": res.get("coverage_pct"), "holes": res.get("holes"),
                            "mutation": res.get("mutation")}
            if self.run_uvm:
                self.log(f"[{name}] building and running the UVM testbench on Verilator ...")
                u = evaluate.run_uvm(plan, self.design, self.out)
                rep["final"]["uvm"] = {k: u.get(k) for k in ("status", "checks", "errors", "coverage_pct",
                                                              "uvm_report", "log")}
                self.log(f"[{name}] UVM on Verilator: {u.get('status')} checks={u.get('checks')} "
                         f"coverage={u.get('coverage_pct')}%")
        (self.out / "report.json").write_text(json.dumps(rep, indent=2) + "\n")
        return rep


def _blocks(turn) -> list:
    b = [{"type": "text", "text": turn.text}] if turn.text else []
    return b + [{"type": "tool_use", "id": c["id"], "name": c["name"], "input": c["input"]} for c in turn.tool_calls]
