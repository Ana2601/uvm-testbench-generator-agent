"""Fail if a replay no longer reproduces the headline results."""
import json
import sys
from pathlib import Path

R = Path(__file__).resolve().parent.parent / "results"
ok = True
for d in ("sync_fifo", "uart_tx", "apb_regs", "seq_mult"):
    rep = json.loads((R / d / "report.json").read_text())
    f = rep["final"]
    good = f["status"] == "PASS" and f["coverage_pct"] == 100.0 and f["mutation"]["survived"] == 0
    uvm = f.get("uvm")
    if uvm:
        good &= uvm["status"] == "PASS"
    ok &= good
    print(f"{d:14s} {f['status']} coverage {f['coverage_pct']} % mutants {f['mutation']['killed']}/"
          f"{f['mutation']['killed'] + f['mutation']['survived']}"
          + (f" UVM {uvm['status']}" if uvm else "") + ("  ok" if good else "  FAIL"))
bug = json.loads((R / "uart_tx_buggy" / "report.json").read_text())
seen = bug["final"]["status"] == "FAIL" and len(bug["bugs"]) == 1
ok &= seen
print(f"{'uart_tx_buggy':14s} seeded bug detected and reported: {seen}")
sys.exit(0 if ok else 1)
