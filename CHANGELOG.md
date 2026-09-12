# Changelog

## 0.3.0

Leaner lifecycle. Architect and implementer run on Opus. A plan is `small`
when it has at most three tasks and no task changes a public interface,
schema, or config format, migrates data, adds a dependency, or touches
auth, secrets, permissions, or crypto: one architect reviews the plan and
one reviewer the branch. qa runs alongside the final review as one
`final-review` phase; `qa` is no longer a phase and old ledgers fold it
in. Re-reviews resume the task's reviewer, role returns are capped at 25
lines, and Gate 1 asks for `/compact`. A new PreCompact hook steers every
compaction, manual or automatic, to keep the ledger path, phase, branch
and open escalations and drop the ceremony.

## 0.2.0

Token budget. Every plan ends with a USD estimate per phase from
`budget.md`; `scripts/usage.py` prices the session transcripts and appends
`Spend:` lines to the ledger; Gate 1 shows the estimate and Gate 2 the
actual. `Phase:` ledger lines now carry a UTC time and the ledger names its
sessions.

## 0.1.0

First release. Four roles, standing orders injected per session, banner and
keep-awake hooks, `/foreman:setup` doctor and applier. macOS only.
