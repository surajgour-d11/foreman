---
name: setup
description: Check and fix the prerequisites for the foreman team plugin - required plugins, macOS tools, gh auth, Agent Teams, resilience settings, and leftovers from a manual install. Run once after installing foreman, and again whenever something seems off.
---

# Foreman setup

The scripts are in `scripts/` under this skill's base directory (the path given at the top of this skill). Call them with `/usr/bin/python3`.

1. Run `scripts/doctor.py` and show its output verbatim.
2. If the summary has no WARN or FAIL lines, say the setup is complete and stop.
3. Otherwise, for each problem the doctor can fix, ask the manager with AskUserQuestion (multiSelect) which to apply:
   - Agent Teams env var (`--env`)
   - Resilience settings (`--resilience`)
   - Move manual-install leftovers to a backup folder (`--migrate`)
   Missing plugins, an old Claude Code, an invalid settings.json, or `gh` auth cannot be fixed by the script; show the exact command or instruction from the doctor line instead.
4. Run `scripts/apply-setup.py` with the chosen flags and `--dry-run`, and show the `would ...` lines. On the manager's confirmation, run it again without `--dry-run` and show its output. Nothing is deleted; moved files land in `~/.claude/backups/foreman-migration-<stamp>/`.
5. Run the doctor again and show the result. If `--env` or `--migrate` ran, tell the manager to restart Claude Code so the env var and hook changes take effect.
