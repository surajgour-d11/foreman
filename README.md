# Foreman

Run Claude Code as a small software team that reports to you. Four roles
(architect, implementer, reviewer, qa), a lead with standing orders, two
approval gates, escalation to your desktop, and work that survives
interruptions. How the team works is in [docs/team-design.md](docs/team-design.md).

## Requirements

macOS. Claude Code 2.1.267 or newer. The `superpowers` plugin. `ponytail` is
optional: the implementer carries its smallest-change rule, and the plugin adds
the full skill. `gh` logged in, for installing from the private marketplace and
for the draft pull request at the end of each feature.

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

## What changes in a session

- The lead follows the standing orders in [orders.md](orders.md): plan, plan
  review by two architects, your approval, execution with per-task review,
  qa, final review by two reviewers, and a draft pull request for you.
- A macOS banner appears whenever Claude Code is waiting on you.
- Your Mac does not idle-sleep while a session is open.
- If a repo has unfinished team work, the session tells you on open, then
  does whatever you ask. It resumes only when you type `resume`.

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
setup scripts against a fake home. `claude plugin validate .` checks the
manifests. Release by bumping `version` in `.claude-plugin/plugin.json` and
adding a CHANGELOG entry.
