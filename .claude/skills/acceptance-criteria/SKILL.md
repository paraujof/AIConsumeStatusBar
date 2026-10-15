---
name: acceptance-criteria
description: Rules for writing .agents/runs/<id>/acceptance.feature in Gherkin — one scenario per behavior, mandatory edge cases, regression scenarios for bugs and upgrade scenarios for vulnerabilities. Use when writing, testing against or checking conformance with acceptance criteria.
---

# Acceptance criteria

File: `.agents/runs/<id>/acceptance.feature`. Gherkin, English keywords.

## Rules
- One `Feature:` per file, titled `<id>: <summary>`.
- **One scenario per behavior.** A scenario with two `When` steps is two scenarios.
- Scenario titles are unique and stable; tests and reports reference them verbatim.
- Steps describe observable behavior (inputs/outputs, UI state, API responses), never
  implementation details (class names, private functions).
- Concrete values in examples; use `Scenario Outline` + `Examples` for data variations.
- Tag every scenario with exactly one of `@happy`, `@edge`, `@error`, `@permissions`,
  `@regression`, `@security`, `@compat`.

## Mandatory edge cases (each one present, or a comment `# N/A: <reason>`)
- **Empty**: empty input / empty list / no data / first run.
- **Error**: dependency fails (network, disk, external service), invalid input.
- **Permissions**: unauthorized / unauthenticated / OS permission denied.

## By type
- **feature**: happy path(s) + the mandatory edge cases.
- **bug**: a `@regression` scenario that reproduces the reported failure exactly and
  **fails on the current code**; plus a scenario confirming the surrounding correct
  behavior is unchanged. The ac-tester writes the regression test first.
- **vulnerability**:
  - `@security` — the vulnerable version of `<package>` is no longer resolved anywhere in
    the dependency tree (installed version ≥ fixed version), or the mitigation blocks the exploit path.
  - `@compat` — existing behavior that uses the package keeps working (no breaking change),
    one scenario per affected usage.

## Example

```gherkin
Feature: PROJ-123: Show daily token usage in the status bar

  @happy
  Scenario: Usage is shown when data is available
    Given the usage provider returns 12500 tokens for today
    When the status bar refreshes
    Then the status bar title shows "12.5k"

  @edge
  Scenario: No usage yet today
    Given the usage provider returns 0 tokens for today
    When the status bar refreshes
    Then the status bar title shows "0"

  @error
  Scenario: Provider unavailable
    Given the usage provider fails with a network error
    When the status bar refreshes
    Then the status bar title shows "—"
    And the error is logged without credentials

  @permissions
  Scenario: Missing API key
    Given no API key is configured
    When the status bar refreshes
    Then the menu shows "Add API key"
```
