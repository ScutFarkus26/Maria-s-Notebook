# Cosmic Daybook

A comprehensive teacher planning and classroom management app for iOS and macOS, built with SwiftUI and Core Data.

## Overview

Cosmic Daybook helps educators manage their classrooms with tools for:

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

- **iOS 27.0+** / **macOS 27.0+**
- Xcode 27+
- Swift 6.0+
- Apple Developer Account (for device testing and CloudKit)

## Getting Started

1. Clone the repository
2. Open `Cosmic Daybook.xcodeproj` in Xcode
3. Select target → Signing & Capabilities → set your development team
4. Select destination (Mac or iOS Simulator) and press Cmd+R

### Build from Command Line

```bash
open "Cosmic Daybook/Cosmic Daybook.xcodeproj"

xcodebuild -project "Cosmic Daybook.xcodeproj" \
  -scheme "Cosmic Daybook" \
  -destination "platform=iOS Simulator,name=iPhone 15"
```

## Project Structure

```
Cosmic Daybook/
├── AppCore/          # App entry, bootstrapping, dependencies, routing, commands
│   ├── Persistence/  #   CoreDataStack, database errors, CloudKit configuration
│   ├── RootView/     #   Root navigation: sidebar, tabs, detail, sheets
│   ├── Windows/      #   Window registration and detail-window plumbing
│   ├── Theme/        #   AppTheme, AppColors, spacing
│   └── SampleClassroom/ # Sample-class seeder
├── Models/           # Cross-feature NSManagedObject subclasses (single-feature entities live in their feature)
├── Repositories/     # Data access repositories
├── Services/         # Cross-feature infrastructure and system integrations
│   ├── Sync/         #   CloudKit status, persistent history, dedup, synced preferences
│   ├── AI/  Search/  Calendar/  Photos/  System/  Migrations/  MCPServer/
│   └── Progression/  #   Lesson progression shared by Lessons, Planning, Presentations, Students, Work
├── Components/       # Reusable SwiftUI used by two or more unrelated features (Toast/, WaitingStudents/, Shared/…)
├── Utils/            # Extensions/, Formatting/, SwiftUI/, Visibility/, Files/, CoreData/, Platform/, Diagnostics/
│
├── Students/         # Student profiles, detail, meetings, progress, notes, import, reports
├── Lessons/          # Lesson library, detail, attachments, scope map, parsha lessons
│   └── Checklist/    #   Class checklist: Views/, Model/, ViewModels/
├── Work/             # Work items, check-ins, practice sessions
├── Presentations/    # Presentation scheduling, queues, sessions, record index
├── Attendance/       # Attendance: Store/, Rules/, Views/, Tile/, Email/, Reports/, Insights/, Delight/
├── Planning/         # Planning tools and AI lesson planning
├── SmallSequencePlanner/ # Small-group planning by area and sequence
├── CommandBar/       # Command bar: Views/, ViewModels/, Services/ (parsing, capture)
├── Today/            # Daily hub views, view model, and support
├── Todos/            # Todo models, screens, forms, and support
├── Notes/            # Observation browsing, editing, and quick capture
├── ObservationMode/  # Developmental traits and observation quick tags
│
├── Albums/           # Teaching-album PDFs: Library/, Search/, Detail/, LessonLinks/
├── BookClub/         # Book club packets, sessions, and meetings
├── Chat/             # AI chat features
├── ClassroomJobs/    # Classroom jobs and job assignments
├── CurriculumMap/    # Three-Year View: per-child grid, class heat map, the shared engine
├── GoingOut/         # Going Out planning
├── Logs/             # Application logging
├── Orders/           # Links to request from the office, tracked to received
├── ParentReports/    # Monthly parent reports, guardians, report generator
├── Parsha/           # Weekly parsha calendar and lesson tagging
├── PerpetualCalendar/# Calendar notes
├── Procedures/       # Procedure documentation
├── ProgressDashboard/# Class progress dashboard and sequence detail
├── Projects/         # Project management & sessions
├── Resources/        # Educational resources
├── Schedules/        # Schedule management
├── Stories/          # Story library: import, analysis, covers
├── Supplies/         # Supply inventory
├── Topics/           # Community topics, solutions, community meetings, and their models
│
├── SchoolYear/       # School-year lens: store, picker, scoping, rollover grades
├── Sharing/          # CloudKit sharing (classroom collaboration)
├── Siri/             # App Intents, Siri attendance, Spotlight indexing
├── Backup/           # Backup & restore
├── Settings/         # App configuration: Classroom/, Sync/, Intelligence/, DataManagement/, Templates/, Preferences/, Dashboard/
├── AppIcon.icon/     # App icon
├── Assets.xcassets/  # Asset catalog
└── CosmicDaybook.xcdatamodeld/ # Core Data model

Daybook Assistant/    # Assistant iPhone app: Attendance/, Onboarding/, Siri/, Reminders/, Sync/, FrontDesk/, Wallpaper/
                      # (also compiles ~90 notebook files by path; see project.pbxproj)
Cosmic Daybook Tests/ # Feature-mirrored test target
Scripts/              # Build lock, install/archive, structure and unused-code checks
Documentation/        # Architecture, ADRs, plans, manuals, organization audits
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

Disabled by default. Enable in Settings → CloudKit Status, then restart. See the [CloudKit Guide](../Documentation/Architecture/CloudKit/CLOUDKIT_GUIDE.md).

Container: `iCloud.DanielSDeBerry.MariasNoteBook`

### Apple Intelligence (Optional)

AI-powered observation summarization using Foundation Models. Requires the `ENABLE_FOUNDATION_MODELS` build flag. See the [AI architecture guide](../Documentation/Architecture/AI.md#8-build-flag--entitlement).

### Backup

- Auto-backup enabled by default (10 backup retention)
- Location: `~/Documents/Backups/Auto/`
- Format: `.mtbbackup` (v19 encrypted Apple Archive)
- See the [Backup System](../Documentation/Architecture/BACKUP_SYSTEM.md) for details

### SwiftLint

Configuration in `.swiftlint.yml`. Install via `brew install swiftlint`.

After moving files or folders, run `Scripts/check_repository_structure.sh` from the repository root.

## Documentation

| Document | Description |
|----------|-------------|
| [ARCHITECTURE.md](../Documentation/Architecture/ARCHITECTURE.md) | Architecture, patterns, and guidelines |
| [DATA_MODELS.md](../Documentation/Architecture/DATA_MODELS.md) | Core Data model documentation |
| [CloudKit Guide](../Documentation/Architecture/CloudKit/CLOUDKIT_GUIDE.md) | CloudKit verification & troubleshooting |
| [ADRs](../Documentation/ADRs/) | Architecture Decision Records |
| [Manuals](../Documentation/Manuals/) | Developer and user manuals |
| [BACKUP_SYSTEM.md](../Documentation/Architecture/BACKUP_SYSTEM.md) | Backup system documentation |

## Keyboard Shortcuts (macOS)

| Shortcut | Action |
|----------|--------|
| Cmd+N | New note |
| Cmd+F | Search |
| Cmd+, | Settings |
| Esc | Close sheet/cancel |

## Troubleshooting

**Signing issues** — Verify Apple Developer account and team in Signing & Capabilities

**CloudKit not syncing** — Check iCloud account, network, container ID, and restart app after enabling. See the [CloudKit Guide](../Documentation/Architecture/CloudKit/CLOUDKIT_GUIDE.md).

**Slow performance** — Check for unfiltered `@FetchRequest` usage. Profile with Instruments.

## License

Private project — All rights reserved.
