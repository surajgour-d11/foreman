#!/bin/bash
# Foreman Notification hook: show the event message as a macOS banner.
msg=$(/usr/bin/python3 -c '
import json, sys
try:
    print((json.load(sys.stdin).get("message") or "").replace("\n", " "))
except Exception:
    pass
' 2>/dev/null)
[ -z "$msg" ] && msg="Claude Code needs you"

if [ -n "${FOREMAN_NOTIFY_DRY_RUN:-}" ]; then
  echo "$msg"
  exit 0
fi
[ -x /usr/bin/osascript ] || exit 0
/usr/bin/osascript -e 'on run argv' \
  -e 'display notification (item 1 of argv) with title "Claude Code" sound name "Glass"' \
  -e 'end run' -- "$msg" >/dev/null 2>&1
exit 0
