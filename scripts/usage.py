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
    except UnicodeDecodeError:
        die("%s is not UTF-8" % path)
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
    """Phase current at ISO time t; None once Phase: done has passed. The ledger's trailing
    Z is dropped so its coarser time compares as a prefix of the transcript's .mmmZ time."""
    cur = "intake"
    for pt, name in phases:
        if pt is not None and (pt[:-1] if pt.endswith("Z") else pt) <= t:
            cur = name
    return None if cur == "done" else FOLD.get(cur, cur)


def read_budget(plan):
    est = {}
    try:
        text = open(plan, encoding="utf-8").read()
    except (OSError, UnicodeDecodeError):
        return est
    parts = ("\n" + text).rsplit("\n## Budget", 1)  # the file start is a line boundary too
    if len(parts) < 2:
        return est
    for l in parts[1].split("\n## ", 1)[0].splitlines():
        cells = [c.strip() for c in l.strip().strip("|").split("|")]
        if len(cells) >= 2 and re.fullmatch(r"\$[\d,]+(?:\.\d+)?", cells[-1]):
            est[cells[0].lower()] = float(cells[-1][1:].replace(",", ""))
    return est


def price_of(model):
    m = model or ""
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
    with open(path, encoding="utf-8", errors="replace") as f:
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
        items[("lead, " + ph) if role == "lead" else (role + " — " + label)] += c.usd
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
