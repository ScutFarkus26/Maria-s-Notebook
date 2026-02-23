# Architecture Decision Records (ADRs)

This directory contains all Architecture Decision Records for Maria's Notebook. ADRs document significant architectural decisions, their context, rationale, and consequences.

## What is an ADR?

An Architecture Decision Record (ADR) captures an important architectural decision made along with its context and consequences. ADRs help:

- **Preserve knowledge** - Document "why" decisions were made
- **Onboard new developers** - Understand system design quickly
- **Prevent revisiting** - Avoid repeating past discussions
- **Track evolution** - See how architecture changed over time

## Format

Each ADR follows a standard structure:

1. **Title** - Short, descriptive name
2. **Status** - Accepted, Proposed, Deprecated, Superseded
3. **Context** - Problem being solved
4. **Decision** - Solution chosen
5. **Consequences** - Positive, negative, and neutral impacts
6. **Alternatives** - Options considered and rejected
7. **References** - Related code, docs, or ADRs

## Current ADRs

### Core Infrastructure

| # | Title | Status | Date | Tags |
|---|-------|--------|------|------|
| [001](ADR-001-swiftdata-enum-pattern.md) | SwiftData Enum Raw Value Pattern | ✅ Accepted | 2025-11 | `swiftdata`, `predicate`, `enum` |
| [002](ADR-002-domain-errors.md) | Domain-Specific Error Types | ✅ Accepted | 2026-02-13 | `errors`, `ux`, `type-safety` |
| [003](ADR-003-repository-pattern.md) | Repository Pattern Usage | ✅ Accepted | 2026-01 | `architecture`, `data-access` |
| [004](ADR-004-dependency-injection.md) | Dependency Injection via AppDependencies | ✅ Accepted | 2026-02 | `architecture`, `di` |
| [005](ADR-005-denormalization-strategy.md) | Denormalization for Query Performance | ✅ Accepted | 2025-11 | `performance`, `optimization` |

## Quick Reference

### By Topic

**Data Layer:**
- [ADR-001](ADR-001-swiftdata-enum-pattern.md) - How to store enums in SwiftData
- [ADR-003](ADR-003-repository-pattern.md) - When to use repositories vs @Query
- [ADR-005](ADR-005-denormalization-strategy.md) - When to denormalize for performance

**Error Handling:**
- [ADR-002](ADR-002-domain-errors.md) - Domain-specific errors vs generic Error

**Architecture:**
- [ADR-004](ADR-004-dependency-injection.md) - How dependencies are injected

### By Status

**✅ Accepted (5)**
- All current ADRs are accepted and in use

**📝 Proposed (0)**
- None pending

**🗄️ Superseded (0)**
- None replaced yet

## Common Patterns

### SwiftData Models

When working with SwiftData models, refer to:
1. [ADR-001](ADR-001-swiftdata-enum-pattern.md) for enum properties
2. [ADR-005](ADR-005-denormalization-strategy.md) for performance optimization
3. [ADR-003](ADR-003-repository-pattern.md) for data access

### Error Handling

When handling errors in services/ViewModels:
1. [ADR-002](ADR-002-domain-errors.md) for error types and patterns
2. See `Errors/DOMAIN_ERRORS_GUIDE.md` for usage examples

### Service Architecture

When creating new services:
1. [ADR-004](ADR-004-dependency-injection.md) for dependency injection
2. [ADR-003](ADR-003-repository-pattern.md) for data access layer

## Creating New ADRs

### When to Create an ADR

Create an ADR when:
- ✅ Making a significant architectural decision
- ✅ Choosing between multiple approaches
- ✅ Adopting a new pattern or framework
- ✅ Deprecating an existing pattern
- ✅ Documenting a constraint or limitation
- ✅ Establishing a coding standard

### ADR Template

```markdown
# ADR-XXX: Title

**Status:** Proposed/Accepted/Deprecated/Superseded
**Date:** YYYY-MM-DD
**Deciders:** Who made this decision
**Tags:** `tag1`, `tag2`

## Context

What is the issue we're facing? What constraints exist?

## Decision

What did we decide to do?

## Consequences

### Positive
- What are the benefits?

### Negative
- What are the drawbacks?

### Neutral
- What are the trade-offs?

## Alternatives Considered

What other options did we evaluate?

## References

- Links to code, docs, external resources
```

### Numbering

ADRs are numbered sequentially:
- ADR-001, ADR-002, ADR-003, etc.
- Numbers never reused (even if ADR superseded)
- Use 3-digit format (001, 002, etc.)

### File Naming

Format: `ADR-XXX-short-title.md`

Examples:
- `ADR-001-swiftdata-enum-pattern.md`
- `ADR-002-domain-errors.md`
- `ADR-003-repository-pattern.md`

## Updating ADRs

### When to Update

**DO update when:**
- ✅ Adding implementation details
- ✅ Adding references to code
- ✅ Clarifying consequences
- ✅ Adding metrics/statistics
- ✅ Documenting lessons learned

**DON'T update when:**
- ❌ Changing the decision itself (create new ADR instead)
- ❌ Reversing a decision (mark as Superseded, create new ADR)

### Revision History

Always add changes to the "Revision History" table:

```markdown
## Revision History

| Date | Author | Change |
|------|--------|--------|
| 2026-02-13 | Team | Initial version |
| 2026-03-01 | Dev | Added implementation metrics |
```

## ADR Lifecycle

```
Proposed → Accepted → (Active)
                  ↓
              Deprecated/Superseded
```

**Proposed** - Under discussion
**Accepted** - Decision made, may not be fully implemented
**Active** - Accepted and in use
**Deprecated** - No longer recommended, but not replaced
**Superseded** - Replaced by another ADR

## Related Documentation

- **Architecture Overview:** `../ARCHITECTURE.md` (if exists)
- **Migration Plan:** `../ARCHITECTURE_MIGRATION.md` (7-phase plan)
- **Error Handling Guide:** `../../Errors/DOMAIN_ERRORS_GUIDE.md`
- **Repository Examples:** `../../Repositories/`

## Statistics

**As of 2026-02-13:**
- **Total ADRs:** 5
- **Status:** 5 Accepted, 0 Proposed, 0 Deprecated
- **Topics Covered:** SwiftData, Errors, Repositories, DI, Performance
- **Lines of Documentation:** ~1,400 lines

## Contributing

When making architectural decisions:

1. **Discuss** with team before implementing
2. **Document** decision in ADR
3. **Implement** according to ADR
4. **Update** ADR with lessons learned
5. **Reference** ADR in code comments

Example code comment:
```swift
// ADR-001: Use raw value pattern for enums in SwiftData models
var statusRaw: String = WorkStatus.active.rawValue
var status: WorkStatus {
    get { WorkStatus(rawValue: statusRaw) ?? .active }
    set { statusRaw = newValue.rawValue }
}
```

---

**Questions?** See individual ADRs or ask the Architecture Team.

**Version:** 1.0
**Last Updated:** 2026-02-13
**Maintainer:** Architecture Migration Team
