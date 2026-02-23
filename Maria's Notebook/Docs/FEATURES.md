# Features Guide

This document provides detailed documentation of Maria's Notebook features.

## Navigation

The app uses a split-view navigation pattern:

- **Sidebar** (Mac/iPad): Full navigation menu
- **Tab Bar** (iPhone): Compact navigation with "More" menu

### Main Sections

| Section | Icon | Purpose |
|---------|------|---------|
| Today | sun.max | Daily dashboard |
| Attendance | checklist | Attendance tracking |
| Note | square.and.pencil | Quick note entry |
| Students | person.3 | Student roster |
| Lessons | book | Lesson library |
| More | ellipsis.circle | Additional features |

### Planning Sub-Menu

| Section | Purpose |
|---------|---------|
| Checklist | Class/subject checklists |
| Presentations | Agenda and scheduling |
| Open Work | Work item management |
| Projects | Project management |

---

## Today Dashboard

The Today view provides a daily overview of classroom activities.

### Features

- **Calendar Events**: Shows today's events from connected calendars
- **Reminders**: Synced from a configured reminders list
- **Active Work**: Work items requiring attention
- **Attendance Summary**: Quick attendance status
- **Recent Presentations**: Recently given lessons

### Usage

1. Navigate to Today
2. View consolidated daily information
3. Tap items to navigate to details
4. Use quick actions for common tasks

---

## Student Management

### Student Roster

View and manage all students in the classroom.

**Features:**
- Grid or list view
- Filter by level (Lower/Upper)
- Search by name
- Sort by name or manual order

**Student Fields:**
- First name, Last name
- Nickname (optional)
- Birthday
- Level (Lower Elementary / Upper Elementary)
- Date started
- Custom sort order

### Student Detail View

Comprehensive view of individual student information.

**Tabs:**
- **Overview**: Basic info, upcoming lessons, recent activity
- **History**: Lesson presentation history
- **Notes**: Student observations and notes
- **Progress**: Progress tracking and heatmaps
- **Files**: Attached documents
- **Meetings**: Meeting records

### Student Lessons

Track which lessons each student has received.

**States:**
- **Inbox**: Unscheduled lessons
- **Scheduled**: Planned presentations
- **Presented**: Completed presentations

**Actions:**
- Schedule for a date
- Mark as presented
- Add follow-up work
- Record notes

---

## Lesson Management

### Lesson Library

Organize curriculum lessons by subject and group.

**Organization:**
- Subject (e.g., Math, Language, Sensorial)
- Group (e.g., Decimal System, Fractions)
- Individual lessons within groups

**Lesson Types:**
- **Album** - Standard curriculum lessons
- **Personal** - Custom lessons
  - Personal
  - Extension
  - Remediation

**Lesson Fields:**
- Name and subheading
- Subject and group
- Write-up (Markdown content)
- Attached file (Pages, PDF)
- Default work kind

### Lesson Import

Import lessons from CSV files.

**CSV Format:**
```csv
name,subject,group,subheading
"Golden Beads",Math,Decimal System,"Introduction to place value"
```

---

## Attendance Tracking

### Daily Attendance

Record attendance for all students each day.

**Statuses:**
- Unmarked (default)
- Present
- Absent (with reason)
- Tardy
- Left Early

**Absence Reasons:**
- Sick
- Vacation

### Features

- **Quick Actions**: Mark all present, reset day
- **Locking**: Lock attendance to prevent changes
- **Email Reports**: Send attendance summary emails
- **Notes**: Add notes to individual records

### Email Integration

Configure automated attendance emails:

1. Go to Settings > Attendance Email
2. Enable email feature
3. Set recipient and sender addresses
4. Attendance summaries sent when attendance is locked

---

## Work Management

### Work Items

Track student work through its lifecycle.

**Work Types:**
- Research
- Follow Up
- Practice
- Report

**Work Statuses:**
- **Active**: In progress
- **Review**: Ready for review
- **Complete**: Finished

### Work Detail

Detailed view of individual work items.

**Features:**
- Title and notes
- Linked lesson
- Student participants
- Completion tracking per student
- Work steps (optional)
- Check-ins
- Notes

### Work Agenda

View and manage all open work.

**Views:**
- List view with filters
- Calendar view for scheduling

**Filters:**
- By status (Active/Review)
- By work type
- By student
- By subject

### Work Steps

Break work into discrete steps:

1. Add steps with titles
2. Track completion of each step
3. View overall progress

### Check-Ins

Record periodic check-ins on work:

1. Open work detail
2. Add check-in with notes
3. Track engagement over time

---

## Presentation Scheduling

### Agenda View

Plan and schedule lesson presentations.

**Features:**
- Calendar-based scheduling
- Drag and drop
- Week/day views
- Group presentations

### Creating Presentations

1. From lesson detail, tap "Schedule"
2. Select students
3. Choose date and time
4. Confirm scheduling

### Recording Presentations

1. From scheduled item, tap "Mark Presented"
2. Presentation record created
3. Optional: Create follow-up work

### Presentation History

View all past presentations:

- Filter by date range
- Filter by student
- Filter by subject
- Paginated loading for performance

---

## Project Management

### Projects

Organize classroom projects with structured sessions.

**Project Fields:**
- Title
- Book title (optional)
- Member students
- Active status

### Project Sessions

Individual meetings or sessions within a project.

**Session Fields:**
- Meeting date
- Chapter/pages covered
- Agenda items
- Notes

### Templates

Create reusable assignment templates:

- Template title
- Instructions
- Linked lesson (optional)

---

## Notes & Observations

### Note Types

Notes can be attached to various contexts:

- Students (scoped to one or all)
- Lessons
- Work items
- Presentations
- Attendance records
- Project sessions
- Meetings

### Note Fields

- Body text
- Category (Academic, Behavioral, Social, etc.)
- Scope (All students, specific student(s))
- Pinned status
- Include in report flag
- Image attachment

### Quick Note

Quickly create notes from anywhere:

1. Tap the floating note button
2. Enter note content
3. Select context (optional)
4. Save

### AI Summarization (Optional)

Summarize multiple observations using Apple Intelligence:

1. Enable Foundation Models (see ENABLE_FOUNDATION_MODELS.md)
2. Select multiple observations
3. Tap sparkle icon
4. Choose summary format:
   - Key Points (bullet list)
   - Narrative (paragraph)

---

## Backup & Restore

### Manual Backup

Create a backup of all data:

1. Go to Settings > Data Management
2. Tap "Create Backup"
3. Choose location and filename
4. Optional: Enable encryption

**Backup Format:** `.mtbbackup`

### Restore from Backup

Restore data from a backup file:

1. Go to Settings > Data Management
2. Tap "Restore from Backup"
3. Select backup file
4. Confirm restore (overwrites current data)

### Auto-Backup

Automatic backups are enabled by default.

**Configuration:**
- Enabled by default
- Retention: 10 backups
- Location: `~/Documents/Backups/Auto/`
- Triggered on app termination (macOS)

---

## Settings

### Age Settings

Configure aging indicators for lessons and work:

**Lesson Age:**
- Warning days threshold
- Overdue days threshold
- Custom colors

**Work Age:**
- Warning days threshold
- Overdue days threshold
- Custom colors

### Attendance Email

Configure attendance email reports:

- Enable/disable
- Recipient address
- Sender address

### Data Management

- Create backup
- Restore from backup
- Encryption preference

### CloudKit Status

Monitor CloudKit sync status:

- Sync enabled/disabled
- Last sync time
- Error information
- Manual sync trigger

---

## Integrations

### Calendar

View calendar events in Today dashboard:

1. Grant calendar access when prompted
2. Events appear in Today view
3. Tap to view details

### Reminders

Sync reminders to Today dashboard:

1. Grant reminders access when prompted
2. Configure sync list in Settings
3. Reminders appear in Today view

### iCloud Sync

Sync data across devices (optional):

1. Enable CloudKit sync
2. Sign in to iCloud on all devices
3. Data syncs automatically

### Preference Sync

Preferences sync automatically via iCloud Key-Value Store:

- Lesson/Work age settings
- Attendance email settings
- Backup encryption preference
- Color customizations

---

## Keyboard Shortcuts (macOS)

| Shortcut | Action |
|----------|--------|
| Cmd+N | New note |
| Cmd+F | Search |
| Cmd+, | Settings |
| Esc | Close sheet/cancel |

---

## Performance Tips

### Large Datasets

For classrooms with many students or lessons:

- Use filters to limit displayed data
- Pagination loads data incrementally
- Background operations don't block UI

### Sync Optimization

- CloudKit syncs in background
- Preference sync is lightweight (< 1MB)
- Large data uses external storage

---

## Troubleshooting

### Data Not Appearing

1. Pull to refresh
2. Check filters aren't hiding data
3. Verify CloudKit sync status

### Slow Performance

1. Check for unfiltered views
2. Reduce displayed data with filters
3. See optimization documentation

### Sync Issues

1. Verify iCloud account
2. Check network connectivity
3. Review CloudKit status in Settings

---

## Related Documentation

- [ARCHITECTURE.md](ARCHITECTURE.md) - Technical architecture
- [DATA_MODELS.md](DATA_MODELS.md) - Data model reference
- [Optimization/](Optimization/) - Performance guides
- [CloudKit/](CloudKit/) - CloudKit documentation
