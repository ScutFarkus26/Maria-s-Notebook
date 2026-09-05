# Module dependency map — 2026-09-05

Input to Phase 6 of `BUILD_AND_LAUNCH_PERFORMANCE_PLAN.md`. Computed from the source tree at
`491e297d`: every `struct`/`class`/`enum`/`protocol`/`actor`/`typealias` declared under
`Maria's Notebook/<Folder>/` is attributed to that folder; each file is then scanned for
identifiers that name a type declared in a *different* folder. "out→folders" is how many other
folders a folder references; "in←refs" is how many (file, type) references point at it. Name
collisions between folders are counted once, by first declaration seen, so treat single-digit
edges as approximate.

```
folder                 files   lines out→folders  in←refs  top outbound (distinct types referenced)
Students                 151   26585          29      563  AppCore:442, Models:152, Work:64, Utils:60, Lessons:48, Components:40
Services                  67   14069          26      235  AppCore:117, Models:73, Students:31, Work:17, Lessons:9, Notes:7
Work                      84   13998          19      388  AppCore:263, Students:53, Models:49, Components:31, Presentations:27, Lessons:25
Presentations             71   13911          14      193  AppCore:217, Models:86, Work:63, Students:50, Lessons:25, Utils:24
AppCore                   63   12247          37     3030  Services:39, Students:30, Work:26, Models:24, Components:22, Backup:21
Backup                    59   12017          26      132  Models:260, AppCore:62, Students:50, Work:50, Projects:39, Albums:33
Components                87   10163          26      221  AppCore:278, Students:42, Models:30, Work:24, Services:24, Lessons:22
Lessons                   49    9192          17      249  AppCore:147, Students:28, Models:27, Components:22, Work:21, Presentations:11
Settings                  36    7725          21       44  AppCore:188, Services:31, Backup:25, Models:25, Utils:19, Students:17
Todos                     34    7142          10        7  AppCore:166, Models:63, Presentations:23, Students:16, Utils:8, Components:7
Today                     36    6313          16       40  AppCore:134, Students:41, Models:37, Work:21, Attendance:16, Presentations:11
Notes                     29    6045          17       30  AppCore:123, Models:38, Students:25, Utils:13, Components:11, Presentations:11
Albums                    24    5514           9       73  AppCore:50, Parsha:7, Lessons:7, Services:6, Utils:3, Stories:3
Planning                  24    4483          19       36  AppCore:51, Students:26, Models:21, Lessons:11, Work:8, Services:6
Models                    58    4382          22     1013  AppCore:49, Work:29, Students:18, Lessons:6, Albums:6, Projects:5
Attendance                20    4095          15       87  AppCore:72, Students:18, Utils:12, Models:5, Sharing:5, Presentations:3
Stories                   18    3226          11       27  AppCore:21, Services:7, Students:5, Lessons:5, Components:4, Presentations:4
Resources                 19    3216          10       19  AppCore:66, Components:11, Today:9, Models:7, Lessons:5, Presentations:4
Projects                  23    3087           9       67  AppCore:98, Work:19, Students:12, Backup:9, Lessons:9, Utils:7
Utils                     45    2810          11      255  AppCore:25, Students:8, Models:6, Settings:2, Lessons:2, Services:2
BookClub                  21    2697           6       32  AppCore:23, Stories:8, Components:6, Students:5, Utils:5, Presentations:3
Parsha                     9    2015           7       26  AppCore:29, Lessons:10, Services:3, Backup:2, Repositories:2, Models:1
Chat                       9    1917          14        9  AppCore:54, Services:7, Settings:6, Models:5, Work:5, Students:4
ParentReports              9    1660          11       30  AppCore:24, Students:10, Models:7, Services:6, Attendance:6, Utils:4
Repositories              14    1399          11       24  Sharing:14, Backup:14, Models:12, Students:10, Lessons:6, AppCore:5
GoingOut                  11    1355           7       15  AppCore:45, Students:6, Components:3, Models:2, Lessons:1, Notes:1
ProgressDashboard          8    1328          10        3  AppCore:20, Students:7, Models:5, Work:5, Lessons:3, Today:2
Inbox                      5    1306          12       26  AppCore:21, Models:8, Work:6, Components:3, Students:3, Backup:2
SmallSequencePlanner       5    1227          10        1  AppCore:26, Students:7, Models:6, Work:2, Today:2, Services:2
Procedures                 5    1218           8        1  AppCore:34, Models:8, Today:3, Components:2, Presentations:1, Students:1
Sharing                   10    1151           6       58  AppCore:14, Services:4, Utils:1, Attendance:1, Repositories:1, Backup:1
Supplies                   8    1144           6        1  AppCore:31, Models:11, Today:4, Components:2, Settings:1, Presentations:1
Logs                       3    1105          12        2  AppCore:26, Students:11, Utils:5, Attendance:2, Models:2, Components:2
Schedules                  3     988           5        1  AppCore:14, Models:8, Students:3, Components:2, Presentations:1
PerpetualCalendar          6     846           5       13  AppCore:17, Models:3, Parsha:2, Settings:1, Students:1
ObservationMode            7     829           5        5  AppCore:14, Models:7, Components:4, Students:3, Attendance:1
SchoolYear                 6     700           6       29  AppCore:10, Projects:2, Utils:2, Albums:1, Students:1, Work:1
Siri                       8     684           8       25  AppCore:13, Students:10, Models:3, Presentations:2, Lessons:2, Work:1
Topics                     5     659           8        4  AppCore:12, Models:11, Backup:1, Utils:1, Services:1, Work:1
ViewModels                 3     629           9        2  Services:13, Models:6, Work:4, Students:2, Lessons:2, AppCore:2
Agenda                     5     459           6        4  AppCore:21, Components:3, Utils:2, Models:2, Students:2, Community:2
Community                  1     286           8        4  Topics:3, AppCore:3, Models:2, Utils:2, Backup:1, Work:1
ClassroomJobs              2     107           1       12  AppCore:2
Progression                1      76           4        8  Work:4, Lessons:1, AppCore:1, Presentations:1

Feature folders whose only outbound deps are core folders (package-ready leaves):
  LEAF ClassroomJobs {'AppCore': 2}

Feature folders with cross-feature deps (what they need):
  Students               -> {'Work': 64, 'Projects': 7, 'Lessons': 48, 'Albums': 1, 'Notes': 5, 'Progression': 4, 'Presentations': 36, 'Planning': 5, 'Attendance': 6, 'Parsha': 1, 'PerpetualCalendar': 6, 'Inbox': 3, 'ProgressDashboard': 2, 'SchoolYear': 9, 'ParentReports': 4, 'ObservationMode': 1, 'BookClub': 1, 'Siri': 5, 'Stories': 1, 'Today': 3, 'Settings': 1}
  Work                   -> {'Siri': 1, 'Presentations': 27, 'Lessons': 25, 'Inbox': 6, 'Students': 53, 'Planning': 6, 'Today': 2, 'Notes': 1, 'Projects': 2, 'ParentReports': 1, 'SchoolYear': 2}
  Presentations          -> {'Lessons': 25, 'Students': 50, 'Work': 63, 'Notes': 2, 'Planning': 14, 'Attendance': 1, 'ParentReports': 2}
  Lessons                -> {'Students': 28, 'Parsha': 5, 'Presentations': 11, 'Albums': 11, 'Work': 21, 'Inbox': 1, 'Attendance': 4, 'Resources': 1, 'Settings': 1}
  Settings               -> {'Presentations': 6, 'Students': 17, 'Today': 1, 'Lessons': 8, 'Attendance': 5, 'Work': 3, 'ParentReports': 1, 'Siri': 3, 'Inbox': 1, 'Notes': 1, 'SchoolYear': 1, 'Agenda': 1, 'Projects': 1}
  Todos                  -> {'Presentations': 23, 'Students': 16, 'Attendance': 3, 'Work': 1, 'Parsha': 1}
  Today                  -> {'Students': 41, 'Work': 21, 'Lessons': 8, 'Siri': 1, 'Presentations': 11, 'Attendance': 16, 'Todos': 2, 'Notes': 2, 'ParentReports': 3}
  Notes                  -> {'Students': 25, 'Attendance': 5, 'Lessons': 5, 'Settings': 2, 'Today': 2, 'ObservationMode': 3, 'ParentReports': 3, 'Presentations': 11, 'Work': 5, 'Projects': 1, 'GoingOut': 1}
  Albums                 -> {'Attendance': 1, 'Students': 2, 'Parsha': 7, 'Lessons': 7, 'Inbox': 1, 'Stories': 3}
  Planning               -> {'Lessons': 11, 'Students': 26, 'Attendance': 2, 'Albums': 1, 'Work': 8, 'Inbox': 2, 'Agenda': 1, 'Presentations': 4, 'Chat': 1, 'Settings': 3, 'SchoolYear': 1, 'Parsha': 1}
  Attendance             -> {'Students': 18, 'Notes': 1, 'Presentations': 3, 'Settings': 3, 'Work': 2, 'Today': 2, 'SchoolYear': 3, 'Parsha': 1}
  Stories                -> {'Students': 5, 'Presentations': 4, 'BookClub': 2, 'Attendance': 1, 'Lessons': 5, 'Resources': 1}
  Resources              -> {'Today': 9, 'Presentations': 4, 'Parsha': 3, 'Lessons': 5, 'Students': 4}
  Projects               -> {'Students': 12, 'Work': 19, 'Lessons': 9, 'Presentations': 2}
  BookClub               -> {'Stories': 8, 'Students': 5, 'Presentations': 3}
  Parsha                 -> {'Lessons': 10, 'Albums': 1}
  Chat                   -> {'Presentations': 2, 'Work': 5, 'Settings': 6, 'Students': 4, 'Siri': 1, 'Lessons': 1, 'Attendance': 1}
  ParentReports          -> {'Students': 10, 'Attendance': 6, 'Lessons': 1, 'Work': 2, 'GoingOut': 1, 'ClassroomJobs': 1, 'Settings': 1}
  GoingOut               -> {'Students': 6, 'Lessons': 1, 'Notes': 1}
  ProgressDashboard      -> {'Students': 7, 'Today': 2, 'Lessons': 3, 'Progression': 2, 'Work': 5, 'BookClub': 1}
  Inbox                  -> {'Students': 3, 'Planning': 2, 'Lessons': 2, 'Presentations': 1, 'Work': 6, 'SchoolYear': 1}
  SmallSequencePlanner   -> {'Work': 2, 'Students': 7, 'Today': 2, 'Lessons': 1, 'Presentations': 1, 'SchoolYear': 1, 'Stories': 1}
  Procedures             -> {'Presentations': 1, 'Today': 3, 'Students': 1, 'Notes': 1}
  Supplies               -> {'Settings': 1, 'Today': 4, 'Presentations': 1}
  Logs                   -> {'Attendance': 2, 'Students': 11, 'SchoolYear': 1, 'Today': 1, 'Presentations': 1, 'Work': 1, 'Notes': 1, 'Projects': 1}
  Schedules              -> {'Students': 3, 'Presentations': 1}
  PerpetualCalendar      -> {'Settings': 1, 'Parsha': 2, 'Students': 1}
  ObservationMode        -> {'Students': 3, 'Attendance': 1}
  SchoolYear             -> {'Albums': 1, 'Students': 1, 'Projects': 2, 'Work': 1}
  Siri                   -> {'Students': 10, 'Presentations': 2, 'Lessons': 2, 'Work': 1, 'Notes': 1}
  Topics                 -> {'Work': 1, 'Community': 1, 'Students': 1}
  Agenda                 -> {'Students': 2, 'Community': 2}
  Community              -> {'Topics': 3, 'Work': 1, 'Agenda': 1, 'Settings': 1}
  Progression            -> {'Lessons': 1, 'Presentations': 1, 'Work': 4}
```

## What it says

- **There are no package-ready feature leaves.** Only `ClassroomJobs` (2 files) depends on nothing
  but `AppCore`. Every candidate the plan named — `Parsha`, `Stories`, `PerpetualCalendar`,
  `Albums` — reaches into `Lessons`, `Students`, `Presentations`, or each other.
- **The core is a cycle.** `Students` → `Work` (64) → `Presentations` (27) → `Students` (50), with
  `Lessons` referenced by all three and referencing all three. Together they are 64 k lines, a third
  of the app, and cannot be split from each other without first inverting some of those edges
  through protocols or shared value types.
- **`AppCore` is two things.** It has the highest fan-in by far (3 030 references) because it holds
  the infrastructure every file uses — `CoreDataStack`, `AppDependencies`, `AppRouter`, `Theme`,
  `AppColors`, `UIConstants`, `AppCalendar`, `SaveCoordinator`, logging — but it also holds the root
  UI (`RootView`, `RootDetailContent`, the main window scenes), which references every feature
  (37 outbound folders). A core package has to take the first half and leave the second.

## Corrected Phase 6 shape

1. **`DaybookCore` first, and it is smaller than "AppCore + Models".** The seam already exists: the
   31 files the Daybook Assistant target compiles from the app (`CoreDataStack*`, `CloudKitConfigurationService`,
   `PersistentHistoryProcessor`, `AppLogging`/`Logger+Extensions`, `AppCalendar`, `SaveCoordinator`,
   `UserDefaultsKeys`, `RepositoryProtocol`, the attendance/student/classroom entity files,
   `ClassroomPermissions`, `SharingPreferences`, `UIConstants`, `String+Extensions`,
   `LaunchSignposts`, and the model bundle). Start from that list and add only what it fails to
   compile without. Expect `Models/` (58 files) to come along in full, and expect to split a few
   `AppCore` files where infrastructure and root UI share a file.
2. **Then measure.** The emit-module job for the app shrinks by roughly the moved fraction; the
   Assistant stops recompiling core. That is the whole, honest Phase 6 return available without
   breaking the Students/Work/Presentations/Lessons cycle.
3. **Breaking the cycle is a separate project**, not a build-performance task: it needs protocol
   seams (for example `Work` consuming a `PresentationSummary` value instead of `Presentations`
   views and view models) and touches the most-edited code in the app. Do not schedule it under
   this plan.
