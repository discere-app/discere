#!/usr/bin/env python3
"""Print ARCH-07 code-line counts and budget status for discere files.

Counts exactly like test/architecture/file_size_budget_test.dart: a line
counts unless it is blank or *starts* with `//`. Reads the ratchet
(`_knownOversized`) and the permanent list (`_permanentlyOversized`) from
that test, so the numbers here can be pasted into a briefing as-is.

Usage (from the repo root):
  python3 .claude/skills/issue-per-subagent/scripts/file_budget.py lib/a.dart lib/b.dart
  python3 .claude/skills/issue-per-subagent/scripts/file_budget.py --dir lib/catalog/species_detail
"""
import os
import re
import sys

BUDGET_TEST = "test/architecture/file_size_budget_test.dart"


def code_lines(path):
    with open(path, encoding="utf-8") as f:
        return sum(
            1 for line in f
            if line.strip() and not line.strip().startswith("//")
        )


def read_lists():
    src = open(BUDGET_TEST, encoding="utf-8").read()
    budget = int(re.search(r"const _budget = (\d+);", src).group(1))
    slack = int(re.search(r"const _slack = (\d+);", src).group(1))

    def block(name):
        m = re.search(name + r" = <String, \w+>\{(.*?)\n\};", src, re.S)
        return m.group(1) if m else ""

    ratchet = {
        p: int(n)
        for p, n in re.findall(r"'(lib/[^']+)':\s*(\d+)", block("_knownOversized"))
    }
    permanent = set(re.findall(r"'(lib/[^']+)':", block("_permanentlyOversized")))
    return budget, slack, ratchet, permanent


def status(path, lines, budget, slack, ratchet, permanent):
    if path in permanent:
        return "permanent list (no limit)"
    if path in ratchet:
        cap = ratchet[path]
        if lines > cap:
            return f"RATCHET {cap} — over by {lines - cap}, test fails"
        if cap - lines > slack:
            return f"RATCHET {cap} — shrank by {cap - lines} > slack {slack}, entry must be lowered"
        return f"RATCHET {cap} — headroom {cap - lines}, don't grow it"
    if lines > budget:
        return f"OVER BUDGET {budget} by {lines - budget}"
    return f"budget {budget}, headroom {budget - lines}"


def main(argv):
    if not os.path.exists(BUDGET_TEST):
        sys.exit(f"run from the repo root ({BUDGET_TEST} not found)")
    paths = []
    if argv[:1] == ["--dir"]:
        for root, _, files in os.walk(argv[1]):
            paths += [os.path.join(root, f) for f in files if f.endswith(".dart")]
    else:
        paths = argv
    if not paths:
        sys.exit(__doc__)
    budget, slack, ratchet, permanent = read_lists()
    for p in sorted(paths):
        p = os.path.normpath(p)
        if p.endswith(".g.dart") or p.startswith("lib/l10n/"):
            continue
        n = code_lines(p)
        print(f"{n:5d}  {p}  — {status(p, n, budget, slack, ratchet, permanent)}")


if __name__ == "__main__":
    main(sys.argv[1:])
