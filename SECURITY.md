# Security

## Reporting a vulnerability

Report privately through GitHub:
[open a security advisory](https://github.com/neels-ai-msp/foreman/security/advisories/new).
Please do not open a public issue for a vulnerability.

Expect an acknowledgement within a week. If the report is valid, you will get
a fix or a plan, and credit in the release notes unless you would rather not
have it.

## Scope

Foreman is a Claude Code plugin. It ships shell scripts and a Python script
that run on your machine with your permissions, hooks that fire on session
lifecycle events, and agent definitions that dispatch subagents. Worth
reporting: anything that lets repository content, a plan file, or a subagent's
output cause the hooks or scripts to execute something the user did not ask
for, or that leaks session transcripts, credentials, or environment outside
the machine.

Out of scope: the behaviour of Claude Code itself and of the models — report
those to [Anthropic](https://hackerone.com/anthropic-vdp). Prompt injection
that only steers a model's reply within the permissions the user already
granted is a limitation of the medium rather than a bug in this plugin,
though a report showing it escaping those permissions is very much in scope.

## Supported versions

The latest release only. Fixes ship forward; there are no backports.
