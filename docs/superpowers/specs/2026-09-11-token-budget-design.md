# Token Budget Design

**Date:** 2026-09-11
**Status:** Approved by the manager; corrected after plan review (pricing rule, figures, cross-check)
**Parent designs:** `docs/team-design.md` (the team), `docs/design.md` (the plugin). This document adds one behaviour to the team: every plan carries a spend estimate, and the lead reports actual spend against it. Nothing else in the lifecycle changes.

## 1. Purpose

Feature work through foreman costs real money, and today nobody sees the number until the bill. Priced from its transcripts at list price, the foreman plugin build (seven tasks) cost about $104: $60 for the lead's 189 API calls and $44 for thirty-five subagent dispatches. Claude Code's own count for that session was $121; the difference is calls that never land in a transcript. Most of the lead's cost is the growing context re-read on every call. A budget makes the cost visible before the work starts and comparable after it ends, so that waste shows up as a number the manager can act on.

## 2. Decisions

| Topic | Decision |
|---|---|
| Overrun | Report only. The budget never stops, pauses, or narrows a run. Overruns are for the manager to read at Gate 2 and in the ledger. |
| Unit | USD at Anthropic list price, computed from the usage counts in the transcripts. Raw token counts appear in the detail file. |
| Who estimates | The lead, while writing the plan, from a baseline table shipped with the plugin. The architect pair checks the arithmetic in plan review. |
| Who measures | A stdlib Python script in the plugin that the lead runs at each ledger transition. No new hooks. The Agent tool result and the completion notice carry no spend figure, and the figure in the notice is the agent's final context size, not its cumulative usage, so transcripts on disk are the only source. |
| Granularity | Estimates per phase: intake, plan-review, execution, qa, final-review. Actuals per phase, per role, and per task, lead included. |
| Configuration | None. The feature is cheap and report-only, so it has no on/off switch. |
| Sessions | A feature may span several sessions. The ledger names them; the script sums them. |

## 3. What the manager sees

- The plan ends with a `## Budget` table: one row per phase with what it counts and a USD estimate, and a total row.
- Gate 1 presents the total and the per-phase estimates alongside the architects' verdict.
- Gate 2 presents the last `Spend:` line (actual versus estimate) and the path of `spend.md`, which holds the per-phase, per-role, per-task breakdown and the three largest line items.
- Between gates, every ledger transition appends one `Spend:` line, so the ledger reads as a running total.

## 4. Estimating

### 4.1 The Budget table

Written by the lead as the last section of every plan:

```
## Budget

| Phase | Counts | Estimate |
|---|---|---|
| intake | 50 lead calls | $18 |
| plan-review | 2 architects, 10 lead calls | $16 |
| execution | 4 tasks | $20 |
| qa | 1 pass, 1 fix cycle, 5 lead calls | $4 |
| final-review | 2 reviewers, 1 fix wave, 15 lead calls | $16 |
| total | | $74 |
```

The first cell is the phase name as the ledger spells it; the last cell is a dollar amount. Everything else is free text for the manager and the architects.

### 4.2 `budget.md`

The baseline lives at the plugin root so it is versioned with the roles it describes, and its figures live there only. It names the sessions the ranges were measured from, then holds one table, one row per kind of dispatch (architect pair member, implementer task, implementer fix round, reviewer task, reviewer re-review, final reviewer pair member, final fix wave, qa pass, and one lead API call) with the model, the measured range at list price, and the budget figure to multiply by. Below it, the recipe: per phase, which figures to multiply by which counts, with starting guesses for the lead's calls per phase, the least certain input.

The lead rounds to whole dollars and copies the total into the Gate 1 summary. The architects' check is arithmetic: every phase present, every count in the Counts cell multiplied by the right baseline figure and rounded to the nearest dollar, total equal to the sum. A missing phase or a wrong sum is Blocking. Whether the estimate is generous or tight is the manager's call at Gate 1, not the architects'.

## 5. Measuring: `scripts/usage.py`

Invocation: `usage.py LEDGER`. Python 3.9, standard library only, one file.

**Sessions.** Every `Session: <id>` line in the ledger. With none, `$CLAUDE_CODE_SESSION_ID`. Each session's main transcript is `${CLAUDE_CONFIG_DIR:-~/.claude}/projects/*/<id>.jsonl`, matched by glob because the project directory is named after the session's working directory, which is not always the repo root. Its subagents are the `agent-*.jsonl` files under `<same directory>/<id>/subagents/`, each with an `agent-*.meta.json` sidecar.

**One turn per API response.** Claude Code writes one `assistant` record per content block of a response, all with the same `message.id` and `requestId`. Input and cache counts repeat identically across them; `output_tokens` is final only on the last. The script keeps the last record per `(message.id, requestId)` and prices it once. Summing every record over-counts by two to three times.

**Pricing.** Dollars per million tokens by the model's prefix, so a variant such as `claude-opus-5[1m]` prices as its base model:

| Model prefix | Input | Output | Cache read | Cache write 5 min | Cache write 1 hour |
|---|---|---|---|---|---|
| `claude-fable-5-1` | 10 | 50 | 0.25 | 12.50 | 20 |
| `claude-opus-5` | 5 | 25 | 0.50 | 6.25 | 10 |
| `claude-sonnet-5` | 2 | 10 | 0.20 | 2.50 | 4 |
| `claude-haiku-4-5` | 1 | 5 | 0.10 | 1.25 | 2 |

Cache writes use the `cache_creation.ephemeral_5m_input_tokens` and `ephemeral_1h_input_tokens` split when present, else the whole `cache_creation_input_tokens` at the 5-minute rate. Records whose model is `<synthetic>` are skipped. Any other unknown model is priced at the Fable row and listed under "unknown models" in `spend.md`, so a price table that has fallen behind over-reports rather than under-reports. There is no long-context premium on these models.

**Phases.** A turn belongs to the latest `Phase: <name> <time>` line whose time is at or before the turn's timestamp; both are ISO 8601 UTC strings and compare as text once the phase time's trailing `Z` is removed, since transcript times carry milliseconds before their `Z`. Turns before the first timed `Phase:` line are intake. Turns after `Phase: done` are dropped. `gate-1` folds into plan-review and `gate-2` into final-review, because the gates are the lead presenting those phases' results.

**Roles and tasks.** A subagent's kind is `customAgentType` from its sidecar, else `agentType`, else `other`, with any plugin namespace such as `foreman:` stripped. Plain subagents from a plugin carry the namespaced type, such as `foreman:implementer`. Teammates carry an `agentType` equal to their name, such as `architect-1`, and sometimes a `customAgentType` holding the bare role; which fields a sidecar has depends on the spawn path, so `customAgentType` wins when present. The role is the first of lead, architect, implementer, reviewer, qa that the stripped kind starts with, else the kind itself. Its task is the first `Task N` in the sidecar's `description`, case-insensitive. The lead is the main transcript.

**Estimates.** The plan path is in the ledger's first line (`# SDD ledger — plan: <path>`), relative to the repo root, which is three directories above the workspace. The script reads the plan's last `## Budget` section: rows whose first cell is a phase name or `total` and whose last cell is a dollar amount. No table, no estimates; the report still works.

**Output.** Three things, in this order:

1. `<workspace>/spend.md`, overwritten on every run. A `Sessions:` line with each session's first and last turn and, when the transcript has the `cost-state` record Claude Code writes at session end, `(Claude Code total $N)`. A `Not found:` line for transcripts that are missing. A phase table with estimate, actual, one column per role (lead, architect, implementer, reviewer, qa, then any other kinds seen) and a final column of raw token counts as `input/output/cache-read/cache-write`; every named phase has a row even at zero, then a total row. A task table with implementer, reviewer, other, and total per task number. The three largest line items, where the lead counts per phase and each subagent as one item. An `Unknown models:` line.
2. One line appended to the ledger: `Spend: <current phase> $<actual> of $<estimate> — total $<actual> of $<estimate>`. Without a Budget table: `Spend: <phase> $<actual> — total $<actual> (no budget in plan)`. When the last `Phase:` line is `done`: `Spend: done — total $<actual> of $<estimate>`. The current phase is the last `Phase:` line, folded.
3. The same line on stdout. Nothing else reaches the lead's context.

**Errors.** A session whose transcript is missing (cleaned up after `cleanupPeriodDays`, or from another machine) is listed under "not found" and the rest is reported; exit 0. A transcript with undecodable bytes is read with replacement characters and counted like any other; a corrupt line in one transcript never aborts the report. A ledger that does not exist, is not UTF-8, or has no plan line: message on stderr, exit 2, nothing written. A phase with no row in the Budget table prints its actual alone, with the total still against its estimate. The script writes only `spend.md` and the ledger, both inside the plan workspace.

## 6. Ledger and standing-orders changes

New ledger lines, all written by the lead except the last:

- `Session: <id>`, when the ledger is created and on every resume.
- `Phase: <name> <time>`, time as `date -u +%Y-%m-%dT%H:%M:%SZ`. The resume protocol reads the name as before.
- `Spend: ...`, appended by the script.

Edits to `orders.md`, in place:

1. Lifecycle step 2 gains: the plan ends with a `## Budget` table built from `budget.md`, one row per phase and a total.
2. Step 4 (Gate 1) gains: the budget total and per-phase estimates.
3. Step 8 (Gate 2) gains: the last `Spend:` line and the `spend.md` path.
4. Resilience gains one paragraph: the `Session:` line, the timestamp on `Phase:` lines, running `usage.py <ledger>` after every `Phase:` line and every `Task N: complete` (the gates are `Phase:` lines, so they are covered), and dispatch descriptions for implementers and reviewers starting with `Task N:`.
5. One sentence: the budget is information; never stop, wait, or cut scope because of it.

`orders.md` stays under 80 lines.

## 7. Hook and agent changes

- `scripts/session-start.sh`: a finished ledger is one whose last `Phase:` line starts with `Phase: done`, not equals it. The injected orders gain one line naming `<plugin root>/budget.md` and `<plugin root>/scripts/usage.py`, because the lead cannot otherwise know the plugin's path; the root is the directory of the orders file the hook already reads.
- `scripts/selftest.sh`: a `Phase: done 2026-09-11T12:00:00Z` ledger is not reported; the injected orders name both paths.
- `agents/architect.md`: one check line for the Budget table, per section 4.2, and the `budget.md` path added to what the spawn prompt names; the orders' Pairs paragraph tells the lead to pass it to each architect.

## 8. Files

```
budget.md                      baseline table and recipe (new)
scripts/usage.py               spend report (new)
tests/test_usage.sh            fixtures and checks for usage.py (new)
orders.md                      section 6 edits
agents/architect.md            section 7
scripts/session-start.sh       section 7
scripts/selftest.sh            section 7
README.md                      a Budget bullet under "What changes in a session"; test_usage.sh in Development
CHANGELOG.md                   0.2.0 entry
.claude-plugin/plugin.json     version 0.2.0
docs/design.md                 layout tree and one Decisions row
docs/team-design.md            one row in section 2, three sentences in section 4, one line in section 8
```

## 9. Verification

1. `tests/test_usage.sh`: fixture transcripts written into a temp `CLAUDE_CONFIG_DIR` with two sessions, timestamped phases including a gate, a lead on Fable, one response written as three records with growing `output_tokens` (so per-record summing and first-record pricing both fail), one Opus subagent whose sidecar has only an `agentType` of `reviewer-task-2` and a `Task 2` description, one subagent on an unknown model typed `foreman:implementer`, one `<synthetic>` record, one unparsable line, a `cost-state` record, a ledger that names one session twice, and a plan with a superseded Budget table before the real one and another section after it. Asserts the phase and task totals to the cent against hand-computed figures, the Claude Code total on the Sessions line, the unknown-model listing, the `Spend:` line appended exactly once per run, `spend.md` overwritten not appended, `Phase: done` dropping later turns, a missing subagents directory tolerated, a plan without a Budget table reported without estimates, the session-id fallback, a missing transcript listed under "not found" with exit 0, and exit 2 with nothing written for a bad ledger.
2. `usage.py` on a ledger naming the build session `b26d3e91` reproduces the design-time figures: lead $60.01, subagents $44.12, total $104.12, with Claude Code's own total $121.37 on the Sessions line.
3. `usage.py` on the smoke session `8f426bbe` reports $9.28 against Claude Code's `cost-state` total of $9.83. The script's figure is expected to be lower by roughly five to fifteen percent: Claude Code also counts calls that never land in a transcript. Per model, where every call is in the transcript, the two agree to the cent.
4. `scripts/selftest.sh`, `tests/test_setup.sh`, `tests/test_usage.sh`, and `claude plugin validate .` pass.
5. This feature's own plan carries the first Budget table, and its Gate 2 presents the first real `Spend:` line. After the qa phase the lead replaces the unmeasured qa figure in `budget.md` with the measured one from `spend.md`.

## 10. Deferred

- Deriving `budget.md` figures automatically from past transcripts, when hand-updating the table gets stale.
- Any warning or stop on overrun. The manager chose report-only.
- Price overrides for Bedrock, Vertex, or contract pricing.
- A per-repo baseline override, if one team's tasks run consistently larger than the plugin's figures.
- Splitting the lead's spend by task inside execution, if per-task totals turn out to hide where lead calls go.
