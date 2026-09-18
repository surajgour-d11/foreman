#!/usr/bin/env python3
"""Apply the fixes the doctor cannot: settings a plugin may not set, and leftovers from a manual install.

Usage: apply-setup.py [--env] [--resilience] [--migrate] [--all] [--dry-run]
Every change is printed. Files are moved to ~/.claude/backups/foreman-migration-<stamp>/, never deleted.
Refuses to touch a settings.json that exists but is not a JSON object.
"""
import datetime
import json
import os
import shutil
import sys

HOME = os.path.expanduser("~")
CLAUDE_DIR = os.path.join(HOME, ".claude")
SETTINGS = os.path.join(CLAUDE_DIR, "settings.json")
ROLES = ("architect", "implementer", "reviewer", "qa")
HOOK_FILES = ("notify.sh", "session-start.sh", "selftest.sh")
HOOK_MARKERS = ("# Foreman", "# Claude Code ", "Runnable check for the")  # plugin copies and the manual-install headers

args = set(sys.argv[1:])
dry = "--dry-run" in args
do_env = "--env" in args or "--all" in args
do_res = "--resilience" in args or "--all" in args
do_mig = "--migrate" in args or "--all" in args
if not (do_env or do_res or do_mig):
    print(__doc__)
    sys.exit(0)

backup = os.path.join(CLAUDE_DIR, "backups", "foreman-migration-" + datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f"))


def say(msg):
    print(("would " if dry else "") + msg)


def move(src, rel):
    if not os.path.exists(src):
        return
    dst = os.path.join(backup, rel)
    say("move %s -> %s" % (src, dst))
    if not dry:
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.move(src, dst)


def is_leftover(hook):
    cmd = hook.get("command", "") if isinstance(hook, dict) else ""
    return "/.claude/hooks/" in cmd and os.path.basename(cmd) in HOOK_FILES


def option(name, default):
    """A foreman userConfig value from pluginConfigs; Bash-run scripts never see CLAUDE_PLUGIN_OPTION_*."""
    configs = s.get("pluginConfigs") if isinstance(s.get("pluginConfigs"), dict) else {}
    for k, v in configs.items():
        if k.startswith("foreman@") and isinstance(v, dict) and isinstance(v.get("options"), dict):
            return v["options"].get(name, default)
    return default


def head(path, n=5):
    """First n lines of a text file, stripped; [] when unreadable."""
    try:
        with open(path) as fh:
            return [fh.readline().strip() for _ in range(n)]
    except (OSError, ValueError):
        return []


settings_exists = os.path.exists(SETTINGS)
s = {}
if settings_exists:
    try:
        with open(SETTINGS) as fh:
            s = json.load(fh)
    except (OSError, ValueError):
        s = None
    if not isinstance(s, dict):
        print("refusing: %s exists but could not be read as a JSON object; fix it by hand first" % SETTINGS)
        sys.exit(1)
original = json.dumps(s, sort_keys=True)

if do_env:
    env = s.get("env") if isinstance(s.get("env"), dict) else {}
    if env.get("CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS") != "1":
        env["CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"] = "1"
        s["env"] = env
        say("set env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1")
if do_res:
    if s.get("autoContinueAtUsageLimit") is not True:
        s["autoContinueAtUsageLimit"] = True
        say("set autoContinueAtUsageLimit=true")
    want = option("notifications", True) is not False
    for key in ("inputNeededNotifEnabled", "agentPushNotifEnabled"):
        if s.get(key) is not want:
            s[key] = want
            say("set %s=%s" % (key, json.dumps(want)))
    channel = s.get("preferredNotifChannel") or "auto"
    if (channel == "notifications_disabled") == want:
        s["preferredNotifChannel"] = "auto" if want else "notifications_disabled"
        say("set preferredNotifChannel=%s" % s["preferredNotifChannel"])
if do_mig:
    hooks = s.get("hooks") if isinstance(s.get("hooks"), dict) else {}
    for ev in ("Notification", "SessionStart"):
        groups = hooks.get(ev)
        if not isinstance(groups, list):
            continue  # unknown shape: leave it alone
        kept_groups = []
        for group in groups:
            entries = group.get("hooks") if isinstance(group, dict) else None
            if not isinstance(entries, list):
                kept_groups.append(group)  # unknown shape: leave it alone
                continue
            for h in entries:
                if is_leftover(h):
                    say("remove user-level %s hook: %s" % (ev, h.get("command")))
            survivors = [h for h in entries if not is_leftover(h)]
            if len(survivors) == len(entries):
                kept_groups.append(group)
            elif survivors:
                kept_groups.append(dict(group, hooks=survivors))
        hooks[ev] = kept_groups

# Settings first, atomically: a failed write must not leave hook entries pointing at moved files.
if json.dumps(s, sort_keys=True) != original:
    if settings_exists:
        say("write %s (previous copy in %s)" % (SETTINGS, os.path.join(backup, "settings.json")))
    else:
        say("create %s" % SETTINGS)
    if not dry:
        os.makedirs(backup, exist_ok=True)
        if settings_exists:
            shutil.copy2(SETTINGS, os.path.join(backup, "settings.json"))
        target = os.path.realpath(SETTINGS)
        with open(target + ".tmp", "w") as fh:
            json.dump(s, fh, indent=2)
            fh.write("\n")
        if settings_exists:
            shutil.copymode(target, target + ".tmp")
        os.replace(target + ".tmp", target)

# Move only files that carry a foreman marker; a shared filename alone is not ownership.
if do_mig:
    if head(os.path.join(CLAUDE_DIR, "CLAUDE.md"), 1) == ["# Standing orders for the lead"]:
        move(os.path.join(CLAUDE_DIR, "CLAUDE.md"), "CLAUDE.md")
    for r in ROLES:
        if "name: " + r in head(os.path.join(CLAUDE_DIR, "agents", r + ".md")):
            move(os.path.join(CLAUDE_DIR, "agents", r + ".md"), os.path.join("agents", r + ".md"))
    for f in HOOK_FILES:
        if any(m in l for l in head(os.path.join(CLAUDE_DIR, "hooks", f)) for m in HOOK_MARKERS):
            move(os.path.join(CLAUDE_DIR, "hooks", f), os.path.join("hooks", f))
print("done" if not dry else "dry run, nothing changed")
