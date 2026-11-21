"""The verification plan: the single artefact the model writes.

Both testbenches (Icarus self-checking SV and UVM) are generated from it, so the
reference model, the stimulus and the coverage model are written once.

Schema (all SystemVerilog snippets must use the subset in skills/.../SKILL.md):

{
  "dut": "sync_fifo",
  "params": {"W": 8, "DEPTH": 8},                  # DUT parameter overrides
  "clock": "clk", "period_ns": 10,
  "reset": {"port": "rst_n", "active": 0, "cycles": 3},
  "defaults": {"wr_valid": "0", ...},              # value of each input when a sequence does not drive it
  "model": {
     "decls":   "logic [7:0] m_mem [8]; int m_count;",   # model state, names start with m_
     "reset":   "m_count = 0; ...",                       # reset the model state
     "outputs": "exp_count = m_count; chk_rd_data = (m_count != 0); ...",
     "step":    "if (wr_valid && exp_wr_ready) ... "      # state update at the rising edge
  },
  "seq_vars": "logic [3:0] s_addr; bit s_wr;",     # variables sequences may use, names start with s_
  "sequences": [
     {"name": "random_traffic", "cycles": 2000,
      "pre": "if (i % 2 == 0) s_addr = 4'($urandom_range(0, 3) * 4);",   # optional, runs each cycle
      "drive": {"wr_valid": "1'($urandom_range(0, 1))", ...},           # SV expression per input
      "reset_when": "i == 700"}                                          # optional
  ],
  "coverage": [{"name": "full", "expr": "count == 8"}, ...]   # sampled every checked cycle
}

Inside model and coverage code: input ports by name, DUT outputs by name (coverage only),
exp_<out> / chk_<out> for each output, model state m_*, and `i` in sequences.
"""
from __future__ import annotations

import re

REQUIRED = ["dut", "clock", "reset", "model", "sequences", "coverage"]


class PlanError(ValueError):
    pass


def validate(plan: dict, ports: dict) -> list[str]:
    """Structural checks; returns a list of problems (empty = OK)."""
    errs = []
    for k in REQUIRED:
        if k not in plan:
            errs.append(f"missing key '{k}'")
    if errs:
        return errs
    ins = {n for n, (d, _) in ports.items() if d == "input"}
    if plan["clock"] not in ins:
        errs.append(f"clock '{plan['clock']}' is not an input port")
    r = plan["reset"]
    if r.get("port") not in ins:
        errs.append(f"reset port '{r.get('port')}' is not an input port")
    for k in ("decls", "reset", "outputs", "step"):
        if not isinstance(plan["model"].get(k), str):
            errs.append(f"model.{k} must be a string of SystemVerilog")
    driven = ins - {plan["clock"], r.get("port")}
    for n in plan.get("defaults", {}):
        if n not in driven:
            errs.append(f"defaults: '{n}' is not a drivable input")
    names = set()
    for s in plan["sequences"]:
        if not re.fullmatch(r"[a-z][a-z0-9_]*", s.get("name", "")):
            errs.append(f"sequence name {s.get('name')!r} must be lower_snake_case")
        if s.get("name") in names:
            errs.append(f"duplicate sequence {s['name']}")
        names.add(s.get("name"))
        if not isinstance(s.get("cycles"), int) or not 1 <= s["cycles"] <= 200000:
            errs.append(f"sequence {s.get('name')}: cycles must be 1..200000")
        for n in s.get("drive", {}):
            if n not in driven:
                errs.append(f"sequence {s.get('name')}: '{n}' is not a drivable input")
    cn = set()
    for c in plan["coverage"]:
        if not re.fullmatch(r"[a-z][a-z0-9_]*", c.get("name", "")) or c["name"] in cn:
            errs.append(f"coverage name {c.get('name')!r} must be unique lower_snake_case")
        cn.add(c.get("name"))
        if not c.get("expr"):
            errs.append(f"coverage {c.get('name')}: empty expr")
    # names that exist only inside the generated Icarus testbench would not compile in UVM
    portable = [plan["model"].get(k, "") for k in ("decls", "reset", "outputs", "step")] + \
               [c.get("expr", "") for c in plan["coverage"]] + \
               [s.get("pre", "") for s in plan["sequences"]] + \
               [e for s in plan["sequences"] for e in s.get("drive", {}).values()]
    for code in portable:
        hit = re.search(r"\b(cyc|checks|errors|cur_seq|cov_hits)\b", code)
        if hit:
            errs.append(f"'{hit.group(1)}' is internal to the generated testbench; use model state (m_*) instead")
            break
    for code in [plan["model"].get(k, "") for k in ("decls", "reset", "outputs", "step")] + [plan.get("seq_vars", "")]:
        for bad in ("$display", "$finish", "fork", "#"):
            if bad in code:
                errs.append(f"model/sequence code must not contain '{bad}'")
                break
    return errs


def driven_inputs(plan: dict, ports: dict) -> list[str]:
    return [n for n, (d, _) in ports.items()
            if d == "input" and n not in (plan["clock"], plan["reset"]["port"])]


def outputs(ports: dict) -> list[str]:
    return [n for n, (d, _) in ports.items() if d == "output"]
