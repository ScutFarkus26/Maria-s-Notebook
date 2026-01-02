# Key-Value Storage Implementation

## Summary

Key-Value Storage (iCloud KVS) has been fully enabled and integrated into the app using best practices. User preferences now sync across devices automatically via iCloud.

## What Was Done

### 1. ✅ Entitlement Configuration
- Added `com.apple.developer.ubiquity-kvstore-identifier` to `Maria_s_Notebook.entitlements`
- Configured with iCloud container: `iCloud.DanielSDeBerry.MariasNoteBook`

### 2. ✅ SyncedPreferencesStore Implementation
Created `Utils/SyncedPreferencesStore.swift` - a comprehensive wrapper for `NSUbiquitousKeyValueStore` that:
- Manages synced preferences via iCloud KVS
- Automatically migrates existing UserDefaults values to KVS on first launch
- Observes external changes from other devices
- Falls back to UserDefaults if KVS is unavailable
- Provides type-safe convenience methods
- Implements `@SyncedAppStorage` property wrapper for SwiftUI

### 3. ✅ Preference Migration
Identified and migrated the following preferences to sync across devices:

**Synced Preferences (via iCloud KVS):**
- `AttendanceEmail.enabled` - Email feature toggle
- `AttendanceEmail.to` - Recipient email address
- `AttendanceEmail.from` - Sender email address
- `LessonAge.warningDays` - Lesson age warning threshold
- `LessonAge.overdueDays` - Lesson age overdue threshold
- `LessonAge.freshColorHex` - Fresh lesson color
- `LessonAge.warningColorHex` - Warning lesson color
- `LessonAge.overdueColorHex` - Overdue lesson color
- `WorkAge.warningDays` - Work age warning threshold
- `WorkAge.overdueDays` - Work age overdue threshold
- `WorkAge.freshColorHex` - Fresh work color
- `WorkAge.warningColorHex` - Warning work color
- `WorkAge.overdueColorHex` - Overdue work color
- `Backup.encrypt` - Backup encryption preference

**Local Preferences (remain in UserDefaults):**
- Debug flags (`EnableCloudKitSync`, `UseInMemoryStoreOnce`, etc.)
- Device-specific state (`LastBackupTimeInterval`, `StudentDetailView.selectedChecklistSubject`)
- Test student settings (`General.showTestStudents`, `General.testStudentNames`)
- UI state (`PlanningInbox.order`, `Attendance.locked.*`)
- Auto-backup settings (`AutoBackup.*`)

### 4. ✅ Code Updates
Updated the following files to use `@SyncedAppStorage` instead of `@AppStorage` for synced preferences:

- `Settings/AgeSettingsViews.swift` - Lesson and Work age settings
- `Attendance/AttendanceEmail.swift` - Email preferences and helper functions
- `Attendance/AttendanceView.swift` - Email UI bindings
- `Settings/DataManagementGrid.swift` - Backup encryption setting
- `Backup/BackupRestoreSectionView.swift` - Backup encryption setting
- `Students/StudentLessonPill.swift` - Lesson age preferences
- `Students/StudentMeetingsTab.swift` - Work age preference
- `Work/WorkCardView.swift` - Work age preferences
- `Backup/BackupService.swift` - Backup/restore preference handling

## How It Works

### Automatic Migration
On first launch after the update, `SyncedPreferencesStore` automatically:
1. Checks if migration has completed
2. Copies existing UserDefaults values to KVS for synced keys
3. Synchronizes with iCloud
4. Marks migration as complete

### Sync Behavior
- Changes are automatically synced to iCloud when preferences are modified
- External changes from other devices trigger `NSUbiquitousKeyValueStoreDidChangeExternallyNotification`
- Views update automatically via `@SyncedAppStorage` property wrapper
- If iCloud is unavailable, preferences fall back to UserDefaults locally

### Property Wrapper Usage
Replace `@AppStorage` with `@SyncedAppStorage` for synced preferences:

```swift
// Before:
@AppStorage("LessonAge.warningDays") private var warningDays: Int = 6

// After:
@SyncedAppStorage("LessonAge.warningDays") private var warningDays: Int = 6
```

The API is identical to `@AppStorage`, so it's a drop-in replacement.

## Best Practices Followed

1. ✅ **1MB Limit Awareness**: Only small preference values are synced
2. ✅ **Migration Strategy**: Automatic one-time migration from UserDefaults
3. ✅ **Fallback Handling**: Graceful fallback to UserDefaults if KVS fails
4. ✅ **Change Observation**: Observes external changes from other devices
5. ✅ **Type Safety**: Type-safe convenience methods and property wrapper
6. ✅ **Separation of Concerns**: Device-specific preferences stay local
7. ✅ **Backup Integration**: Backup/restore handles synced and local preferences correctly

## Testing Recommendations

1. **Multi-Device Testing**:
   - Set a preference on Device A
   - Verify it appears on Device B (may take a few seconds)
   - Change the preference on Device B
   - Verify Device A updates

2. **Migration Testing**:
   - Install update on device with existing preferences
   - Verify preferences are preserved and sync

3. **Offline Testing**:
   - Change preferences while offline
   - Verify preferences work locally
   - Go online and verify sync occurs

4. **Edge Cases**:
   - Test with iCloud account signed out
   - Test with iCloud storage full
   - Test rapid changes from multiple devices

## Limitations

- KVS has a 1MB total limit (all keys combined)
- KVS supports: Bool, Int, Double, String, Data
- Dates must be stored as Double (timeIntervalSinceReferenceDate) if syncing
- Sync is eventual consistency (changes propagate within seconds to minutes)
- Requires active iCloud account and internet connection for sync

## Future Enhancements

Potential improvements:
- Add preference conflict resolution strategy
- Monitor KVS storage usage
- Add preference sync status indicator in UI
- Consider syncing additional preferences if needed (within 1MB limit)

## Files Modified

1. `Maria_s_Notebook.entitlements` - Added KVS entitlement
2. `Utils/SyncedPreferencesStore.swift` - New file (implementation)
3. `Settings/AgeSettingsViews.swift` - Updated to use @SyncedAppStorage
4. `Attendance/AttendanceEmail.swift` - Updated preferences and helpers
5. `Attendance/AttendanceView.swift` - Updated email bindings
6. `Settings/DataManagementGrid.swift` - Updated backup encryption
7. `Backup/BackupRestoreSectionView.swift` - Updated backup encryption
8. `Students/StudentLessonPill.swift` - Updated lesson age preferences
9. `Students/StudentMeetingsTab.swift` - Updated work age preference
10. `Work/WorkCardView.swift` - Updated work age preferences
11. `Backup/BackupService.swift` - Updated backup/restore logic

---

**Implementation Date**: 2025-01-XX
**Status**: ✅ Complete and Ready for Testing


