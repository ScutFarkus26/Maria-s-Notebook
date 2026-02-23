# Setup Guide

This guide covers building and running Maria's Notebook for development.

## Prerequisites

- **macOS 14.0+** (Sonoma or later)
- **Xcode 15.0+** with iOS 17+ and macOS 14+ SDKs
- **Apple Developer Account** (for device testing and CloudKit)
- Git

## Getting Started

### 1. Clone the Repository

```bash
git clone <repository-url>
cd "Maria's Notebook"
```

### 2. Open in Xcode

```bash
open "Maria's Notebook/Maria's Notebook.xcodeproj"
```

Or open Xcode and select the `.xcodeproj` file.

### 3. Configure Signing

1. Select the project in the navigator
2. Select the "Maria's Notebook" target
3. Go to "Signing & Capabilities"
4. Select your development team
5. Xcode will automatically manage signing

### 4. Build and Run

- **Mac**: Select "My Mac" as the destination and press Cmd+R
- **iOS Simulator**: Select an iPhone/iPad simulator and press Cmd+R
- **iOS Device**: Connect device, select it, and press Cmd+R

## Project Configuration

### Bundle Identifier

The app uses bundle identifier: `DanielSDeBerry.MariasNoteBook`

### Capabilities

The app requires the following capabilities (configured in entitlements):

| Capability | Purpose |
|------------|---------|
| iCloud | CloudKit sync and key-value storage |
| Push Notifications | CloudKit change notifications |
| App Sandbox | macOS security (with file access exceptions) |

### Entitlements

Located at `Maria_s_Notebook.entitlements`:

```xml
<key>com.apple.developer.icloud-container-identifiers</key>
<array>
    <string>iCloud.DanielSDeBerry.MariasNoteBook</string>
</array>
<key>com.apple.developer.icloud-services</key>
<array>
    <string>CloudDocuments</string>
    <string>CloudKit</string>
</array>
<key>com.apple.developer.ubiquity-kvstore-identifier</key>
<string>$(TeamIdentifierPrefix)$(CFBundleIdentifier)</string>
```

### Info.plist

Key privacy permissions configured:

| Key | Purpose |
|-----|---------|
| `NSCameraUsageDescription` | Taking photos for notes |
| `NSRemindersUsageDescription` | Syncing reminders to Today view |
| `NSCalendarsUsageDescription` | Showing calendar events |

## Build Configurations

### Debug

- Debug symbols enabled
- Assertions active
- Optimizations disabled
- `DEBUG` compilation condition set

### Release

- Optimizations enabled
- Debug symbols stripped
- Ready for distribution

## Optional Features

### CloudKit Sync

CloudKit sync is disabled by default. To enable for testing:

**Option 1: UserDefaults (Recommended)**
```swift
UserDefaults.standard.set(true, forKey: "EnableCloudKitSync")
```

**Option 2: Build Setting**

Add `EnableCloudKitSync=1` to scheme environment variables.

See [CLOUDKIT_VERIFICATION_GUIDE.md](CloudKit/CLOUDKIT_VERIFICATION_GUIDE.md) for testing.

### Apple Intelligence (Foundation Models)

AI-powered observation summarization requires additional setup:

1. Open Build Settings
2. Find "Swift Compiler - Custom Flags"
3. Under "Active Compilation Conditions", add:
   - Debug: `ENABLE_FOUNDATION_MODELS`
   - Release: `ENABLE_FOUNDATION_MODELS`

**Requirements:**
- Xcode 16+ (with Foundation Models support)
- macOS 26.0+ deployment target (for AI features)

See [ENABLE_FOUNDATION_MODELS.md](ENABLE_FOUNDATION_MODELS.md) for details.

## Development Tools

### SwiftLint

Configuration in `.swiftlint.yml`:

```yaml
disabled_rules:
  - trailing_whitespace
opt_in_rules:
  - empty_count
```

### Swift Format

Configuration in `.swift-format.json` for consistent code formatting.

## Testing

### Running Tests

```bash
# Command line
xcodebuild test -scheme "Maria's Notebook" -destination 'platform=macOS'

# Or use Xcode: Cmd+U
```

### Debug Views

Debug and test views are in the `Tests/` directory:

- `CloudKitStatusView` - CloudKit sync status
- `TrackPopulationView` - Data population tools

Access via Settings > Debug section (Debug builds only).

## Troubleshooting

### Build Errors

**"No such module 'SwiftData'"**
- Ensure deployment target is iOS 17+ or macOS 14+

**Signing Issues**
- Verify Apple Developer account is configured
- Check team selection in Signing & Capabilities

**CloudKit Container Not Found**
- Ensure iCloud capability is enabled
- Verify container ID matches entitlements
- Check Apple Developer portal for container setup

### Runtime Issues

**"Failed to initialize CloudKit"**
- CloudKit requires active iCloud account
- Check network connectivity
- Verify entitlements match container ID

**Data Not Syncing**
- Verify `EnableCloudKitSync` UserDefault is set
- Check CloudKit dashboard for errors
- Ensure both devices use same iCloud account

### Performance Issues

- See [PERFORMANCE_OPTIMIZATION_GUIDE.md](Optimization/PERFORMANCE_OPTIMIZATION_GUIDE.md)
- Check for unfiltered `@Query` usage
- Profile with Instruments

## Directory Structure

```
Maria's Notebook/
├── Maria's Notebook.xcodeproj    # Xcode project
├── Maria's Notebook/             # Source code
│   ├── AppCore/                  # App entry, navigation
│   ├── Models/                   # SwiftData models
│   ├── Services/                 # Business logic
│   ├── Components/               # Reusable UI
│   ├── Students/                 # Student features
│   ├── Lessons/                  # Lesson features
│   ├── Work/                     # Work management
│   ├── ...                       # Other features
│   ├── Docs/                     # Documentation
│   ├── Info.plist                # App configuration
│   └── Maria_s_Notebook.entitlements
└── README.md
```

## Related Documentation

- [README.md](../README.md) - Project overview
- [ARCHITECTURE.md](ARCHITECTURE.md) - Architecture guide
- [DATA_MODELS.md](DATA_MODELS.md) - Data model reference
- [FEATURES.md](FEATURES.md) - Feature documentation
