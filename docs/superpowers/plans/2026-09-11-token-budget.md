# Token Budget Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every foreman plan carries a USD estimate per phase, and the lead reports actual spend against it from the session transcripts, in the ledger and at both gates.

**Architecture:** One stdlib Python script prices every API response of the sessions a ledger names (the lead's main transcript plus its subagents' transcripts under the Claude projects directory), buckets them by the ledger's timestamped `Phase:` lines, writes `<workspace>/spend.md`, and appends one `Spend:` line to the ledger. A baseline file gives the lead per-dispatch figures to estimate from. The standing orders, the architect role, the SessionStart hook, and the docs change in place. Report only: nothing stops on overrun.

**Tech Stack:** bash, `/usr/bin/python3` 3.9 (standard library only), Claude Code 2.1.268 transcript layout.

**Spec:** `docs/superpowers/specs/2026-09-11-token-budget-design.md`

## Global Constraints

- Branch `feat/budget` off `main`; every task commits there (or on its batch branch, merged into `feat/budget` in task order). Commit messages start with `wip:` unless the commit completes the task.
- Scripts use `/usr/bin/python3` and `/bin/bash` only; no third-party packages; Python must run on 3.9 (no `match`, no `X | Y` types).
- Hooks exit 0 always and write nothing to stderr on the happy path.
- `orders.md` stays under 80 lines.
- One turn per API response: `assistant` records sharing `message.id` and `requestId` are one response; price the last such record once.
- Prices, dollars per million tokens (input, output, cache read, cache write 5 min, cache write 1 hour): `claude-fable-5-1` 10, 50, 0.25, 12.50, 20; `claude-opus-5` 5, 25, 0.50, 6.25, 10; `claude-sonnet-5` 2, 10, 0.20, 2.50, 4; `claude-haiku-4-5` 1, 5, 0.10, 1.25, 2. Match by prefix, so a `[1m]` variant prices as its base model. Unknown models price as `claude-fable-5-1` and are listed. Records whose model is `<synthetic>` are skipped.
- Ledger line formats, verbatim: `Session: <id>`; `Phase: <name> <time>` with time from `date -u +%Y-%m-%dT%H:%M:%SZ`; `Spend: <phase> $<actual> of $<estimate> — total $<actual> of $<estimate>`; without a Budget table `Spend: <phase> $<actual> — total $<actual> (no budget in plan)`; when the last phase is done, `Spend: done — total $<actual> of $<estimate>`.
- Phase names: `intake`, `plan-review`, `execution`, `qa`, `final-review`; `gate-1` folds into `plan-review`, `gate-2` into `final-review`; turns before the first timed `Phase:` line are `intake`; turns after `Phase: done` are dropped. Times are ISO 8601 UTC strings compared as text.
- Version `0.2.0` in `.claude-plugin/plugin.json` only.
- Quality: thin docs, comments only where code cannot say it, edit in place, one meaningful commit per task at the end.

**Parallel-safe batch: Tasks 1, 2, 3.** Disjoint files, no ordering dependency. Task 2's selftest checks a string the hook prints, not a file from Task 1; Task 2's `budget.md` figures were measured by the lead before dispatch; Task 3's docs describe the spec, not the code.

---

### Task 1: The spend script and its test

**Files:**
- Create: `scripts/usage.py`
- Create: `tests/test_usage.sh`

**Interfaces:**
- Consumes: the ledger format from Global Constraints (a session id may be listed more than once; count it once); transcripts at `${CLAUDE_CONFIG_DIR:-~/.claude}/projects/*/<session-id>.jsonl` with subagents at `<same dir>/<session-id>/subagents/agent-*.jsonl` and sidecars `agent-*.meta.json` (keys `customAgentType`, `agentType`, `description`; the type may carry a plugin namespace such as `foreman:implementer`, which is stripped before the role match); the plan's last `## Budget` table (first cell phase or `total`, last cell `$<amount>`); the `cost-state` record (`totalCostUSD`) Claude Code appends to a main transcript at session end.
- Produces: `/usr/bin/python3 scripts/usage.py LEDGER` → writes `<dirname LEDGER>/spend.md`, appends one `Spend:` line to LEDGER, prints that line; exit 2 with a message on stderr and nothing written for a missing ledger or one whose first line is not `# SDD ledger — plan: <path>`.

- [ ] **Step 1: Write the test with the fixtures and the first run's assertions**

```bash
cat > tests/test_usage.sh <<'SH'
#!/bin/bash
# Runnable check for scripts/usage.py against fixture transcripts.
set -e
here="$(cd "$(dirname "$0")/.." && pwd)"
py=/usr/bin/python3
usage="$here/scripts/usage.py"
fail() { echo "FAIL: $1"; exit 1; }

tmp=$(mktemp -d)
export CLAUDE_CONFIG_DIR="$tmp/config"
repo="$tmp/repo"; ws="$repo/.superpowers/sdd/plan"; ledger="$ws/progress.md"
mkdir -p "$ws" "$repo/docs/superpowers/plans"

cat > "$repo/docs/superpowers/plans/plan.md" <<'MD'
# Plan

## Budget

| Phase | Counts | Estimate |
|---|---|---|
| execution | superseded draft | $1 |
| total | | $2 |

## Budget

| Phase | Counts | Estimate |
|---|---|---|
| intake | 60 lead turns | $24 |
| plan-review | 2 architects, 20 lead turns | $38 |
| execution | 5 tasks | $50 |
| qa | 1 pass | $9 |
| final-review | 2 reviewers | $38 |
| total | | $159 |

## Notes

| qa | not a budget row | $999 |
MD

# Session A: a Fable lead with one response per phase, one response written as three
# records (output 100, 100, 1000: only the last counts), a synthetic record, an
# unparsable line, a late response that Phase: done will drop, and a cost-state record.
# Two subagents: a reviewer whose sidecar has only a suffixed agentType, and an unknown
# model whose sidecar carries the plugin-namespaced type foreman:implementer.
# Session B: a Sonnet lead in another project directory, no subagents directory.
$py - "$CLAUDE_CONFIG_DIR" <<'PY'
import json, os, sys
cfg = sys.argv[1]
def rec(ts, mid, model, usage):
    return json.dumps({"type": "assistant", "timestamp": ts, "requestId": "req-" + mid,
                       "message": {"id": mid, "model": model, "usage": usage}})
def write(path, lines):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w").write("\n".join(lines) + "\n")
A = os.path.join(cfg, "projects", "-fake", "aaaa1111")
write(A + ".jsonl", [
    json.dumps({"type": "user", "message": {"content": "hi"}}),
    rec("2026-09-11T10:00:00.000Z", "m1", "claude-fable-5-1", {"input_tokens": 0, "output_tokens": 1000, "cache_read_input_tokens": 200000, "cache_creation_input_tokens": 10000, "cache_creation": {"ephemeral_5m_input_tokens": 0, "ephemeral_1h_input_tokens": 10000}}),
    rec("2026-09-11T10:30:00.000Z", "m2", "claude-fable-5-1[1m]", {"output_tokens": 2000, "cache_read_input_tokens": 200000, "cache_creation_input_tokens": 4000}),
    rec("2026-09-11T10:55:00.000Z", "m3", "claude-fable-5-1", {"output_tokens": 200}),
    rec("2026-09-11T11:05:00.000Z", "m4", "claude-fable-5-1", {"output_tokens": 200}),
    rec("2026-09-11T11:07:00.000Z", "m5", "claude-fable-5-1", {"output_tokens": 100}),
    rec("2026-09-11T11:07:00.000Z", "m5", "claude-fable-5-1", {"output_tokens": 100}),
    rec("2026-09-11T11:07:00.000Z", "m5", "claude-fable-5-1", {"output_tokens": 1000}),
    rec("2026-09-11T11:06:00.000Z", "m6", "<synthetic>", {"output_tokens": 999999}),
    "not json at all",
    rec("2026-09-11T13:00:00.000Z", "m7", "claude-fable-5-1", {"output_tokens": 1000000}),
    json.dumps({"type": "cost-state", "sessionId": "aaaa1111", "totalCostUSD": 1.23}),
])
write(A + "/subagents/agent-abc.jsonl", [rec("2026-09-11T11:10:00.000Z", "s1", "claude-opus-5", {"input_tokens": 0, "output_tokens": 1000, "cache_read_input_tokens": 60000, "cache_creation_input_tokens": 20000, "cache_creation": {"ephemeral_5m_input_tokens": 20000, "ephemeral_1h_input_tokens": 0}})])
write(A + "/subagents/agent-abc.meta.json", [json.dumps({"agentType": "reviewer-task-2", "description": "Review Task 2 branch: shout", "model": "opus"})])
write(A + "/subagents/agent-def.jsonl", [rec("2026-09-11T11:08:00.000Z", "s2", "claude-nova-9", {"output_tokens": 200})])
write(A + "/subagents/agent-def.meta.json", [json.dumps({"agentType": "foreman:implementer", "description": "Implement Task 2: shout", "model": "inherit"})])
B = os.path.join(cfg, "projects", "-other", "bbbb2222")
write(B + ".jsonl", [rec("2026-09-11T11:30:00.000Z", "b1", "claude-sonnet-5", {"output_tokens": 1000})])
PY
# Hand-priced: intake m1 = 1000*50 + 200000*0.25 + 10000*20 = $0.30
#   plan-review m2 = 2000*50 + 200000*0.25 + 4000*12.5 = $0.20, gate-1 m3 $0.01 -> $0.21
#   execution: lead m4 $0.01 + m5 $0.05 (last record only) + m7 $50.00 + B $0.01 = $50.07;
#   reviewer s1 = 1000*25 + 60000*0.5 + 20000*6.25 = $0.18; unknown s2 = 200*50 = $0.01

cat > "$ledger" <<'LEDGER'
# SDD ledger — plan: docs/superpowers/plans/plan.md
Session: aaaa1111
Phase: plan-review 2026-09-11T10:20:00Z
Phase: gate-1 2026-09-11T10:50:00Z
Phase: execution 2026-09-11T11:00:00Z
Session: bbbb2222
Session: cccc3333
Task 2: complete
Session: aaaa1111
LEDGER

out=$($py "$usage" "$ledger")
want='Spend: execution $50.26 of $50.00 — total $50.77 of $159.00'
[ "$out" = "$want" ] || fail "run 1 stdout: '$out'"
[ "$(tail -1 "$ledger")" = "$want" ] || fail "run 1 ledger tail: '$(tail -1 "$ledger")'"
[ "$(grep -c '^Spend:' "$ledger")" = "1" ] || fail "run 1 Spend line count"
spend="$ws/spend.md"
[ -f "$spend" ] || fail "spend.md not written"
grep -qF '| intake | $24.00 | $0.30 | $0.30 |' "$spend" || fail "intake row: $(grep intake "$spend")"
grep -qF '| plan-review | $38.00 | $0.21 | $0.21 |' "$spend" || fail "plan-review row (gate-1 must fold in): $(grep plan-review "$spend")"
grep -qF '| execution | $50.00 | $50.26 | $50.07 |  | $0.01 | $0.18 |  |' "$spend" || fail "execution row: $(grep '^| execution' "$spend")"
grep -qF '| qa | $9.00 | $0.00 |' "$spend" || fail "qa row present with zero actual"
grep -qF '| total | $159.00 | $50.77 |' "$spend" || fail "total row: $(grep '^| total' "$spend")"
grep -qF '| 2 | $0.01 | $0.18 | $0.00 | $0.19 |' "$spend" || fail "task 2 row: $(grep '^| 2 ' "$spend")"
grep -qF 'Not found: cccc3333' "$spend" || fail "missing session not listed"
grep -qF 'Unknown models: claude-nova-9 (priced as claude-fable-5-1)' "$spend" || fail "unknown model not listed"
grep -qF 'Sessions: aaaa1111 2026-09-11T10:00 → 2026-09-11T13:00 (Claude Code total $1.23); bbbb2222 2026-09-11T11:30 → 2026-09-11T11:30' "$spend" || fail "session spans: $(grep '^Sessions' "$spend")"
grep -qF '1. lead, execution — $50.07' "$spend" || fail "largest line item: $(grep -A3 'Largest' "$spend")"

rm -rf "$tmp"
echo "usage.py test: OK"
SH
chmod +x tests/test_usage.sh
```

- [ ] **Step 2: Run it and watch it fail**

Run: `tests/test_usage.sh`
Expected: the test stops at the first run with python's own error, `can't open file '.../scripts/usage.py': [Errno 2] No such file or directory`, and a non-zero exit; no `OK` line.

- [ ] **Step 3: Write the script**

Superseded after qa and the final review: the shipped `scripts/usage.py` on the branch is authoritative. The heredoc below is the pre-qa version and lacks the UnicodeDecodeError handling, the leading-newline Budget search, the replacement-character transcript read, and the trailing-`Z` phase compare.

```bash
cat > scripts/usage.py <<'PY'
#!/usr/bin/env python3
"""Spend report for one foreman plan.

Usage: usage.py LEDGER

Prices every API response of the sessions the ledger names (the lead's main
transcript and its subagents) at Anthropic list price, buckets them by the
ledger's timestamped Phase: lines, writes <workspace>/spend.md, appends one
Spend: line to the ledger, and prints that line.
"""
import glob
import json
import os
import re
import sys
from collections import Counter, defaultdict

# Dollars per million tokens: input, output, cache read, cache write 5 min, cache write 1 hour.
PRICES = {
    "claude-fable-5-1": (10.0, 50.0, 0.25, 12.5, 20.0),
    "claude-opus-5": (5.0, 25.0, 0.5, 6.25, 10.0),
    "claude-sonnet-5": (2.0, 10.0, 0.2, 2.5, 4.0),
    "claude-haiku-4-5": (1.0, 5.0, 0.1, 1.25, 2.0),
}
FALLBACK = "claude-fable-5-1"  # an unknown model over-reports rather than under-reports
PHASES = ["intake", "plan-review", "execution", "qa", "final-review"]
FOLD = {"gate-1": "plan-review", "gate-2": "final-review"}
ROLES = ["lead", "architect", "implementer", "reviewer", "qa"]
TOKEN_KINDS = ("input_tokens", "output_tokens", "cache_read_input_tokens", "cache_creation_input_tokens")


def die(msg):
    print("usage.py: " + msg, file=sys.stderr)
    sys.exit(2)


def read_ledger(path):
    try:
        lines = open(path, encoding="utf-8").read().splitlines()
    except OSError as e:
        die("cannot read %s: %s" % (path, e.strerror))
    m = re.match(r"# SDD ledger — plan: (.+)", lines[0] if lines else "")
    if not m:
        die("%s does not start with '# SDD ledger — plan: <path>'" % path)
    sessions = list(dict.fromkeys(l.split(":", 1)[1].strip() for l in lines if l.startswith("Session:")))
    phases = []  # (ISO time or None, name) in ledger order
    for l in lines:
        pm = re.match(r"Phase: (\S+)(?: (\d{4}-\S+))?", l)
        if pm:
            phases.append((pm.group(2), pm.group(1)))
    return m.group(1).strip(), sessions, phases


def phase_of(t, phases):
    """Phase current at ISO time t; None once Phase: done has passed."""
    cur = "intake"
    for pt, name in phases:
        if pt is not None and pt <= t:
            cur = name
    return None if cur == "done" else FOLD.get(cur, cur)


def read_budget(plan):
    est = {}
    try:
        text = open(plan, encoding="utf-8").read()
    except OSError:
        return est
    parts = text.rsplit("\n## Budget", 1)
    if len(parts) < 2:
        return est
    for l in parts[1].split("\n## ", 1)[0].splitlines():
        cells = [c.strip() for c in l.strip().strip("|").split("|")]
        if len(cells) >= 2 and re.fullmatch(r"\$[\d,]+(?:\.\d+)?", cells[-1]):
            est[cells[0].lower()] = float(cells[-1][1:].replace(",", ""))
    return est


def price_of(model):
    m = (model or "").replace("[1m]", "")
    for k, v in PRICES.items():
        if m.startswith(k):
            return v, True
    return PRICES[FALLBACK], False


def turn_cost(u, p):
    i, o, r, w5, w1 = p
    cc = u.get("cache_creation") or {}
    if "ephemeral_5m_input_tokens" in cc or "ephemeral_1h_input_tokens" in cc:
        c5, c1 = cc.get("ephemeral_5m_input_tokens", 0), cc.get("ephemeral_1h_input_tokens", 0)
    else:
        c5, c1 = u.get("cache_creation_input_tokens", 0), 0
    return (u.get("input_tokens", 0) * i + u.get("output_tokens", 0) * o
            + u.get("cache_read_input_tokens", 0) * r + c5 * w5 + c1 * w1) / 1e6


def read_transcript(path):
    """One (time, model, usage) per API response, from the last record of each, in first-seen
    order, plus Claude Code's own session total when a cost-state record is present."""
    last, total = {}, None
    with open(path, encoding="utf-8") as f:
        for line in f:
            try:
                d = json.loads(line)
            except ValueError:
                continue
            if d.get("type") == "cost-state":
                total = d.get("totalCostUSD")
            if d.get("type") != "assistant":
                continue
            msg = d.get("message") or {}
            u = msg.get("usage")
            if not u or msg.get("model") == "<synthetic>":
                continue
            last[(msg.get("id"), d.get("requestId"))] = (d.get("timestamp") or "", msg.get("model") or "", u)
    return list(last.values()), total


class Cell:
    def __init__(self):
        self.usd = 0.0
        self.tok = Counter()

    def add(self, other):
        self.usd += other.usd
        self.tok.update(other.tok)
        return self


def money(x):
    return "$%.2f" % x


def main(ledger):
    plan, sessions, phases = read_ledger(ledger)
    workspace = os.path.dirname(os.path.abspath(ledger))
    root = os.path.dirname(os.path.dirname(os.path.dirname(workspace)))  # <root>/.superpowers/sdd/<plan>
    est = read_budget(os.path.join(root, plan))
    if not sessions:
        sessions = [s for s in [os.environ.get("CLAUDE_CODE_SESSION_ID", "")] if s]
    projects = os.path.join(os.path.expanduser(os.environ.get("CLAUDE_CONFIG_DIR") or "~/.claude"), "projects")

    cells = defaultdict(Cell)  # (phase, role, label, task) -> Cell
    spans, missing, unknown = [], [], set()

    def add(path, role, label, task):
        turns, total = read_transcript(path)
        for t, model, u in turns:
            p, known = price_of(model)
            if not known:
                unknown.add(model)
            ph = phase_of(t, phases)
            if ph is None:
                continue
            c = cells[(ph, role, label, task)]
            c.usd += turn_cost(u, p)
            for k in TOKEN_KINDS:
                c.tok[k] += u.get(k, 0)
        return turns, total

    for sid in sessions:
        hits = glob.glob(os.path.join(projects, "*", sid + ".jsonl"))
        if not hits:
            missing.append(sid)
            continue
        turns, claude_total = add(hits[0], "lead", "lead", None)
        span = "%s %s → %s" % (sid[:8], turns[0][0][:16] if turns else "?", turns[-1][0][:16] if turns else "?")
        if claude_total is not None:
            span += " (Claude Code total %s)" % money(claude_total)
        spans.append(span)
        for sub in sorted(glob.glob(os.path.join(hits[0][:-6], "subagents", "agent-*.jsonl"))):
            try:
                meta = json.load(open(sub[:-6] + ".meta.json", encoding="utf-8"))
            except (OSError, ValueError):
                meta = {}
            kind = (meta.get("customAgentType") or meta.get("agentType") or "other").rsplit(":", 1)[-1]
            role = next((r for r in ROLES if kind.startswith(r)), kind)
            desc = meta.get("description") or os.path.basename(sub)
            tm = re.search(r"task\s+(\d+)", desc, re.I)
            add(sub, role, desc, int(tm.group(1)) if tm else None)

    by_phase = defaultdict(lambda: defaultdict(Cell))
    by_role = defaultdict(Cell)
    by_task = defaultdict(lambda: defaultdict(float))
    items = defaultdict(float)
    total = Cell()
    for (ph, role, label, task), c in cells.items():
        by_phase[ph][role].add(c)
        by_role[role].add(c)
        total.add(c)
        if task is not None:
            by_task[task][role] += c.usd
        items["lead, " + ph if role == "lead" else role + " — " + label] += c.usd
    roles = ROLES + sorted({k[1] for k in cells} - set(ROLES))

    def row(name, e, cellmap):
        merged = Cell()
        for c in cellmap.values():
            merged.add(c)
        return "| %s | %s | %s | %s | %s |" % (
            name, money(e) if e is not None else "", money(merged.usd),
            " | ".join(money(cellmap[r].usd) if r in cellmap else "" for r in roles),
            "/".join(str(merged.tok[k]) for k in TOKEN_KINDS))

    out = ["# Spend — plan: " + plan, "", "Sessions: " + ("; ".join(spans) or "none found")]
    if missing:
        out.append("Not found: " + ", ".join(missing))
    out += ["", "## Phases", "",
            "| Phase | Estimate | Actual | " + " | ".join(roles) + " | Tokens in/out/cache-read/cache-write |",
            "|" + "---|" * (len(roles) + 4)]
    for ph in PHASES + sorted(set(by_phase) - set(PHASES)):
        out.append(row(ph, est.get(ph), by_phase.get(ph, {})))
    out.append(row("total", est.get("total"), by_role))
    out += ["", "## Tasks", ""]
    if by_task:
        out += ["| Task | Implementer | Reviewer | Other | Total |", "|---|---|---|---|---|"]
        for t in sorted(by_task):
            r = by_task[t]
            other = sum(v for k, v in r.items() if k not in ("implementer", "reviewer"))
            out.append("| %d | %s | %s | %s | %s |" % (t, money(r.get("implementer", 0.0)), money(r.get("reviewer", 0.0)),
                                                     money(other), money(sum(r.values()))))
    else:
        out.append("No dispatch description named a task.")
    out += ["", "## Largest line items", ""]
    for i, (name, usd) in enumerate(sorted(items.items(), key=lambda kv: -kv[1])[:3], 1):
        out.append("%d. %s — %s" % (i, name, money(usd)))
    out += ["", "Unknown models: " + (", ".join(sorted(unknown)) + " (priced as %s)" % FALLBACK if unknown else "none"), ""]
    with open(os.path.join(workspace, "spend.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(out))

    def pair(actual, e):
        return money(actual) + (" of " + money(e) if e is not None else "")

    current = phases[-1][1] if phases else "intake"
    current = FOLD.get(current, current)
    if current == "done":
        line = "Spend: done — total " + pair(total.usd, est.get("total"))
    else:
        cur_actual = sum(c.usd for c in by_phase.get(current, {}).values())
        line = "Spend: %s %s — total %s" % (current, pair(cur_actual, est.get(current)), pair(total.usd, est.get("total")))
    if not est:
        line += " (no budget in plan)"
    with open(ledger, "a", encoding="utf-8") as f:
        f.write(line + "\n")
    print(line)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        die("usage: usage.py LEDGER")
    main(sys.argv[1])
PY
chmod +x scripts/usage.py
```

- [ ] **Step 4: Run the test and watch it pass**

Run: `tests/test_usage.sh`
Expected: `usage.py test: OK`

- [ ] **Step 5: Commit**

```bash
git add scripts/usage.py tests/test_usage.sh
git commit -m "wip: usage.py prices sessions and reports spend per phase"
```

- [ ] **Step 6: Add the second run and the edge cases to the test**

Insert before the `rm -rf "$tmp"` line of `tests/test_usage.sh`:

```bash
# Run 2: Phase: done drops the late response; spend.md is overwritten; one more Spend line.
echo 'Phase: done 2026-09-11T12:00:00Z' >> "$ledger"
out=$($py "$usage" "$ledger")
want='Spend: done — total $0.77 of $159.00'
[ "$out" = "$want" ] || fail "run 2 stdout: '$out'"
[ "$(grep -c '^Spend:' "$ledger")" = "2" ] || fail "run 2 Spend line count"
[ "$(grep -c '^# Spend' "$spend")" = "1" ] || fail "spend.md appended instead of overwritten"
grep -qF '| execution | $50.00 | $0.26 | $0.07 |' "$spend" || fail "run 2 execution row: $(grep '^| execution' "$spend")"
grep -qF '| total | $159.00 | $0.77 |' "$spend" || fail "run 2 total row"

# Run 3: a plan without a Budget table, no Phase lines before execution.
ws2="$repo/.superpowers/sdd/plan2"; mkdir -p "$ws2"
printf '# Plan two\n\nNo budget here.\n' > "$repo/docs/superpowers/plans/plan2.md"
printf '# SDD ledger — plan: docs/superpowers/plans/plan2.md\nSession: aaaa1111\nPhase: execution 2026-09-11T11:00:00Z\n' > "$ws2/progress.md"
out=$($py "$usage" "$ws2/progress.md")
[ "$out" = 'Spend: execution $50.25 — total $50.76 (no budget in plan)' ] || fail "run 3 stdout: '$out'"
grep -qF '| intake |  | $0.51 |' "$ws2/spend.md" || fail "run 3 intake row without estimate: $(grep '^| intake' "$ws2/spend.md")"

# Run 4: no Session lines; the current session id is the fallback.
ws3="$repo/.superpowers/sdd/plan3"; mkdir -p "$ws3"
printf '# SDD ledger — plan: docs/superpowers/plans/plan.md\nPhase: qa 2026-09-11T11:00:00Z\n' > "$ws3/progress.md"
out=$(CLAUDE_CODE_SESSION_ID=bbbb2222 $py "$usage" "$ws3/progress.md")
[ "$out" = 'Spend: qa $0.01 of $9.00 — total $0.01 of $159.00' ] || fail "run 4 stdout: '$out'"

# Bad input: exit 2 with a message, nothing written.
set +e
err=$($py "$usage" "$tmp/nope.md" 2>&1 >/dev/null); rc=$?
set -e
[ "$rc" = "2" ] && [ -n "$err" ] || fail "missing ledger: rc=$rc err='$err'"
printf 'Phase: execution\n' > "$tmp/bad.md"
set +e
err=$($py "$usage" "$tmp/bad.md" 2>&1 >/dev/null); rc=$?
set -e
[ "$rc" = "2" ] && [ -n "$err" ] || fail "ledger without plan line: rc=$rc err='$err'"
[ ! -f "$tmp/spend.md" ] || fail "spend.md written for a bad ledger"
```

Hand-priced for run 3: without a plan-review line, m2 ($0.20) and m3 ($0.01) are intake with m1 ($0.30): $0.51. Execution: m4 $0.01 + m5 $0.05 + m7 $50.00 + reviewer $0.18 + unknown $0.01 = $50.25. Total $50.76.

- [ ] **Step 7: Run the test**

Run: `tests/test_usage.sh`
Expected: `usage.py test: OK`. If a run fails, the failing assertion names the run; fix the script, not the expected values, unless you can show the hand pricing above is wrong.

- [ ] **Step 8: Check against the real build session**

The foreman build session's transcripts are on this machine. Expected at these prices: lead $60.01, subagents $44.12, printed total $104.12; Claude Code's own total on the Sessions line $121.37.

```bash
d=$(mktemp -d); mkdir -p "$d/.superpowers/sdd/x"
printf '# SDD ledger — plan: none.md\nSession: b26d3e91-98d6-4764-9e99-792c374bfbd4\n' > "$d/.superpowers/sdd/x/progress.md"
/usr/bin/python3 scripts/usage.py "$d/.superpowers/sdd/x/progress.md"
grep '^Sessions\|^| total' "$d/.superpowers/sdd/x/spend.md"
```

Expected stdout: `Spend: intake $104.12 — total $104.12 (no budget in plan)`, and a Sessions line ending `(Claude Code total $121.37)`. Paste the actual lines in your report. If the transcripts have been cleaned up, the script prints `Spend: intake $0.00 — total $0.00 (no budget in plan)` and `spend.md` lists the session under Not found; say so in the report and move on.

- [ ] **Step 9: Cross-check against Claude Code's own count on the smoke session**

```bash
printf '# SDD ledger — plan: none.md\nSession: 8f426bbe-bdb9-41ff-a104-ea1ad03d160f\n' > "$d/.superpowers/sdd/x/progress.md"
/usr/bin/python3 scripts/usage.py "$d/.superpowers/sdd/x/progress.md"
grep '^Sessions' "$d/.superpowers/sdd/x/spend.md"
```

Expected: `Spend: intake $9.28 — total $9.28 (no budget in plan)` and `(Claude Code total $9.83)`. The script's figure is lower by roughly five to fifteen percent because Claude Code also counts calls that never land in a transcript; a figure higher than Claude Code's, or lower by more than a quarter, is a bug. Paste both lines in your report.

- [ ] **Step 10: Commit**

```bash
git add scripts/usage.py tests/test_usage.sh
git commit -m "Add usage.py, the spend report for a plan's sessions"
```

---

### Task 2: Orders, baseline, architect check, and the hook

**Files:**
- Create: `budget.md`
- Modify: `orders.md:9,11,15,35`
- Modify: `agents/architect.md:22`
- Modify: `scripts/session-start.sh:29,40`
- Modify: `scripts/selftest.sh:23-32,61`

**Interfaces:**
- Consumes: nothing from other tasks. The hook prints paths as text; the script at that path is Task 1's, but the hook does not run it. The `budget.md` figures were measured by the lead before this plan was dispatched.
- Produces: the ledger conventions the lead follows (`Session:`, timed `Phase:`, running `usage.py`), read by Task 1's script.

- [ ] **Step 1: Add the selftest cases**

In `scripts/selftest.sh`, the first session-start case is the block at lines 23-32 that ends `|| { echo "FAIL session-start orders/no-ledger case"; exit 1; }`. Inside its python, after the line `assert "# Standing orders for the lead" in ctx, "orders missing"`, add:

```python
assert "/budget.md" in ctx and "/scripts/usage.py" in ctx, "budget paths missing from orders"
```

After the reopened-ledger case (line 61, ending `"reopened ledger not reported"`), add:

```bash
printf 'Phase: done 2026-09-11T12:00:00Z\n' >> "$tmp/.superpowers/sdd/demo/progress.md"
out=$(cd "$tmp" && CLAUDE_PID=$$ "$s/session-start.sh")
echo "$out" | $py -c 'import json,sys; d=json.load(sys.stdin); assert "systemMessage" not in d, "timestamped done ledger reported"' || { echo "FAIL timestamped-done case"; exit 1; }
```

- [ ] **Step 2: Run the selftest and watch it fail**

Run: `scripts/selftest.sh`
Expected: `FAIL session-start orders/no-ledger case` (the paths are not in the orders yet).

- [ ] **Step 3: Edit the hook**

In `scripts/session-start.sh`, line 29, replace

```bash
    [ "$phase" = "Phase: done" ] && continue
```

with

```bash
    case "$phase" in "Phase: done"*) continue ;; esac
```

In the python heredoc, after the two `auto_pr` lines (the `if os.environ.get("CLAUDE_PLUGIN_OPTION_AUTO_PR") == "false":` block), add:

```python
root = os.path.dirname(os.environ["FOREMAN_ORDERS"])
orders += "\nBudget baseline: %s/budget.md. Spend script: /usr/bin/python3 %s/scripts/usage.py LEDGER.\n" % (root, root)
```

- [ ] **Step 4: Run the selftest**

Run: `scripts/selftest.sh`
Expected: `foreman hooks selftest: OK`

- [ ] **Step 5: Commit**

```bash
git add scripts/session-start.sh scripts/selftest.sh
git commit -m "wip: hook names budget.md and usage.py, treats timed Phase: done as finished"
```

- [ ] **Step 6: Write `budget.md`**

```bash
cat > budget.md <<'MD'
# Budget baseline

What one dispatch costs at Anthropic list price, one turn per API response, measured from the foreman plugin build (session `b26d3e91`, seven tasks), the team smoke run (`8f426bbe`), and the token-budget plan review, all with Fable 5.1 as the session model. The lead's calls per phase are the least certain input; each plan's `spend.md` corrects them.

| Dispatch | Model | Measured | Budget figure |
|---|---|---|---|
| architect, one pair member including the joint report | session model | $1.0 to $6.8 | $6 |
| implementer, one task | session model | $0.44 to $1.15 | $1 |
| implementer, one fix round | session model | $0.52 to $1.01 | $1 |
| reviewer, one task | Opus | $0.26 to $1.34 | $1 |
| reviewer, one re-review | Opus | $0.29 to $1.86 | $1 |
| reviewer, final pair member including the joint report | Opus | $1.81 to $2.68, plus $1.51 joint | $3 |
| final fix wave | session model | $1.93 to $5.71 | $4 |
| qa, one pass | Sonnet | not yet measured | $0.50 |
| lead, one API call | session model | $0.11 to $0.33 | $0.35 |

## Recipe

- intake: lead calls × $0.35. Fifty calls for a small feature, a hundred for a large one.
- plan-review: 2 × $6 + 10 lead calls ($3.50).
- execution, per task: $1 implementer + $1 reviewer + 30% fix allowance ($0.60) + 6 lead calls ($2.10). About $5 a task.
- qa: $0.50 + one fix cycle ($2) + 5 lead calls ($1.75).
- final-review: 2 × $3 + $4 fix wave + $1 re-review + 15 lead calls ($5.25).

Round to whole dollars. Put the counts you multiplied in the table's Counts cell so the architects can check the arithmetic.
MD
```

- [ ] **Step 7: Edit `orders.md`**

Line 9 (Lifecycle step 2), append this sentence at the end:

```
End the plan with a `## Budget` table from `budget.md`: one row per phase (intake, plan-review, execution, qa, final-review) with a Counts cell and a USD estimate, and a total row.
```

Line 11 (GATE 1) becomes:

```
4. GATE 1: notify, present a short summary, the budget total and per-phase estimates, the architects' verdict and manager questions, and the plan path. Never the plan inline. Wait.
```

Line 15 (GATE 2) becomes:

```
8. GATE 2: push, open a draft pull request, notify, present the PR link, both verdicts, the qa report, minor findings, the last `Spend:` line and the `spend.md` path. No remote: escalate, never merge locally.
```

Line 35 (first paragraph of Resilience) becomes:

```
Ledger every transition: `Phase: <plan-review | gate-1 | execution | qa | final-review | gate-2 | done> <time>` with the time from `date -u +%Y-%m-%dT%H:%M:%SZ`, `Gate 1: approved <time>`, `Gate 2: <decision> <time>`, `Batch: tasks n,m — <branches>`. Ledger `Session: $CLAUDE_CODE_SESSION_ID` when you create the ledger and on every resume. After every `Phase:` line and every `Task N: complete`, run the spend script on the ledger (the hook prints its path below these orders); it appends the `Spend:` line and writes `<workspace>/spend.md`. Dispatch descriptions for implementers and reviewers start with `Task N:`. The budget is information for the manager: never stop, wait, or cut scope because of it.
```

- [ ] **Step 8: Edit `agents/architect.md`**

After line 22 (`- The test strategy covers the risky parts.`), add:

```
- The plan ends with a `## Budget` table: every phase (intake, plan-review, execution, qa, final-review) present, each estimate equal to its Counts cell times the `budget.md` figures to the nearest dollar (the lead's context names the path), total equal to the sum. A missing phase or a wrong sum is Blocking. How generous the estimate is belongs to the manager.
```

- [ ] **Step 9: Check the texts**

```bash
[ "$(wc -l < orders.md)" -lt 80 ] && echo "orders lines ok"
grep -c 'Spend:' orders.md            # expected 2 (Gate 2 line and Resilience)
grep -c 'Session: \$CLAUDE_CODE_SESSION_ID' orders.md   # expected 1
grep -c '## Budget' agents/architect.md   # expected 1
scripts/selftest.sh                   # expected: foreman hooks selftest: OK
tests/test_setup.sh                   # expected: its OK line
claude plugin validate .              # expected: pass
```

- [ ] **Step 10: Commit**

```bash
git add budget.md orders.md agents/architect.md scripts/session-start.sh scripts/selftest.sh
git commit -m "Add the budget baseline and the ledger spend conventions"
```

---

### Task 3: Docs and release

**Files:**
- Modify: `README.md:40,77-79`
- Modify: `CHANGELOG.md:2`
- Modify: `.claude-plugin/plugin.json:4`
- Modify: `docs/design.md:22,36,39,45,48`
- Modify: `docs/team-design.md:29,66-68,72-74,93-95,326-327`

**Interfaces:**
- Consumes: the file names `budget.md`, `scripts/usage.py`, `tests/test_usage.sh`, `spend.md`, and the spec path `docs/superpowers/specs/2026-09-11-token-budget-design.md`.
- Produces: nothing other tasks read.

- [ ] **Step 1: README**

After line 40 (`  does whatever you ask. It resumes only when you type \`resume\`.`), add a bullet:

```
- Every plan ends with a budget in dollars, estimated per phase from measured
  runs. The ledger carries the running spend, and Gate 2 shows actual against
  estimate. The budget never stops the work.
```

In the Development paragraph near the end, after the sentence about `tests/test_setup.sh`, add: `` `tests/test_usage.sh` checks the spend script against fixture transcripts. ``

- [ ] **Step 2: CHANGELOG**

After line 2 (blank line under `# Changelog`), insert:

```
## 0.2.0

Token budget. Every plan ends with a USD estimate per phase from
`budget.md`; `scripts/usage.py` prices the session transcripts and appends
`Spend:` lines to the ledger; Gate 1 shows the estimate and Gate 2 the
actual. `Phase:` ledger lines now carry a UTC time and the ledger names its
sessions.

```

- [ ] **Step 3: Version**

In `.claude-plugin/plugin.json`, line 4: `"version": "0.1.0",` becomes `"version": "0.2.0",`.

- [ ] **Step 4: `docs/design.md`**

After line 22 (the Version row), add a Decisions row:

```
| Budget | Every plan carries a USD estimate per phase from `budget.md`; `scripts/usage.py` reports actual spend from the session transcripts into the ledger and `spend.md`. Report only, list price, no option. Design: `docs/superpowers/specs/2026-09-11-token-budget-design.md`. |
```

In the layout tree: after the `session-start.sh` line add `│   ├── usage.py             spend report from the session transcripts`; after the `orders.md` line add `├── budget.md                per-dispatch cost baseline and the estimating recipe`; after the `tests/test_setup.sh` line add `├── tests/test_usage.sh      runnable check for usage.py against fixture transcripts`; after the `docs/superpowers/plans/` line add `├── docs/superpowers/specs/  design documents for features after 0.1.0`, and change that plans line's description to `the implementation plans`. Keep the column alignment of the neighbouring lines.

- [ ] **Step 5: `docs/team-design.md`**

After line 29 (row R9), add:

```
| R10 | Budget | Every plan carries a USD estimate per phase; the lead reports actual spend against it in the ledger and at Gate 2. Report only. |
```

Step 2 of section 4 (lines 66-68) gains a final sentence: ``The plan ends with a Budget table; see `docs/superpowers/specs/2026-09-11-token-budget-design.md`.``

Step 4 (lines 72-74): `presents a short summary,` becomes `presents a short summary, the budget total and per-phase estimates,`.

Step 8 (lines 93-95): `the qa report, and the minor findings.` becomes ``the qa report, the minor findings, and the last `Spend:` line.``

Lines 326-327: `- Phase markers the lead writes on every transition:` becomes `- Phase markers the lead writes on every transition, each followed by a UTC time:`.

Reflow the edited paragraphs to the file's line width.

- [ ] **Step 6: Check**

```bash
claude plugin validate .                              # expected: pass
grep -c 'budget' README.md CHANGELOG.md docs/design.md docs/team-design.md   # each at least 1
grep -c 'test_usage' README.md                        # expected 1
grep '"version"' .claude-plugin/plugin.json           # expected: "version": "0.2.0",
```

- [ ] **Step 7: Commit**

```bash
git add README.md CHANGELOG.md .claude-plugin/plugin.json docs/design.md docs/team-design.md
git commit -m "Document the token budget and release 0.2.0"
```

---

### After qa: the measured qa figure (lead, before the squash)

The qa row of `budget.md` says `not yet measured`. Once the qa phase of this plan has run:

- [ ] Run the spend script on this plan's ledger and read the `qa` column of the `qa` row in `spend.md`.
- [ ] In `budget.md`, replace `not yet measured` with the measured amount as `$N.NN` and set the Budget figure to that amount rounded up to the nearest $0.50.
- [ ] Commit as `wip: measured qa figure`; fold it into Task 2's commit at the squash.

The Budget table below keeps its pre-measurement figures (qa $4, total $74): every `Spend:` line in the ledger was written against them, and the measured qa figure changes the baseline for the next plan, not this one.

---

## Budget

| Phase | Counts | Estimate |
|---|---|---|
| intake | 50 lead calls | $18 |
| plan-review | 2 architects, 10 lead calls | $16 |
| execution | 3 tasks, Task 1 counted twice for its size | $20 |
| qa | 1 pass, 1 fix cycle, 5 lead calls | $4 |
| final-review | 2 reviewers, 1 fix wave, 15 lead calls | $16 |
| total | | $74 |
