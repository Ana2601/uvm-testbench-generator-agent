"""python -m unittest -v tests/test_uvmgen.py"""
from __future__ import annotations

import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from uvmgen import emit_uvm, evaluate                     # noqa: E402
from uvmgen.llm import ClaudeBackend                      # noqa: E402
from uvmgen.plan import validate                          # noqa: E402
from uvmgen.rtl import interface                          # noqa: E402

D = ROOT / "designs"
TR = ROOT / "trajectories"


def plan(d: str, v: str) -> dict:
    return json.loads((TR / d / f"plan_{v}.json").read_text())


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)


class PlanValidation(Base):
    def test_rejects_unknown_port_and_tb_internal_names(self):
        p = plan("sync_fifo", "v2")
        ports = interface(D / "sync_fifo/rtl/sync_fifo.sv", "sync_fifo", p["params"])
        self.assertEqual(validate(p, ports), [])
        bad = json.loads(json.dumps(p))
        bad["sequences"][0]["drive"]["no_such_port"] = "1'b1"
        bad["coverage"].append({"name": "late", "expr": "cyc > 100"})
        errs = validate(bad, ports)
        self.assertTrue(any("no_such_port" in e for e in errs), errs)
        self.assertTrue(any("'cyc'" in e for e in errs), errs)


class Simulation(Base):
    def test_model_bug_fails_and_fix_passes(self):
        r1 = evaluate.run_plan(plan("sync_fifo", "v1"), D / "sync_fifo", self.tmp / "v1")
        r2 = evaluate.run_plan(plan("sync_fifo", "v2"), D / "sync_fifo", self.tmp / "v2")
        self.assertEqual(r1["status"], "FAIL")
        self.assertIn("port=count", " ".join(r1["first_mismatches"]))
        self.assertEqual(r2["status"], "PASS")
        self.assertEqual(r2["coverage_pct"], 100.0)

    def test_seeded_dut_bug_is_caught(self):
        good = evaluate.run_plan(plan("uart_tx", "v2"), D / "uart_tx", self.tmp / "good")
        bad = evaluate.run_plan(plan("uart_tx_buggy", "v1"), D / "uart_tx_buggy", self.tmp / "bad")
        self.assertEqual(good["status"], "PASS")
        self.assertEqual(bad["status"], "FAIL")
        self.assertIn("port=tx_ready", bad["first_mismatches"][0])


class Mutation(Base):
    def test_directed_reset_sequence_kills_the_v1_survivor(self):
        m1 = evaluate.mutation_score(plan("uart_tx", "v1"), D / "uart_tx", self.tmp / "v1")
        m2 = evaluate.mutation_score(plan("uart_tx", "v2"), D / "uart_tx", self.tmp / "v2")
        self.assertEqual([s["after"] for s in m1["survivors"]], ["txd     <= 1'b0;"])
        self.assertEqual(m2["survived"], 0)
        self.assertGreater(m2["killed"], 15)
        self.assertGreater(m2["equivalent"], 0)        # proven by SymbiYosys, not guessed


class UvmEmission(Base):
    def test_uvm_files_contain_the_architecture(self):
        p = plan("apb_regs", "v2")
        files = emit_uvm.emit(p, interface(D / "apb_regs/rtl/apb_regs.sv", "apb_regs"))
        pkg = files["apb_regs_tb_pkg.sv"]
        for cls in ("apb_regs_item extends uvm_sequence_item", "apb_regs_driver extends uvm_driver",
                    "apb_regs_monitor extends uvm_monitor", "apb_regs_scoreboard extends uvm_scoreboard",
                    "apb_regs_env extends uvm_env", "apb_regs_test extends uvm_test",
                    "apb_regs_reset_then_read_all_seq extends uvm_sequence"):
            self.assertIn(cls, pkg)
        self.assertIn(p["model"]["step"].splitlines()[0].strip(), pkg)   # the plan's model, verbatim
        self.assertIn('run_test("apb_regs_test")', files["tb_top.sv"])


class ClaudeRequestShape(unittest.TestCase):
    def test_request_and_parse(self):
        seen = {}

        def create(**kw):
            seen.update(kw)
            return SimpleNamespace(stop_reason="tool_use", stop_details=None, content=[
                SimpleNamespace(type="tool_use", id="t1", name="run_plan", input={"plan_json": "{}", "note": "x"})])

        b = ClaudeBackend.__new__(ClaudeBackend)
        b.client = SimpleNamespace(beta=SimpleNamespace(messages=SimpleNamespace(create=create)))
        b.effort, b.rec = "high", None
        turn = b.step("s", [{"role": "user", "content": "u"}], [])
        self.assertEqual(seen["model"], "claude-opus-5-5")
        self.assertEqual(seen["fallbacks"], "default")
        self.assertEqual(turn.tool_calls[0]["name"], "run_plan")


if __name__ == "__main__":
    unittest.main(verbosity=2)
