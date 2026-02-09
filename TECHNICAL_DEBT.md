# Technical Debt & TODO Tracking

This document tracks TODOs extracted from code comments. These should be converted to GitHub issues for proper tracking.

## High Priority

### Attendance Email - Multi-recipient Support
**File:** `Attendance/AttendanceEmail.swift`  
**Description:** Add support for multiple recipients in attendance emails  
**Effort:** Medium  
**Impact:** High - improves parent communication flexibility

### Attendance Email - Timeout Fallback
**File:** `Attendance/AttendanceEmail.swift`  
**Description:** Implement fallback mechanism for email timeout scenarios  
**Effort:** Small  
**Impact:** Medium - improves reliability

## Medium Priority

### Backup Telemetry - Compression Ratio
**File:** `Backup/Telemetry/BackupTelemetryService.swift`  
**Description:** Calculate and display compression ratio in backup telemetry  
**Effort:** Small  
**Impact:** Low - nice-to-have metric for backup efficiency

### Enhanced Backup - Conflict Detection
**File:** `Backup/EnhancedBackupService.swift`  
**Description:** Implement conflict detection for backup restore operations  
**Effort:** Large  
**Impact:** High - prevents data loss during restore

### Lesson Picker - Move Formatting to ViewModel
**File:** `Lessons/LessonPickerComponents.swift`  
**Description:** Refactor to move presentation formatting logic from view to ViewModel  
**Effort:** Medium  
**Impact:** Medium - improves code organization and testability

## Low Priority

### Performance Benchmarks - Update API Usage
**File:** `Tests/Performance/PerformanceBenchmarks.swift`  
**Description:** Update WorkParticipantEntity usage to reflect current API  
**Effort:** Small  
**Impact:** Low - test maintenance

## Completed
_Track completed items here before removing them from the file_

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
