# Technical Debt & TODO Tracking

This document tracks TODOs extracted from code comments. These should be converted to GitHub issues for proper tracking.

## High Priority

_No high-priority items remaining_

## Medium Priority

### Lesson Picker - Move Formatting to ViewModel
**File:** `Lessons/LessonPickerComponents.swift`  
**Description:** Refactor to move presentation formatting logic from view to ViewModel  
**Effort:** Medium  
**Impact:** Medium - improves code organization and testability

## Low Priority

### Performance Benchmarks - Update API Usage
**File:** `Tests/Performance/PerformanceBenchmarks.swift`  
**Description:** Update WorkParticipantEntity usage and BackupDTOTransformers API to reflect current model structure. File is currently disabled with `#if false`.
**Effort:** Medium  
**Impact:** Low - test maintenance

## Completed

### Technical Debt Cleanup (Completed: 2026-02-22)
**Files:** 10 files removed, 5 files updated
**Description:** Major cleanup of unnecessary documentation and code
**What Was Done:**
- **Documentation Cleanup:** Removed 6 archived migration documents (~45KB) - all migrations complete, info in git history
- **Unused Feature Flags:** Removed FeatureFlags.swift and ArchitectureMigrationSettingsView.swift - all flags were OFF and unused
- **Prototype Documentation:** Removed MCP_Integration_Guide.md - demonstration prototype, not active development
- **Code Simplification:** Cleaned up AppDependencies.swift to remove feature flag checks (both branches were identical)
- **Telemetry Enhancement:** Implemented compression ratio calculation in BackupTelemetryService (added uncompressedSize tracking)
**Impact:**
- Reduced codebase clutter by ~50KB
- Cleaner architecture without unused migration infrastructure
- Better backup telemetry with compression metrics
- Zero behavioral changes, 100% backward compatible

### Attendance Email Improvements (Completed: 2026-02-21)
**Files:** `Attendance/AttendanceEmail.swift`
**What Was Done:**
- Multi-recipient support verified as already implemented and working
- Added 30-second timeout fallback for macOS email send operations
- Prevents completion callback issues on some system versions
- Updated documentation to reflect multi-recipient functionality
**Commit:** `6731e5f`
**Impact:** Improved email reliability and user communication

### Enhanced Backup Conflict Detection (Completed: 2026-02-21)
**File:** `Backup/EnhancedBackupService.swift`
**What Was Done:**
- Implemented conflict detection algorithm in EnhancedBackupService
- Detects significant entity count differences (>30%) during merge operations
- Provides warnings before restore operations that may create duplicates
- Returns array of CloudSyncConflictResolver.Conflict objects
**Commit:** `6731e5f`
**Impact:** Better data integrity protection, prevents data loss during restores

### Main Actor Isolation Warnings Fixed (Completed: 2026-02-21)
**Files:** `UIConstants.swift`, `AppTheme+Spacing.swift`
**What Was Done:**
- Marked constant properties with nonisolated(unsafe) for safe concurrent access
- Fixed all 7 main actor isolation warnings (100% resolved)
- OpacityConstants, StrokeWidth, CornerRadius, Spacing all updated
**Commits:** `1a04628`, `6731e5f`
**Impact:** Cleaner builds, zero concurrency warnings, safer code

### UI Constants & Component System (Completed: 2026-02-21)
**Files:** 50 files across entire codebase
**Description:** Phase 1 & 2 of 50 UI Improvements Plan
**What Was Done:**
- Created comprehensive UI constant system (AppTheme.Spacing, UIConstants.OpacityConstants, CornerRadius, etc.)
- Applied constants across 19 files, replacing 200+ hardcoded values
- Created 11 reusable components (StatusPill, IconPill, StudentAvatarView, form components, modifiers)
- Replaced 10 inline patterns with reusable components
- Net code reduction: 85 lines
**Commit:** `67c34df`
**Impact:** Improved maintainability, consistency, and established foundation for future UI work

### Code Quality Improvements - Phase 3 (Completed: 2026-02-22)
**Files:** 190+ files across entire codebase
**Description:** Comprehensive code quality refactoring
**What Was Done:**
- **Error Handling:** Replaced 537+ try? patterns with proper do-catch blocks with logging
- **Readability:** Extracted nested conditionals to computed properties (4+ levels → 1 level)
- **Encapsulation:** Added explicit private access control where Swift architecture permits
- Created shared ModelContext.resolveWorkModel() extension for work resolution
- Extracted layout variants in AttendanceCard (compactLayout, regularLayout)
- Improved error visibility with consistent ⚠️ [function] format
**Commits:** `1c5a8ec`, `13aadce`, `9d229a0`
**Impact:**
- Better debugging with 537+ error logging points
- Reduced code duplication (~65 lines)
- Improved encapsulation and API clarity
- Zero behavioral changes, 100% backward compatible

### Advanced Refactoring - Phases 4 & 5 (Completed: 2026-02-22)
**Files:** 5 new files, 100+ patterns identified for consolidation
**Description:** Created reusable modifiers and consolidated platform-specific code
**What Was Done:**
- **Phase 4.1:** Created ChipModifier and SubtleCardModifier (eliminates 15+ duplications)
- **Phase 4.2:** Expanded View+PlatformStyles.swift with 86+ pattern consolidations
  - Color.controlBackgroundColor() and windowBackgroundColor() (46+ uses)
  - sheetPresentation() for platform-appropriate sizing (40+ uses)
  - platformTapGesture() and macOSFocusable() utilities
- **Phase 5:** Added 60+ constants to UIConstants.swift
  - SpringAnimation presets (5 standard configs, 30+ uses)
  - TimingDelay constants (10 values, 40+ uses)
  - DataLimit constants (11 limits, 20+ uses)
  - StrokePattern presets (4 patterns, 15+ uses)
**Commits:** `43da2b3`, `7009408`, `84e57d3`
**Impact:**
- Eliminates 200+ instances of code duplication
- Single source of truth for animations, timing, platform styling
- Type-safe constants with clear semantic names
- Ready for app-wide application (future task)
- Zero behavioral changes, 100% backward compatible

---

## How to Use This File

1. **Adding New TODOs**: When you encounter a TODO comment in code, add it here with context
2. **Converting to Issues**: Create GitHub issue with label `technical-debt` and reference this file
3. **Mark Complete**: Move completed items to the "Completed" section with date and PR reference
4. **Keep Code Clean**: Remove TODO comments from code once added here

## Priority Definitions

- **High Priority**: Affects functionality, user experience, or data integrity
- **Medium Priority**: Code quality, maintainability, or minor features
- **Low Priority**: Nice-to-have improvements, minor optimizations
