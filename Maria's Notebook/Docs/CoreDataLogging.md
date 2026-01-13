# Core Data and SQLite Logging in Debug Builds

## Overview

When running the app in Debug mode from Xcode, you may see verbose logging from Core Data and SQLite, including:

- **WAL checkpoint operations**: SQLite's Write-Ahead Logging (WAL) checkpoint messages
- **PostSaveMaintenance**: Core Data's post-save maintenance operations
- **SQL query execution**: Detailed SQL query logs
- **CoreData+CloudKit messages**: Initialization and sync-related messages

## Are These Logs Normal?

**Yes, these logs are completely normal and expected in Debug builds.** They do not indicate errors or problems with the database.

## Why Do These Logs Appear?

1. **Xcode Debug Diagnostics**: Xcode enables verbose Core Data/SQLite logging by default in Debug builds
2. **System-Level Logging**: Core Data and SQLite emit these logs at the system level, not from app code
3. **SwiftData Internals**: SwiftData uses Core Data internally, which generates these diagnostic messages

## Can These Logs Be Disabled?

**No, not from app code.** These logs are controlled by:
- Xcode scheme environment variables (e.g., `-com.apple.CoreData.CloudKitDebug`)
- System-level Core Data diagnostics
- Xcode's Debug build settings

The app does not enable or configure these logs programmatically. If you see them, they originate from Xcode's diagnostics or system defaults.

## What About Release Builds?

Release builds typically have much less verbose logging. The diagnostic logs you see in Debug are primarily for development and debugging purposes.

## Related Logs

You may also see harmless CoreData+CloudKit messages during initialization:
- "store was removed from coordinator"
- "file:///dev/null" references

These occur during SwiftData's CloudKit initialization and are expected. They do not affect functionality.

## Detached Signature Errors

You may see SQLite errors about `/private/var/db/DetachedSignatures`:
- "cannot open file at line 51043 of [f0ca7bba1c]"
- "os_unix.c:51043: (2) open(/private/var/db/DetachedSignatures) - No such file or directory"

These errors occur when SQLite tries to access a system directory for detached signature logging (a security/auditing feature) that doesn't exist on your system. **These errors are harmless** and do not affect database functionality.

**Fix Attempted**: The app attempts to suppress these errors by setting the `SQLITE_DISABLE_SIGNATURE_LOGGING` environment variable early in app initialization. However, since these errors occur at SQLite library initialization time (very early in the process), they may still appear if SQLite initializes before the environment variable is set or doesn't respect the variable.

If you still see these errors, they can be safely ignored. They indicate that SQLite is working normally but couldn't access an optional system directory for signature logging.

## Summary

- ✅ WAL checkpoint and PostSaveMaintenance logs are **normal** in Debug builds
- ✅ They do **not** indicate database errors or problems
- ✅ They **cannot** be suppressed from Swift code
- ✅ They are **expected** and can be safely ignored
- ✅ Release builds will have **less verbose** logging

If you're seeing these logs, it means Xcode's diagnostics are working as intended. No action is required.
