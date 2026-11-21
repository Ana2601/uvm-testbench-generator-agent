"""Formal equivalence of a mutant against the original (SymbiYosys + ABC pdr).

Used only to classify surviving mutants: a survivor that is provably
equivalent on every compared output could never be killed, so it is removed
from the score's denominator. Power-up register values are free, reset is held
in cycle 0, outputs are compared from cycle 1. designs/<d>/lec.json may give
spec-level don't-cares: {"compare": {"rd_data": "gold_rd_valid"}} compares
rd_data only while the condition holds; the condition is an expression over the
inputs and the ORIGINAL design's outputs (gold_<name>).
"""
from __future__ import annotations

import json
import re
from pathlib import Path

from .rtl import interface, run


def _wrapper(p: dict, top: str, clk: str, rst: str, act: int, compare: dict) -> str:
    ins = [n for n, (d, _) in p.items() if d == "input"]
    outs = [n for n, (d, _) in p.items() if d == "output"]
    w = lambda n: f"[{p[n][1]-1}:0] " if p[n][1] > 1 else ""
    L = ["module lec_top(" + ", ".join(f"input wire {w(n)}{n}" for n in ins) + ");"]
    for side in ("gold", "gate"):
        for n in outs:
            L.append(f"  wire {w(n)}{side}_{n};")
        conns = [f".{n}({n})" for n in ins] + [f".{n}({side}_{n})" for n in outs]
        L.append(f"  lec_{side} u_{side}({', '.join(conns)});")
    L += ["  reg f_init = 1'b1;", f"  always @(posedge {clk}) f_init <= 1'b0;",
          f"  always @* if (f_init) assume ({rst} == 1'b{act});", "  always @* begin"]
    for n in outs:
        q = compare.get(n)
        L.append(f"    if (!f_init{' && (' + q + ')' if q else ''}) assert (gold_{n} == gate_{n});")
    L += ["  end", "endmodule"]
    return "\n".join(L) + "\n"


def equivalent(gold: Path, gate: Path, top: str, params: dict, clk: str, rst: str, act: int,
               compare: dict, work: Path, timeout: int = 90) -> str:
    """'EQUIVALENT' (proven), 'DIFFERENT' (counterexample) or 'UNKNOWN' (time-out)."""
    work.mkdir(parents=True, exist_ok=True)
    p = interface(gold, top, params)
    (work / "lec_top.sv").write_text(_wrapper(p, top, clk, rst, act, compare))
    chp = "".join(f" -chparam {k} {v}" for k, v in params.items())
    (work / "lec.sby").write_text(f"""[options]
mode prove
timeout {timeout}

[engines]
abc pdr

[script]
read_verilog -sv gold.sv
hierarchy -top {top}{chp}
proc
flatten
rename {top} lec_gold
design -stash gold
read_verilog -sv gate.sv
hierarchy -top {top}{chp}
proc
flatten
rename {top} lec_gate
design -stash gate
design -copy-from gold -as lec_gold lec_gold
design -copy-from gate -as lec_gate lec_gate
read_verilog -formal lec_top.sv
prep -top lec_top

[files]
gold.sv {gold}
gate.sv {gate}
lec_top.sv {work / 'lec_top.sv'}
""")
    rc, log = run(["sby", "-f", "lec.sby"], work, timeout + 60)
    if "DONE (PASS" in log:
        return "EQUIVALENT"
    if "DONE (FAIL" in log or re.search(r"returned FAIL", log):
        return "DIFFERENT"
    return "UNKNOWN"


def config(design_dir: Path) -> dict:
    """designs/<d>/lec.json: {"compare": {...don't-cares...}, "params": {...reduced widths...}}"""
    f = design_dir / "lec.json"
    return json.loads(f.read_text()) if f.exists() else {}
