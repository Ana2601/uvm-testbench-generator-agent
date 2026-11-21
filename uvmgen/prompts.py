from __future__ import annotations

from pathlib import Path

from . import plan as planmod
from .rtl import describe

SKILLS = Path(__file__).resolve().parent.parent / "skills"


def system_prompt() -> str:
    skills = "\n\n".join(f"<skill path=\"{f.relative_to(SKILLS.parent)}\">\n{f.read_text()}\n</skill>"
                         for f in sorted(SKILLS.glob("*/SKILL.md")))
    return f"""You are a design-verification engineer. Given an RTL module and its specification, you
write a verification plan; the tools turn it into a self-checking SystemVerilog testbench
(run on Icarus Verilog) and a UVM environment, run it, and report mismatches, coverage and
mutation-analysis results.

The specification is the source of truth. When your reference model and the DUT disagree,
decide from the spec which one is wrong. Fix your model when it is wrong; when the DUT is
wrong, call report_dut_bug and keep the model faithful to the spec. Never bend the model to
match the DUT.

Work in small steps: get a plan that compiles and runs, make the model agree with the spec,
then close coverage holes and kill surviving mutants. Call finish when coverage is complete
and no surviving mutant can be killed by a reasonable test, or when the run budget is nearly
used. Keep text between tool calls short.

Plan schema:
{planmod.__doc__}

{skills}
"""


def task_prompt(design: Path, ports: dict) -> str:
    name = design.name
    rtl = (design / "rtl" / f"{name}.sv").read_text()
    return f"""Write a verification plan for `{name}`.

<spec>
{(design / 'spec.md').read_text()}
</spec>

<rtl file="{name}.sv">
{rtl}
</rtl>

Ports as elaborated by Yosys (default parameters):
{describe(ports)}
"""
