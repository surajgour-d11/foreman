# Foreman Plugin Design

**Date:** 2026-09-11
**Status:** Implemented and verified 2026-09-11
**Parent design:** `docs/team-design.md`, the agent-team design this plugin packages. Nothing in the team's behaviour changes here; this document covers only distribution, prerequisites, and configuration.

## 1. Purpose

Ship the agent team as a Claude Code plugin named `foreman`, hosted in the public GitHub repo `neels-ai-msp/foreman`, which is also its own marketplace. Anyone installs with two commands.

## 2. Decisions

| Topic | Decision |
|---|---|
| Name | `foreman`. Skills appear as `/foreman:<skill>`, agents as `foreman:<role>`. |
| Hosting | One repo, both marketplace and plugin. `.claude-plugin/marketplace.json` lists `./` as the single plugin. |
| Platform | macOS only in this version. The macOS-specific parts (banner, caffeinate) exit silently elsewhere; the standing orders and ledger notice are platform-neutral and always emitted. |
| Standing orders | Fixed text, injected into every session by the SessionStart hook as `additionalContext`, the same mechanism superpowers uses. Plugins cannot ship a CLAUDE.md. |
| Configuration | Three `userConfig` booleans, all default true. Two are read by the SessionStart hook: `keep_awake` runs caffeinate; `auto_pr` off makes the hook append one sentence to the orders telling the lead to ask before pushing or opening the pull request at Gate 2. The Notification hook reads `notifications`, and off exits before doing anything. No per-role overrides: plugin agents are namespaced `foreman:<role>`, so a copied agent file becomes a different agent and is never dispatched. Per-role overrides are deferred. |
| Prerequisites | `superpowers` declared in `dependencies` in cross-marketplace form, since a bare name resolves only inside the foreman marketplace. macOS tools, `gh` auth, Agent Teams env, and the two resilience settings are checked by `/foreman:setup`, which offers to apply the settings a plugin cannot set itself. `ponytail` is optional: the implementer's prompt carries its smallest-change rule, and the doctor reports a missing ponytail as WARN with the install commands, so passing setup never requires trusting a new marketplace. |
| Trust boundary | A repo's ledger text is untrusted input. Both hooks that read it fence it as data, allow only printable ASCII and strip `"`, `<` and `>` — `session-start.sh` strips `;` as well, since it joins ledgers with `; ` — and cap what they print before it reaches the lead: `session-start.sh` fences at most five ledgers with phases cut to 120 characters, `pre-compact.sh` one ledger. The manager's unfenced startup message carries a count and no repo text at all, since prose needs no structural character to forge authority. |
| Version | `version` in `plugin.json` only, starting at `0.1.0`. Bumped on every release; users update with `claude plugin update foreman@foreman`. |
| Budget | Every plan carries a USD estimate per phase from `budget.md`; `scripts/usage.py` reports actual spend from the session transcripts into the ledger and `spend.md`. Report only, list price, no option. Design: `docs/superpowers/specs/2026-09-11-token-budget-design.md`. |
| License | MIT, so that going public needs no relicensing. Change before publishing if you prefer otherwise. |

## 3. Layout

```
foreman/
├── .gitignore               keeps .superpowers/ and Python caches out of the repo
├── .claude-plugin/
│   ├── plugin.json          name, version, dependencies, userConfig
│   └── marketplace.json     single entry, source "./"
├── agents/                  architect.md, implementer.md, reviewer.md, qa.md
├── hooks/hooks.json         SessionStart (startup|clear|compact), Notification, PreCompact
├── scripts/
│   ├── session-start.sh     orders + ledger message + caffeinate, one JSON output
│   ├── usage.py             spend report from the session transcripts
│   ├── notify.sh            macOS banner
│   ├── pre-compact.sh       compaction instructions that keep the run's state
│   └── selftest.sh          runnable check for the three hooks
├── orders.md                the standing orders, verbatim
├── budget.md                per-dispatch cost baseline and the estimating recipe
├── skills/setup/
│   ├── SKILL.md             /foreman:setup
│   └── scripts/
│       ├── doctor.py        prerequisite report
│       └── apply-setup.py   settings merge and migration
├── tests/test_setup.sh      runnable check for doctor and apply against a fake HOME
├── tests/test_usage.sh      runnable check for usage.py against fixture transcripts
├── docs/design.md           this file
├── docs/team-design.md      the parent agent-team design, copied so the repo is self-contained
├── docs/superpowers/plans/  the implementation plans
├── docs/superpowers/specs/  design documents for features after 0.1.0
├── README.md                install, update, configure, project auto-enable
├── CHANGELOG.md
└── LICENSE
```

## 4. Changes to existing files

- **Agents.** The plugin's agent files are the source of truth; the migrated originals are kept only in the migration backup. Against those originals: the reviewer and architect descriptions say "Does not edit code." instead of "Read-only." (their Bash is unrestricted), and their pair-protocol sentence names the findings file as the one file they may write; the implementer no longer preloads `ponytail:ponytail` and carries the smallest-change rule in its own prompt. Body references to role names become `foreman:architect`, `foreman:reviewer`, and so on where a role is named as a dispatch target.
- **Standing orders** (`orders.md`). Same text as the current `~/.claude/CLAUDE.md` with six edits: roles and pairs are named `foreman:<role>` wherever they are dispatch targets, "live in `~/.claude/agents`" becomes "ship with the foreman plugin", and the hook line "the SessionStart hook prints it" stays true.
- **session-start.sh.** Gains a third job: read `orders.md` from `${CLAUDE_PLUGIN_ROOT}` and include it in `additionalContext` ahead of any ledger notice. Honours `CLAUDE_PLUGIN_OPTION_KEEP_AWAKE`. Runs on `startup|clear|compact` so orders survive compaction, matching superpowers.
- **notify.sh.** Exits at once when the `notifications` option is off. Drops `idle_prompt` events: Claude Code raises one about a minute into any wait for the manager, so passing them through banners every turn and drowns the permission prompts. The banner title is `Claude Code — <dir>`, the basename of the payload's `cwd`, so a manager running a session per repo can tell which window is asking. On iTerm2 and Ghostty the banner is an OSC 9 sequence written to the terminal of the process in `CLAUDE_PID`, so clicking it switches to that session; the terminal has to be allowed to post notifications, and the sound follows its settings rather than the script's. Anywhere else — another terminal, tmux or screen, no `CLAUDE_PID` — it is an `osascript` banner, and the script exits quietly when `osascript` is absent. Control characters are stripped from the message and the repo name before either path, since on the first one they would end the sequence early. `FOREMAN_NOTIFY_DRY_RUN` prints the title and message instead of delivering; `FOREMAN_NOTIFY_TTY` delivers to that path instead of a terminal.
- **pre-compact.sh.** New. Runs on every compaction, manual or automatic, and prints instructions for the summary: keep the open run's ledger path and phase, the plan and spec paths, the branch and worktrees, pending escalations, the tier, and the last `Spend:` line; drop the intake conversation and quoted plan, spec, or review text. Silent when no team run is open.
- **hooks.json.** All three hooks reference scripts via `"${CLAUDE_PLUGIN_ROOT}"/scripts/...`.

## 5. `/foreman:setup`

Idempotent. Run once after install, again any time to re-check.

1. Runs `skills/setup/scripts/doctor.py`, which prints one line per check: Claude Code version, superpowers enabled, ponytail enabled, macOS with `osascript` and `caffeinate`, `gh auth status`, `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` in settings env, `autoContinueAtUsageLimit`, `inputNeededNotifEnabled`, and leftovers from a manual install: a `~/.claude/CLAUDE.md` starting "# Standing orders for the lead", user-level agents with the four role names, user-level Notification or SessionStart hooks pointing at `~/.claude/hooks/`.
2. Shows the report and asks the user which fixes to apply. Missing plugins get the exact install commands. Settings and leftovers are applied by `skills/setup/scripts/apply-setup.py`, which merges into `~/.claude/settings.json` preserving every other key, and moves leftovers to `~/.claude/backups/foreman-migration-<date>/` rather than deleting them.
3. Re-runs the doctor and shows the result.

## 6. Install and update

```
claude plugin marketplace add neels-ai-msp/foreman
claude plugin install foreman@foreman
/foreman:setup
```

Private repo access uses the team member's existing `gh auth login` or SSH key. Team repos can pre-register and enable the plugin for everyone who trusts the folder:

```json
{
  "extraKnownMarketplaces": { "foreman": { "source": { "source": "github", "repo": "neels-ai-msp/foreman" } } },
  "enabledPlugins": { "foreman@foreman": true }
}
```

Release: bump `version` in `plugin.json`, add a CHANGELOG entry, merge to `main`. Users run `claude plugin update foreman@foreman`.

## 7. Verification

1. `claude plugin validate .` passes.
2. `scripts/selftest.sh` passes.
3. Plugin installed on this machine from the local checkout, the manual files migrated, and the doctor reports all green. The GitHub path, including private-repo access, is exercised by the post-merge re-register.
4. A fresh session in the throwaway repo: the lead can quote the first line of its standing orders, lists `foreman:architect`, `foreman:implementer`, `foreman:reviewer`, `foreman:qa`, and a dispatched `foreman:implementer` reports that its preloaded skills are present.
5. The `keep_awake` option set to false stops caffeinate from starting.
6. The `notifications` option set to false silences the banner and nothing else.

## 8. Git flow for this repo

The first commit on `main` is the scaffold (README, LICENSE, CHANGELOG, this design, and the plan) because an empty repo has nothing to open a pull request against. Everything else lands on a branch and is delivered as a draft pull request for the manager to review and merge.

## 9. Deferred

- Per-user or per-project role overrides.
- Linux support (`notify-send`, `systemd-inhibit`).
- Templated standing orders driven by `userConfig`.
- Submission to the official Anthropic marketplace when the repo goes public.
