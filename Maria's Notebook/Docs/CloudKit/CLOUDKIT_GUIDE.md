# CloudKit Verification Guide

This guide explains how to verify CloudKit sync is working correctly in Maria's Notebook.

**Last Updated**: January 2026

## How to Know if CloudKit is Working

### 1. Check Console Logs on App Launch

When you launch the app with CloudKit enabled, you should see these log messages in Xcode's console:

**✅ CloudKit is Active:**
```
CoreData: Creating CloudKit-enabled container...
CoreData: CloudKit configuration:
  - Container ID: iCloud.DanielSDeBerry.MariasNoteBook
  - Store URL: /path/to/store
  - Database: Private
CoreData: ✅ CloudKit container created successfully!
CoreData: CloudKit sync is now active. Changes will sync across devices.
CoreData: ✅ Using CloudKit-enabled storage.
```

**❌ CloudKit is Disabled:**
```
CoreData: Creating local storage container (CloudKit disabled - set 'EnableCloudKitSync' UserDefaults flag to enable)...
CoreData: Using local storage.
```

### 2. Check the Settings UI

1. Open **Settings** → **Advanced / Debug**
2. Look at the **CloudKit Sync** section
3. The status indicator shows:
   - 🟢 **Green dot**: CloudKit is enabled (restart required if you just toggled it)
   - ⚪ **Gray dot**: CloudKit is disabled

### 3. Verify iCloud Account

Make sure you're signed into iCloud on your device:
- **macOS**: System Settings → Apple ID → iCloud
- **iOS**: Settings → [Your Name] → iCloud

CloudKit requires an active iCloud account to sync.

### 4. Test Multi-Device Sync

The best way to verify CloudKit is working:

1. **Enable CloudKit** on Device A
2. **Create or modify** some data (e.g., add a student, create a lesson)
3. **Wait a few seconds** for sync (CloudKit syncs in the background)
4. **Open the app on Device B** (same iCloud account)
5. **Check if the changes appear** on Device B

**Note**: Initial sync can take a few minutes, especially with large datasets.

### 5. Check CloudKit Dashboard (Advanced)

For developers, you can verify CloudKit activity in the CloudKit Console:

1. Go to [CloudKit Console](https://icloud.developer.apple.com/dashboard)
2. Select your app's container: `iCloud.DanielSDeBerry.MariasNoteBook`
3. Check the **Private Database** for records
4. Monitor **Operations** to see sync activity

### 6. Common Issues

**CloudKit not syncing? Check:**

- ✅ iCloud account is signed in
- ✅ iCloud Drive is enabled
- ✅ App has CloudKit entitlements (already configured ✅)
- ✅ Network connection is active
- ✅ Console logs show CloudKit is enabled
- ✅ App was restarted after enabling CloudKit

**If CloudKit still doesn't work:**

1. Check Xcode console for error messages
2. Verify the bundle ID matches the container ID in entitlements
3. Ensure you're testing on iOS 17+ / macOS 14+ devices
4. Try disabling and re-enabling CloudKit
5. Check iCloud storage quota (CloudKit uses iCloud storage)

### 7. Debugging Tips

**Enable verbose CloudKit logging:**
- In Xcode, add environment variable: `-com.apple.CoreData.CloudKitDebug 1`
- This will show detailed CloudKit sync operations in the console

**Check sync status programmatically:**
- CloudKit sync happens automatically in the background
- Core Data + CloudKit sync status can be monitored via NSPersistentCloudKitContainer event notifications
- Monitor console logs for sync activity
- Changes typically sync within seconds to minutes

### 8. What to Look For

**Signs CloudKit is working:**
- ✅ Console shows "CloudKit container created successfully"
- ✅ Data appears on other devices
- ✅ Changes sync within minutes
- ✅ No sync errors in console

**Signs CloudKit is NOT working:**
- ❌ Console shows "Using local storage"
- ❌ Data doesn't appear on other devices
- ❌ Console shows CloudKit errors
- ❌ Toggle is off in settings

### 9. Mac-Specific Sync Issues

**If data syncs between iPhone and iPad but NOT to Mac:**

1. **Verify Container ID matches:**
   - On Mac: Open Settings → iCloud Status → Check "Container ID"
   - On iPhone/iPad: Open Settings → iCloud Status → Check "Container ID"
   - **They must be identical!** If different, the bundle IDs don't match.

2. **Check Mac Console Logs:**
   - Launch Mac app from Xcode
   - Look for: `CoreData: ✅ CloudKit container created successfully!`
   - If you see `CoreData: Using local storage`, CloudKit is disabled on Mac

3. **Verify Mac iCloud Settings:**
   - System Settings → Apple ID → iCloud
   - Ensure iCloud Drive is enabled
   - Ensure you're signed into the same iCloud account as iPhone/iPad

4. **Check Bundle ID:**
   - Mac and iOS apps must have the same bundle ID
   - Container ID is derived from: `iCloud.{BundleID}`
   - If bundle IDs differ, they'll use different CloudKit containers

5. **Force CloudKit Re-initialization on Mac:**
   - Quit the Mac app completely
   - Delete the local store (Settings → Data Management → Reset Local Database)
   - Restart the app (it will re-sync from iCloud)

6. **Verify Mac OS Version:**
   - Core Data + CloudKit requires macOS 26.0 or later
   - Check: Apple menu → About This Mac

---

**Remember**: After enabling CloudKit, you **must restart the app** for the change to take effect!

---

## Related Documentation

- [KEY_VALUE_STORAGE_IMPLEMENTATION.md](../Implementation/KEY_VALUE_STORAGE_IMPLEMENTATION.md) - iCloud KVS preference sync
- [ARCHITECTURE.md](../ARCHITECTURE.md) - Architecture guide



