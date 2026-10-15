---
name: security-review
description: Security checklist for reviewing a diff — authentication/authorization, input validation, secrets, dependencies, and sensitive data in logs. Use when reviewing a PR for security or deciding how to fix a vulnerability.
---

# Security review checklist

Review the diff against each item. A finding must cite file:line, the item below, and —
when applicable — the AC scenario or ADR section it violates. Items that do not apply
are marked `N/A` in the report, not omitted.

## Authentication and authorization
- [ ] New entry points (endpoints, URL handlers, IPC, CLI flags) enforce the same auth as existing ones.
- [ ] Authorization is checked server-side / at the trust boundary, not only in UI.
- [ ] No privilege escalation through new parameters or defaults.

## Input validation
- [ ] All external input (user, network, files, env, clipboard, URL schemes) is validated for type, length, range and format.
- [ ] No injection: shell commands, SQL, paths (traversal), format strings, HTML/JS.
- [ ] Deserialization of untrusted data uses safe decoders with explicit types.

## Secrets
- [ ] No secrets, tokens or keys in source, tests, fixtures, config or commit history.
- [ ] Secrets read from env or the OS keychain (TODO(team): confirm the approved store).
- [ ] Secrets never sent to third parties other than their intended service.

## Dependencies
- [ ] New dependencies are justified in the ADR, maintained, and pinned/locked.
- [ ] No known vulnerable versions introduced (TODO(team): command to check, e.g. `snyk test`).
- [ ] For `vulnerability` work items: the vulnerable version is gone from the whole tree
      (direct and transitive) and the lockfile is updated.

## Sensitive data in logs and errors
- [ ] No tokens, API keys, passwords, PII or full request/response bodies logged.
- [ ] Error messages shown to users do not leak internals (paths, stack traces, queries).
- [ ] Telemetry/analytics changes do not add sensitive fields.

## Transport and storage
- [ ] Network calls use TLS; certificate validation not disabled.
- [ ] Sensitive data at rest is stored in the approved secure store.

## Verdict rule
CHANGES if any applicable item fails. For `vulnerability` work items this verdict blocks
on its own, regardless of the other reviewers.
