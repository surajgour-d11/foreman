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
# Two subagents: a reviewer whose sidecar has a suffixed customAgentType and an agentType
# that maps to no role, and an unknown model whose sidecar has the plugin-namespaced type.
# Session B: a Sonnet lead in another project directory, no subagents directory.
# Session E: a Fable lead with one turn in the first second of each of two phases.
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
write(A + "/subagents/agent-abc.meta.json", [json.dumps({"customAgentType": "reviewer-task-2", "agentType": "helper", "description": "Review Task 2 branch: shout", "model": "opus"})])
write(A + "/subagents/agent-def.jsonl", [rec("2026-09-11T11:08:00.000Z", "s2", "claude-nova-9", {"output_tokens": 200})])
write(A + "/subagents/agent-def.meta.json", [json.dumps({"agentType": "foreman:implementer", "description": "Implement Task 2: shout", "model": "inherit"})])
B = os.path.join(cfg, "projects", "-other", "bbbb2222")
write(B + ".jsonl", [rec("2026-09-11T11:30:00.000Z", "b1", "claude-sonnet-5", {"output_tokens": 1000})])
E = os.path.join(cfg, "projects", "-fake", "eeee5555")
write(E + ".jsonl", [rec("2026-09-11T11:00:00.000Z", "e1", "claude-fable-5-1", {"output_tokens": 1000}),
                     rec("2026-09-11T11:30:00.500Z", "e2", "claude-fable-5-1", {"output_tokens": 2000})])
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
! grep -q '^| qa ' "$spend" || fail "qa row printed; qa folds into final-review"
grep -qF '| total | $159.00 | $50.77 |' "$spend" || fail "total row: $(grep '^| total' "$spend")"
grep -qF '| 2 | $0.01 | $0.18 | $0.00 | $0.19 |' "$spend" || fail "task 2 row: $(grep '^| 2 ' "$spend")"
grep -qF 'Not found: cccc3333' "$spend" || fail "missing session not listed"
grep -qF 'Unknown models: claude-nova-9 (priced as claude-fable-5-1)' "$spend" || fail "unknown model not listed"
grep -qF 'Sessions: aaaa1111 2026-09-11T10:00 → 2026-09-11T13:00 (Claude Code total $1.23); bbbb2222 2026-09-11T11:30 → 2026-09-11T11:30' "$spend" || fail "session spans: $(grep '^Sessions' "$spend")"
grep -qF '1. lead, execution — $50.07' "$spend" || fail "largest line item: $(grep -A3 'Largest' "$spend")"

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
[ "$out" = 'Spend: final-review $0.01 of $38.00 — total $0.01 of $159.00' ] || fail "run 4 stdout (Phase: qa must fold into final-review): '$out'"

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

# Regression: a ledger with a valid plan line but a non-UTF-8 byte later on must
# fail like any other bad input (message on stderr, exit 2, nothing written), not
# crash with a raw UnicodeDecodeError traceback.
ws4="$repo/.superpowers/sdd/plan4"; mkdir -p "$ws4"
printf '# SDD ledger — plan: docs/superpowers/plans/plan.md\n\xff\xfe garbage\n' > "$ws4/progress.md"
set +e
err=$($py "$usage" "$ws4/progress.md" 2>&1 >/dev/null); rc=$?
set -e
[ "$rc" = "2" ] && [ -n "$err" ] && ! echo "$err" | grep -q Traceback \
    || fail "non-UTF-8 ledger: rc=$rc err='$err'"
[ ! -f "$ws4/spend.md" ] || fail "spend.md written for a non-UTF-8 ledger"

# Regression: a plan whose Budget table is the very first thing in the file (no
# preceding blank line to match "\n## Budget" against) is not found at all, even
# though it is a real, well-formed Budget table.
ws5="$repo/.superpowers/sdd/plan5"; mkdir -p "$ws5"
printf '## Budget\n\n| Phase | Counts | Estimate |\n|---|---|---|\n| intake | x | $5 |\n| total | | $5 |\n' > "$repo/docs/superpowers/plans/plan5.md"
printf '# SDD ledger — plan: docs/superpowers/plans/plan5.md\n' > "$ws5/progress.md"
out=$(env -u CLAUDE_CODE_SESSION_ID $py "$usage" "$ws5/progress.md")
[[ "$out" != *"no budget in plan"* ]] || fail "Budget table at the very start of the plan not found: '$out'"

# Regression: a subagent transcript with one invalid UTF-8 byte used to crash with
# a traceback. The corrupt byte is replaced and the report proceeds, counting the
# response like any other (spec §5 Errors): exit 0, one Spend line on stdout.
ws6="$repo/.superpowers/sdd/plan6"; mkdir -p "$ws6"
printf '# Plan\n' > "$repo/docs/superpowers/plans/plan6.md"
D="$CLAUDE_CONFIG_DIR/projects/-fake6/dddd4444"
mkdir -p "$(dirname "$D")" "$D/subagents"
: > "$D.jsonl"
printf '{"type": "assistant", "timestamp": "2026-09-11T10:00:00.000Z", "requestId": "req-s1", "message": {"id": "s1", "model": "claude-opus-5", "usage": {"output_tokens": 10000}}, "note": "bad \xff byte"}\n' > "$D/subagents/agent-x.jsonl"
printf '%s' '{"agentType": "foreman:reviewer", "description": "Review Task 1"}' > "$D/subagents/agent-x.meta.json"
printf '# SDD ledger — plan: docs/superpowers/plans/plan6.md\nSession: dddd4444\n' > "$ws6/progress.md"
out=$($py "$usage" "$ws6/progress.md")
[ "$out" = 'Spend: intake $0.25 — total $0.25 (no budget in plan)' ] \
    || fail "subagent transcript with an invalid byte: out='$out'"

# Regression: ledger times end in Z with no milliseconds (and sometimes no seconds),
# transcript times in .mmmZ, and "." sorts before "Z", so a turn inside a phase's
# first second (or minute) used to land in the phase before it.
ws7="$repo/.superpowers/sdd/plan7"; mkdir -p "$ws7"
printf '# SDD ledger — plan: docs/superpowers/plans/plan.md\nSession: eeee5555\nPhase: execution 2026-09-11T11:00Z\nPhase: qa 2026-09-11T11:30:00Z\n' > "$ws7/progress.md"
out=$($py "$usage" "$ws7/progress.md")
[ "$out" = 'Spend: final-review $0.10 of $38.00 — total $0.15 of $159.00' ] || fail "turn in the phase's first second: out='$out'"
grep -qF '| execution | $50.00 | $0.05 |' "$ws7/spend.md" || fail "minute-precision phase line: $(grep '^| execution' "$ws7/spend.md")"

# A phase with no Budget row prints its actual alone; the total still shows its estimate.
ws8="$repo/.superpowers/sdd/plan8"; mkdir -p "$ws8"
printf '# Plan\n\n## Budget\n\n| Phase | Counts | Estimate |\n|---|---|---|\n| intake | x | $10 |\n| total | | $30 |\n' > "$repo/docs/superpowers/plans/plan8.md"
printf '# SDD ledger — plan: docs/superpowers/plans/plan8.md\nSession: bbbb2222\nPhase: qa 2026-09-11T11:00:00Z\n' > "$ws8/progress.md"
out=$($py "$usage" "$ws8/progress.md")
[ "$out" = 'Spend: final-review $0.01 — total $0.01 of $30.00' ] || fail "phase without a Budget row: out='$out'"

rm -rf "$tmp"
echo "usage.py test: OK"
