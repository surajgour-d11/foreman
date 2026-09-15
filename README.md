# Foreman

Run Claude Code as a small software team that reports to you. You are the
manager. Claude is the lead, and it dispatches four specialist roles —
architect, implementer, reviewer, qa — through a fixed lifecycle with two
approval gates, escalation to your desktop, a running cost report, and state
that survives compaction, crashes, and quitting for the day. The full design
is in [docs/team-design.md](docs/team-design.md); the lead's standing orders
are [orders.md](orders.md).

Foreman applies to feature work — anything that goes through brainstorming or
has a plan. Questions, one-file fixes, and "just do it" requests are still
answered directly by the session you are talking to.

## The lifecycle

1. **Intake.** The lead brainstorms with you, then writes a spec.
2. **Plan.** A task-by-task plan, with a per-phase dollar budget and a tier:
   `small` (at most three tasks, nothing touching a public interface, schema,
   config format, migration, dependency, auth, secrets, or crypto) or
   `standard`. Tier decides how much review the work gets.
3. **Plan review.** One architect for a small plan, a reviewing pair for a
   standard one, checking the plan against the spec *and the real code* before
   you ever read it.
4. **Gate 1 — your approval.** You get a short summary, the tier and why, the
   budget, the architects' verdict, open questions, and the plan path. Nothing
   is built until you say go.
5. **Execution.** One implementer per task, working test-first in the plan's
   worktree; one reviewer per task, immediately after. Failed review goes back
   to the same reviewer that raised it, not a fresh one.
6. **Verification.** History squashed to one commit per task, then qa and the
   final review run together on the branch. Critical and Important findings
   and qa's bugs go to a single fix wave, then one scoped re-review.
7. **Gate 2 — handoff.** A draft pull request, the review verdicts, the qa
   report, the minor findings, and what the run actually cost.

## The roles

| Role | Model | Does | Cannot |
|---|---|---|---|
| `architect` | Opus | Reviews a plan against the spec and the codebase; opens the files the plan names instead of assuming | Edit anything |
| `implementer` | Opus | Implements exactly one task, TDD, smallest change that works, commits and self-reviews | Pick the next task, widen this one, or decide behaviour the plan left open |
| `reviewer` | Opus | Reviews a diff for correctness, spec compliance, security, and over-engineering; runs the tests | Edit anything |
| `qa` | Sonnet | Runs the suite, launches the app, walks the acceptance criteria as a user, probes edge cases, commits failing regression tests for bugs | Touch production code, or pass without evidence |

Each role returns at most 25 lines; anything longer goes to a file the return
names. The lead reads the summary, not a transcript.

## What it gives you

- **Two gates, and nothing built behind your back.** Plan approval before any
  code, a draft PR at the end — never a merge.
- **Peer review in pairs.** Standard-tier plan and final reviews run two
  reviewers as teammates with different lenses (correctness and simplicity by
  default; security, behaviour-preservation, performance, or data-integrity
  when the work calls for it). They reconcile into one joint report, and the
  lead rules on what they dispute.
- **Parallel execution.** Tasks the plan marks as a parallel-safe batch run up
  to three implementers at once, each in its own git worktree, reviewed per
  branch and merged in task order.
- **Escalation instead of guessing.** Eight triggers — unspecified
  user-visible behaviour, deviating from the approved plan, an interface,
  schema or config change, a data migration, a new dependency, anything
  touching auth, secrets or crypto, an ambiguous requirement, and a task that
  fails review twice — stop the run and ask you, with options and a
  recommendation. Everything else the lead decides and records.
- **Cost, per phase and actual.** Every plan ends with an estimated budget
  built from measured runs ([budget.md](budget.md)). After each phase the
  spend script prices the real transcripts of the lead and every subagent, so
  Gate 2 shows what the feature cost against what it was estimated at. The
  budget never stops or shrinks the work; it only informs you.
- **Work that survives interruption.** Every phase transition, ruling,
  escalation, and spend line goes to an append-only ledger in the repo. Quit,
  crash, or compact, and the state is on disk.
- **Compaction that keeps the run.** The `PreCompact` hook tells the summary
  what to keep (ledger, phase, plan, spec, branch, worktrees, pending
  escalations, spend) and what to drop (the intake chatter and quoted
  documents that live on disk anyway).
- **Resume on your word only.** Open a repo with unfinished team work and the
  session says so in one line, then does whatever you asked. It picks the run
  back up when you type `resume` — reading the ledger and git, not its memory
  of the conversation.
- **Desktop notifications.** A macOS banner when Claude Code needs a
  permission decision or the lead needs you, titled with the repo it came from.
  Idle nags are suppressed.
- **No idle sleep.** Your Mac stays awake for the life of the session, so
  unattended work is not cut in half by the lid closing.

## Requirements

macOS. Claude Code 2.1.267 or newer. The `superpowers` plugin. `ponytail` is
optional: the implementer carries its smallest-change rule, and the plugin adds
the full skill. `gh` logged in, for the draft pull request at the end of each
feature.

## Install

```
claude plugin marketplace add surajgour-d11/foreman
claude plugin install foreman@foreman
```

Then, in any Claude Code session:

```
/foreman:setup
```

It checks the requirements, offers to apply the three settings a plugin
cannot set for itself, and moves any files from a manual install into a
backup folder. Restart Claude Code afterwards.

## Configure

`keep_awake` (default on) controls the caffeinate behaviour. Set it at install
with `claude plugin install foreman@foreman --config keep_awake=false`, or
change it later from `/plugin`.

`auto_pr` (default on) lets the lead push and open the draft pull request at
Gate 2 without asking. Turn it off and the lead presents the branch and waits
for your word.

Roles cannot be customised per user in this version; the lead dispatches the
plugin's own `foreman:<role>` agents. Per-role overrides are on the list for a
later release.

To enable foreman for everyone who opens a repo, add to its `.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": { "foreman": { "source": { "source": "github", "repo": "surajgour-d11/foreman" } } },
  "enabledPlugins": { "foreman@foreman": true }
}
```

## Update and remove

```
claude plugin update foreman@foreman
claude plugin uninstall foreman@foreman
```

Uninstalling leaves the settings `/foreman:setup` applied; your backups are
in `~/.claude/backups/foreman-migration-*`.

## Development

`scripts/selftest.sh` checks the hooks. `tests/test_setup.sh` checks the
setup scripts against a fake home. `tests/test_usage.sh` checks the spend
script against fixture transcripts. `claude plugin validate .` checks the
manifests. Release by bumping `version` in `.claude-plugin/plugin.json` and
adding a CHANGELOG entry.
