---
name: pr-description
description: Template for .agents/runs/<id>/pr-description.md — source link, summary, how to test, risks and AC covered. Use when drafting a pull request description.
---

# PR description

File: `.agents/runs/<id>/pr-description.md`. The first line is the PR title; the rest is the body.

```markdown
<type>(<id>): <imperative summary, ≤ 70 chars>

## Source
- <jira|datadog|snyk|prompt>: <source_link or "direct request">
- Tracking ticket: <key or "none">
- Type / severity: <type> / <severity>

## Summary
2–4 sentences: what changed and why. Link the decision: "Design: ADR <id> (summarized below)".

## Design
3–6 bullets from adr.md Decision. For vulnerabilities: package, from → to version, upgrade/patch/mitigation.

## How to test
1. Exact commands from repo-conventions (build, AC tests in `tests/<id>/`, full suite).
2. Manual steps if any scenario needs them.

## Risks
From adr.md Consequences/Risk. "None identified" only if the ADR says so.

## Acceptance criteria covered
| Scenario | Test |
|---|---|
| <scenario title verbatim> | tests/<id>/<file>::<test name> |

## Checklist
- [ ] Conformance: APPROVED
- [ ] Tests and lint pass locally

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

Rules:
- Every AC scenario appears in the table. A scenario without a test is listed with `NOT COVERED` — never hidden.
- No claims that are not backed by an artifact in `.agents/runs/<id>/`.
- Never paste secrets, internal stack traces with tokens, or customer data from the evidence.
