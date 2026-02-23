# Maria's Notebook

A comprehensive teacher planning and classroom management app for iOS and macOS, built with SwiftUI and SwiftData.

## Overview

Maria's Notebook helps educators manage their classrooms by providing tools for:

- **Student Management** - Track student profiles, progress, and development
- **Lesson Planning** - Organize lessons by subject and group with detailed write-ups
- **Attendance Tracking** - Record daily attendance with absence reasons and email reporting
- **Work Management** - Track student work assignments through their lifecycle
- **Presentation Scheduling** - Plan and schedule lesson presentations
- **Project Management** - Organize classroom projects with roles and sessions
- **Notes & Observations** - Record observations with optional AI-powered summarization
- **Backup & Restore** - Full database backup with encryption support

## Requirements

- **iOS 17.0+** / **macOS 14.0+**
- Xcode 15.0+
- Swift 5.9+

## Getting Started

See [SETUP.md](Docs/SETUP.md) for detailed build and configuration instructions.

### Quick Start

1. Clone the repository
2. Open `Maria's Notebook.xcodeproj` in Xcode
3. Select your target device (Mac or iOS Simulator)
4. Build and run (Cmd+R)

## Project Structure

```
Maria's Notebook/
├── AppCore/           # App initialization, routing, main views
├── Models/            # SwiftData model definitions
├── Services/          # Business logic and data services
├── Components/        # Reusable SwiftUI components
├── Students/          # Student management features
├── Lessons/           # Lesson management and organization
├── Work/              # Work item tracking and management
├── Presentations/     # Presentation scheduling
├── Planning/          # Planning tools and agenda views
├── Attendance/        # Attendance tracking
├── Projects/          # Project management
├── Inbox/             # Follow-up inbox and reminders
├── Settings/          # App configuration
├── Backup/            # Backup and restore functionality
├── Utils/             # Utility functions and extensions
├── ViewModels/        # MVVM view models
├── Docs/              # Documentation
└── Tests/             # Debug and test views
```

## Documentation

| Document | Description |
|----------|-------------|
| [SETUP.md](Docs/SETUP.md) | Build instructions and environment setup |
| [ARCHITECTURE.md](Docs/ARCHITECTURE.md) | App architecture and design patterns |
| [DATA_MODELS.md](Docs/DATA_MODELS.md) | SwiftData model documentation |
| [FEATURES.md](Docs/FEATURES.md) | Detailed feature documentation |
| [CloudKit/](Docs/CloudKit/) | CloudKit sync configuration and status |
| [Optimization/](Docs/Optimization/) | Performance optimization guides |

## Key Features

### Multi-Device Sync

- **CloudKit Integration** - Optional cloud sync across devices (disabled by default)
- **iCloud Key-Value Store** - Preference syncing across devices
- See [CloudKit Documentation](Docs/CloudKit/CLOUDKIT_COMPATIBILITY_REPORT.md) for setup

### Data Management

- **Automatic Backups** - Configurable auto-backup with retention policy
- **Manual Backup/Restore** - Export and import `.mtbbackup` files
- **Encrypted Backups** - Optional encryption for sensitive data

### Apple Intelligence (Optional)

- AI-powered observation summarization using Foundation Models
- See [ENABLE_FOUNDATION_MODELS.md](Docs/ENABLE_FOUNDATION_MODELS.md) for setup

### Calendar & Reminders Integration

- View calendar events in Today dashboard
- Sync reminders from a specific list

## Configuration

### CloudKit Sync

CloudKit is disabled by default. To enable:

```swift
UserDefaults.standard.set(true, forKey: "EnableCloudKitSync")
```

See [CLOUDKIT_VERIFICATION_GUIDE.md](Docs/CloudKit/CLOUDKIT_VERIFICATION_GUIDE.md) for testing.

### Backup Settings

- Auto-backup enabled by default (10 backup retention)
- Backup location: `~/Documents/Backups/Auto/`
- Custom backup format: `.mtbbackup`

## Technology Stack

- **SwiftUI** - User interface
- **SwiftData** - Local persistence
- **CloudKit** - Cloud sync (optional)
- **EventKit** - Calendar and reminders integration
- **Foundation Models** - AI features (optional, macOS 26+)

## License

Private project - All rights reserved.

## Support

For issues or feature requests, contact the development team.
