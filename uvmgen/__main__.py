"""python -m uvmgen [--design sync_fifo ...] [--backend replay|claude] [--uvm]"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from .agent import Generator
from .llm import ClaudeBackend, ReplayBackend

ROOT = Path(__file__).resolve().parent.parent


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="LLM agent that writes UVM / SV testbenches from RTL + spec")
    ap.add_argument("--design", nargs="+", default=None)
    ap.add_argument("--backend", choices=["replay", "claude"], default="replay")
    ap.add_argument("--max-runs", type=int, default=8)
    ap.add_argument("--uvm", action="store_true", help="also build and run the UVM testbench on Verilator")
    ap.add_argument("--out", type=Path, default=ROOT / "results")
    a = ap.parse_args(argv)
    names = a.design or sorted(p.name for p in (ROOT / "trajectories").iterdir() if (p / "trajectory.json").exists())
    reps = []
    for n in names:
        design = ROOT / "designs" / n
        out = a.out / n
        backend = (ClaudeBackend(record_dir=out / "trajectory") if a.backend == "claude"
                   else ReplayBackend(ROOT / "trajectories" / n))
        rep = Generator(design, backend, out, max_runs=a.max_runs, run_uvm=a.uvm).run()
        rep["name"] = n
        reps.append(rep)
    summary(a.out, reps)
    return 0


def summary(out: Path, reps: list[dict]) -> None:
    rows = ["| Design | Runs | Final status | Checks | Coverage | Mutants killed | Equivalent / stillborn | UVM on Verilator | DUT bugs reported |",
            "|---|---:|---|---:|---:|---:|---|---|---|"]
    for r in reps:
        f = r.get("final") or {}
        m = f.get("mutation") or {}
        u = f.get("uvm") or {}
        rows.append(
            f"| `{r['name']}` | {len(r['runs'])} | {f.get('status', '-')} | {f.get('checks', '-')} | "
            f"{f.get('coverage_pct', '-')} % | "
            + (f"**{m['killed']}/{m['killed'] + m['survived']} ({m['score_pct']} %)** | {m['equivalent']} / {m['stillborn']} | "
               if m else "- | - | ")
            + (f"{u.get('status')} ({u.get('checks')} checks, {u.get('coverage_pct')} % cov) | " if u else "not run | ")
            + f"{len(r['bugs'])} |")
    det = []
    for r in reps:
        det.append(f"\n### {r['name']}\n\n| Run | Status | Errors | Coverage | Mutation score | Change |\n|---:|---|---:|---:|---:|---|")
        for x in r["runs"]:
            det.append(f"| {x['run']} | {x['status']} | {x['errors'] if x['errors'] is not None else '-'} | "
                       f"{x['coverage_pct'] if x['coverage_pct'] is not None else '-'} | "
                       f"{str(x['mutation_pct']) + ' %' if x['mutation_pct'] is not None else '-'} | "
                       f"{x['note'].replace('|', chr(92) + '|')[:200]} |")
        for b in r["bugs"]:
            det.append(f"\n**DUT bug reported:** {b['title']}\n\n- spec: {b['spec_clause']}\n- evidence: {b['evidence']}")
        if r.get("summary"):
            det.append(f"\nAgent summary: {r['summary']}")
    out.mkdir(parents=True, exist_ok=True)
    (out / "summary.md").write_text("\n".join(rows) + "\n" + "\n".join(det) + "\n")
    print((out / "summary.md").read_text())


if __name__ == "__main__":
    sys.exit(main())
