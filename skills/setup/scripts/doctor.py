#!/usr/bin/env python3
"""Report foreman prerequisites. One line per check: OK|WARN|FAIL <name>: <detail>. Always exits 0."""
import json
import os
import platform
import shutil
import subprocess

MIN_CLAUDE = (2, 1, 267)
HOME = os.path.expanduser("~")
CLAUDE_DIR = os.path.join(HOME, ".claude")
SETTINGS = os.path.join(CLAUDE_DIR, "settings.json")
ROLES = ("architect", "implementer", "reviewer", "qa")
HOOK_FILES = ("notify.sh", "session-start.sh", "selftest.sh")
counts = {"OK": 0, "WARN": 0, "FAIL": 0}


def line(level, name, detail):
    counts[level] += 1
    print("%s %s: %s" % (level, name, detail))


def load_settings():
    """Return (dict, state) where state is None, "missing", or "invalid"."""
    try:
        with open(SETTINGS) as fh:
            data = json.load(fh)
    except OSError:
        return {}, "missing"
    except ValueError:
        return {}, "invalid"
    if not isinstance(data, dict):
        return {}, "invalid"
    return data, None


def run(cmd, timeout=20):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired):
        return None


def version_tuple(text):
    for tok in text.split():
        parts = tok.split(".")
        if len(parts) == 3 and all(p.isdigit() for p in parts):
            return tuple(int(p) for p in parts)
    return None


def as_dict(value):
    return value if isinstance(value, dict) else {}


def head(path, n=5):
    """First n lines of a text file, stripped; [] when unreadable."""
    try:
        with open(path) as fh:
            return [fh.readline().strip() for _ in range(n)]
    except (OSError, ValueError):
        return []


s, state = load_settings()
if state == "invalid":
    line("FAIL", "settings-json", "%s is not a JSON object; fix it by hand before running apply-setup.py" % SETTINGS)
env = as_dict(s.get("env"))
enabled = as_dict(s.get("enabledPlugins"))
hooks = as_dict(s.get("hooks"))

if platform.system() == "Darwin":
    line("OK", "macos", platform.mac_ver()[0])
else:
    line("FAIL", "macos", "foreman supports macOS only in this version")

for tool in ("/usr/bin/osascript", "/usr/bin/caffeinate"):
    line("OK" if os.path.exists(tool) else "FAIL", os.path.basename(tool), tool)

claude = shutil.which("claude")
result = run([claude, "--version"]) if claude else None
if not claude:
    line("FAIL", "claude-version", "`claude` not on PATH")
elif result is None:
    line("WARN", "claude-version", "`claude --version` did not answer")
else:
    v = version_tuple(result.stdout + result.stderr)
    if v is None:
        line("WARN", "claude-version", "could not parse `claude --version`: %r" % result.stdout.strip())
    elif v >= MIN_CLAUDE:
        line("OK", "claude-version", ".".join(map(str, v)))
    else:
        line("FAIL", "claude-version", "%s is below %s; run `claude update`" % (".".join(map(str, v)), ".".join(map(str, MIN_CLAUDE))))


def plugin_on(prefix):
    return any(k.startswith(prefix + "@") and v for k, v in enabled.items())


line("OK" if plugin_on("superpowers") else "FAIL", "superpowers",
     "enabled" if plugin_on("superpowers") else "run: claude plugin install superpowers@claude-plugins-official")
line("OK" if plugin_on("ponytail") else "WARN", "ponytail",
     "enabled" if plugin_on("ponytail") else "optional; for the full skill run: claude plugin marketplace add DietrichGebert/ponytail && claude plugin install ponytail@ponytail")

gh = shutil.which("gh")
gh_result = run([gh, "auth", "status"]) if gh else None
if gh_result is not None and gh_result.returncode == 0:
    line("OK", "gh-auth", "logged in")
else:
    line("WARN", "gh-auth", "draft PRs at Gate 2 need `gh auth login`")

if env.get("CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS") == "1":
    line("OK", "agent-teams", "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1")
else:
    line("FAIL", "agent-teams", "not set; fix: apply-setup.py --env")

if s.get("autoContinueAtUsageLimit") is True and s.get("inputNeededNotifEnabled") is True:
    line("OK", "resilience", "autoContinueAtUsageLimit and inputNeededNotifEnabled are on")
else:
    line("WARN", "resilience", "autoContinueAtUsageLimit or inputNeededNotifEnabled off; fix: apply-setup.py --resilience")

orders = os.path.join(CLAUDE_DIR, "CLAUDE.md")
try:
    first = open(orders).readline().strip()
except OSError:
    first = ""
if first == "# Standing orders for the lead":
    line("WARN", "leftover-orders", "%s duplicates the plugin's orders; fix: apply-setup.py --migrate" % orders)

leftover_agents = [r for r in ROLES if "name: " + r in head(os.path.join(CLAUDE_DIR, "agents", r + ".md"))]
if leftover_agents:
    line("WARN", "leftover-agents", "~/.claude/agents/{%s}.md duplicate the plugin roles; fix: apply-setup.py --migrate" % ",".join(leftover_agents))


def is_leftover(hook):
    cmd = hook.get("command", "") if isinstance(hook, dict) else ""
    return "/.claude/hooks/" in cmd and os.path.basename(cmd) in HOOK_FILES


leftover_hooks = sorted({ev for ev in ("Notification", "SessionStart")
                         for group in (hooks.get(ev) or []) if isinstance(group, dict)
                         for h in (group.get("hooks") or []) if is_leftover(h)})
if leftover_hooks:
    line("WARN", "leftover-hooks", "user-level %s hooks point at ~/.claude/hooks and would fire twice; fix: apply-setup.py --migrate" % ",".join(leftover_hooks))

print("summary: %d ok, %d warn, %d fail" % (counts["OK"], counts["WARN"], counts["FAIL"]))
