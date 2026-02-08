# Concurrency Safety Guidelines

## Sendable Conformance

The following types are thread-safe and conform to Sendable:
- All SwiftData model types (backed by ModelContext's actor isolation)
- All DTO types in Backup/BackupDocuments.swift (immutable structs)
- All constant enums and value types

## @MainActor Isolation

View models and UI-related types are marked with @MainActor to ensure thread safety.

## Future Improvements

Consider adding explicit Sendable conformance to:
- Service layer types that are passed across actor boundaries
- Repository types
- Cache coordinators
