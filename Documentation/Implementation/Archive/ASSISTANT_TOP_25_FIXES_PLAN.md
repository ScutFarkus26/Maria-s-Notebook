> Moved from `~/.claude/plans/polymorphic-crafting-kahan.md` on 2026-10-04; archived the same day: built and on main.

# Daybook Assistant: 20 fixes from the top-25 review

> **Built 2026-09-29** (944eb2c5) The 20 fixes are on main (Milestones 8–12 in `../../PROGRESS.md`); shipped to devices under Milestone 13.

## Context
On 2026-09-29 I reviewed the Daybook Assistant (the assistant's attendance app) and
ranked 25 improvements. Danny picked 20 of them: 3–17, 19, 22–25. Items 1 and 2 are
talked through after this plan:
- **1:** a tap aimed at the half-hidden bottom row hits the Late pill and marks the class
  absent.
- **2:** 22 children don't fit on her iPhone SE.

Both reshape the same tiles and bottom bar as #10, #12 and #13, so those three wait for
that conversation (Phase 5).

Decisions made:
- **#3** adds a departure time: new `AttendanceRecord.leftAt` (schema 11, backup v33).
- **#9** adds Appointment, Family and Other. Choosing Other opens the day's note.
- **#17** reminds her at 8:15 by default, and the time is a setting.

Constraints found while exploring:
- The classroom share holds only Student, AttendanceRecord, NonSchoolDay,
  SchoolDayOverride and AttendanceDayLock.
- A new AttendanceRecord field must be deployed to CloudKit **Production** before any
  device runs a build that writes it (CLOUDKIT_GUIDE.md §1).
- `CLOUDKIT_ENVIRONMENT` is Production for Debug *and* Release. Every simulator run of
  the real app therefore touches the live classroom share; the Sample Class
  (`-AssistantSampleClass`, in-memory) is the safe test bed.
- The Assistant targets iOS 18.0 and compiles ~49 notebook files by explicit path (the
  pbxproj Sources list). Shared-file changes reach both apps; anything newer than iOS 18
  needs `#available`.

## Work order
- One commit per item (or tight pair) on a branch off main, each built and tested.
- Phases run in order: tests first, and the intents need the Phase 4a stack accessor.
- Danny's manual steps are collected at the end.

---

## Phase 0 — Foundations

### #24 Assistant test target
- New target **Daybook Assistant Tests**:
  - Swift Testing, as the notebook's 297 test files are.
  - Hosted by the Assistant app, iOS simulator.
  - Synchronized folder `Daybook Assistant Tests/`.
  - Added to the Assistant scheme's (currently empty) TestAction.
  - The pbxproj is hand-edited the way d304f6b6 added the Assistant (DA-prefixed IDs).
- Test host guard, same as the notebook's `AppBootstrapping.isRunningUnitTests`
  (AppBootstrapping.swift:19): `AssistantApp` skips `bootstrapper.start()` when
  `XCTestConfigurationFilePath` is set. Without it, the host would open the simulator's
  Production store.
- Tests make stacks with `CoreDataStack(enableCloudKit: false, inMemory: true)`.
- First suites pin down today's rules:
  - `statusAfterTap`
  - `gridNames` (two Ettys, two Sarahs)
  - `LatePhaseMemory`: UserDefaults becomes injectable
  - the Late → Undo batch
  - `dayOff`
- Every later item adds its tests here, or to `Cosmic Daybook Tests/Attendance/` for
  shared files.

### #23 Privacy manifest + icon variants
- Add `Daybook Assistant/PrivacyInfo.xcprivacy`:
  - UserDefaults / CA92.1 only. Its sources use no file-timestamp, boot-time or
    disk-space APIs.
  - No tracking, no collected data types.
  - The synchronized folder picks the file up automatically.
- Icon, following the notebook's pattern (a2a01d62). There's no source art today, only
  a flat 1024 PNG.
  1. Redraw the icon as SVG layers in its colours: the cream gradient, the purple check
     and the pink rule.
  2. Build `Daybook Assistant/AppIcon.icon` (Icon Composer bundle with light and dark
     fills), used on iOS 26+.
  3. Render dark and tinted luminosity PNGs from those layers into the appiconset, used
     on iOS 18.
- Fix the stale entitlements comment ("Development until the notebook moves to
  Production").

---

## Phase 1 — Attendance correctness

### #3 Time rules + departure time (schema 11)
- Model:
  - `leftAt: Date?` on AttendanceRecord.
  - `currentSchemaVersion` 10 → 11 and a history line.
  - New `CoreDataSchemaVersionTests.expectedModelDigest`.
  - Backup v33: writer/reader versions, the DTO field, export and import.
  - Golden re-record (`TEST_RUNNER_RECORD_BACKUP_GOLDEN=1`).
  - Dedup merge carries `leftAt`.
  - The file list mirrors commit a3f5eea2 (14 files).
- Rules in `CDAttendanceStore.mark(_:as:at:)`, shared so notebook and MCP marks obey
  them:
  - Times are stamped only when the record's day is today. Past and future marks get
    no time, so a Monday fixed on Wednesday no longer shows "3:42 PM".
  - Present or Tardy → Left Early keeps `markedAt` (the arrival) and sets `leftAt = now`.
  - Unmarked or Absent → Left Early sets only `leftAt`.
  - Leaving Left Early clears `leftAt`.
- Tile: "8:02 → 1:15" for Left Early.
- Tests: extend `AttendanceMarkedAtTests`.
- **Danny, before any install** (Cosmic Daybook/CLAUDE.md):
  1. Tick `-InitializeCloudKitSchema` for one run of a DEBUG build with
     `CLOUDKIT_ENVIRONMENT=Development`, in a simulator, not on the Mac.
  2. Check the CloudKit Console.
  3. Deploy Development → Production.
  4. Untick the argument.
  5. Update all devices together.

### #4 Future days (Assistant-level)
- Enforced in the Assistant's view model and intents only. The notebook's grid cycles
  unmarked→present→…, and MCP marks future days, so a shared-store refusal would
  strand both.
- On a future day:
  - only Absent (with a reason) and notes are allowed;
  - the Late switch is hidden;
  - a tap on an unmarked tile shows the hint line "Only absences ahead of time";
  - the menu offers only the Absent options.
- Past days keep everything, including Late: catching up a missed morning.

### #6 Haptics only for her own taps
- `AssistantAttendanceTile`: the selection haptic moves off `row.status` onto a tap
  counter bumped by `tap()` and the menu actions.
- Imports and day changes stay silent.

### #7 Errors that clear and tell the truth
- `load()` clears `errorMessage` on success.
- The save-failure text becomes "Couldn't save that mark. Try again." A failed local
  save isn't a network problem and won't retry by itself.
- Messages name the day on screen, not "today".

### #8 Roster by day (shared)
Your live roster shows why a plain date filter is unsafe: many start dates are
data-entry dates (2025-11-29, 2025-12-09) for children who were there from August 2025.

- New shared file `Cosmic Daybook/Attendance/AttendanceRoster.swift`, added to the
  Assistant's compile list. `AttendanceRoster.students(on:from:records:)` shows a child
  on a day when either:
  - **they have an attendance record that day** (the record is proof, so history is
    never hidden), or
  - **their dates say so**:
    - `dateStarted` is nil or ≤ the day, and
    - they're enrolled, or departed with `dateWithdrawn` ≥ the day. `dateWithdrawn` is
      the last day in class, inclusive (RolloverService). A departed child with no date
      shows only when they have a record.
- The date semantics match `CDStudent.isActive(in:)` (SchoolYear/SchoolYearScoping.swift)
  for enrolled children, except that departed children without a date don't fail open.
- Callers switched from "enrolled now":
  - Assistant `load()`
  - the notebook grid (`Today/Views/AttendanceExpandedView.swift:23`, which feeds
    AttendanceMacView, AttendanceStandaloneView and TodayView), whose mark-all and reset
    follow the same visible list
  - MCP `attendance_for_day` and `mark_all_present`
    (`MCPNotebookTools+Attendance.swift:48,353`)
- Fix the editor that invents start dates:
  - `StudentDetailView.swift:154,171` saves `draftStartDate` only if a date was already
    set or the user changed it.
  - Today any edit turns a nil start date into the edit date.
- Tests:
  - notebook: `CoreDataTestHelpers.seedStudent(…dateStarted:dateWithdrawn:)` already
    exists;
  - Assistant: the new target.
- Optional for Danny: correct the placeholder start dates. They only matter for 2025–26
  days that have no record.

### #22 Less work per tap
- `CDAttendanceStore.markUnmarkedAbsent` and `markAllPresent` fetch the day's records
  once, then create only the missing ones.
- They keep the lock/permission gate, the dedup winner, the `destinationStore`
  assignment, the stamp, and the "changed only" return value that the Late Undo relies
  on.
- Single-tap `ensureRecord` keeps its re-fetch.
- Assistant view model:
  - updates changed rows in place instead of `load()` after every save;
  - caches the day's roster and short names;
  - reloads fully only on imports and day changes;
  - fetches students with a predicate instead of all 40-plus.

---

## Phase 2 — Joining & identity

### #5 Join errors visible
- Shared `ClassroomSharingService`:
  - `acceptShare`'s trailing `try refreshParticipants()` becomes best-effort (`try?` +
    log). Today it can throw after a successful accept and pin, so `.didJoinClassroom`
    never posts and a good join reads as a failure.
  - `shareError` clears on success.
- Assistant:
  - onboarding shows `shareError`;
  - the stub `ToastService` gets a real overlay in `AssistantRootView`, so shared code's
    `showError` reaches her.

### #15 Joining state + iCloud check
- `ClassroomSharingService` gains an observable `isJoining`, set around the accept Task
  in `acceptPendingInvitation`.
- Onboarding shows "Joining your classroom…" with a progress view.
- `AssistantBootstrapper` checks `CloudKitConfigurationService.container.accountStatus()`
  at start and on `.CKAccountChanged`, following `CloudKitHealthCheck`
  (Services/CloudKitHealthCheck.swift:145-249).
- Onboarding and the sync line say which it is:
  - Not signed in to iCloud
  - Restricted
  - Temporarily unavailable

### #14 Name
- First-run name sheet: `.interactiveDismissDisabled()` until a name is saved.
- Copy: "so your guide can tell your marks from anyone else's". No he or her in UI text.
- Her name is mirrored to `NSUbiquitousKeyValueStore` (the KVS entitlement is already
  there), so a new phone on her Apple ID gets it back.
  - The mirror is Assistant-only; the notebook's `ClassroomIdentity` is untouched.

### #16 Classroom screen
The toolbar's person button opens a Classroom sheet:
- **Guide:** the share owner's name, resolved at display time and never stored.
  - Needs `com.apple.developer.icloud-extended-share-access =
    InProcessShareOwnerParticipantInfo` in DaybookAssistant.entitlements.
  - **Danny adds that capability to the Assistant's App ID**, or signed builds fail
    provisioning.
  - Falls back to "Your guide".
- **Joined:** the membership row's `joinedAt`.
- **Classroom ID:** the first 8 characters of the pinned zone name, for support.
- **Your name** (moves here) and the **Arrival reminder** setting (#17).
- **Leave Classroom**:
  - Destructive confirm: "Removes the class from this iPhone. Your marks stay with your
    guide."
  - Uses the existing `ClassroomSharingService.leaveClassroom()` (line 253), fixed
    first:
    - re-fetch the pinned share when `currentShare` is nil (today the purge is skipped
      after any relaunch);
    - purge only the shared store;
    - assistant role only;
    - don't flip `currentRole` to leadGuide.
  - Then `bootstrapper.refreshMembership()` returns her to onboarding.
- The Assistant fetches `currentShare` once at launch (today only `acceptShare` sets it).
- Leave testing:
  - UI in the Sample Class.
  - The real purge only on the test-Apple-ID simulator after Danny says go, then
    re-added via the Mac's Manage Sharing sheet.

---

## Phase 3 — The tile's menu

### #9 Absent + reason in one step; new reasons
- `AbsenceReason` gains `appointment`, `family` and `other`, with names and SF Symbols.
- Sites to update:
  - exhaustive switches: `AttendanceModels.swift:53,61` and
    `Attendance/Insights/AttendanceRecentActivityCard.swift:113`;
  - hard-coded lists: the notebook card's menu (`AttendanceCard.swift:332-352`, today
    only Sick/Vacation) and the MCP schema enum (`MCPNotebookTools+Attendance.swift:235`);
  - tests naming `sick`: SidebarInsights, BackupFieldCoverage and the MCP attendance
    tests.
- Old builds read an unknown reason as `.none` and can overwrite it, so all devices
  update together (schema 11 forces that anyway).
- Assistant menu:

  ```
  Present · Tardy · Left Early
  Absent  (Sick, Vacation, Appointment, Family, Other…)
  Clear Mark
  Add/Edit Note
  ```

  - One save per choice, via a new `markAbsent(reason:)`.
  - "Other…" marks absent, then opens the note sheet.
  - Items carry the tile's glyphs.

### #11 Who marked it
- `Row` carries `recordedBy`, `recordedByName`, `recordedByID` and `leftAt`.
- The menu gets a header: "Marked by you at 8:02" / "by Rivka at 8:05" / "by your guide
  at 8:10".
  - "you" = `recordedByID` matches `ClassroomIdentity.currentUserRecordName`, else the
    name matches hers.
  - Guide marks carry no name (`stamp` stores nil for the lead guide), so it says "your
    guide", or the owner's name once #16's entitlement resolves it.
- The notebook card is unchanged (icon + name).

---

## Phase 4 — Features

### 4a. One stack per process (enabler)
- `AssistantBootstrapper` gets a `shared` instance and `ensureStack()`, used by the
  app's `.task`, intents and notification taps.
  - Today the stack is built only in the WindowGroup `.task`, so a background intent
    launch would have none.
  - Never two `CoreDataStack`s in the process.
- The view model's save → attach → reload path moves into `AssistantMarker`:
  `CDAttendanceStore(role: .assistant)` + save + `attachNewRecordsToClassroomShare`.
  The grid and the intents share it.

### #17 Arrival reminder (8:15 default)
- `ArrivalReminderScheduler` (Assistant-only):
  - one-shot `UNCalendarNotificationTrigger` requests for the next 10 school days at the
    set time;
  - identifiers like `arrival-2026-09-30`;
  - school days come from `SchoolDayChecker.nonSchoolDaySet(in:using:)` (two bulk
    fetches) + the pure `isNonSchoolDay(_:nonSchoolDayDates:overrideDates:)`;
  - it removes its own requests, then re-adds them.
- Reschedules on:
  - launch
  - scenePhase .active
  - setting change
  - RemoteImportReloader reloads (calendar changes arrive there; `.schoolDayDataDidChange`
    never posts in this app)
- Today's request is removed once nobody is unmarked.
- Text: "Arrival closes" / "Switch to Late to mark anyone not here absent."
- Tapping it opens today, via a `UNUserNotificationCenterDelegate` on the existing app
  delegate.
- Setting in the Classroom sheet:
  - on/off + time, default on at 8:15, stored per device;
  - permission is asked when the setting is first shown on, with one line of
    explanation (as ParentReportNotificationService asks when its toggle turns on).
- Never marks anyone by itself.

### #19 Siri & Shortcuts
Assistant-own intents. The notebook's use a notebook-only static stack, skip the share
attach, ignore a refused write and don't check school days.

| Intent | Behaviour |
|---|---|
| `AssistantStudentEntity` + `EntityStringQuery` | Modelled on `StudentEntityQuery` (Siri/StudentAppEntity.swift:85; its helpers are already Assistant-compiled); suggests today's roster (#8) |
| Mark Present | Today only |
| Mark Absent | Optional reason; today or ahead |
| Mark Tardy | Today only |
| Who's Not Here Yet? | Dialog listing today's unmarked children |

- All go through `AssistantMarker` and honour locks, days off and #4.
- A refusal gets an honest dialog ("Today is locked by your guide").
- `AppShortcutsProvider` phrases, e.g. "Mark ${student} present in Daybook Assistant".

### #25 Sync line tells both directions
- `AssistantSyncStatusView` records the end of the last successful `.import` for the
  shared store (AppStorage).
- It shows "Updated from your guide 2 min ago", refreshed each minute only while on
  screen.

---

## Phase 5 — Layout, with 1 and 2 (decided 2026-09-29)
- **#1 Close Arrival button + confirm list.** The Arrival|Late pill pair goes. The bar shows
  the count and a "Close Arrival…" button; tapping opens a sheet naming exactly who will be
  marked absent ("Mark these 4 absent?" · Cancel / Mark Absent). After closing, the bar says
  taps now mark Late, keeps Undo until the next mark, and offers "Reopen Arrival"
  (`returnToArrival`). Hidden on future days (#4) and locked days.
- **#2 Keep tiles, scroll.** No resizing. A clear gap + fade above the bar so no half-hidden
  tile sits on the button; update the "fits 22 on one screen" comments (96abff0a) to match.
- **#10** falls out of #1 (the label is now an action).
- **#12** At accessibility text sizes: two columns and a two-line detail; times drop AM/PM
  on this screen (`.hour(.defaultDigits(amPM: .omitted))`).
- **#13** Horizontal swipe on the grid steps school days — high threshold, horizontal-
  dominant so it doesn't fight scrolling or long-press; slide transition; arrows stay for
  VoiceOver.

---

## Verification
- Build the Assistant for the iPhone SE simulator after each item
  (`Scripts/locked_xcodebuild.sh`, scheme Daybook Assistant).
- Run `-only-testing:` the touched suites in the new target and in
  `Cosmic Daybook Tests/Attendance` (+ Backup / MCP for schema 11 and #9).
- Build the notebook (macOS + iOS) after each shared-file change.
- Full suites once at the end.
- Sample Class on the SE simulator (`-AssistantSampleClass`), headless taps and
  screenshots:
  - past, today and future rules
  - Left Early times
  - Late/Undo
  - reasons + Other → note
  - who-marked header
  - Classroom sheet
  - pending reminder requests
  - intents from the Shortcuts app
  - large text + dark mode
- Real-share checks only with Danny's go-ahead, on the test-Apple-ID simulator: joining
  state, join error, owner name, Leave.
- **Danny's manual steps:**
  1. Schema 11 Development → Production deploy before any install.
  2. Extended-share-access capability on the Assistant's App ID.
  3. Roll out Mac, iPhone, iPad and the Assistant together.
