---
name: repo-conventions
description: Folder structure, code style, naming, and the exact commands to build, test and lint this repository. Use before writing or running any code or tests.
---

# Repo conventions

State of the repo when this was written (2026-10-15): **empty** — no commits, no source,
no build files, no CI, no CLAUDE.md, no ADRs. Machine toolchain seen: Swift 6.4 (Command
Line Tools, no Xcode) and python3. The repo name (`ai-consume-status-bar`) suggests a
macOS status-bar app, but nothing confirms the stack. Fill in every TODO before the first run.

If a command below is still a TODO when an agent needs it, the agent writes
`BLOCKED: repo-conventions does not define <command>` and stops. Never guess a command.

## Stack
- Language / version: TODO(team)
- Framework / UI toolkit: TODO(team)
- Package manager / dependency manifest: TODO(team) (Snyk vulnerabilities are fixed here)

## Commands
| Purpose | Command |
|---|---|
| Install deps | TODO(team) |
| Build | TODO(team) |
| Full test suite | TODO(team) |
| Run tests in one folder (`tests/<id>/`) | TODO(team) |
| Lint | TODO(team) |
| Format | TODO(team) |
| Type check (if separate) | TODO(team) |

## Folder structure
- Source: TODO(team)
- Tests: TODO(team) — the multi-agent flow puts acceptance tests of each work item in
  `tests/<id>/`; the test runner must discover that folder (TODO(team): confirm/configure).
- Architecture decisions: `docs/adr/NNNN-<slug>.md` (proposed; TODO(team): confirm).
- Agent run artifacts: `.agents/runs/<id>/` (gitignored, never committed).

## Style and naming
- Formatter / style guide: TODO(team)
- File naming: TODO(team)
- Type / function / variable naming: TODO(team)
- Test naming: one test per AC scenario, named after the scenario title.

## Git
- Default branch: `main`. Never commit or push to it directly.
- Branches: `feature/<id>`, `fix/<id>`, `security/<id>` (from work-item type).
- Commit messages: `<type>(<id>): <imperative summary>` (TODO(team): confirm convention).
- Remote: none configured yet — TODO(team): add `origin` on GitHub so the PR stage works.

## CI
- None yet. TODO(team): describe the pipeline (checks required to merge, preview environments).
