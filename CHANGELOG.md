# Changelog

## 0.3.4

Notifications come from Claude Code itself. The plugin's Notification hook is
gone. Claude Code already posts a desktop
notification for permission prompts, idle waits, and `PushNotification` on
iTerm2, Ghostty, and Kitty, and rings the bell on Apple Terminal, and a hook
runs alongside that rather than replacing it, so foreman's banner was a second
one for every permission prompt on the terminals that mattered.
`/foreman:setup` now reports `preferredNotifChannel` and offers to set it back
to `auto` when it is `notifications_disabled`; `/config` changes the channel.
The `notifications` option now drives Claude Code's own settings instead: on,
`/foreman:setup` turns on the phone pushes (`inputNeededNotifEnabled`,
`agentPushNotifEnabled`) and re-enables a disabled desktop channel; off, it
turns the pushes off and sets the channel to `notifications_disabled`.
Gone with the hook: the repo name in the title, and the osascript banner on
other terminals. On iTerm2, allow Notification Center alerts and
escape-sequence alerts in the profile's Terminal settings. `osascript` is no
longer a prerequisite.

## 0.3.3

The repository lives in the `neels-ai-msp` organisation. The install command,
the settings snippet, the manifests, and the security advisory link all name
`neels-ai-msp/foreman`. GitHub redirects the old `surajgour1496/foreman` URLs,
but the 0.3.2 notes record that `gh` treats a redirect as a second repository,
so nothing relies on it. Existing installs must re-register the marketplace:
`claude plugin marketplace remove foreman`, then add `neels-ai-msp/foreman` and
install `foreman@foreman` again. Removing the marketplace resets `keep_awake`
and `auto_pr` to their defaults.

Clicking the banner goes back to the session that raised it. On iTerm2 and
Ghostty the notification is posted by the terminal itself, which attributes it
to the tab or split that wrote it; the osascript banner belongs to Script
Editor, so clicking it opened Script Editor and left you to find the window
yourself. The terminal has to be allowed to post notifications, and the sound
is whatever it is set to. Other terminals, and tmux or screen inside either,
get the osascript banner as before. Control characters are removed from the
message and the repo name on every path; accented and non-Latin text is kept.
A new `notifications` option, default on, silences the banner and nothing else.

## 0.3.2

The banner names the repo it came from: the title is now `Claude Code — <dir>`,
taken from the hook payload's `cwd`. One session per repo is the normal way to
run foreman, and a bare "Claude Code" banner gave no clue which window wanted
you.

The repository URLs name the renamed GitHub account, `surajgour1496`. Every
link had been relying on GitHub's redirect from the old `surajgour-d11`, which
broke `gh` when it resolved the two names as separate repositories.

Contribution guidelines for the repo going public: `CONTRIBUTING.md`,
`CODE_OF_CONDUCT.md` (Contributor Covenant 2.1), `SECURITY.md` with a scope
that separates plugin bugs from Claude Code's own, issue forms for bugs and
ideas, and a pull request template. No change to the plugin itself.

## 0.3.1

The banner hook ignores idle prompts. Claude Code raises a Notification
about a minute after any turn the manager has not replied to, so a session
left to read produced a banner per turn and buried the permission prompts
that matter. Only permission prompts and foreman's own pushes ring now.

## 0.3.0

Leaner lifecycle. Architect and implementer run on Opus. A plan is `small`
when it has at most three tasks and no task changes a public interface,
schema, or config format, migrates data, adds a dependency, or touches
auth, secrets, permissions, or crypto: one architect reviews the plan and
one reviewer the branch. qa runs alongside the final review as one
`final-review` phase; `qa` is no longer a phase and old ledgers fold it
in. Re-reviews resume the task's reviewer, role returns are capped at 25
lines, and Gate 1 asks for `/compact`. A new PreCompact hook steers every
compaction, manual or automatic, to keep the ledger path, phase, branch
and open escalations and drop the ceremony.

## 0.2.0

Token budget. Every plan ends with a USD estimate per phase from
`budget.md`; `scripts/usage.py` prices the session transcripts and appends
`Spend:` lines to the ledger; Gate 1 shows the estimate and Gate 2 the
actual. `Phase:` ledger lines now carry a UTC time and the ledger names its
sessions.

## 0.1.0

First release. Four roles, standing orders injected per session, banner and
keep-awake hooks, `/foreman:setup` doctor and applier. macOS only.
