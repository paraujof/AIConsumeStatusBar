---
name: performance-review
description: Performance checklist for reviewing a diff — N+1 queries, caching, algorithmic complexity and payload size. Use when reviewing a PR for performance.
---

# Performance review checklist

Review the diff against each item. A finding must cite file:line, the item below, the
expected impact (with an estimate of input size), and — when applicable — the ADR section
or AC scenario. Mark non-applicable items `N/A`. Do not request micro-optimizations
without a measurable impact.

## N+1 and I/O
- [ ] No query, network request or file read inside a loop over a collection when a batch call exists.
- [ ] No repeated identical calls within one operation (fetch once, pass down).
- [ ] Polling intervals and timers are justified and bounded (TODO(team): app-specific limits, e.g. refresh rate).
- [ ] I/O happens off the main/UI thread.

## Caching
- [ ] Expensive or remote results that are read repeatedly are cached with a clear invalidation rule.
- [ ] Caches are bounded (size or TTL); no unbounded growth.
- [ ] Cache keys include everything that changes the result (no stale/cross-user data).

## Complexity
- [ ] No accidental O(n²) or worse on collections that can grow (nested loops, `contains` on arrays inside loops).
- [ ] Sorting/searching uses appropriate data structures.
- [ ] No unnecessary copies of large data.

## Payload size and memory
- [ ] Requests ask only for needed fields/pages; responses are paginated where they can grow.
- [ ] Large payloads are streamed or processed incrementally.
- [ ] No retained references causing leaks (closures, observers, timers not invalidated).

## Verdict rule
CHANGES only for findings with a concrete, explainable impact under realistic load, or
that violate a performance requirement in spec.md / adr.md.
