# AIConsumeStatusBar

[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](https://www.swift.org)
[![Platform: macOS 13+](https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey?logo=apple)](https://www.apple.com/macos/)
[![SwiftPM](https://img.shields.io/badge/SwiftPM-compatible-brightgreen?logo=swift&logoColor=white)](https://www.swift.org/package-manager/)
[![Dependencies: none](https://img.shields.io/badge/dependencies-none-brightgreen)](Package.swift)
[![Tests: Swift Testing](https://img.shields.io/badge/tests-Swift%20Testing-blue)](tests/)
[![Last commit](https://img.shields.io/github/last-commit/paraujof/AIConsumeStatusBar)](https://github.com/paraujof/AIConsumeStatusBar/commits/main)
[![Open issues](https://img.shields.io/github/issues/paraujof/AIConsumeStatusBar)](https://github.com/paraujof/AIConsumeStatusBar/issues)
[![Pull requests](https://img.shields.io/github/issues-pr/paraujof/AIConsumeStatusBar)](https://github.com/paraujof/AIConsumeStatusBar/pulls)

A tiny macOS menu bar app that shows how many **Claude Code** tokens you have used this month,
broken down by token type, plus your top 5 sessions — read entirely from the local data
Claude Code writes on your Mac.

```
[gauge] Claude total: 12.5M tokens                 ← menu bar

Total this month: 12.5M tokens
Input: 1.2M
Output: 402.1k
Cache write: 2M
Cache read: 8.9M
Top sessions this month
1. ai-consume-status-bar · 03/10/2026 09:12 · 4.1M
2. other-project · 12/10/2026 18:40 · 2.3M
…
Updated 10:45
Refresh now
Quit
```

## Why local data?

Anthropic does not offer a public API for the usage limits of Claude.ai Pro/Max subscriptions,
so this app does **not** show a "% of plan used". Instead it aggregates the token counts that
Claude Code records locally in `~/.claude/projects`. Usage from claude.ai (web, desktop,
mobile) and from other devices is not included.

## Features

- Lives only in the menu bar — no Dock icon, no window (`LSUIElement`).
- Total tokens for the **current calendar month**, resetting on the 1st (local time).
- Breakdown by token type: input, output, cache write (creation) and cache read.
- Top 5 sessions by tokens (Claude Code `sessionId`), labelled by project folder and start time.
- Refreshes on launch, every 5 minutes, on wake from sleep and on **Refresh now**;
  one refresh at a time with a 15 s timeout.
- Duplicate records (same message id + request id) are counted once; malformed lines are skipped.
- Clear failure states: `no Claude Code data found`, `permission denied`, `unreadable data`,
  `timed out` — the last good values stay visible.
- **Private by design:** no network access, no credentials, no files written, the Claude Code
  data is opened read-only and conversation content is never shown, logged or copied.

## Requirements

- macOS 13 (Ventura) or later.
- Swift 6 toolchain — Xcode **or** just the Command Line Tools (`xcode-select --install`).
- Claude Code installed and used at least once (so `~/.claude/projects` exists).

## Install and run

```sh
git clone https://github.com/paraujof/AIConsumeStatusBar.git
cd AIConsumeStatusBar

# Build the app bundle (release build, ad-hoc signed) into build/AIConsumeStatusBar.app
scripts/build-app.sh

# Run it
open build/AIConsumeStatusBar.app

# Optional: install it
cp -R build/AIConsumeStatusBar.app /Applications/
```

To start it automatically, add it under **System Settings → General → Login Items**.

For a quick run during development (without the app bundle, a Dock icon may appear):

```sh
swift run AIConsumeStatusBar
```

## Development

| Task | Command |
|---|---|
| Build | `swift build` |
| All tests | `swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing` |
| Lint | `swift format lint --strict --recursive Package.swift Sources tests` |
| Format | `swift format --in-place --recursive Package.swift Sources tests` |
| App bundle | `scripts/build-app.sh` |

The `-plugin-path` flag is only needed with the Command Line Tools: without Xcode, SwiftPM
does not find the Swift Testing macro plugin on its own. With Xcode installed, plain
`swift test` works.

### Project structure

```
Sources/
  TokenUsageCore/       Pure logic (Foundation only): parsing, aggregation, month period,
                        formatting, menu model, refresh coordinator
  TokenUsageData/       The only code that touches the disk: read-only scanner of
                        ~/.claude/projects/*/*.jsonl with a per-file cache
  AIConsumeStatusBar/   Thin AppKit shell: NSStatusItem + NSMenu, wake observer, wiring
tests/
  unit/                 Unit tests per target
  req-…/                Acceptance tests, one per scenario of the work item
docs/adr/               Architecture decision records
scripts/build-app.sh    Builds and ad-hoc signs the .app bundle
Resources/Info.plist    Bundle metadata (LSUIElement, minimum macOS)
```

Design decisions are documented in
[ADR 0001](docs/adr/0001-macos-status-bar-token-usage.md).

### Logs

The app logs only fixed event names and failure reasons:

```sh
log stream --predicate 'subsystem == "dev.pablo.AIConsumeStatusBar"'
```

## Limitations

- Claude Code's local data format is undocumented; a Claude Code update may change it. If
  nothing can be parsed, the menu shows `Update failed: unreadable data`.
- Only `~/.claude/projects` is read (`~/.config/claude/projects` and `CLAUDE_CONFIG_DIR` are not).
- Counts are an approximation of your usage, not Anthropic's billing or limit figures.
- Dates use `dd/mm/yyyy` and a 24-hour clock; the UI is English only.

## Contributing

This repository uses a multi-agent workflow for Claude Code (see `.claude/`): run
`/work <Jira key | Datadog URL | snyk:<id> | description>` to take a change from intake through
spec, design, implementation, review and QA to a pull request. Conventions live in
`.claude/skills/repo-conventions/SKILL.md`. Changes go through pull requests; `main` is never
committed to directly.

## License

No license has been chosen yet. Until one is added, all rights are reserved by the author.
