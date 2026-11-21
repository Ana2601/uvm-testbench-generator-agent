"""Mutation testing: how good is a generated testbench at catching real bugs?

Each mutant changes ONE operator or constant in the DUT. A mutant is
  - stillborn   if it no longer compiles (dropped),
  - killed      if the testbench reports FAIL on it,
  - equivalent  if formal equivalence (lec.py) proves it behaves like the original
                on every cycle where the spec compares outputs (it cannot be killed),
  - survived    otherwise: a real bug the testbench missed.

score = killed / (killed + survived)
"""
from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

# (pattern, replacement, label). Patterns are applied to code only (comments stripped).
OPERATORS = [
    (r"(?<![=!<>])==(?!=)", "!=", "== -> !="),
    (r"!=(?!=)", "==", "!= -> =="),
    (r"&&", "||", "&& -> ||"),
    (r"\|\|", "&&", "|| -> &&"),
    (r"(?<![+])\+(?![+=:])", "-", "+ -> -"),
    (r"(?<![-])-(?![-=:>])", "+", "- -> +"),
    (r"(?<![<>=!])>(?![>=])", ">=", "> -> >="),
    (r"(?<![<>=!])>=", ">", ">= -> >"),
    (r"(?<![&])&(?![&=])", "|", "& -> |"),
    (r"(?<![|])\|(?![|=])", "&", "| -> &"),
    (r"1'b1", "1'b0", "1'b1 -> 1'b0"),
    (r"1'b0", "1'b1", "1'b0 -> 1'b1"),
    (r"(?<![\w'])!(?!=)", "", "drop !"),
    (r"(?<![\w'])~(?![&|^])", "", "drop ~"),
    (r"(\d+)'d(\d+)", None, "constant +1"),
    (r"(?<![\w'])'0\b", "'1", "'0 -> '1"),
    (r"<<", ">>", "<< -> >>"),
    (r">>", "<<", ">> -> <<"),
    (r"\[0\]", "[1]", "bit [0] -> [1]"),
]

SKIP = re.compile(r"^\s*(module|input|output|parameter|localparam|typedef|endmodule|logic\s*\[|logic\s+\w+\s*;|//)")


@dataclass
class Mutant:
    id: int
    line: int
    label: str
    before: str
    after: str
    text: str


def mutants(rtl: str, limit: int = 60) -> list[Mutant]:
    lines = rtl.splitlines()
    out: list[Mutant] = []
    for ln, line in enumerate(lines):
        code, _, comment = line.partition("//")
        if not code.strip() or SKIP.match(code) or "$clog2" in code:
            continue
        # don't mutate the sensitivity list of an always block
        if re.search(r"@\s*\(", code):
            head, _, rest = code.partition(")")
            prefix, body = head + ")", rest
        else:
            prefix, body = "", code
        for pat, rep, label in OPERATORS:
            for m in re.finditer(pat, body):
                if rep is None:                         # constant +1
                    w, v = int(m.group(1)), int(m.group(2))
                    new = f"{w}'d{(v + 1) % (1 << w)}"
                else:
                    new = rep
                nb = body[:m.start()] + new + body[m.end():]
                if label in ("- -> +",) and re.search(r"\[[^\]]*$", body[:m.start()]):
                    continue                            # inside a part-select [a-1:0]
                newline = prefix + nb + (("//" + comment) if comment else "")
                txt = "\n".join(lines[:ln] + [newline] + lines[ln + 1:]) + "\n"
                out.append(Mutant(len(out) + 1, ln + 1, label, line.strip(), newline.strip(), txt))
    # deterministic thinning: spread the sample over the whole file
    if len(out) > limit:
        step = len(out) / limit
        out = [out[int(k * step)] for k in range(limit)]
        for k, m in enumerate(out):
            m.id = k + 1
    return out


def write(m: Mutant, d: Path, top: str) -> Path:
    d.mkdir(parents=True, exist_ok=True)
    p = d / f"{top}.sv"
    p.write_text(m.text)
    return p
