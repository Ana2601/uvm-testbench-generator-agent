"""Model backends: live Claude (Anthropic Messages API, tool use) or replay of a
recorded trajectory. Replay supplies the model's proposals (plans, bug reports)
only; every simulation, coverage figure and mutation score is recomputed."""
from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path

MODEL = "claude-opus-5-5"


@dataclass
class Turn:
    text: str
    tool_calls: list[dict]          # [{"id", "name", "input"}]
    raw_content: object = None


class ClaudeBackend:
    def __init__(self, record_dir: Path | None = None, effort: str = "high"):
        import anthropic
        self.client = anthropic.Anthropic()   # ANTHROPIC_API_KEY or an `ant auth login` profile
        self.effort = effort
        self.rec = TrajectoryWriter(record_dir) if record_dir else None

    def step(self, system: str, messages: list, tools: list[dict]) -> Turn:
        resp = self.client.beta.messages.create(
            model=MODEL,
            max_tokens=32000,
            system=system,
            tools=tools,
            messages=messages,
            output_config={"effort": self.effort},
            betas=["server-side-fallback-2026-07-01"],   # refusal -> retried on a fallback model
            fallbacks="default",
        )
        if resp.stop_reason == "refusal":
            raise RuntimeError(f"model declined the request: {resp.stop_details}")
        if resp.stop_reason == "max_tokens":
            raise RuntimeError("model output hit max_tokens; the plan was truncated")
        text = "\n".join(b.text for b in resp.content if b.type == "text")
        calls = [{"id": b.id, "name": b.name, "input": b.input} for b in resp.content if b.type == "tool_use"]
        turn = Turn(text, calls, resp.content)
        if self.rec:
            self.rec.add(turn)
        return turn


class ReplayBackend:
    """Replays trajectories/<design>/trajectory.json; `plan_file` inputs are inlined."""

    def __init__(self, traj_dir: Path):
        self.dir = traj_dir
        self.steps = json.loads((traj_dir / "trajectory.json").read_text())["steps"]
        self.i = 0

    def step(self, system: str, messages: list, tools: list[dict]) -> Turn:
        if self.i >= len(self.steps):
            return Turn("(trajectory exhausted)", [])
        s = self.steps[self.i]
        self.i += 1
        calls = []
        for j, c in enumerate(s.get("tool_calls", [])):
            inp = dict(c["input"])
            if "plan_file" in inp:
                inp["plan_json"] = (self.dir / inp.pop("plan_file")).read_text()
            calls.append({"id": f"replay_{self.i}_{j}", "name": c["name"], "input": inp})
        return Turn(s.get("text", ""), calls)


@dataclass
class TrajectoryWriter:
    dir: Path
    steps: list = field(default_factory=list)

    def __post_init__(self):
        self.dir.mkdir(parents=True, exist_ok=True)

    def add(self, turn: Turn) -> None:
        calls = []
        for c in turn.tool_calls:
            inp = dict(c["input"])
            if "plan_json" in inp:
                fname = f"plan_{len(self.steps) + 1:02d}.json"
                try:
                    (self.dir / fname).write_text(json.dumps(json.loads(inp.pop("plan_json")), indent=2) + "\n")
                except json.JSONDecodeError:
                    (self.dir / fname).write_text(inp.pop("plan_json", ""))
                inp["plan_file"] = fname
            calls.append({"name": c["name"], "input": inp})
        self.steps.append({"text": turn.text, "tool_calls": calls})
        (self.dir / "trajectory.json").write_text(json.dumps({"model": MODEL, "steps": self.steps}, indent=2) + "\n")
