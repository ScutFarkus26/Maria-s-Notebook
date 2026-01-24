# Archived Documentation

This directory contains documentation for completed migrations and historical reference.

## Contents

### LegacyCleanupNotes.md

Documentation of the `WorkContract` to `WorkModel` migration.

**Status:** Completed

**Summary:**
- All active code migrated from `WorkContract` to `WorkModel`
- Legacy compatibility layers preserved for data migration
- Dead code removed
- Migration functions remain in `Services/DataMigrations.swift`

---

## When to Archive

Documentation should be moved here when:

1. A migration is fully complete and verified
2. The information is historical reference only
3. Active development no longer requires the document

## Current Active Documentation

See the parent `Docs/` directory for active documentation:

- [ARCHITECTURE.md](../ARCHITECTURE.md) - App architecture
- [DATA_MODELS.md](../DATA_MODELS.md) - Data model reference
- [FEATURES.md](../FEATURES.md) - Feature documentation
- [SETUP.md](../SETUP.md) - Build and setup guide
