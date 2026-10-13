# ParentLocker attendance

> **Done 2026-10-13** (main 020ef75b). On TestFlight: Cosmic Daybook 1.1 (300000000018) for iPhone/iPad and Mac, and Daybook Assistant 1.1 (019) in the Assistants group. Danny's steps are rows in Tide, linked under Phase 6.
> In short: Close Arrival sends the class's attendance from the notebook or the Daybook Assistant to the school's ParentLocker site, every later change follows within seconds, through each person's own ParentLocker sign-in, made once and kept privately in their iCloud Keychain; the front-desk email stays as a choice in Settings.

**Runs autonomously from Phase 5 on** (Danny, 2026-10-12, at bedtime): "After this is pushed to main I'd like a final bug check on the latest changes. /plan-efficiently to fix the bugs. then push to main, close out, and send to testflight. do this all autonomously." And: "my dev account is in the browser if you need to deploy anything." Decisions that come up are made by the main session from the project's rules and this plan, and listed under "Decided during the run" for Danny to read afterward. Danny also said: "assistant app should be added to the assistants group for testing." Never: lose data, touch the live notebook (no schema-18 build opens it; no Mac app launch), type a password, add the notebook's build to any TestFlight group, or register a device.

## Goal

The school now takes attendance in ParentLocker instead of by email. When it's done:
- Settings › Messages has **Send attendance by: ParentLocker / Email to the front desk**. With email picked, everything works exactly as today. The guide's choice reaches the assistants' phones.
- Danny signs in to ParentLocker **once**: one time covers his Mac, iPad and iPhone. Each assistant signs in once on her phone with her own ParentLocker account. Nobody signs in again. If ParentLocker ever signs someone out, the app signs them back in by itself. The password lives only in that person's iCloud Keychain, encrypted by Apple.
- **Close Arrival & Send** marks the rest absent and sends the whole class to ParentLocker at once, each child in the right one of Danny's two classes (Girls Middle School, Upper Elementary Girls). Nothing goes before that, so the office never sees a half-taken class.
- **After that it's live:** a late arrival, an early pickup or any other change, by tap, Siri or Claude, shows up in ParentLocker a few seconds later.
- The attendance screen shows one plain line: "Sent to ParentLocker 8:47 AM by Sarah · up to date". The 9:00 reminder fires only when the day hasn't been sent.
- "Send Now" in the menu catches up by hand. Claude can send or preview a day over MCP.

## Progress
Build board: https://claude.ai/artifact/WAKaFZGNPQsfKD4A5GbqsM (a new milestone per phase).
- [x] Phase 1: Schema 18 and the shared pieces (session: here, agent `feature-phase-deep`, Opus high) · est. ~2–3% weekly · started at 54% · cost <1% (54→54) · 3574a866. iOS, macOS and Assistant build with no warnings; notebook 102 tests in 18 suites and Assistant 18 in 3 pass. Differed: `canSend` still means "the email can go", and the new `canSendAttendance` is method-aware (Phase 4 switches three Assistant spots to it); the site is cleaned to a bare host; the Development schema run was done after the agent, on a new simulator Danny signed in to his test Apple ID (C0EDC79D, iPhone 17 Pro, leased to the scratchpad), and all four fields were confirmed in the Development Console on 2026-10-12; the agent was stopped once by a session restart and resumed.
- [x] Phase 2a: Talking to ParentLocker: wire, planner, requests, Keychain (session: here, agent `feature-phase-deep`, Opus high) · est. ~2–3% weekly · started at 54% · cost ~2% (54→56, including the schema run and Console check) · 9254907a, 455b17b4. Nine engine files, 40 tests in 5 suites pass; Assistant, iOS and macOS build with no warnings. Differed (accepted): a child who came late and then left early goes as Late with "Left early at …", so the Late isn't overwritten; the transport follows no redirects (on-site = signed out, off-site = refused); cookies are a Codable struct of their properties; the redirect check uses the completion-handler form (Swift 6.4 crashes compiling the async one); the planner words absence reasons itself, with a test keeping them in step with `AbsenceReason.displayName`. To settle in the live check: whether a save's `attendance_report_id` comes from the roster reply or the course list (the planner prefers the reply's).
- [x] Phase 2b: Sign-in and the live sync, then a read-only live check with Danny (session: here, agent `feature-phase-deep`, Opus xhigh) · est. ~4–5% weekly · started at 56% · cost ~3% (56→59, live check included) · 86a6652d, 0571a255, 0e5eb1c6. 69 ParentLocker tests in 9 suites pass; notebook iOS and macOS, Assistant Debug and Release build; efficiency audit clean. Differed (accepted): the password is saved only after ParentLocker accepts it; only daily-attendance classes are read, and on today a "not expected" class is skipped; a whole-class send with no matched child records nothing. **Live check, 2026-10-12, on the iPhone simulator, not the Mac:** a schema-18 build would have opened the live notebook, and the installed copy couldn't have opened it afterward. Danny signed in himself; it read both classes (6 and 17 children) and stayed signed in after a relaunch; nothing was saved.
  - **More than one sign-in at a time is fine.** The browser stayed signed in alongside the simulator. The browser's earlier sign-out was its own session timing out after a few hours.
  - **The save's `attendance_report_id` comes from the course list;** the roster reply has none.
  - **Matching against the real 23 children** (read through MCP, compared by hand): every child matches except "Toba (Aliza)". A bracketed second name now counts (0e5eb1c6, with a test).
  - **Not checked live:** signing back in after a real expiry. The unit tests cover it, and it's a device check in Phase 6.
  - **Left for the Phase 5 review:** a device that hasn't yet received another device's change can still send its own older mark for that child, because ParentLocker carries no time to compare against.
- [x] Phase 3: The notebook's screens, MCP and Shortcuts (session: here, agent `feature-phase`) ‖ Phase 4 · est. ~2–3% weekly · started at 59% · 4115b51a, 5c69e0cf. Notebook iOS and macOS build; 88 tests in 12 suites, then `SettingsSearchTests` again (a search for "PARENT" now finds ParentLocker first; the test searches "PARENT REPORTS"); registry at 92 tools with the open-world set pinned. Differed: also touched `AttendanceArrivalControl`, `AttendanceExpandedView` and `+Undoable`; `MacOSMailSender` and the comings-and-goings row moved to files of their own (SwiftLint's 400-line limit); Mark as Sent records a ParentLocker send when ParentLocker is picked; Settings has an editable address while the sheet only shows it.
- [x] Phase 4: The Assistant's screens (session: here, agent `feature-phase`) ‖ Phase 3 · est. ~1.5–2% weekly · started at 59% · 1b6a2a26, 38d6c06d. Phases 3 and 4 together: 59→61%. Assistant builds; 50 tests in 6 suites plus onboarding 14 in 2. The sign-in sheet was checked on the iPhone SE (3rd gen, iOS 26.5) at default and the largest text, with the keyboard up: nothing clipped; at the largest size Sign In needs one scroll. Screenshots sent to Danny. Differed (accepted):
  - The sheet's third line also mentions the left-early time, which is sent too.
  - "Send to ParentLocker" shows when everyone is marked and nothing has been sent, since there's no Close Arrival button then.
  - Siri sends at once and waits, so it can say whether it worked.
  - After Close Arrival & Send, Undo disappears after 6 seconds.
  - The sheet's title is "ParentLocker" once signed in.
- [x] Phase 5: Combine, review, full builds, whole suites, simulator look, merge (session: here) · est. ~3–4% weekly · started at 61% · cost ~1% (61→62). Review and plain-English pass: 12 bugs and 14 phrases, all fixed (see Decided during the run). Five builds clean (notebook iOS, macOS, Release; Assistant Debug and Release); the only warning is the existing one at `AssistantSampleClass.swift:177`. Whole suites: notebook 3,657 tests in 604 suites pass; Assistant 323 in 48 pass. Its first run failed 2 Siri keep-alive tests in `UnsentChangesKeepAliveTests` (timing); they passed alone, together with the ParentLocker tests, and in a whole rerun. The simulator look was the Phase 4 iPhone SE screenshots; Settings on iPhone is left for the Phase 6 device check. Squashed to main and pushed; the unsquashed history is on `parentlocker-attendance-unsquashed`.
- [x] Phase 7: Final bug check of the whole ParentLocker diff on main (session: here, Opus `Plan` reviewers, read-only) · est. ~2–3% weekly · started at 62% · four Opus reviewers; 19 distinct findings (6 high), written up in `docs/Reviews/ParentLocker bug check 2026-10-13.md`. A1 was checked live, read-only: a past day's own report ids come from `?date=`.
- [x] Phase 8: Fix the findings, planned with /plan-efficiently into its own plan, `docs/Plans/Plan - ParentLocker bug check fixes.md` (session: here, agents sized to the findings) · est. 8–12% · cost ~3% (62→65). All 19, then 5 more from the fixes' review, then a latent Assistant test hang the work exposed (see that plan's Progress). Squashed to main with this plan's close-out.
- [x] Phase 9: Push to main, deploy schema 18 to CloudKit Production (Danny's signed-in developer account in the browser pane; allowed by Danny), close out, and send the notebook and the Assistant to TestFlight with the `roll-out` skill (the Assistant's build added to the Assistants group, per Danny; the notebook's uploaded only) (session: here) · est. ~2–3% weekly · started at 65% · done 2026-10-13. Schema 18 deployed to Production and checked. Uploads (from main 020ef75b, after a further bug hunt Danny asked for and its fixes, see <Plan - ParentLocker bug hunt afternoon fixes.md>):
  - Cosmic Daybook 1.1 (300000000018) for iOS and Mac. 300000000017 was already in App Store Connect, so `LAST_BUILD` is now 18.
  - Daybook Assistant 1.1 (019), added to the Assistants group with a "What to Test" note Danny approved. It was in Testing at once.

  Xcode's App Store Connect sign-in had lapsed overnight; Danny signed in again in the afternoon.
- [ ] Phase 6: Danny's steps, as Tide rows (no session)

## Cost

About **15–20%** of the weekly all-models limit (Max). This is sized from the cost log: recent deep agents ran ~2–4% each, feature agents ~1–1.5%, and a final phase with a review ~2–3%, all on a crowded build queue. The plan review (~0.5%) is already spent. At writing, 53% was used and 47% is left until **Sun Oct 18, 4 PM EDT**. **Fits.** At most two agents run at once (Phases 3 ‖ 4), so the 5-hour window (5% used) is safe.

## How ParentLocker works

Read 2026-10-12 from Danny's signed-in page; nothing was changed.
- **The teacher page** is `https://yyli.parentlocker.com/sis/newattendance.php`, an AngularJS 1.4.5 page. It carries `var courses = [...]`, and each course has `course_id`, `course_name`, `period`, `attendance_report_id`, `attendance_report_status` (`submitted`, `not_expected`, or empty when not taken), `isDailyAttendance` and `hasAttendance`. Both of Danny's classes "set daily attendance", so a class mark is the child's mark for the day. Six people are listed as teachers on them, the assistants included.
- **Load a class:** `POST newattendance.php` with JSON `{action: "course_roster", course_id, period, date}`. The reply carries:
  - `students`, each with `student_id`, `first_name`, `last_name`, `alternate_name` and an `attendance` object
  - `attendance_settings` (the marks)
  - `is_today`, `isDailyAttendance` and `error`
- **The marks at this school** are Present (type `present`), Late (`late`) and Absent (`absent`). None is excused and there is no Left Early. Their ids (689/690/691) belong to this school, so always look a mark up by its `type`.
- **Save a class:** `POST newattendance.php` with `{action: "save", students: [attendance objects], attendance_report_id, date}`.
  - Each attendance object is the one the roster sent, with `attendance_code` set to `{id, type, name, is_excused}`, `confirmed: true` and `comment` (the Notes box). The page skips children with no mark.
  - The reply has `error` and `updated`, plus `conflicts` (`[{student_id, desired: {attendance_code_id}, current: {attendance_code_id}}]`) when someone changed a child since the load.
  - **There is no way to clear a mark.**
- **Dates** are written `YYYY-M-D`, with no leading zeros.
- **Locked rows:** `attendance.is_locked` with "Locked by Admin" means the office set the mark. The page won't change those, and neither will we.
- **Sign-in:** `POST /process.php` from `#login-form`, with fields `user` (email) and `pass`, plus hidden `sublogin=1`, `remember=1`, `login_url`, `return_to`, `usid=yyli` and `plDeviceId`. "Sign in with Google" is at `/oauthlanding.php`, but Danny uses email and password. The site asks to remember the sign-in (`remember=1`). The sign-in cookie is HttpOnly, and how long it lasts is measured in Phase 2.

## Decisions

### Sending
- **The app makes ParentLocker's own three requests itself** (load the page for the course list, load a class, save a class), with `URLSession`, carrying the person's sign-in cookies. Why:
  - There is no public API; only a directory listing says "API", with nothing behind it.
  - Typing into the page by position breaks whenever its layout moves.
  - A web view's JavaScript stalls when the app is in the background or the view is off-screen (Apple guidance, item 5). An assistant's phone locks right after Close Arrival, and `URLSession` keeps going inside a background-task window.
  - It is testable with recorded replies.
  - Ruled out: Claude filling the form in Chrome each morning.
- **A web view is used only to sign in.** It fills ParentLocker's own sign-in form, so the site sets its cookies the way it expects (`plDeviceId` is filled by the page's script). Afterward, the cookies for the site host are read from the web view's store (`WKHTTPCookieStore.getAllCookies`). They are kept as cookie properties in this device's Keychain (`ThisDeviceOnly`, never synced), because Apple doesn't promise that a web view's session cookies survive a relaunch (item 3). Every `Set-Cookie` the site sends back replaces them.
- **Echo the roster's own attendance objects back,** changing only `attendance_code`, `confirmed` and `comment`, exactly as the page's `save()` does. That way fields we don't know about survive.
- **One shared engine, compiled into both apps.** The sign-in web view is `WKWebView` in a small UIKit/AppKit wrapper, not SwiftUI's `WebPage`, which needs iOS 26; the Assistant still builds for iOS 18 (`docs/Technical notes/SIRI.md`). The course list is read from the page's `var courses = [...]` line.

### Marks and matching
- **How each mark is sent** (Danny, 2026-10-12):
  - Here → Present; Late → Late, with no arrival time in the Notes box.
  - Absent → Absent, with only the reason picked (Sick, Appointment, Vacation, Family, Other) in the Notes box. The written attendance note stays private.
  - Left early → Present, with "Left early at 1:30 PM" in the Notes box.
  - Unmarked → nothing is sent.
  - The Notes box is written only when we have something to say. Otherwise its text is left alone.
- **Matching children:**
  - **The first time, by name.** The notebook's first name, last name and nickname are checked against ParentLocker's first, last and alternate name, ignoring case, accents and extra spaces. A match counts only when exactly one child fits.
  - **Kept by ID.** A match is stored on the student as `parentLockerID`, so later syncs go by ID and survive a rename.
  - **Who writes matches.** Only the guide's devices write them; assistants can't write students. An assistant's phone uses the stored IDs and matches the rest by name in memory.
  - **Children it can't match** are listed in Settings › Match Names, and the guide picks the right child once.
  - **ParentLocker children who aren't in the notebook,** and classes holding none of the notebook's children, are never touched. So an assistant whose account shows other classes never changes them.

### Sending at Close Arrival, then live (Danny, 2026-10-12: "sync in real time", then "wait until we close attendance", then "send in batch when we close arrival, and then each change goes live")
- **Nothing goes to ParentLocker before arrival closes,** so the office never sees a half-taken class.
- **Close Arrival & Send** (with ParentLocker picked) marks the rest absent. Once Close Arrival's Undo toast has gone, it sends the whole class in one save per class. Undo cancels the pending send, because ParentLocker can't take back a mark. It works on any signed-in device: the guide's, or an assistant's phone. Afterward it records the day's send, one `CDAttendanceEmailSend` with `channelRaw = "parentLocker"`.
  - That record also drives `latestSend`, the reminder's "already sent today" check and the "Sent to ParentLocker 8:47 AM by Sarah" line.
  - A device that isn't signed in still closes arrival, then opens the one-time sign-in sheet. If nobody signs in, the guide's device sends it (the "after" rule below).
  - **Send Now** in the ⋯ menu does the same whole-class send without closing arrival. It is for a day taken some other way, or for catching up.
- **What counts as "after".** Live updates start when the day either has a ParentLocker send record or has arrival closed (`CDAttendanceStore.arrivalClosed(on:)`, which syncs as the automatic absences). So a phone that closed arrival without being signed in still starts the live updates everywhere.
  - **The guide's device as backstop.** If arrival is closed and no ParentLocker send is recorded within 60 s, a signed-in device of the guide's does the whole-class send and records it.
- **After that, each change goes live, one child at a time.**
  - **What it watches.** Each device watches saves of that day's attendance records from every context, the CloudKit import included. The observer is the engine's own (the notebook's `ManagedObjectChangeFlag` isn't in the Assistant). Taps, Siri, MCP, undo and synced changes all count: a late arrival, an early pickup, a reason added, Back in Class.
  - **A change made on this device** syncs after **4 s** of quiet, so a wrong tap that is undone never reaches ParentLocker and a run of taps goes as one save. **Only the children in those saves are sent,** never the whole class. A device that hasn't caught up with another's changes must not push its old marks over newer ones.
  - **A change that arrived from another device** syncs after **60 s**, for those children only, and only if ParentLocker still differs. This is the backstop for a phone that went offline or isn't signed in.
  - **On launch and on returning to the app,** the catch-up waits for the first CloudKit import to finish (`NSPersistentCloudKitContainer.eventChangedNotification`, import ended), so it compares fresh marks. Then it sends the children whose mark was changed on this device since the last sync and never reached ParentLocker.
  - **Whole-class comparisons happen only** for Close Arrival & Send, Send Now, the guide's backstop and MCP.
- **What a sync does.** For each class it touches, it loads the roster, compares the children it was given with ParentLocker's current marks, and saves only the ones that differ. A repeat, or a second device doing the same work, changes nothing.
  - A conflict whose current mark already equals ours is ignored.
  - Other conflicts and locked rows are reported, never overridden: "The office already marked Maya S Absent."
- **Which record counts.** A child can have more than one record for a day (CloudKit duplicates), so the planner reads the `AttendanceDeduplication` winner (`attendanceStatuses(for:on:)`). An automatic Close Arrival absence (reason `closeArrival`) goes as Absent with an empty Notes box.
- **Changing a mark works; clearing one doesn't.** Present → Absent, Absent → Late and so on are re-sent like any change; ParentLocker's own page lets a saved mark be changed (checked on Danny's page 2026-10-12). It has no way to go back to no mark. So when a child is unmarked after the send, the line says so: "Maya S is still Present in ParentLocker. ParentLocker can't clear a mark; mark her Late or Absent if that's right."
- **Live updates run only when all of these hold:**
  - ParentLocker is the chosen method, and this device is signed in.
  - It is a school day.
  - The day is today and past "after". Past days go only through Send Now or MCP with a date.
  - The save policy allows it (see Safety).
- **Failures retry quietly** after 30 s, 2 min and 5 min, then wait for the next change, a return to the app, or Send Now. The line says "Couldn't reach ParentLocker. It'll try again." Nothing polls. All waits use an injected clock, so tests run instantly.
- **Background.** On iPhone, a send or sync already under way when the app goes to the background finishes inside a `beginBackgroundTask` window (Apple guidance, item 5). Signing back in needs the web view, which stalls in the background. So a sync in the background (or from the Siri intent) that finds itself signed out doesn't try: it records nothing, says "Couldn't send to ParentLocker yet," and signs in and retries on the next return to the app.
- **No new Siri shortcut.** Siri and Claude marks sync like taps, because they save through the same store. The Assistant's existing Close Arrival Siri shortcut also sends when ParentLocker is picked and her phone is signed in; otherwise it says plainly that it closed arrival but couldn't send yet. The notebook gets no Siri phrase (Danny: skip).

### Sign in once, kept private (Danny, 2026-10-12)
- **Each person signs in once.**
  - Danny, once for all his devices: the password is saved in his iCloud Keychain (`kSecAttrSynchronizable`), which syncs it to his own devices only.
  - Each assistant, once on her phone with her own ParentLocker account, saved the same way to her own iCloud Keychain. ParentLocker then shows who took attendance.
- **The app's own small sign-in sheet,** with Email and Password fields.
  - The fields are marked as username and password, so the Passwords app may offer to fill them by hand. Apple gives apps no way to read ParentLocker's saved password from Passwords on their own (Apple guidance, item 2).
  - Under the fields: "Your password stays in your iCloud Keychain, encrypted by Apple, and is only used to sign in to ParentLocker."
  - **Its words** (Danny, 2026-10-12: "I like all of your suggestions. also a privacy notice on that page too. Explain clearly and plainly what is happening."):
    - The title "Sign in to ParentLocker", with the school's site under it.
    - "You only need to do this once."
    - A short "What happens when you sign in" notice: the app signs in for you, as on the website; the password sits in your iCloud Keychain, encrypted by Apple and readable only by your own devices; "It's never stored in the app or its backups, and none of your co-workers can see it or use it" (Danny's wording, 2026-10-12); it's used only to sign in and send the attendance you take (here, late, absent, and an absence's reason), and your own notes stay in the notebook; the app signs back in by itself; signing out deletes it from all your devices.
  - On Sign In, the app saves the password, then fills ParentLocker's own form in an invisible web view and submits it, with `remember=1` and `return_to` pointing at the attendance page. Success means the attendance page loads with its course list.
  - The web view is shown only if ParentLocker asks for something more (new terms, a password reset).
- **Signing back in by itself.** When a sync in the foreground finds the sign-in page instead of the attendance page, it signs in again with the saved password and carries on. Only when ParentLocker refuses the saved password (it was changed) does anyone see "ParentLocker didn't take your saved password. Sign in again."
- **Privacy rules,** each pinned by a test:
  - **Where the password lives.** Only in the Keychain: never Core Data, the classroom share, backups, preferences, logs, MCP replies or error text. Logs carry rosters and replies only as `privacy: .private`, and never the sign-in request's body.
  - **Filling the form.** The password goes into the form through `callAsyncJavaScript(arguments:)`, never pasted into script text. It is filled only on `https`, on the exact site host from Settings, on the sign-in form; a redirect anywhere else stops the sign-in. The sign-in web view uses `WKWebsiteDataStore.nonPersistent()`, so nothing of the site stays on disk outside the Keychain.
  - **Sending.** `URLSession` uses an ephemeral configuration with `httpShouldHandleCookies = false`, so nothing lands in the shared cookie storage. Cookies are added by hand, and any redirect to another host is refused (a `willPerformHTTPRedirection` delegate), so they never leave ParentLocker.
  - **The site's cookies** are a Keychain item of their own, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. They never sync, never go into a backup and are never logged.
  - **Sign Out** deletes the synced password (so it is gone on all of Danny's devices) and this device's cookies. Every other device checks that the password is still there before each sync; if it's gone, it deletes its own cookies and shows as signed out. So "Sign Out signs out your other devices too" is true.
  - **The MCP tool** can trigger a send but never reads or returns sign-in details.

### Settings, records, schema
- **The choice and the site address live on the shared `CDAttendanceEmailSettings`** (new `sendMethodRaw`, `parentLockerSite`, default `yyli.parentlocker.com`), so the guide sets them and the assistants follow. Existing rows read as email until the guide picks ParentLocker.
  - **Old Assistant builds.** Their `canSend` doesn't know the new field. So when the guide picks ParentLocker, the shared row's `isEnabled` is also set to false, and they stop offering the email. New builds decide by `sendMethod`.
- **Schema 18, all additive:**
  - `CDAttendanceEmailSettings.sendMethodRaw` (String, default "email")
  - `CDAttendanceEmailSettings.parentLockerSite` (String, optional)
  - `CDAttendanceEmailSend.channelRaw` (String, default "email")
  - `CDStudent.parentLockerID` (String, optional)
- **Backup format v40:** the fields go in the student DTO (`Backup/BackupTypes+Core.swift`), the AttendanceEmailSend and Settings DTOs (`Backup/ModelRowKinds.swift`, `Backup/BackupTypes.swift`) and `Backup/BackupEntityTable.swift`. Older backups restore with "email" defaults. The password and cookies are never in a backup.
- **Permissions:** `ClassroomPermissions` already lets assistants write `AttendanceEmailSend`, and `recordSend` puts hers in the shared store. Settings and students stay the guide's to write. Nothing changes there.
- **Close Arrival:** with ParentLocker picked, it becomes "Close Arrival & Send". "Close Arrival & Email" stays for the email method. "Mark as Sent" stays, for a day taken on the site by hand.
- **MCP gets its first outward tool,** `send_attendance_to_school(date?, preview?)`.
  - It is annotated open-world. The registry test's "only reads the local notebook" rule gets this one exception, and `docs/Technical notes/MCP_SERVER.md` says why.
  - `preview: true` writes nothing (`markNothingWritten`).
  - `attendance_for_day` reports the ParentLocker state.
- **Plain English** goes through `AppErrorMessages`. Raw replies and ParentLocker's own error text go only to the log or a Details disclosure. The messages:
  - "Couldn't reach ParentLocker. It'll try again."
  - "ParentLocker's attendance page changed, so the app can't send. Take attendance on the ParentLocker site for now."

### Safety while building
- **Debug builds and test runs never save to ParentLocker and never record a ParentLocker send.** They read, match and show what they would send. Only Release and TestFlight builds save. Why:
  - A macOS test run launches the real app on Danny's live store (memory: test host opens the live store).
  - A Debug build's send record would silence the 9:00 reminder and switch every Release device into live updates.
  - A Debug build may be reading stale data.
- **How the guard works.** It is a `ParentLockerSavePolicy` passed into the sync: `.live` in Release, `.previewOnly` under `#if DEBUG` or when `XCTestConfigurationFilePath` is set. It is its own ProcessInfo check, because `AppBootstrapping` isn't in the Assistant. Sync tests pass `.live` with a fake transport, so they check real saving; one test pins that the default in a test run is `.previewOnly`.
- **Nobody but Danny or an assistant types a ParentLocker password.** Claude never enters one, and a live check waits for Danny to sign in himself.

## Apple guidance

Checked 2026-10-12 against Xcode 27.0 (27A266a). Xcode 27.1 RC and 27.2 beta 2 exist; their notes say nothing about keychain, cookies, WebKit data stores or AutoFill, so there is no need to update first.

1. **Keychain.**
   - Use `kSecClassInternetPassword` with `kSecAttrServer`, `kSecAttrProtocolHTTPS` and `kSecAttrAccount`. Use generic passwords only when there's no server ([Adding a password](https://developer.apple.com/documentation/security/adding-a-password-to-the-keychain), 2026-08-14).
   - **Sync:** `kSecAttrSynchronizable = true`. Reads, updates and deletes need `kSecAttrSynchronizableAny`, and an update or delete affects every copy (`SecItem.h`).
   - **Accessibility for synced items** can't be a `ThisDeviceOnly` value. Use `kSecAttrAccessibleAfterFirstUnlock`, which the header recommends for background use. Avoid `kSecAttrAccessibleAlways*`, deprecated since iOS 12.
   - **On the Mac,** set `kSecUseDataProtectionKeychain = true` ([TN3137](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains), 2026-09-25).
   - **No `keychain-access-groups` entitlement is needed;** the app ID is the default group.
   - iCloud Keychain passwords are end-to-end encrypted by default ([Apple Support 102651](https://support.apple.com/en-us/102651)).
   - Store cookies as `HTTPCookie.properties` in the Keychain, never in UserDefaults; `HTTPCookie` isn't `NSSecureCoding`.
   - There is no Swift-first Keychain API in the 27 SDK.
2. **AutoFill and Passwords.**
   - No API lets an app read a saved password for a site it doesn't own.
   - `SecAddSharedWebCredential` is deprecated (26.2). Its replacement, `ASCredentialDataManager.save`, needs an associated domain, is iOS 26.2+ only, and isn't on the Mac.
   - Password AutoFill recommends credentials only for the app's own associated domains ([Password AutoFill](https://developer.apple.com/documentation/security/password-autofill), 2026-08-14), and we can't add ParentLocker's. So the app keeps its own Keychain item.
3. **Cookies.**
   - `getAllCookies` and `setCookie` are iOS 11+.
   - `setCookies(_:)` is iOS 26+, and `getCookies(for:)` is 27.0+, so the Assistant (iOS 18 floor) uses the old pair.
   - `WKWebsiteDataStore.fetchData(of:)` and `restoreData` carry local storage only, not cookies (WebKit source, not Apple docs).
   - Apple doesn't document whether session cookies survive a relaunch, so we keep them ourselves.
4. **Privacy guidance.**
   - [HIG Privacy](https://developer.apple.com/design/human-interface-guidelines/privacy) (2026-09-14): "Store sensitive information in a keychain"; never store passwords in plain text; explain the purpose plainly when asking.
   - Nothing from Apple covers filling a web form with a saved credential.
   - App Review 5.2.2 asks for permission under a third-party service's terms. These builds are TestFlight-only, but ParentLocker's terms are worth a glance before any App Store release.
5. **Background.**
   - Apple makes no promise for `WKWebView` work in the background, and forum reports say its JavaScript stalls there.
   - `beginBackgroundTask` gives a short window ([Extending your app's background execution time](https://developer.apple.com/documentation/uikit/extending-your-app-s-background-execution-time), 2026-08-14).
   - App Intents' `supportedModes` can run an intent in the background (2026-09-11).
   - Hence `URLSession` for sending, and the web view only for signing in.

## Phase 1: Schema 18 and the shared pieces
- **Who:** agent `feature-phase-deep` (Opus, high: four additive fields and a backup bump in an established pattern; high is enough).
- **Steps:**
  - Model `CosmicDaybook.xcdatamodeld`: the four fields above.
  - Entity files: `Attendance/Email/AttendanceEmailSettingsEntity.swift`, `AttendanceEmailSendEntity.swift` and `Students/Models/StudentEntity.swift`.
  - `Attendance/Email/AttendanceEmailLog.swift`:
    - `Settings` gains `sendMethod` and `parentLockerSite`; picking ParentLocker also writes `isEnabled = false`.
    - `recordSend(channel:)`.
    - The summaries say "Sent to ParentLocker at…" or "Emailed at…".
    - Old rows read as email.
  - `Attendance/Email/FrontDeskEmailReminder.swift`: `canSend` by method, and the wording for both methods ("Attendance is due in ParentLocker at 9:00."). This phase owns all of the reminder's wording, so Phases 3 and 4 don't touch it.
  - Backup v40: the DTOs and table listed under Decisions, plus `Backup/Archive/BackupWriter.swift`.
  - Docs counts: `docs/Technical notes/DATA_MODELS.md`, `BACKUP_SYSTEM.md`, `CloudKit/CLOUDKIT_GUIDE.md`, `Cosmic Daybook/CLAUDE.md`.
- **Cost:** ~2–3% (Opus high, small file count, backup tests).
- **Done when:**
  - The notebook iOS and macOS schemes and the Assistant build with no warnings.
  - `-only-testing:` passes for the AttendanceEmailLog, FrontDeskEmailReminder and backup golden and round-trip suites, with new tests for:
    - old rows reading as email,
    - the channel round-tripping,
    - the two new settings fields syncing, and picking ParentLocker turning `isEnabled` off,
    - the reminder offering ParentLocker,
    - a v40 backup carrying all four fields,
    - a v39 backup restoring with "email" defaults.
  - **Then the main session** runs one Debug Development `-InitializeCloudKitSchema` and confirms the four fields in the Development Console, so a schema mistake surfaces before Phases 2–4 build on it.
- **Hand off:** no. The main session merges it into this branch.

## Phase 2a: Talking to ParentLocker (wire, planner, requests, Keychain)
- **Who:** agent `feature-phase-deep` (Opus, high: pure logic and a network client, heavily tested).
- **Steps:** new files in `Cosmic Daybook/Attendance/ParentLocker/`, each added to the Assistant by path in `project.pbxproj`:
  - `ParentLockerWire.swift`: the `Decodable` course, roster, mark, save-reply and conflict types. Attendance objects are kept as raw JSON to echo back.
  - `ParentLockerPlanner.swift`: pure.
    - Matching, mark mapping (from the dedup winner; `closeArrival` gives an empty Notes box), and the diff for a given set of children or the whole class.
    - Per-class batches, plus the skipped list: unmatched, locked, unmarked, can't-clear.
  - `ParentLockerTransport.swift`: the protocol `courses() / roster(course:date:) / save(batch:)`.
  - `ParentLockerHTTP.swift`: the `URLSession` transport, exactly as under Privacy rules: ephemeral, no cookie handling, other hosts refused, cookies taken back from every reply.
  - `Services/Migrations/DataCleanupService+DeduplicateStudents.swift`: copy `parentLockerID` from a duplicate when the kept student has none (from Phase 1).
  - `ParentLockerKeychain.swift`:
    - The synced internet-password item and the `ThisDeviceOnly` cookie item, as in Apple guidance item 1.
    - Reads and deletes use `kSecAttrSynchronizableAny`.
    - `kSecUseDataProtectionKeychain` on the Mac.
    - It follows `Backup/Archive/BackupEncryptionKeyStore.swift`'s pattern but is self-contained, since that file isn't in the Assistant.
- **Tests** in `Cosmic Daybook Tests/Attendance/ParentLocker/`, with fixture JSON and HTML using made-up names, shaped like the real replies:
  - **Planner:**
    - Every mark mapping.
    - Unmarked children skipped, locked rows reported, the can't-clear case, and Notes left alone.
    - Split by class, the `YYYY-M-D` date, and a duplicate record using the winner.
    - Name matching: case and accents, nickname against alternate name, the same first name twice, ambiguous, unmatched.
  - **HTTP** over a `URLProtocol` stub:
    - Courses read from the page HTML.
    - "Signed out" detected.
    - A redirect to another host refused.
    - Nothing written to `HTTPCookieStorage.shared`.
    - Cookies updated from the replies.
  - **Keychain:** a round trip and delete.
- **Cost:** ~2–3%.
- **Done when:**
  - The notebook iOS and macOS schemes and the Assistant build with no warnings.
  - `-only-testing:` the new suites pass.
- **Hand off:** no.

## Phase 2b: Sign-in and the live sync
- **Who:** agent `feature-phase-deep` (Opus, xhigh: sync-reactive code, races between devices and privacy, where a mistake sends wrong attendance or signs someone out). After it, the main session runs the live check with Danny.
- **Steps:**
  - `ParentLockerSignIn.swift` (`@MainActor`): the invisible `WKWebView` (`.nonPersistent()` store) that fills the site's own form under the Privacy rules and hands the cookies to the Keychain. It is foreground only.
  - `ParentLockerSync.swift` (`@MainActor`):
    - The whole-class send (Close Arrival & Send, after Undo's window), Send Now, and `send(day:preview:)`.
    - The "after" rule and the guide's backstop.
    - The per-child live updates (4 s local / 60 s imported), with its own DidSave observer.
    - The catch-up after the first import.
    - Retries on an injected clock, and the background rules.
    - The password-gone check before each sync.
    - The send record, and matches written only on the guide's devices.
    - `ParentLockerSavePolicy`.
    - Returns `ParentLockerStatus`: its plain line, plus the problems.
  - `ParentLockerSignInSheet.swift`: Email, Password, the privacy line, Sign In and Sign Out.
  - `ParentLockerStatusLine.swift`: the shared one-line status view that both apps show.
  - `ParentLockerMatchView.swift`: Match Names. It is notebook only, but lives here so Phase 3 only places it.
- **Tests** over a fake transport, a fake clock and a fake Keychain:
  - **Nothing before "after":**
    - No send or watch before the day is sent.
    - Arrival closed on an unsigned phone starts live updates, and the guide's backstop sends once.
  - **The Close Arrival send:**
    - Undo inside the window sends nothing.
    - Close Arrival sends once per class.
  - **Live updates:**
    - Local changes wait 4 s, coalesce, and send only those children.
    - Imported changes wait 60 s and are skipped when already in.
    - Two fake devices, one holding stale marks, never push the stale mark over a newer one.
    - The catch-up waits for the import.
  - **Problems:**
    - Retries, conflicts (ignored when equal), signing back in in the foreground, none in the background, and a refused password.
    - A password deleted on another device signs this one out.
  - **Saving:**
    - The send is recorded once, and never under `.previewOnly`.
    - Matches are written only by the guide.
    - A preview writes nothing.
    - The default policy in a test run is `.previewOnly`.
  - **Privacy:** the password never appears in logs, status lines, error text, preferences or a backup, and is passed as an argument, not in script text.
  - **Efficiency:** `.claude/skills/efficiency-pass/check_audit_rules.py` is clean on the new files (sync-reactive code).
- **Then the live check** (main session, read-only, with Danny):
  - In the Debug Mac app, Danny types his own ParentLocker email and password into the sheet.
  - Today's preview shows the right children in the right classes with the right marks; nothing is saved.
  - Quit and relaunch: still signed in without asking.
  - Danny signs out on the website itself to stand in for an expiry; the next preview signs back in by itself.
  - Note how long the site's sign-in lasts.
- **Cost:** ~4–5% (xhigh, plus the live check).
- **Done when:**
  - The notebook iOS and macOS schemes and the Assistant build with no warnings, including an **Assistant Release** build, since the guard is `#if DEBUG`.
  - `-only-testing:` the ParentLocker suites pass.
  - The audit script is clean.
  - The live check's four points hold.
- **Hand off:** no.

## Phase 3: The notebook's screens, MCP and Shortcuts ‖ Phase 4
- **Who:** agent `feature-phase` (Opus, high: screens and an MCP tool on an engine that exists).
- **Files:** only in notebook-only folders, which the notebook target picks up by folder. No `project.pbxproj`, reminder or engine edits.
- **Steps:**
  - **Settings:** `Attendance/Email/AttendanceEmail.swift` and `AttendanceEmail+Prefs.swift`.
    - The method picker, with the email fields only when email is picked.
    - The site, Sign In / Sign Out (the shared sheet) and Match Names (placed from Phase 2b).
    - `Settings/SettingsCopy.swift` and `Settings/SettingsView+Sections.swift`: the group becomes "Attendance to the School".
  - **The attendance screen:** `Today/Views/Attendance/AttendanceExpandedView+FrontDesk.swift`, `+Band.swift`, `+Controls.swift`, `+ActionBars.swift` and `AttendanceFrontDeskControl.swift`.
    - The shared status line.
    - "Close Arrival & Send", with the send started after Undo's window.
    - Send Now in the ⋯ menu.
  - **MCP:**
    - `Services/MCPServer/MCPNotebookTools+SchoolAttendance.swift`, and `attendance_for_day` reporting ParentLocker.
    - `Cosmic Daybook Tests/Services/MCPServer/MCPToolRegistryTests.swift`: 92 tools, the write set, and the open-world exception.
    - `docs/Technical notes/MCP_SERVER.md`.
  - **Shortcuts:** `Siri/SendAttendanceIntent.swift` as a Shortcuts action only, plus a `docs/Technical notes/SIRI.md` line.
  - **Launch:** start `ParentLockerSync` from `AppCore/AppBootstrapper.swift`.
- **Cost:** ~2–3% (Opus high, iOS and Mac).
- **Done when:**
  - The notebook iOS and macOS schemes build with no warnings.
  - `-only-testing:` passes for MCPToolRegistryTests, the new MCP tool tests, and the Settings and attendance suites it touches.
  - SwiftLint is clean.
- **Hand off:** no.

## Phase 4: The Assistant's screens ‖ Phase 3
- **Who:** agent `feature-phase` (Opus, high: screens on the shared engine, one platform).
- **Files:** only in `Daybook Assistant/`, which the Assistant target picks up by folder. No `project.pbxproj`, reminder or engine edits.
- **Steps:**
  - `Sync/AssistantClassroomSheet.swift`: a ParentLocker row with Sign In / Sign Out.
  - `FrontDesk/AssistantFrontDesk.swift` and `AssistantFrontDeskRow.swift`: the shared status line and Send Now when ParentLocker is picked; the email row unchanged otherwise.
  - `Attendance/AssistantArrivalBar.swift`: "Close Arrival & Send".
  - `Siri/AssistantAttendanceIntents.swift` and `AssistantSiriCommands`: Close Arrival also sends when signed in, and otherwise says it couldn't send yet.
  - `Sync/AssistantBootstrapper*.swift`: start `ParentLockerSync`.
  - Switch `ArrivalReminder.askPermission`, `AssistantSetupPages.dueAt` and `AssistantClassroomSheet.frontDeskDueAt` from `canSend` to `canSendAttendance` (from Phase 1).
  - Onboarding's last page: one line, "Sign in to ParentLocker once to send attendance."
- **Cost:** ~1.5–2%.
- **Done when:**
  - The Assistant scheme builds with no warnings.
  - `-only-testing:` the Assistant front-desk, attendance and Siri suites pass.
  - A check on the leased iPhone SE (`--os 26.5`, 1 simulator, then `sim-lease --done`) shows the sign-in row and the status line rendering at the largest text size.
- **Hand off:** no.

## Phase 5: Combine, review, builds, suites, merge
- **Who:** main session.
- **Steps:**
  - Merge Phases 3 and 4.
  - A review of the whole diff by an Opus `Plan` agent, aimed at privacy, live-update races and the save policy. Fix what holds up with a fresh small agent or here.
  - **A plain-English pass** (Danny, 2026-10-12: "check and update all language the user sees to be in plain English"). Read every word the feature shows in both apps, and fix what isn't plain:
    - Where to look: the sign-in sheet, the status line and its problems, Match Names, the Settings group, the attendance buttons and menus, the Assistant's rows, the reminders, Siri's replies, the MCP tool's text and the preview.
    - The rules are the project's Plain English rules (`docs/Plans/Plan - Plain English messages.md`, `AppErrorMessages`): say what happened and what to do, in everyday words, with no codes, hosts, cookie or HTTP words, or type names.
    - The pass is done when a test or a read-through lists every string, and each one is plain.
  - Full builds: notebook iOS, macOS and Release, and the Assistant Debug and Release.
  - Whole suites once (notebook, then Assistant) on the leased simulator with `-parallel-testing-enabled NO` (1 simulator each).
  - A simulator look at Settings and the attendance line on iPhone, and at the **sign-in sheet on the iPhone SE (3rd generation)**, at the default and largest text sizes with the keyboard up (Danny, 2026-10-12: "Make sure the sign in sheet looks good on an iphone se 3rd gen"). Phase 4 checks it first; this is the check after everything is combined.
  - Docs: a new `docs/Technical notes/PARENTLOCKER.md` (the site's requests, the guards, how to check the page still works) and a `Cosmic Daybook/CLAUDE.md` line.
  - Delete the live-check simulator's copy of the notebook and its saved ParentLocker sign-in (uninstall the app from this checkout's simulator).
  - Squash to main, push, `docs-index`, and close-out.
- **Cost:** ~3–4%.
- **Done when:**
  - All five builds are clean.
  - Both whole suites pass.
  - The review's findings are fixed or answered.
  - It is on main and pushed.
- **Hand off:** no.

## Phase 7: Final bug check
- **Who:** main session, sending three or four Opus `Plan` reviewers, read-only and split by area: engine and privacy; live updates and races; the notebook's screens and MCP; the Assistant.
- **Steps:**
  - Each reviewer reads the diff from `043cdd7b` to main's head, plus the plan's Decisions.
  - Each reports real bugs only, as numbered findings with file:line and a concrete failure.
  - The main session checks each finding against the code and writes the confirmed ones to `docs/Reviews/ParentLocker bug check 2026-10-13.md`.
- **Done when:** the report is committed, with every finding marked confirmed or dropped, and why.

## Phase 8: Fix the findings
- **Who:** the main session runs /plan-efficiently on the report and writes `docs/Plans/Plan - ParentLocker bug check fixes.md`, then carries it out. Agents are sized to the findings; at most three run at once. Each finding gets a failing test first where one can be written.
- **Done when:** every confirmed finding is fixed or answered, all builds are clean, both whole suites pass, and the work is on main and pushed.
- **If a fix changes the model:** run the Development schema again on the test-account simulator (C0EDC79D), as in Phase 1, before Phase 9.

## Phase 9: Push, Production schema, close-out, TestFlight
- **Who:** main session.
- **Steps:**
  1. **Make sure main is pushed.**
  2. **Deploy schema 18 to Production** in the CloudKit Console (Danny's developer account, already signed in to the browser pane): Development → Deploy Schema Changes. It's additive, and it has to happen before any TestFlight copy runs. Then confirm the four fields under Production. If the browser is signed out, stop here: don't upload, and add Tide rows instead.
  3. **Close out:** tick the plan, set the status line to Done with main's commit, run `docs-index`, mark the board's plan done (`board-touch --done`), add Tide rows for Phase 6 (see below), and write memory.
  4. **TestFlight:** run the `roll-out` skill for the notebook (iPhone/iPad and Mac) and the Daybook Assistant. Once it has processed, add the Assistant's build to the **Assistants** group (Danny, 2026-10-12: "assistant app should be added to the assistants group for testing"). The notebook's build goes to no group.
- **Done when:**
  - Production shows the four fields.
  - Both apps' builds are uploaded to App Store Connect, with their build numbers recorded here.
  - The Assistant's build is in the Assistants group.
  - The Tide rows exist.

## Phase 6: Danny's steps

Danny's steps are rows in Tide (Cosmic Daybook › To do), added 2026-10-13:
- Every assistant has Daybook Assistant 1.1 (019) before switching to ParentLocker: [Release](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=Make%20sure%20every%20assistant%20has%20Daybook%20Assistant%201.1%20%28019%29%20before%20switching%20attendance%20to%20ParentLocker). Installing the notebook everywhere is the existing Release row "Roll out main (ba5c5e15 or later)…", which TestFlight 300000000018 now covers.
- Switch to ParentLocker, sign in once, check Match Names: [Check](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=Switch%20Attendance%20to%20the%20School%20to%20ParentLocker%20in%20Settings%2C%20sign%20in%20once%2C%20and%20check%20Match%20Names%20finds%20all%2023%20children).
- One morning with Close Arrival & Send, a late arrival and an early pickup: [Check](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=Take%20one%20morning%27s%20attendance%20with%20Close%20Arrival%20%26%20Send%2C%20then%20check%20the%20class%20in%20ParentLocker).
- Each assistant signs in once and tries Siri: [Check](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=Have%20each%20assistant%20sign%20in%20to%20ParentLocker%20once%20in%20the%20Assistant%27s%20Classroom%20sheet%20and%20try%20Siri%27s%20%22Close%20arrival%22).
- The iPhone's Send button and the Mac's Send Now question: [Check](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=Check%20the%20iPhone%27s%20front-desk%20row%20shows%20Send%20to%20ParentLocker%2C%20and%20the%20Mac%27s%20%E2%8B%AF%20Send%20Now%20asks%20about%20unmarked%20children%20first).
- After a week, nobody was asked to sign in again (starts Oct 20): [Check](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=After%20a%20week%20on%20ParentLocker%2C%20check%20nobody%20was%20asked%20to%20sign%20in%20to%20ParentLocker%20again).
- The Match Names row wrapping at the largest text: [Build & fix](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=Ask%20Claude%20to%20fix%20Settings%27%20Match%20Names%20row%20wrapping%20letter%20by%20letter%20at%20the%20largest%20text%20size).
- The main folder's stale staged change: [Build & fix](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=Ask%20Claude%20to%20clear%20the%20stale%20staged%20change%20to%20AssistantAttendanceIntents.swift%20in%20the%20main%20Maria%27s%20Notebook%20folder).

## Phase 6 (original list) (Tide rows in `Areas/App Development/Cosmic Daybook/To do.md` and the Assistant's list)
- **Release** (Phase 9 does the schema deploy and the upload; Danny does the rest):
  - Install the notebook everywhere together: the Mac's Release copy (`Scripts/install_release.sh`) and TestFlight on the iPad and iPhone.
  - **Every phone gets the update before switching to ParentLocker.**
- **Check on a device:**
  - Settings › Messages → ParentLocker, and sign in once.
  - Match Names.
  - One morning: take attendance, Close Arrival & Send, and check ParentLocker.
  - Mark a child late later and see it change on the site.
  - Over the next days, ParentLocker never asks anyone to sign in again (the app signs back in by itself after a real expiry).
  - Each assistant signs in once on her phone.

## Starting a phase
Read the plan usage (`get_usage`) and note the weekly % used next to the phase under Progress ("started at N%"). Agents work in their own worktrees from this branch. They don't tick this file (the main session does), and they reply in at most 15 lines.

## Ending a phase
1. Check every "Done when" item for the phase.
2. Tick the phase under Progress and note anything that differed from the plan. Read the plan usage again and note the actual cost (end % minus start %).
3. Add a row to the log in `~/.claude/skills/plan-efficiently/references/cost-estimates.md`.
4. Update the build board.
5. Make every "not verified", "for your review" or "check on a device" item from this phase a row in the app's list in Tide (`add_action`), skipping ones already there. The repo line keeps one plain sentence plus the row's `tide://` link.
6. Run /close-out. It sets the plan's status line and runs `docs-index`.
7. If the next phase is a fresh session, print its starter prompt.

## Decided during the run

- **Phase 5 review** (an Opus reviewer, read-only): 12 real bugs and 14 phrases that weren't plain, out of about 115 strings checked. All fixed:
  - 3 in the screens by the main session (3e937689): Mark as Sent records nothing in a test copy; the Assistant's send goes a second after its Undo; plainer words.
  - 9, with the rest of the wording, in the engine by a deep fix agent (6b48ccad):
    - a per-child "last seen in ParentLocker" check, so a synced-in change never overwrites a newer mark
    - the guide's backstop a minute after the due time when everyone was marked and nothing was sent
    - Notes the app wrote are cleared when the new mark has none
    - Match Names is gated by the save policy
    - the catch-up gives up waiting for an import after 20 s, and on the Mac only a return after a minute away counts
    - the Assistant always counts as an assistant here
    - a recorded send reschedules the reminder
    - cancelling a sign-in stops it
    - only "no item" counts as signed out, and a failed Sign Out says so
    - the Assistant's school days come from the class share

  Every targeted test was seen failing with its fix undone.
- **The Assistant's Release build warns at `AssistantSampleClass.swift:177`** ("will never be executed"). That warning was there before this work, in a file it doesn't touch; it's left alone and noted for Danny.
- **Flaky Assistant tests:** in the first whole run, `UnsentChangesKeepAliveTests` › "Siri waits for its marks to go into the share" and "An attach that never finishes…" failed; they passed alone, with the ParentLocker tests, and in a whole rerun. They're timing-sensitive Siri tests, not ParentLocker's, and are left as a Tide row.
- **The main checkout has a stale staged change** to `Daybook Assistant/Siri/AssistantAttendanceIntents.swift` (it undoes 043cdd7b; the file is dated Oct 7), left by an earlier move of main. It wasn't touched. Main was moved with `update-ref`, so that checkout's files are behind main.
- **Phase 9 so far (2026-10-13):**
  - **Schema 18 is in CloudKit Production.** Deployed after Danny signed in to the developer account again in the browser pane. The deploy preview showed exactly the four fields on three types, plus CloudKit's companion fields and indexes, and Production then listed all four.
  - **The notebook's iOS archive 1.1 (300000000017) is built from 3ba3c2f8 but not uploaded.** The upload stopped at "Failed to Use Accounts": Xcode's App Store Connect sign-in had lapsed overnight.
  - **TestFlight is on hold** (Danny: "don't send to testflight yet"). The Mac roll-out was stopped mid-archive and nothing went up. `LAST_BUILD` is unchanged at 16 for the notebook and 18 for the Assistant.
  - **A fresh bug hunt has started** at Danny's request ("bug hunt the parentlocker changes"). Four Opus reviewers come at it from new angles: a real morning end to end, a fresh line-by-line read of the engine, data and sync and backup and MCP, and screens and words.
- **The live-check simulator was cleaned:** the app uninstalled and its keychain reset, so the ParentLocker password Danny typed there is gone.

## Open questions

None. Danny's answers on 2026-10-12:
- No Siri phrase in the notebook.
- No arrival time in the Notes box.
- Sign in once, for him and each assistant, with email and password kept in iCloud Keychain.
- Close Arrival sends the whole class in one batch, then each change goes live ("send in batch when we close arrival, and then each change goes live").
