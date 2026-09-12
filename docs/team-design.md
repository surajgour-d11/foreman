# Agent Team Design

> This is the design the foreman plugin packages. Sections 11 to 14 describe the original manual install on the author's machine; the plugin's hooks, agents, and `/foreman:setup` replace those files.

**Date:** 2026-09-10
**Status:** Implemented and verified 2026-09-11. All section 12 checks passed.
**Scope:** User-level Claude Code configuration (`~/.claude`), every project on this machine

## 1. Purpose

Run the local Claude Code setup as a software team with the user as
manager. The manager sets requirements, approves the plan, reviews the
finished branch, and answers escalations. A lead session plus four named
roles do everything in between, unattended, and survive interruptions
without losing work.

## 2. Requirements

| # | Requirement | Decision |
|---|---|---|
| R1 | Manager gates | Two: approve the plan (Gate 1), review the finished branch (Gate 2). Everything between runs unattended. |
| R2 | Escalation | Behaviour-changing decisions stop the team and notify the manager, the way a developer asks a manager. |
| R3 | Roster | architect, implementer, reviewer, qa. The lead is the session itself. Up to three implementers run in parallel when the plan splits cleanly. |
| R4 | Peer review | Plan review and final code review by one reviewer for a small feature, and by pairs that confer and return one joint report for a standard one. |
| R5 | Notification | macOS banner plus Claude Code push. |
| R6 | Models | architect, implementer, and reviewer on Opus. qa on Sonnet. The lead is the session model. |
| R7 | Integration | Layer on the installed superpowers and ponytail plugins without forking their skills. |
| R8 | Resilience | Survive network disconnect, laptop sleep, usage limits, and laptop shutdown with no lost work and a deterministic resume. |
| R9 | Quality | Thin documents, lean comments, clean commit history, update in place instead of appending. |
| R10 | Budget | Every plan carries a USD estimate per phase; the lead reports actual spend against it in the ledger and at Gate 2. Report only. |

## 3. Architecture

Three layers:

1. **Harness.** Claude Code 2.1.267: subagents from `~/.claude/agents/*.md`,
   Agent Teams (experimental, env-enabled) for teammates that can message
   each other, hooks in `~/.claude/settings.json`.
2. **Process.** superpowers skills (brainstorming, writing-plans,
   subagent-driven-development or SDD, test-driven-development,
   verification-before-completion, finishing-a-development-branch) and
   ponytail. Unchanged.
3. **Team.** This design: four agent files, a user-level `CLAUDE.md` with
   the lead's standing orders, three hooks, one env var.

The team layer changes the process layer only through the lead's
standing orders, which win over plugin skill text where they conflict.

**Execution modes.** Teammates are used only where peers must talk: the
architect pair and the final reviewer pair of a standard feature.
Everything else is an ordinary subagent. Teammates run in-process
(Ghostty, no tmux).

**When the team model applies.** Feature work: anything that goes
through brainstorming or has a plan. Questions, one-file fixes, and
explicit "just do it" requests are handled directly by the lead. The
escalation list and notification hooks apply always.

## 4. Lifecycle and gates

```
intake → spec → plan → plan review → GATE 1 → execution
→ verification (qa with the final review) → GATE 2 (draft PR)
```

1. **Intake.** Lead runs superpowers:brainstorming with the manager and
   writes the spec.
2. **Plan.** Lead runs superpowers:writing-plans, marking any group of
   tasks with disjoint files and no ordering dependency as a parallel-safe
   batch, then creates the plan's workspace and ledger (section 8.1).
   The plan ends with a Budget table; see
   `docs/superpowers/specs/2026-09-11-token-budget-design.md`. The lead
   decides the tier: small when the plan has at most three tasks and no
   task changes a public interface, schema, or config format, migrates
   data, adds a dependency, or touches auth, secrets, permissions, or
   crypto; otherwise standard. Count deliverables, not headings: if a
   task would still make sense split in two, count it as two. The ledger
   records it.
3. **Plan review.** One architect for a small plan, the architect pair
   (section 6) for a standard one, returns one verdict. Lead fixes
   blocking issues and agreed recommendations, records rulings on the
   rest.
4. **Gate 1.** Lead notifies the manager and presents a short summary,
   the tier and why, the budget total and per-phase estimates, the
   architects' verdict and manager questions, and the plan's file path.
   Never the plan inline. Asks the manager to run `/compact` before
   approving, so the intake conversation does not ride along for the
   rest of the run. Waits.
5. **Execution.** SDD, with every implementer dispatch using the
   `implementer` role and every per-task review a single `reviewer`.
   Pairs are reserved for steps 3 and 6 of a standard feature. Dispatch
   prompts name the brief file, never the task text. A re-review resumes
   the task's reviewer with the fix range. A task failing review twice
   escalates (trigger 7).
   **Parallel batches.** When the plan marks a group of tasks
   parallel-safe (disjoint files, no ordering dependency; the architects
   verify this), the lead dispatches up to three implementers at once,
   each in its own worktree on a task branch off the plan branch. Each
   branch gets its single review, then the lead merges them into the
   plan branch in task order. A merge conflict means the batch was not
   clean: one implementer rebases the conflicting branch onto the merged
   result, recorded as a ruling; failing twice escalates.
6. **Verification.** Lead squashes `wip:` commits to one commit per task,
   then dispatches `qa` and the final review together on the branch: one
   `reviewer` (lens solo) for a small feature, the reviewer pair for a
   standard one. Critical and Important findings and qa's bugs go to one
   implementer fix wave, then one scoped re-review by the same reviewer
   (the primary, for a pair). qa does not run again; its `test(qa):`
   commits fold into their tasks.
7. **Gate 2.** Lead pushes the branch, opens a **draft** pull request,
   and notifies the manager with the PR link, the review verdict or
   verdicts, the qa report, the minor findings, and the last `Spend:`
   line with the `spend.md` path. The manager requests changes or marks
   it ready and merges. The push and draft PR are pre-approved by this
   design. A repo with no remote is an escalation, never a local merge.
   superpowers:finishing-a-development-branch does the mechanics.

## 5. Roles

Four files in `~/.claude/agents/`. Rules common to every role:

- Read the brief. Ask before starting if it is ambiguous. Break the work
  into a step checklist, work it in order, report steps with done marks.
- Never guess on a behaviour-changing point: return an escalation block
  (section 7) and stop. Never talk to the manager directly.
- Report in the role's fixed format, short and concrete, citing
  `file:line`, in at most 25 lines; anything longer goes in a file under
  the workspace that the return names. Write any finding you would hate
  to lose to disk first.

### 5.1 architect

| Field | Value |
|---|---|
| description | Reviews an implementation plan against its spec and the real codebase before the manager sees it. Use alone for a small plan or in pairs as teammates for a standard one, after writing-plans and before Gate 1. Does not edit code. |
| model | `opus` |
| disallowedTools | `Edit, Write, NotebookEdit` |
| color | `purple` |

**Checks:** every spec requirement has a plan step and every step traces
to the spec; steps are feasible against the actual code (read it); tasks
are sized for one implementer dispatch, oversized ones flagged for
splitting; tasks marked parallel-safe truly touch disjoint files and
have no ordering dependency; hidden behaviour changes the spec does not name; missing edge
cases, migrations, rollback; steps YAGNI would delete; test strategy
covers the risky parts; spec and plan meet section 9.

**Does not:** redesign for taste, rewrite the plan, or approve a plan
with an unanswered manager question.

```
ARCHITECT REVIEW — <lens> — <plan path>
Verdict: APPROVE | APPROVE WITH CHANGES | REJECT
Blocking:          - item — why — plan step or file:line
Recommend:         - item — why
Manager questions: - question — options — recommendation
```

### 5.2 implementer

| Field | Value |
|---|---|
| description | Implements one plan task at a time with TDD in the plan's worktree, commits, self-reviews, and reports. Use for every implementer dispatch in subagent-driven-development and for qa fix tasks. |
| model | `opus` |
| skills | `superpowers:test-driven-development`, `superpowers:verification-before-completion` |
| color | `green` |

**Rules:** step checklist first. TDD, committing after every green
(`wip:` prefix unless the step is complete) so a crash loses at most one
cycle. Comments only where the code cannot say it. No scope expansion;
files outside the task's area are touched only when unavoidable and the
report says so. Run the tests and show the output before claiming done.
Works in the plan's worktree when dispatched alone. In a parallel batch
the lead dispatches it with `isolation: worktree`, so it works on its own
task branch and reports the branch name for the lead to merge.

```
IMPLEMENTER REPORT — Task <N>: <name>
Status: DONE | BLOCKED | ESCALATION
Branch: <plan branch | task branch name>
Steps: - [x] <step> — <sha>  - [ ] <step not reached>
Tests: <command> → <pass/fail counts>
Touched outside task scope: none | <file — why>
Self-review notes: ...
[ESCALATION block if Status is ESCALATION]
```

### 5.3 reviewer

| Field | Value |
|---|---|
| description | Reviews a diff for correctness, spec compliance, and over-engineering. Use as a single subagent for every per-task review and for a small feature's final review, and in pairs as teammates for a standard feature's final review. Does not edit code. |
| model | `opus` |
| disallowedTools | `Edit, Write, NotebookEdit` |
| color | `orange` |

**Checks:** the diff does what the plan step says, no more, no less;
bugs, unhandled edge cases, error paths; whether the tests would fail if
the code were wrong; security mistakes (injection, auth, secrets, unsafe
defaults); over-engineering (speculative abstraction, dependency for a
few lines, config for constants); consistency with existing patterns;
section 9 (bloated docs, needless comments, appended-not-edited text).
Runs the tests and any read-only command.

**Does not:** edit files, approve code that faithfully implements a plan
mistake (report it under Plan findings), or nitpick style when a
formatter exists.

**Lenses** (paired reviews only; the lead picks two per feature):
`correctness` (bugs, edge cases, tests) and `simplicity` (over-engineering,
patterns, maintainability) by default; `security` for auth or secrets
work, `behaviour-preservation` for refactors, `performance` for hot
paths, `data-integrity` for migrations. Solo reviews cover correctness
and simplicity.

```
CODE REVIEW — <task N | branch> — <lens | solo> — <base>..<head>
Verdict: APPROVE | APPROVE WITH FIXES | REJECT
Critical:      - file:line — issue — fix      (wrong, unsafe, breaks spec)
Important:     - file:line — issue — fix      (fix before merge)
Minor:         - file:line — issue            (note for later)
Plan findings: - step — issue                 (the plan is wrong, not the code)
```

### 5.4 qa

| Field | Value |
|---|---|
| description | Verifies a feature works end to end by running the suite and the app, exercising it as a user, and probing edge cases. Writes failing regression tests for bugs, never fixes production code. Use after all plan tasks complete, alongside the final review. |
| model | `sonnet` |
| color | `cyan` |

**Does:** runs the full suite; finds the entry point (README, package
scripts, Makefile) and runs the app where one exists; exercises the
spec's acceptance criteria as a user would; tries invalid inputs, empty
states, boundaries, concurrency where relevant; for each bug, commits a
failing regression test with a `test(qa):` message so the lead can fold
it into its task's commit at step 6.

**Does not:** edit production code, skip a check because it looks fine,
or report PASS without the commands and output.

```
QA REPORT — <branch> — <plan path>
Verdict: PASS | FAIL
Suite: <command> → <result>
App run: <how launched> → <observed> | not applicable — <why>
Acceptance criteria: - <criterion> — PASS | FAIL — <evidence>
Bugs: - <title> — repro steps — regression test <path> — commit <sha>
```

## 6. Peer review protocol

Standard tier only: the architect pair (step 3) and the final reviewer
pair (step 6). Both members come from the same agent file, spawned as
teammates named `<role>-1` (primary) and `<role>-2` (secondary). The
spawn prompt gives each: the artifact (spec and plan paths, or base and
head commits), the peer's name, its lens, its role in the pair, and the
workspace path for findings. The lead picks two different lenses per
feature and records them in the ledger.

1. **Independent.** Review alone. Write the findings list to
   `<workspace>/reviews/<phase>-<name>.md` before sending any message.
2. **Exchange.** Send the list to the peer; answer the peer's list item
   by item: `agree`, `disagree — <reason>`, or `manager — <why only they
   can decide>`. At most two rounds.
3. **Joint report.** Primary writes it in the role's format plus
   `Disputed:` (both positions) and `Manager questions:`. Secondary
   replies `confirm` or sends amendments. Primary saves it to
   `<workspace>/reviews/<phase>-joint.md`, sends it to the lead, and
   both finish.

Findings files are written with a shell heredoc, since the Write tool is
disabled for these roles. Messages cross in flight; a member whose
question the peer has already answered treats the round as closed.
A finding is never dropped to reach agreement; unresolved after two
rounds ships as Disputed and the lead rules or escalates. One report,
one author. If a member dies, the lead respawns it with the same name;
it skips phase 1 if its findings file exists.

## 7. Escalation

The lead escalates to the manager on any of these, from any role or its
own work:

1. User-visible behaviour the approved spec or plan does not describe.
2. Deviating from the approved plan: skipping, replacing, or materially
   reordering a step.
3. Changing or removing a public interface, API contract, schema, or
   config format; any data migration.
4. Adding a dependency or external service, including dev-only and
   test-only ones.
5. Anything touching authentication, secrets, permissions, or crypto.
6. A requirement with two readings that lead to materially different
   work.
7. A task that fails review or qa twice in a row. Two is a starting
   value, to be tuned after a few features.
8. SDD's own stops: irreversible or destructive operation,
   security-sensitive action, side effect outside the worktree (merge,
   publish, any push other than the Gate 2 draft PR), or a plan so
   broken every path is a guess.

Everything else gets a ruling under SDD's "rulings, not stalls" rule,
recorded in the ledger. This list supersedes that rule where they
conflict.

**Escalation block** (a role returns this and stops):

```
ESCALATION
Trigger: <number and name>
Question: <one sentence>
Options: A) ... B) ... [C) ...]
Recommendation: <letter> — <why>
Cost if wrong: <what gets redone>
```

**Lead procedure.** Confirm the trigger applies; if the approved spec or
plan already answers it, rule, record `Ruling:` in the ledger, resume.
Otherwise append `Escalation: <question> — pending` to the ledger, call
`PushNotification` with one line leading with the decision needed, ask
the manager with `AskUserQuestion` (question, options, recommendation,
cost if wrong), wait, then append `— answered: <choice>` and resume. The
Notification hook (section 11) shows a desktop banner on every idle or
permission prompt regardless.

## 8. Resilience

All state the team needs lives on disk. Agent context is a cache. Any
interruption is recovered by resuming the session and reading disk.

### 8.1 Durable state

superpowers already keeps the spec and plan under `docs/superpowers/`,
commits in the plan's worktree, and a per-plan ledger at
`<repo>/.superpowers/sdd/<plan-basename>/progress.md` with `Task N:
complete` and `Ruling:` lines. SDD resumes at the first task without a
complete line and trusts the ledger over memory after compaction.

This design adds, inside the same workspace:

- The lead creates the workspace and ledger right after writing the plan
  (superpowers' `scripts/sdd-workspace PLAN_FILE`, first line
  `# SDD ledger — plan: <plan path>`) so SDD adopts it at execution and
  everything below has one home from plan review to done.
- Phase markers the lead writes on every transition, each followed by
  a UTC time:
  `Phase: plan-review | gate-1 | execution | final-review | gate-2 | done`,
  `Gate 1: approved <timestamp>`, `Gate 2: <decision> <timestamp>`,
  `Tier: small | standard — <why>`, `Lenses: <a>, <b>`,
  `Batch: tasks <n,m> — <branch>, <branch>`,
  `Escalation: ... — pending | — answered: ...`.
- `reviews/<phase>-<name>.md` per reviewing role and
  `reviews/<phase>-joint.md`.

The workspace is git-ignored scratch, so `git clean -fdx` destroys it;
commits survive in `git log` and only review findings would be redone.

### 8.2 Resume protocol

Run only when the manager says "resume" or "continue". A session that
starts in a repo with an unfinished ledger tells the manager about it and
waits for that word; it never resumes on its own.

1. Find `.superpowers/sdd/*/progress.md` without a `Phase: done` line.
2. Read its last `Phase:` line, `git log` on the plan branch,
   `git worktree list`, `git status` in the worktree.
3. Reconstruct: tasks complete, task mid-flight (started, not complete),
   escalation pending, pair phase (findings files present or not).
4. Report the state to the manager in five lines or fewer.
5. Continue. A pending escalation is re-asked before anything else runs.
   A dirty worktree gets an implementer told to inspect the uncommitted
   work, then continue or reset it and say which; an unmerged batch
   branch with a passed review is merged, otherwise reviewed first. An interrupted pair is
   respawned from its findings files. Otherwise resume at the named
   phase.

The SessionStart hook (section 11) tells the manager how many
unfinished ledgers the repo has and nothing else about them -- that
message is not fenced and a human reads it, so it carries no repo-written
text. The ledger paths and phases go to the lead in fenced
`additionalContext`, along with the instruction not to resume unasked;
the manager asks, and the lead names them.

### 8.3 Failure modes

| Failure | Recovery | Residual |
|---|---|---|
| Network disconnect | Claude Code retries; a long outage idles the session and the banner fires. Manager says "continue". | Manual continue |
| Laptop sleep | `caffeinate -i` tied to the session PID prevents idle sleep. Forced sleep on wake behaves like a disconnect. | Lid-close on battery needs root to prevent |
| Usage or rate limit | Claude Code waits for the reset and continues by itself (`autoContinueAtUsageLimit`); banner fires meanwhile. | Wall-clock wait |
| Context limit | Manager-run `/compact` at Gate 1, auto-compaction after. The PreCompact hook tells either summary to keep the ledger path, phase, branch and open escalations and to drop the intake conversation. The ledger is the source of truth. The lead stays small by delegating. | None expected |
| Shutdown or crash | `claude --resume`, then the resume protocol. Pairs respawn from findings files; implementer resumes from last commit plus dirty worktree. | Manual resume |
| Manager unavailable | Push reached the phone, banner on the desktop. Session waits. | Idle only |

True independence from the laptop needs cloud execution (section 13).

## 9. Quality standards

Applied by the lead in everything it writes, checked by the reviewer on
every review and by the architect on specs and plans. A violation is an
Important finding.

- **Documents** are thin, to the point, and read as if a person wrote
  them. Every important aspect once. No restating what the code or
  another document already says.
- **Comments** are lean and only where the code cannot say it. None on
  obvious changes, no banner blocks, no change history.
- **Commit history** at Gate 2 is a short sequence of meaningful
  commits, normally one per plan task. `wip:` commits are squashed before
  final review; fixups after Gate 2 are squashed into the commit they
  fix.
- **Update in place.** Edit the existing text; never append a new
  version beside it. Append only when the old information matters for a
  future decision, such as a decision record or changelog. The ledger is
  the one append-only artefact, because it is a log.

## 10. Lead standing orders (`~/.claude/CLAUDE.md`)

New file, under 80 lines, in this order: team model, when it applies,
and precedence over plugin skill text (section 3); lifecycle, one line
per step (4); dispatch mapping: when subagent-driven-development or
requesting-code-review dispatches a general-purpose implementer or
reviewer, use the named role, and pairs are teammates `<role>-1` and
`<role>-2` (5, 6); parallel batches of up to three implementers in
isolated worktrees, merged in task order (4); peer protocol in six lines (6); escalation triggers
and procedure (7); phase markers and resume protocol (8); quality in
four lines (9); what each gate presents (4).

## 11. Files and settings

| Path | Purpose |
|---|---|
| `~/.claude/agents/{architect,implementer,reviewer,qa}.md` | the four roles (section 5) |
| `~/.claude/CLAUDE.md` | lead standing orders (section 10) |
| `~/.claude/hooks/notify.sh` | reads the Notification event JSON from stdin, shows an osascript banner titled "Claude Code" with the message |
| `~/.claude/hooks/session-start.sh` | starts `caffeinate -i -w <claude pid>` if not already running for that PID; in a git repo with unfinished ledgers, emits JSON with a `systemMessage` for the manager giving the count of unfinished ledgers only, and `additionalContext` carrying the fenced ledger paths and phases and telling the lead to ask before resuming |
| `~/.claude/settings.json` | add `env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS="1"`, a `Notification` hook (no matcher) running notify.sh, a `SessionStart` hook running session-start.sh, `autoContinueAtUsageLimit: true` (native wait-and-continue after a usage limit), `inputNeededNotifEnabled: true` (native phone push when a question or permission prompt waits). `teammateMode` stays unset. Existing keys kept. |

`~/.claude` is not a git repository and holds session data, so nothing
is committed. Plans go to `~/.claude/docs/superpowers/plans/`.

## 12. Verification

On a throwaway git repo in the session scratchpad with a one-function
app, one test, and a three-task plan: tasks 1 and 2 parallel-safe, task 3
carrying a deliberate trigger-6 ambiguity. One check per mechanism:

1. **Roles load.** A fresh session lists the four roles among its agent
   types, and a dispatched role's transcript shows its configured model.
2. **Reviewer is read-only.** `reviewer` on a small diff returns the
   CODE REVIEW format and an attempted edit is denied.
3. **Pair converges.** `architect-1` and `architect-2` on the toy plan
   write two findings files, exchange at least one message, and return
   exactly one joint report.
4. **Parallel batch merges.** Tasks 1 and 2 run as two implementers in
   separate worktrees; each report names its branch and shows test
   output; both branches merge into the plan branch in order.
5. **Escalation fires.** On task 3 the implementer returns an ESCALATION
   block, the lead
   writes the pending line, the banner appears, `PushNotification` is
   called (delivery not required), and the session waits.
6. **Resume works.** Kill the session mid-task 3, start a new one. The
   hook tells the manager one ledger is unfinished and gives the lead its
   path and phase; the lead reports state and resumes without redoing
   tasks 1 and 2.
7. **Hooks are inert elsewhere.** A session in a non-git directory shows
   no hook errors, no ledger line, and caffeinate running.

## 13. Deferred

- More than three parallel implementers, if batches routinely have
  more independent tasks than that.
- Pairs on per-task reviews, if the final pair keeps catching what
  single reviews missed.
- security-reviewer, docs, release-manager, analyst roles, when the
  reviewer's security checks or the Gate 2 write-up prove thin.
- Reviewer `memory: project` for recurring codebase issues, after the
  same finding appears three times.
- Cloud execution for laptop independence, if unattended overnight runs
  become the norm.
- Auto-continue after a network drop via a polling loop, if manual
  "continue" becomes a chore. The usage-limit case is handled natively.

## 14. Assumptions

Verified during section 12 checks:

- Agent Teams stays available under the documented env var. If removed,
  pairs degrade to two sequential subagents with the lead relaying
  findings.
- Teammates spawned from an agent file inherit `tools`,
  `disallowedTools`, `model`, and body, but not `skills`; lenses are in
  the body for this reason.
- The Notification hook fires on idle and permission prompts with the
  message as JSON on stdin.
- `caffeinate -i -w <pid>` exits with the session.
