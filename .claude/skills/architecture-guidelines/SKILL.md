---
name: architecture-guidelines
description: Layers, module boundaries, approved patterns and anti-patterns for this repository. Use when designing a change (ADR), reviewing a design, or checking an implementation for conformance.
---

# Architecture guidelines

The repo has no code or ADRs yet (2026-10-15), so the project-specific sections are TODO.
The general rules below apply until the team replaces them; validators judge against
what is written here, never against personal taste.

## Layers
TODO(team): list the layers and the allowed dependency direction, e.g.
`UI → application/use cases → domain ← infrastructure (adapters)`.

General rule until defined: dependencies point inward toward business logic; I/O
(network, filesystem, OS APIs, persistence) lives behind an interface at the edge.

## Module boundaries
TODO(team): list modules, what each owns, and what each may import.

- A module only uses another module through its public API.
- No cyclic dependencies between modules.

## Approved patterns
- Dependency injection through initializers/constructors (no hidden globals) so code is testable.
- Pure functions for calculations and data transformation; side effects isolated.
- Explicit error types / results at module boundaries; no silently swallowed errors.
- Configuration and secrets from environment or the OS keychain, never in source.
- TODO(team): add stack-specific patterns (state management, concurrency model, networking client).

## Anti-patterns (a validator may request CHANGES citing these)
- Business logic in UI/view code.
- Singletons or global mutable state introduced for convenience.
- Catch-all error handling that hides failures.
- Duplicated logic instead of reusing an existing helper.
- New third-party dependency without an ADR entry justifying it.
- Blocking I/O on the main/UI thread.
- TODO(team): add project-specific anti-patterns.

## Where design decisions live
- Accepted ADRs: `docs/adr/` (TODO(team): confirm path). The architect reads them before
  writing a new one; a new ADR that contradicts an accepted one must say so and supersede it explicitly.
