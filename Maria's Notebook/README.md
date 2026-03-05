# Maria's Notebook

A comprehensive teacher planning and classroom management app for iOS and macOS, built with SwiftUI and SwiftData.

## Overview

Maria's Notebook helps educators manage their classrooms with tools for:

- **Student Management** — Track profiles, progress, meetings, and development
- **Lesson Planning** — Organize lessons by subject/group with write-ups and attachments
- **Attendance Tracking** — Daily attendance with absence reasons and email reporting
- **Work Management** — Track assignments through active → review → complete lifecycle
- **Presentation Scheduling** — Plan and schedule lesson presentations with agenda views
- **Project Management** — Organize projects with roles, sessions, and templates
- **Notes & Observations** — Record observations with optional AI summarization
- **Community** — Community topics, proposed solutions, and attachments
- **Progression** — Student progress tracking and analytics
- **Todos** — Smart todo lists with parsing, notifications, and location support
- **Schedules** — Schedule management and time allocation
- **Issues** — Issue tracking with priorities and actions
- **Supplies** — Supply inventory and transaction tracking
- **Procedures** — Procedure documentation
- **Backup & Restore** — Full database backup with encryption support

## Requirements

- **iOS 26.0+** / **macOS 26.0+**
- Xcode 16+
- Swift 5.9+
- Apple Developer Account (for device testing and CloudKit)

## Getting Started

1. Clone the repository
2. Open `Maria's Notebook.xcodeproj` in Xcode
3. Select target → Signing & Capabilities → set your development team
4. Select destination (Mac or iOS Simulator) and press Cmd+R

### Build from Command Line

```bash
open "Maria's Notebook/Maria's Notebook.xcodeproj"

xcodebuild -project "Maria's Notebook.xcodeproj" \
  -scheme "Maria's Notebook" \
  -destination "platform=iOS Simulator,name=iPhone 15"
```

## Project Structure

```
Maria's Notebook/
├── AppCore/          # App entry, bootstrapping, navigation, routing
├── Models/           # SwiftData @Model definitions (51 models)
├── Services/         # Business logic (70+ services)
├── ViewModels/       # Shared ViewModels (Today, GiveLesson, etc.)
├── Components/       # Reusable SwiftUI components
├── Utils/            # Extensions & utilities
├── Repositories/     # Data access repositories (13 repos)
│
├── Students/         # Student profiles, meetings, detail views
├── Lessons/          # Lesson library, attachments, exercises
├── Work/             # Work items, check-ins, practice sessions
├── Presentations/    # Presentation scheduling
├── Attendance/       # Attendance tracking
├── Planning/         # Planning & checklist tools
├── Inbox/            # Follow-up inbox
│
├── Agenda/           # Calendar day/month grid views
├── Chat/             # AI chat features
├── Community/        # Community topics & solutions
├── Issues/           # Issue tracking
├── Logs/             # Application logging
├── Procedures/       # Procedure documentation
├── Progression/      # Student progress tracking & analytics
├── Projects/         # Project management & sessions
├── Resources/        # Educational resources
├── Schedules/        # Schedule management
├── Supplies/         # Supply inventory
├── Topics/           # Educational topics
│
├── Backup/           # Backup & restore
├── Settings/         # App configuration
└── Docs/             # Documentation
```

## Configuration

### Capabilities (Entitlements)

| Capability | Purpose |
|------------|---------|
| iCloud | CloudKit sync and key-value storage |
| Push Notifications | CloudKit change notifications |
| App Sandbox | macOS security (with file access exceptions) |

**Privacy permissions:** Camera (note photos), Reminders (sync), Calendars (events)

### CloudKit Sync

Disabled by default. Enable in Settings → CloudKit Status, then restart. See [CloudKit Guide](Docs/CloudKit/CLOUDKIT_GUIDE.md).

Container: `iCloud.DanielSDeBerry.MariasNoteBook`

### Apple Intelligence (Optional)

AI-powered observation summarization using Foundation Models. Requires `ENABLE_FOUNDATION_MODELS` build flag. See [Setup Guide](Docs/ENABLE_FOUNDATION_MODELS.md).

### Backup

- Auto-backup enabled by default (10 backup retention)
- Location: `~/Documents/Backups/Auto/`
- Format: `.mtbbackup` (optional encryption)
- See [Backup System](Backup/BACKUP_SYSTEM.md) for details

### SwiftLint

Configuration in `.swiftlint.yml`. Install via `brew install swiftlint`.

## Documentation

| Document | Description |
|----------|-------------|
| [ARCHITECTURE.md](Docs/ARCHITECTURE.md) | Architecture, patterns, and guidelines |
| [DATA_MODELS.md](Docs/DATA_MODELS.md) | SwiftData model documentation |
| [CloudKit Guide](Docs/CloudKit/CLOUDKIT_GUIDE.md) | CloudKit verification & troubleshooting |
| [ADRs](Docs/ADRs/) | Architecture Decision Records |
| [BACKUP_SYSTEM.md](Backup/BACKUP_SYSTEM.md) | Backup system documentation |

## Keyboard Shortcuts (macOS)

| Shortcut | Action |
|----------|--------|
| Cmd+N | New note |
| Cmd+F | Search |
| Cmd+, | Settings |
| Esc | Close sheet/cancel |

## Troubleshooting

**"No such module 'SwiftData'"** — Verify deployment target is iOS 26+ / macOS 26+

**Signing issues** — Verify Apple Developer account and team in Signing & Capabilities

**CloudKit not syncing** — Check iCloud account, network, container ID, and restart app after enabling. See [CloudKit Guide](Docs/CloudKit/CLOUDKIT_GUIDE.md).

**Slow performance** — Check for unfiltered `@Query` usage. Profile with Instruments.

## License

Private project — All rights reserved.
