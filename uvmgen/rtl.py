"""Read the DUT's interface from the RTL itself (Yosys elaboration), so the
generated testbench never relies on the model's reading of the port list."""
from __future__ import annotations

import json
import os
import signal
import subprocess
import tempfile
from pathlib import Path


def run(cmd: list[str], cwd: Path, timeout: int = 600) -> tuple[int, str]:
    """Run a tool; on timeout kill the whole process group."""
    p = subprocess.Popen(cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                         text=True, start_new_session=True)
    try:
        out, _ = p.communicate(timeout=timeout)
        return p.returncode, out
    except subprocess.TimeoutExpired:
        os.killpg(p.pid, signal.SIGKILL)
        out, _ = p.communicate()
        return 124, (out or "") + f"\nTIMEOUT after {timeout}s"


def interface(rtl: Path, top: str, params: dict | None = None) -> dict:
    """{port: (direction, width)} in declaration order, plus '__params__'."""
    with tempfile.TemporaryDirectory() as td:
        out = Path(td) / "p.json"
        chp = "".join(f" -chparam {k} {v}" for k, v in (params or {}).items())
        rc, log = run(["yosys", "-q", "-p",
                       f"read_verilog -sv {rtl}; hierarchy -top {top}{chp}; proc; write_json {out}"], Path(td))
        if rc:
            raise RuntimeError(log[-3000:])
        mod = json.loads(out.read_text())["modules"][top]
    ports = {n: (p["direction"], len(p["bits"])) for n, p in mod["ports"].items()}
    return ports


def describe(ports: dict) -> str:
    return "\n".join(f"  {d:6s} [{w:>2}] {n}" for n, (d, w) in ports.items())
