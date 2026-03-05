# Architecture Decision Records (ADRs)

ADRs document significant architectural decisions, their context, rationale, and consequences.

## Current ADRs

| # | Title | Status | Date | Tags |
|---|-------|--------|------|------|
| [001](ADR-001-swiftdata-enum-pattern.md) | SwiftData Enum Raw Value Pattern | Accepted | 2025-11 | `swiftdata`, `predicate`, `enum` |
| [003](ADR-003-repository-pattern.md) | Repository Pattern Usage | Accepted | 2026-01 | `architecture`, `data-access` |
| [004](ADR-004-dependency-injection.md) | Dependency Injection via AppDependencies | Accepted | 2026-02 | `architecture`, `di` |

## Quick Reference

**Data Layer:**
- [ADR-001](ADR-001-swiftdata-enum-pattern.md) — How to store enums in SwiftData
- [ADR-003](ADR-003-repository-pattern.md) — When to use repositories vs @Query

**Architecture:**
- [ADR-004](ADR-004-dependency-injection.md) — How dependencies are injected

## ADR Template

```markdown
# ADR-XXX: Title

**Status:** Proposed/Accepted/Deprecated/Superseded
**Date:** YYYY-MM-DD
**Tags:** `tag1`, `tag2`

## Context
What is the issue?

## Decision
What did we decide?

## Consequences
### Positive / ### Negative / ### Neutral

## Alternatives Considered
What else was evaluated?
```

**Last Updated:** 2026-03-05
