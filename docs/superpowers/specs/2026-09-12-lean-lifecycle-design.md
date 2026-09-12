# Lean Lifecycle Design

**Date:** 2026-09-12
**Status:** Approved by the manager in chat; spec and plan presented together at Gate 1
**Parent designs:** `docs/team-design.md` (the team), `docs/design.md` (the plugin), `docs/superpowers/specs/2026-09-11-token-budget-design.md` (the budget). This document changes how much process a feature gets and which models do the work. The roles, the ledger, the gates, and the budget mechanism stay.

## 1. Purpose

Priced from its transcripts, the token-budget feature (three tasks) cost $80 and about 75 machine minutes. The lead took $36 of it. The four ceremony phases took $60 against $20 for execution, and 19 of the 75 minutes were spent implementing. The causes, in order of cost:

- The implementer and the architect inherit the session model, the most expensive one, and the orders forbid the model selection the subagent-driven-development skill recommends.
- Every feature gets an architect pair, a qa pass with its own fix cycle, a reviewer pair, a fix wave, and a re-review, whatever its size.
- The lead carries the intake conversation, about 200K tokens, through sixty more turns and re-writes it to cache on every resume.
- Every re-review is a fresh dispatch that re-reads a diff the previous reviewer already had.
- qa and the final review run one after the other, each followed by a fix cycle.

## 2. Decisions

| Topic | Decision |
|---|---|
| Models | `architect` and `implementer` set `model: opus`. `reviewer` stays on Opus, `qa` on Sonnet. The orders still forbid passing a model at dispatch; the agent file is authoritative. |
| Tier | A plan is `small` when it has at most three tasks and no task changes a public interface, schema, or config format, migrates data, adds a dependency, or touches auth, secrets, permissions, or crypto. Otherwise it is `standard`. Count deliverables, not headings: if a task would still make sense split in two, count it as two. The lead decides when the plan is written, ledgers `Tier: small \| standard — <why>`, and Gate 1 shows it. |
| Small tier | Plan review by one `foreman:architect` as a plain subagent. Final review by one `foreman:reviewer`, lens `solo`. No pair protocol. |
| Standard tier | Pairs, as today. |
| Verification | After execution the lead squashes to one commit per task, then dispatches `foreman:qa` and the final review together on the branch under one phase, `final-review`. One `foreman:implementer` fix wave takes the Critical and Important findings and qa's bugs. One scoped re-review by the same reviewer (the primary, for a pair). qa does not run again: its regression tests passing in the re-review is the evidence. |
| Phases | `intake`, `plan-review`, `execution`, `final-review`. `qa` in an older ledger folds into `final-review`, as `gate-1` and `gate-2` fold today. Budget tables carry four phase rows and a total. |
| Re-review | The lead resumes the task's reviewer with SendMessage and the fix range. A fresh reviewer only when the original cannot be reached. |
| Briefs | Dispatch prompts name the brief file written by the subagent-driven-development skill's `task-brief` script, the plan path, and the report path. Never the task text. |
| Returns | Every role returns at most 25 lines. Anything longer goes in a file under the workspace that the return names. |
| Compact | At Gate 1 the lead asks the manager to run `/compact` before approving. The hook re-injects the orders on compaction and the ledger holds the state. |
| Auto-compaction | A plugin cannot start a compaction: `PreCompact` can only block one, no hook output requests one, and the lead has no way to run `/compact`. What it can do is steer the summary. A new `PreCompact` hook prints, when this repo has an open ledger, what the summary must keep (ledger path and phase, plan and spec paths, branch and worktrees, pending escalations, tier, last `Spend:` line) and what to drop (the intake conversation, quoted plan text, full findings). Claude Code merges that into the summarizer's instructions. So the manual `/compact` at Gate 1 and any automatic one mid-run both land safely, and the run survives compaction without the manager watching for it. |
| Spend | The spend script runs after every `Phase:` line only, no longer after each completed task. |
| Budget figures | Rows that move to Opus take the Fable measurement halved and say so; the next run's `spend.md` corrects them. The recipe gains the small tier and folds qa into final-review. |

## 3. What the manager sees

- Gate 1 names the tier and the reason, and asks for `/compact` before approval.
- Gate 2 presents one review verdict for a small feature, two for a standard one, and the qa report as today.
- Every `Spend:` line and `spend.md` has four phase rows.

## 4. Files

- `orders.md`: tier, small and standard paths, verification phase, reviewer resume, brief-by-file, return cap, compact request, spend at phase lines only. Stays under 80 lines.
- `hooks/hooks.json`, `scripts/pre-compact.sh`: the `PreCompact` hook, no matcher so it covers both triggers. Silent outside a repo and when every ledger is done, which also means silent inside a worktree, where the git-ignored workspace does not exist; that is the right answer, since only the lead's session is compacted. Ledger text reaching the summarizer is untrusted, so it goes inside an `<untrusted-ledger-data>` fence with control bytes, angle brackets and double quotes stripped and the phase line cut to 120 characters, the same treatment `session-start.sh` gives the same data. `scripts/selftest.sh` covers the shape, the silent cases and a hostile ledger that tries to close the fence, break out of a quote and smuggle a C1 control byte.
- `budget.md`: models, halved Opus figures marked estimated, recipe with the small tier and four phases.
- `agents/architect.md`, `agents/implementer.md`: `model: opus`. All four agent files: the return cap. `agents/reviewer.md`: resumed re-review and a solo findings path. `agents/architect.md`: four-phase Budget check, a solo findings path, and one bullet checking the lead's tier against the rule in `orders.md`, since a wrong tier silently removes a review seat.
- `scripts/usage.py`: `PHASES` without `qa`, `FOLD` with `qa`. `tests/test_usage.sh`: fixtures and expectations follow.
- `docs/team-design.md`, `README.md`, `CHANGELOG.md`, `.claude-plugin/plugin.json` (0.3.0); one Status line in the token-budget spec pointing here for the phase list.

## 5. Out of scope

- Plans still carry the full code of each step; the writing-plans skill owns that.
- The lead's model is the session model.
- Per-task review stays one reviewer per task.

## 6. Verification

1. `scripts/selftest.sh`, `tests/test_usage.sh`, `tests/test_setup.sh`, and `claude plugin validate .` pass.
2. This feature runs under its own rules by a ledgered ruling: small tier, qa in parallel with a solo final review. Its `spend.md` is the first measurement of the small tier and feeds the next `budget.md` correction.
