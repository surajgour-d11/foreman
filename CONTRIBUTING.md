# Contributing

Thanks for looking. Foreman is a Claude Code plugin — markdown, bash, and
Python from the standard library. There is no build step and no dependency
tree, so getting set up is cloning the repo.

## Before you write code

Open an issue first for anything beyond a typo. Foreman is opinionated about
process on purpose, and the most useful contribution is often a report of
where the lifecycle got in your way rather than a patch that adds a knob to
turn it off. Small, boring changes that make the existing lifecycle work
better are very welcome.

## Working on it

Install the plugin from your clone so you are running the code you are
editing:

```
claude plugin marketplace add ~/path/to/your/clone
claude plugin install foreman@foreman
```

Restart Claude Code after any change to `hooks/hooks.json` or the scripts it
points at; hooks are read once at session start.

The test scripts and what each one covers are in the
[Development](README.md#development) section of the README. Run all three
before you open a pull request. They need macOS — the hooks use `caffeinate`
and `pgrep`, and the plugin hardcodes `/usr/bin/python3` — which is also why
CI runs on `macos-latest`.

## Shape of a good pull request

- One concern per pull request. If it needs an "and" in the title, it is two.
- A test for anything with a branch or a loop in it. The existing tests are
  plain bash with `assert`-style checks; match them rather than reaching for
  a framework.
- [Conventional Commits](https://www.conventionalcommits.org) for the subject
  line: `feat:`, `fix:`, `docs:`, `chore:`, `ci:`, `test:`.
- Update `CHANGELOG.md` under an `Unreleased` heading. The maintainer bumps
  `version` in `.claude-plugin/plugin.json` at release time, not you.
- `claude plugin validate .` passes.

Documentation is part of the change, not a follow-up. If you alter the
lifecycle, `orders.md` and the README's lifecycle list both have to agree with
the code — the lead reads `orders.md` at runtime, so a stale line there is a
bug, not a typo.

## Prose style

Documents here are meant to read like a person wrote them: thin, specific, no
repetition between files. Reviewers flag padding. If a paragraph defends a
simplification rather than describing behaviour, it probably should not exist.

## Code of conduct

Participation is governed by the [Code of Conduct](CODE_OF_CONDUCT.md).
