# ParentLocker attendance

> **Not started.** Written 2026-10-12 on branch `claude/parentlocker-attendance-integration-36de87`.
> In short: On command, the notebook and the Daybook Assistant send the day's attendance to the school's ParentLocker site (yyli.parentlocker.com) through the person's own signed-in session, keep it up to date when a mark changes later, and keep the front-desk email as a choice in Settings.

## Goal

The school now takes attendance in ParentLocker instead of by email. When it's done:
- Settings › Messages has **Send attendance by: ParentLocker / Email to the front desk**. ParentLocker is the new choice; the email works exactly as today when picked. The guide's choice reaches the assistants' phones.
- Each person signs in to ParentLocker once, inside the app, with Google or their password. The app never sees or keeps the password.
- **Send Attendance** works from the attendance screen, from **Close Arrival & Send**, from Siri on the Assistant, and from Claude over MCP. It sends every marked child to whichever of the guide's two ParentLocker classes (Girls Middle School, Upper Elementary Girls) they're in, and answers in one plain line: "Sent to ParentLocker: Upper Elementary Girls 14 here, 1 late, 1 absent · Girls Middle School 6 here."
- After a send, a later change (a late arrival, an early pickup) goes to ParentLocker by itself, and the app says so.
- The 9:00 reminder and the "Sent 8:42 AM by Sarah" line work for ParentLocker as they do for the email.

## How ParentLocker works (read 2026-10-12 from Danny's signed-in page, nothing changed)

- The teacher page is `https://yyli.parentlocker.com/sis/newattendance.php`, an AngularJS 1.4.5 page. The page itself carries `var courses = [...]`: each has `course_id`, `course_name`, `period`, `attendance_report_id`, `attendance_report_status` (`submitted`, `not_expected`, or empty when not taken), `isDailyAttendance`, `hasAttendance`.
- Both of Danny's classes say "This class sets daily attendance", so a class mark is the child's mark for the day. Six people are listed as teachers on them, the assistants included.
- **Load a class:** `POST newattendance.php` with JSON `{action: "course_roster", course_id, period, date}`. The reply has `students` (each with `student_id`, `first_name`, `last_name`, `alternate_name`, and an `attendance` object), `attendance_settings` (the marks), `is_today`, `isDailyAttendance`, `error`.
- **The marks** at this school: Present (type `present`), Late (`late`), Absent (`absent`), none excused, no Left Early. Their ids (689/690/691) are this school's; always look a mark up by its `type`.
- **Save a class:** `POST newattendance.php` with `{action: "save", students: [attendance objects], attendance_report_id, date}`. Each attendance object is the one the roster sent, with `attendance_code` set to `{id, type, name, is_excused}`, `confirmed: true`, and `comment` (the Notes box). The page skips children with no mark. The reply has `error`, `conflicts` (`[{student_id, desired: {attendance_code_id}, current: {attendance_code_id}}]` when someone else changed a child since the load) and `updated`.
- **Dates** are written `YYYY-M-D` with no leading zeros (`getDateString`).
- **Locked rows:** `attendance.is_locked` with `is_locked_title` "Locked by Admin" (the office set it). The page won't change those, and neither will we.
- **Sign-in:** email and password or "Sign in with Google" at the site root. The sign-in cookie is HttpOnly. How long it lasts, and whether it survives quitting the app, is not known yet (Phase 2 checks).

## Decisions

- **The app uses ParentLocker's own two requests from inside a signed-in web view** (`fetch` run in the page, so the person's sign-in cookie goes with it). Why: no public API exists (only a directory listing says "API", with nothing behind it). Typing into the page by position breaks when its layout moves. Copying the requests into URLSession would mean handling the sign-in cookie ourselves and would break Google sign-in. Ruled out: storing a password, and Claude filling it in Chrome each morning.
- **Echo the roster's own attendance objects back**, changing only `attendance_code`, `confirmed` and `comment`, exactly as the page's `save()` does, so fields we don't know about survive.
- **One shared engine on `WKWebView`** (`WKWebsiteDataStore.default()`, `callAsyncJavaScript(_:arguments:in:contentWorld: .page)`), compiled into both apps. SwiftUI's `WebPage` needs iOS 26 and the Assistant still builds for iOS 18 (`docs/Technical notes/SIRI.md`). `.page` world because the course list is a page global.
- **Marks** (Danny, 2026-10-12):
  - Present → Present.
  - Late → Late.
  - Absent → Absent, with only the reason picked (Sick, Appointment, Vacation, Family, Other) in the Notes box. The written attendance note stays private.
  - Left early → Present, with "Left early at 1:30 PM" in the Notes box.
  - Unmarked → not sent (ParentLocker's mark, if any, is left alone).
  - We write the Notes box only when we have something to say; otherwise its text is left as it is.
- **Matching children:** the first time, by name: notebook first/last/nickname against ParentLocker's first/last/alternate name, ignoring case, accents and extra spaces, and only when exactly one child matches. A match is kept on the student as `parentLockerID`, so later sends go by ID and a renamed child still matches. Only the guide's devices write matches (assistants can't write students); an assistant's phone uses the stored IDs and name-matches the rest in memory. Children it can't match are listed in Settings › Match Names, where the guide picks the right one once. ParentLocker children who aren't in the notebook are never touched.
- **Who sends** (Danny): the guide and the assistants, each with their own ParentLocker sign-in. The send is gated like Close Arrival (`CDAttendanceStore.canWrite(on:)`). Only classes whose rosters hold matched children are sent, so an assistant whose account shows other classes never touches them.
- **Changes after sending** (Danny: automatically): once a ParentLocker send is recorded for today, every signed-in device watches saves of today's attendance records (a `NSManagedObjectContextDidSave` observer from every context, as `ManagedObjectChangeFlag` does, so local marks, Siri, MCP and synced changes all count). It waits 20 s for more, re-reads ParentLocker and saves only the children whose mark differs. Because each run compares against ParentLocker's current marks, two devices doing it is harmless. It runs only while the app is open; on the Mac that is all day. It never re-sends a whole day by itself.
- **Conflicts and locks are reported, never overridden:** "The office already marked Maya S Absent", "Someone changed 2 children in ParentLocker since; kept theirs."
- **The send is recorded on the existing `CDAttendanceEmailSend`** with a new `channelRaw` ("email" / "parentLocker"), so `latestSend`, the reminder's "already sent today" check and the "Sent … by …" line keep working. Automatic updates are not recorded as sends; they show a toast and go to the log.
- **The choice lives on the shared `CDAttendanceEmailSettings`** (new `sendMethodRaw`, `parentLockerSite`), so the guide picks it and the assistants follow. Existing rows read as email until the guide picks ParentLocker.
- **Schema 18, all additive:** `CDAttendanceEmailSettings.sendMethodRaw` (String, default "email"), `CDAttendanceEmailSettings.parentLockerSite` (String, optional), `CDAttendanceEmailSend.channelRaw` (String, default "email"), `CDStudent.parentLockerID` (String, optional). Backup format v39 → v40 with lines in `Backup/BackupEntityTable.swift`.
- **Safety while building:**
  - Debug builds and test runs never save to ParentLocker. They read, match and show "would send …" (a preview). Only Release and TestFlight builds save. Why: a macOS test run launches the real app on Danny's live store and sign-in (memory: test host opens the live store), and a Debug build may read stale data.
  - The guard uses `AppBootstrapping.isRunningUnitTests` plus `#if DEBUG`, and a test pins it.
- **MCP gets its first outward tool**, `send_attendance_to_school(date?, preview?)`. It is annotated open-world, the registry test's "only reads the local notebook" rule gets this one exception, and `docs/Technical notes/MCP_SERVER.md` says why. With `preview: true` it writes nothing (`markNothingWritten`).
- **Siri:** the Assistant has room for one more App Shortcut (9 of 10), so **"Send attendance in Daybook Assistant"** is added. The notebook is at 10 of 10, so it gets the intent as a Shortcuts action with no Siri phrase of its own (see Open questions).
- **Plain English:** every result and failure is one everyday sentence through `AppErrorMessages`. Raw replies and ParentLocker's error text go to the log or a Details disclosure. The messages:
  - "ParentLocker signed you out. Sign in to send."
  - "Couldn't reach ParentLocker. Check the internet and try again."
  - "ParentLocker's attendance page changed, so the app couldn't send. Take attendance on the ParentLocker site for now."

## Files

New, in `Cosmic Daybook/Attendance/ParentLocker/` (each also compiled into the Assistant via `project.pbxproj`):
- `ParentLockerWire.swift`: the `Decodable` course, roster, mark, save-reply and conflict types; attendance objects kept as raw JSON to echo back.
- `ParentLockerPlanner.swift`: pure. Matches children, maps marks, compares with ParentLocker's current marks, and builds one save batch per class plus the skipped list (unmatched, locked, unmarked). Most of the tests live here.
- `ParentLockerTransport.swift`: protocol `courses() / roster(course:date:) / save(batch:)`, so the sender is testable without WebKit.
- `ParentLockerSession.swift` (`@MainActor`): the `WKWebView` transport. Loads the page, tells signed-in from signed-out (redirected to the sign-in page, or no `courses` global), and runs the two requests as `fetch` in the page. If a sign-in doesn't survive relaunch, it keeps the site's cookies in this device's Keychain (not synced) and puts them back before loading.
- `ParentLockerSender.swift` (`@MainActor`): `send(day:preview:)` and `update(day:)`. Reads the day's roll (`AttendanceLookup`, `AttendanceRoster`), runs the planner, saves, records the send through `AttendanceEmailLog.recordSend(channel:)`, writes new matches (guide only), and returns `ParentLockerResult` with its plain summary line.
- `ParentLockerAutoUpdate.swift`: the DidSave observer, 20-s debounce, today and after-a-send gates.
- `ParentLockerSignInView.swift`: the sign-in sheet (UIView/NSView representable over the session's web view, with Done). It closes itself when the attendance page loads signed in.
- `ParentLockerMatchView.swift`: Settings › Match Names. Each class's children with their notebook match, and a picker for the ones it couldn't match.

Changed:
- Model: `CosmicDaybook.xcdatamodeld` (schema 18); `Attendance/Email/AttendanceEmailSettingsEntity.swift`, `AttendanceEmailSendEntity.swift`, `Students/Models/StudentEntity.swift`; `Attendance/Email/AttendanceEmailLog.swift` (method, site, channel; summaries say "Sent to ParentLocker" or "Emailed"); `Backup/BackupEntityTable.swift`, `Backup/Archive/BackupWriter.swift` (v40).
- Reminder: `Attendance/Email/FrontDeskEmailReminder.swift`. `canSend` accepts ParentLocker with a site set; the wording follows the method ("Attendance is due at 9:00. Send it to ParentLocker.").
- Notebook Settings: `Attendance/Email/AttendanceEmail.swift` + `AttendanceEmail+Prefs.swift` (method picker at the top; email fields only when email is picked; ParentLocker site, Sign In/Out, Match Names); `Settings/SettingsCopy.swift`, `Settings/SettingsView+Sections.swift` (the group's title becomes "Attendance to the School").
- Notebook attendance: `Today/Views/Attendance/AttendanceExpandedView+FrontDesk.swift`, `+Band.swift`, `+Controls.swift`, `+ActionBars.swift`, `AttendanceFrontDeskControl.swift`. "Email" wording becomes "Send" when ParentLocker is picked; "Close Arrival & Send"; result toast; "Mark as Sent" stays for a day sent on the site by hand.
- Assistant: `Daybook Assistant/FrontDesk/AssistantFrontDesk.swift`, `AssistantFrontDeskRow.swift`, `Attendance/AssistantArrivalBar.swift`, `Sync/AssistantClassroomSheet.swift` (Sign In to ParentLocker row), `Siri/AssistantAttendanceIntents.swift`, `Siri/AssistantAppShortcuts.swift`.
- Notebook Siri: `Siri/` gets `SendAttendanceIntent` (Shortcuts action, opens the app when it needs a sign-in).
- MCP: new `Services/MCPServer/MCPNotebookTools+SchoolAttendance.swift`; `attendance_for_day` reports the ParentLocker send; `Cosmic Daybook Tests/Services/MCPServer/MCPToolRegistryTests.swift` (92 tools, write set, the open-world exception).
- Docs: `docs/Technical notes/DATA_MODELS.md`, `BACKUP_SYSTEM.md`, `MCP_SERVER.md`, `SIRI.md`, `CloudKit/CLOUDKIT_GUIDE.md` (schema 18), `Cosmic Daybook/CLAUDE.md` (schema/backup numbers, a ParentLocker line), and a new `docs/Technical notes/PARENTLOCKER.md` (the site's requests above, the guards, how to check it still works).

## Progress
Build board: https://claude.ai/artifact/WAKaFZGNPQsfKD4A5GbqsM (a new milestone for this plan).
- [ ] Phase 1: Schema 18 and the shared pieces: four attributes, `AttendanceEmailLog` method/site/channel, reminder `canSend`, backup v40, docs counts (agent `feature-phase-deep`) · est. ~2–3% weekly
- [ ] Phase 2: The engine: wire types, planner, transport, `WKWebView` session, sender, auto-update, sign-in sheet, the Debug/test guard; fixture and fake-transport tests; a signed-in check in the Mac app of whether a sign-in survives relaunch, and a **preview** against the real site with Danny signed in (agent `feature-phase-deep`; the live check with Danny in the main session) · est. ~3–4% weekly
- [ ] Phase 3: The notebook: Settings (method, sign-in, Match Names), attendance band/controls/iPhone row, MCP tool, Shortcuts action (agent `feature-phase`) ‖ Phase 4 · est. ~1.5–2.5% weekly
- [ ] Phase 4: The Assistant: sign-in row, Send and Close Arrival & Send, Siri shortcut, reminder wording (agent `feature-phase`) ‖ Phase 3 · est. ~1–2% weekly
- [ ] Phase 5: Combine, full builds (notebook iOS, macOS, Release; Assistant), whole suites, a simulator look at both apps, one review, Development `-InitializeCloudKitSchema` run, merge to main (session: here) · est. ~2–3% weekly
- [ ] Phase 6: Danny's steps, as Tide rows (no session): deploy schema 18 to Production; roll out the notebook and Assistant together; sign in on each device; Match Names; the first real send; mark a child late and see the update arrive.

## Cost

About **10–15%** of the weekly all-models limit (Max), sized from "Names you set yourself" (a shared-schema feature of the same shape, 7–12% planned) plus the web engine. 53% used at writing, 47% left until **Sun Oct 18, 4 PM EDT**. **Fits.** The 5-hour window was 5% used.

## Verification

- **Unit tests** (`Cosmic Daybook Tests/Attendance/ParentLocker/`):
  - **Planner:**
    - Each mark mapping, including left early's note and absent's reason-only note.
    - Unmarked children skipped, and locked rows skipped and reported.
    - No-change children left out; Notes left alone when we have nothing to say.
    - Split by class.
    - Name matching: case and accents, nickname against alternate name, two children with the same first name, ambiguous and unmatched names.
    - The `YYYY-M-D` date.
  - **Wire:** decoding from fixture JSON with made-up names, shaped like the real replies.
  - **Sender**, over a fake transport:
    - Signed out, network down, unknown page, conflicts, the preview writes nothing, matches written only by the guide.
    - The send record carries its channel.
  - **Auto-update:** gated on today and on a prior send, debounced, and saves only the changed child.
  - **The guard:** a Debug or test build never calls `save`.
  - **The log:** old rows read as email, and the reminder can send with ParentLocker picked.
  - **The MCP registry test.**
- **Builds:** notebook iOS + macOS + Release, Assistant; zero warnings; SwiftLint.
- **Whole suites** once at the end (notebook, Assistant), on the leased simulator with `-parallel-testing-enabled NO` (1 simulator).
- **Live, read-only:** with Danny signed in to the Debug Mac app, a preview of today shows the right children in the right classes with the right marks. This checks matching and reading against the real site; nothing is saved.
- **First real save:** Danny, on the rolled-out build (Phase 6), with the result line and the site compared.

## Open questions

- **A Siri phrase in the notebook.** It's at Apple's limit of 10. Recommendation: none for now (the Shortcuts action works, and Claude can send over MCP). If Danny wants one, merge Open Lesson into Open Section to free a slot.
- **Late arrivals' time in the Notes box** ("Arrived 9:20 AM")? Recommendation: no, to match "reason only".
- **How long a ParentLocker sign-in lasts** decides how often anyone signs in again; Phase 2 measures it. If it ends daily, the 9:00 reminder could check first and say "Sign in to ParentLocker before 9:00."
