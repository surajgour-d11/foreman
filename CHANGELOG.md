# Changelog

## 0.2.0

Token budget. Every plan ends with a USD estimate per phase from
`budget.md`; `scripts/usage.py` prices the session transcripts and appends
`Spend:` lines to the ledger; Gate 1 shows the estimate and Gate 2 the
actual. `Phase:` ledger lines now carry a UTC time and the ledger names its
sessions.

## 0.1.0

First release. Four roles, standing orders injected per session, banner and
keep-awake hooks, `/foreman:setup` doctor and applier. macOS only.
