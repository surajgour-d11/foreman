#!/bin/bash
# Runnable check for /foreman:setup scripts against fake HOMEs.
set -e
here="$(cd "$(dirname "$0")/.." && pwd)"
py=/usr/bin/python3
doctor="$here/skills/setup/scripts/doctor.py"
apply="$here/skills/setup/scripts/apply-setup.py"
fail() { echo "FAIL: $1"; exit 1; }

# Fixture: a manual install plus unrelated hooks that must survive.
fake=$(mktemp -d); export HOME="$fake"
mkdir -p "$HOME/.claude/agents" "$HOME/.claude/hooks"
cat > "$HOME/.claude/settings.json" <<'JSON'
{
  "model": "keep-me",
  "enabledPlugins": {"superpowers@claude-plugins-official": true},
  "hooks": {
    "Notification": [{"hooks": [
      {"type": "command", "command": "/Users/x/.claude/hooks/notify.sh"},
      {"type": "command", "command": "/opt/mytools/pager.sh"}
    ]}],
    "SessionStart": [
      {"hooks": [{"type": "command", "command": "/Users/x/.claude/hooks/session-start.sh"}]},
      {"hooks": [{"type": "command", "command": "/Users/x/.claude/hooks/my-reminder.sh"}]}
    ],
    "PostToolUse": [{"hooks": [{"type": "command", "command": "echo keep"}]}]
  }
}
JSON
printf '# Standing orders for the lead\nold text\n' > "$HOME/.claude/CLAUDE.md"
for r in architect implementer reviewer qa; do printf -- '---\nname: %s\n---\n' "$r" > "$HOME/.claude/agents/$r.md"; done
printf '#!/bin/bash\n# Claude Code Notification hook\n' > "$HOME/.claude/hooks/notify.sh"
echo '#!/bin/bash' > "$HOME/.claude/hooks/my-reminder.sh"

report=$($py "$doctor")
echo "$report" | grep -q "^FAIL agent-teams" || fail "doctor missed agent-teams env"
echo "$report" | grep -q "^WARN resilience" || fail "doctor missed resilience settings"
echo "$report" | grep -q "^WARN leftover-orders" || fail "doctor missed CLAUDE.md leftover"
echo "$report" | grep -q "^WARN leftover-agents" || fail "doctor missed agents leftover"
echo "$report" | grep -q "^WARN leftover-hooks: user-level Notification,SessionStart" || fail "doctor missed hooks leftover"
echo "$report" | grep -q "^OK superpowers" || fail "doctor should see superpowers enabled"
echo "$report" | grep -q "^WARN ponytail: optional" || fail "missing ponytail should be a WARN"
echo "$report" | grep -qE "^summary: [0-9]+ ok, [0-9]+ warn, [0-9]+ fail$" || fail "doctor summary line missing"

before=$(cat "$HOME/.claude/settings.json")
$py "$apply" --all --dry-run | grep -q "^would " || fail "dry-run printed no would-lines"
[ "$before" = "$(cat "$HOME/.claude/settings.json")" ] || fail "dry-run changed settings"
[ -f "$HOME/.claude/CLAUDE.md" ] || fail "dry-run moved CLAUDE.md"
[ ! -d "$HOME/.claude/backups" ] || fail "dry-run created a backup dir"

chmod 600 "$HOME/.claude/settings.json"
$py "$apply" --all >/dev/null
$py - <<'PY'
import json, os, glob
s = json.load(open(os.path.expanduser("~/.claude/settings.json")))
assert os.stat(os.path.expanduser("~/.claude/settings.json")).st_mode & 0o777 == 0o600, "settings mode changed"
assert s["model"] == "keep-me"
assert s["env"]["CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"] == "1"
assert s["autoContinueAtUsageLimit"] is True and s["inputNeededNotifEnabled"] is True
assert [h["command"] for g in s["hooks"]["Notification"] for h in g["hooks"]] == ["/opt/mytools/pager.sh"], s["hooks"]
assert [h["command"] for g in s["hooks"]["SessionStart"] for h in g["hooks"]] == ["/Users/x/.claude/hooks/my-reminder.sh"], s["hooks"]
assert s["hooks"]["PostToolUse"][0]["hooks"][0]["command"] == "echo keep"
assert not os.path.exists(os.path.expanduser("~/.claude/CLAUDE.md"))
assert not os.path.exists(os.path.expanduser("~/.claude/agents/reviewer.md"))
assert os.path.exists(os.path.expanduser("~/.claude/hooks/my-reminder.sh")), "unrelated hook file moved"
backups = glob.glob(os.path.expanduser("~/.claude/backups/foreman-migration-*"))
assert len(backups) == 1, backups
for f in ("CLAUDE.md", "settings.json", "agents/reviewer.md", "hooks/notify.sh"):
    assert os.path.exists(os.path.join(backups[0], f)), f
print("apply: OK")
PY

report=$($py "$doctor")
echo "$report" | grep -q "leftover" && fail "leftovers still reported"
echo "$report" | grep -q "^FAIL agent-teams" && fail "env still reported"
echo "$report" | grep -q "^OK resilience" || fail "resilience not OK after apply"

# Idempotent: a second run changes nothing and makes no second backup.
$py "$apply" --all | grep -q "^set \|^move \|^remove " && fail "second run reported changes"
[ "$(ls "$HOME/.claude/backups" | wc -l | tr -d ' ')" = "1" ] || fail "second run created another backup"

# A CLAUDE.md that is not the standing orders must stay put.
printf '# My notes\n' > "$HOME/.claude/CLAUDE.md"
$py "$apply" --migrate >/dev/null
[ -f "$HOME/.claude/CLAUDE.md" ] || fail "unrelated CLAUDE.md was moved"

# Files that merely share a foreman name stay put; only the foreman markers move them.
printf -- '---\nname: code-reviewer\n---\n' > "$HOME/.claude/agents/reviewer.md"
printf '#!/bin/bash\n# my own notifier\n' > "$HOME/.claude/hooks/notify.sh"
$py "$doctor" | grep -q "leftover-agents" && fail "foreign reviewer.md flagged as leftover-agents"
$py "$apply" --migrate >/dev/null
[ -f "$HOME/.claude/agents/reviewer.md" ] && [ -f "$HOME/.claude/hooks/notify.sh" ] || fail "foreign reviewer.md or notify.sh was moved"
rm -rf "$fake"

# Hook groups of unknown shape are kept as they are; only leftovers go, and each removal is printed.
fake=$(mktemp -d); export HOME="$fake"; mkdir -p "$HOME/.claude"
cat > "$HOME/.claude/settings.json" <<'JSON'
{"hooks": {"Notification": [null, {"hooks": {"weird": "shape"}}],
           "SessionStart": [{"matcher": "startup", "hooks": []},
                            {"hooks": [{"type": "command", "command": "/Users/x/.claude/hooks/session-start.sh"},
                                       {"type": "command", "command": "echo keep"}]}]}}
JSON
out=$($py "$apply" --migrate --dry-run)
[ "$(echo "$out" | grep -c '^would remove')" = "1" ] || fail "dry run did not name exactly one removal: $out"
echo "$out" | grep -q '^would remove user-level SessionStart hook: /Users/x/.claude/hooks/session-start.sh$' || fail "dry run named the wrong removal: $out"
$py "$apply" --migrate >/dev/null
$py - <<'PY'
import json, os
s = json.load(open(os.path.expanduser("~/.claude/settings.json")))
assert s["hooks"]["Notification"] == [None, {"hooks": {"weird": "shape"}}], s["hooks"]
assert s["hooks"]["SessionStart"] == [{"matcher": "startup", "hooks": []}, {"hooks": [{"type": "command", "command": "echo keep"}]}], s["hooks"]
print("odd shapes: OK")
PY
rm -rf "$fake"

# Settings are written before any move, so a failed write never leaves hook entries pointing at moved files.
# ~/.claude is read-only (no settings temp file can be created there) while ~/.claude/hooks stays writable.
fake=$(mktemp -d); export HOME="$fake"; mkdir -p "$HOME/.claude/hooks" "$HOME/.claude/backups"
echo '{"hooks": {"SessionStart": [{"hooks": [{"type": "command", "command": "/Users/x/.claude/hooks/session-start.sh"}]}]}}' > "$HOME/.claude/settings.json"
printf '#!/bin/bash\n# Foreman SessionStart hook\n' > "$HOME/.claude/hooks/session-start.sh"
chmod 555 "$HOME/.claude"
$py "$apply" --migrate >/dev/null 2>&1 || true
chmod 755 "$HOME/.claude"
$py - <<'PY'
import json, os
home = os.path.expanduser("~")
s = json.load(open(home + "/.claude/settings.json"))
for ev in ("Notification", "SessionStart"):
    for g in s.get("hooks", {}).get(ev) or []:
        for h in g.get("hooks") or []:
            f = home + "/.claude/hooks/" + os.path.basename(h["command"])
            assert os.path.exists(f), "settings point at a missing hook file: " + f
assert not os.path.exists(home + "/.claude/settings.json.tmp"), "temp file left behind"
print("atomic write: OK")
PY
rm -rf "$fake"

# Fixture: an unparseable settings.json is reported, never overwritten.
fake=$(mktemp -d); export HOME="$fake"; mkdir -p "$HOME/.claude"
printf '{"model": "keep-me",}\n' > "$HOME/.claude/settings.json"
report=$($py "$doctor"); rc=$?
[ "$rc" = "0" ] || fail "doctor exited $rc on invalid settings"
echo "$report" | grep -q "^FAIL settings-json" || fail "doctor did not flag invalid settings"
echo "$report" | grep -q "^summary:" || fail "doctor summary missing on invalid settings"
if $py "$apply" --all >/dev/null 2>&1; then fail "applier accepted invalid settings"; fi
[ "$(cat "$HOME/.claude/settings.json")" = '{"model": "keep-me",}' ] || fail "applier rewrote invalid settings"

# Odd but parseable shapes must not crash the doctor or the applier.
printf '{"env": null, "hooks": {"Notification": [null]}}\n' > "$HOME/.claude/settings.json"
$py "$doctor" | grep -q "^summary:" || fail "doctor crashed on null env"
out=$($py "$apply" --all 2>&1) || fail "applier failed on null env: $out"
echo "$out" | grep -q "Traceback" && fail "applier traceback on null env: $out"
$py - <<'PY'
import json, os
s = json.load(open(os.path.expanduser("~/.claude/settings.json")))
assert s["env"]["CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"] == "1" and s["hooks"] == {"Notification": [None]}, s
PY

# An unreadable settings.json is refused, never traced back or rewritten.
chmod 000 "$HOME/.claude/settings.json"
out=$($py "$apply" --all 2>&1) && fail "applier accepted an unreadable settings.json"
echo "$out" | grep -q "^refusing:" || fail "no refusing line for unreadable settings: $out"
chmod 644 "$HOME/.claude/settings.json"
rm -rf "$fake"
echo "setup selftest: OK"
