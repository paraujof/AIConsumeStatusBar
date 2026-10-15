---
name: repo-conventions
description: Folder structure, code style, naming, and the exact commands to build, test and lint this repository. Use before writing or running any code or tests.
---

# Repo conventions

Established by the ADR of work item `req-20261015-macos-status-bar-token-usage` (Decision §12),
approved at TL_GATE on 2026-10-15. Machine toolchain: Swift 6.4 via Command Line Tools only
(no Xcode).

If a command below is still a TODO when an agent needs it, the agent writes
`BLOCKED: repo-conventions does not define <command>` and stops. Never guess a command.

## Stack
- Language / version: Swift 6 language mode (strict concurrency), `swift-tools-version: 6.0`, toolchain Swift 6.4.
- Framework / UI toolkit: AppKit (`NSStatusItem` + `NSMenu`), no SwiftUI. Minimum macOS 13.0.
- Package manager / dependency manifest: Swift Package Manager — `Package.swift`
  (`Package.resolved` only if a dependency is ever added). No third-party dependencies.
- Test framework: Swift Testing (`import Testing`). XCTest is **not** available with Command Line Tools only.

## Commands
Swift Testing's macro plugin is not found automatically under Command Line Tools
(`plugin for module 'TestingMacros' not found`). Every command that compiles tests MUST pass
the plugin path (verified 2026-10-15):

`TESTING_PLUGIN = -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing`

| Purpose | Command |
|---|---|
| Install deps | `swift package resolve` (no-op today) |
| Build | `swift build` |
| Full test suite | `swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing` |
| Run tests in one folder (`tests/<id>/`) | `swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing --filter Acceptance_<id with "-" replaced by "_">` |
| Lint | `swift format lint --strict --recursive Package.swift Sources tests` |
| Format | `swift format --in-place --recursive Package.swift Sources tests` |
| Type check (if separate) | covered by `swift build` |
| Build app bundle | `scripts/build-app.sh` |

## Folder structure
- Source: `Sources/<Target>/` (targets: `TokenUsageCore`, `TokenUsageData`, `AIConsumeStatusBar`).
- Unit tests: `tests/unit/<Target>Tests/` (owned by the implementer).
- Acceptance tests: `tests/<id>/`, one SwiftPM test target per work item named
  `Acceptance_<id with "-" replaced by "_">`, depending on every library target. The implementer
  declares the target in `Package.swift`; only ac-tester writes inside the folder.
- Only lowercase `tests/` is used (the disk is case-insensitive; never create `Tests/`).
- Architecture decisions: `docs/adr/NNNN-<slug>.md`.
- Agent run artifacts: `.agents/runs/<id>/` (gitignored, never committed).

## Style and naming
- Formatter / style guide: `swift format` with `.swift-format` at the repo root, 4-space indent, line length 120.
- File naming: one type per file, file named after the type.
- Type / function / variable naming: types `UpperCamelCase`; functions and variables `lowerCamelCase`.
- Test naming: one test per AC scenario, named after the scenario title.

## Git
- Default branch: `main`. Never commit or push to it directly.
- Branches: `feature/<id>`, `fix/<id>`, `security/<id>` (from work-item type).
- Commit messages: `<type>(<id>): <imperative summary>` (TODO(team): confirm convention).
- Remote: none configured yet — TODO(team): add `origin` on GitHub so the PR stage works.

## CI
- None yet. TODO(team): describe the pipeline (checks required to merge, preview environments).
