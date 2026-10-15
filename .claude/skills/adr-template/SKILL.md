---
name: adr-template
description: Templates for .agents/runs/<id>/adr.md — a full ADR for features or design-changing fixes, and a short variant for bugs and vulnerabilities. Use when writing or reviewing an ADR.
---

# ADR template

Which variant:
- `feature` → **Full**.
- `bug` → **Short**, unless the fix changes a module boundary, a public interface, a data
  model or adds a dependency → **Full**.
- `vulnerability` → **Short**, but the Decision section MUST choose upgrade, patch or
  mitigation and state its risk. Use Full if the fix needs a major-version upgrade or code redesign.

Every section is mandatory in its variant. A section with nothing to say states why
("No impact: …"); it is never left empty. Validators cite sections by their heading.

## Full

```markdown
# ADR <id>: <title>
Status: proposed
Type: feature | bug | vulnerability
Inputs: work-item.md, spec.md, acceptance.feature

## Context
Problem, forces and constraints. Cite relevant parts of spec.md and existing ADRs.

## Decision
What will be built and how: components touched, new/changed interfaces (signatures),
data flow, error handling, dependencies added or removed.

## Discarded alternatives
| Alternative | Why discarded |
|---|---|

## Consequences
- Positive:
- Negative / trade-offs:
- Risks and mitigations:
- Security considerations:
- Performance considerations:

## Impact on acceptance criteria
For every scenario in acceptance.feature: which part of the decision satisfies it.
| Scenario | Satisfied by |
|---|---|
Any scenario that cannot be satisfied is listed here as CONFLICT: <scenario> — <reason>.

## Files expected to change
- path — reason
```

## Short (bugs and vulnerabilities)

```markdown
# ADR <id>: <title>
Status: proposed
Type: bug | vulnerability

## Context
Root cause (bug) or vulnerable package/version/path and reachability (vulnerability).

## Decision
The fix. For vulnerabilities: **upgrade | patch | mitigation**, target version, and why.

## Risk
What could break (breaking changes in the upgrade, behavior change) and how it is contained.

## Impact on acceptance criteria
| Scenario | Satisfied by |
|---|---|

## Files expected to change
- path — reason
```
