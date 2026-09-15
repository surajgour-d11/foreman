# Changelog

## Unreleased

The banner names the repo it came from: the title is now `Claude Code — <dir>`,
taken from the hook payload's `cwd`. One session per repo is the normal way to
run foreman, and a bare "Claude Code" banner gave no clue which window wanted
you.

Contribution guidelines for the repo going public: `CONTRIBUTING.md`,
`CODE_OF_CONDUCT.md` (Contributor Covenant 2.1), `SECURITY.md` with a scope
that separates plugin bugs from Claude Code's own, issue forms for bugs and
ideas, and a pull request template. No change to the plugin itself.

## 0.3.1

The banner hook ignores idle prompts. Claude Code raises a Notification
about a minute after any turn the manager has not replied to, so a session
left to read produced a banner per turn and buried the permission prompts
that matter. Only permission prompts and foreman's own pushes ring now.

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
