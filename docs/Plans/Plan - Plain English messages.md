> Archived 2026-10-04: built and on main.

# Plain English in the apps — plan (2026-10-03)

> **Done 2026-10-03** (9503d7f2).
> In short: Every message the apps show says what happened and what to do.
> All six phases are on main (the branch `claude/festive-morse-7d0b1a` is gone). Git cannot say whether Danny has since looked at the screens; his on-screen check is in Tide.

**Rule** (Danny's `~/.claude/CLAUDE.md`, "Plain English in the apps"): everything Cosmic Daybook and the
Daybook Assistant show him — notifications, alerts, error messages, status lines, empty states, toasts,
banners, Siri results — says what happened and what (if anything) to do, in everyday words. No raw
system errors, codes, IDs, file paths, type names or developer jargon. Useful technical detail goes in a
"Details" disclosure or the log. Apple-framework errors are translated for the cases the app knows;
anything else gets a plain general sentence, never the raw text.

**Status: built 2026-10-03, on main as 9503d7f2 (merged from branch `claude/festive-morse-7d0b1a`).** Danny approved
every recommendation (decisions at the end). Phase 1 (shared translator) built in session; phases 2–6 ran
as parallel agents, one isolated worktree each, then merged with no conflicts. Final check on the merged
branch: notebook iOS + Mac and the Assistant build clean (no new warnings); full suites: notebook 2,466
passed, 5 timing tests failed under a load average of ~470 and passed alone (12/12); Assistant 149/149.
Nothing has been looked at on screen yet.

- [x] Phase 1 — shared translator (`AppErrorMessages`, `AppleIntelligenceMessages`, `save(alertOnFailure:)`,
  `TechnicalDetailsDisclosure`), 6d72faa8.
- [x] Phase 2 — sync, database, startup: raw sync text kept separately for Details and Sync History; the
  safe-mode banner reads a stored flag, not its own text. b30691dd.
- [x] Phase 3 — backup & restore: plain error enums; `BackupPlainNames` (every backed-up type has a plain
  name); restore warnings translated at display (`BackupWarningText`), the frozen legacy restore untouched;
  "Clean Up Leftovers". f1f03818.
- [x] Phase 4 — sharing, Assistant, Siri, attendance: `sharingMessage` everywhere; "Class code" under
  Details; Siri says "late"; the saved Siri undo gained an optional `name` (old records still decode);
  attendance grid failures now toast. ff873917.
- [x] Phase 5 — Students, Presentations, Work, Today: typed errors are plain and carry no save text;
  `PresentationFailureMessage`; their saves keep the global alert quiet; silent failures surfaced. c9ad9fe2.
- [x] Phase 6 — Lessons, Notes, Stories, Book Club, Parsha, Command Bar, Planning, Resources, Todos, Albums,
  Chat, Claude Desktop status; silent failures surfaced. eaca3c32.
- [x] Leftover scan: the on-device chat tool's failure reply was the one remaining leak (fixed 7a903135);
  every other `localizedDescription` left is a log line or Details text.

Known gaps, not wording: if saving fails in `MarkLessonPresentedIntent`, the half-made presentation stays
unsaved in the main context (pre-existing). (Fixed the same day: MCP tool failure replies, which only Claude
reads, carry the plain sentence plus a `Details:` line — the error's case, values, domain, code and
underlying error — via `MCPToolError(_:underlying:)`.)

Paths are relative to `Cosmic Daybook/` unless they start with `Daybook Assistant/` or `Cosmic Daybook Tests/`.
Line numbers are from commit 89474e75.

---

## Part 1 — the shared fixes (one change each, many screens fixed)

Most raw text reaches the screen through a few shared paths. Fixing these first does most of the work.

| # | Where | Now | Change |
|---|---|---|---|
| S1 | `Utils/Diagnostics/AppErrorMessages.swift` `saveFailureMessage` (shown by the global "Couldn't Save" alert, `Backup/SaveCoordinator.swift:86`) | appends `(While: <reason>)` — 188 call sites pass developer labels like "Update CDStudent Selections", "Toggling pin status", "Repair student order" | Drop the suffix from the message; keep the reason in the log (it's already logged as `.fault`). Alert fallback "Unknown error." → "Your change couldn't be saved. Try again." |
| S2 | `AppErrorMessages.backupMessage` fallback | "Couldn't back up your notebook: <raw> [domain=… code=…]" | Use the app's own error text when it has one (after Part 3 rewrites it), else "Couldn't {operation}. Try again." Domain/code → log. |
| S3 | `AppErrorMessages.aiMessage` + `Services/AI/LocalModelClient.swift:175–225` + `AIClientRouter.swift:171–200` | passes "Generation failed: <raw>" / "Apple Intelligence unavailable: <raw reasons> Private Cloud Compute is off in Settings → AI." straight through; fallback "The AI feature encountered a problem."; ignores app errors (so "student not found" becomes an AI error) | One shared Apple Intelligence translator (below) replacing the five copies in QuickNoteViewModel, NoteEditorAISuggestion, StoryAnalyzer, AppleIntelligenceSheet+Generation and LocalModelClient. Honor app-defined errors first. Fix the stale path to "Settings › Intelligence". |
| S4 | `AppErrorMessages.userMessage` iCloud default | "An iCloud issue prevented {x}. Your changes are saved locally and will sync later." — wrong for sharing, members, leave (nothing saved, nothing retries) | Add a sharing context (no "saved locally"): "Couldn't {add Sam}. iCloud didn't answer. Check you're online and try again." |
| S5 | `AppErrorMessages.coreDataMessage` | every Cocoa code 256–1024 → "There was a problem reading your data" | Split: 640 out of space → "This device is out of space. Free some up and try again."; 513/642 no permission → "Cosmic Daybook isn't allowed to save there."; reads keep the read wording. |
| S6 | `AppErrorMessages` network + account wording | "The request timed out…", "Couldn't reach the server…", "Sign in to iCloud in Settings" (wrong on Mac) | "That took too long. Try again in a moment."; "Couldn't connect. Try again later."; use `SystemSettingsApp.name`. |
| S7 | Typed `saveFailed(String)` error cases (`RecordError`, `RecordingError`, `CommitError`, `MoveError`, `LogError`) carry `lastSaveErrorMessage`, **and** SaveCoordinator raises its global alert at the same moment → two alerts for one failure | Screens that report their own failure save with the global alert suppressed; their own message is the plain one in Part 4. |

**New shared Apple Intelligence wording** (S3), used by Notes, Stories, Parsha, Planning, Chat, Albums, Insights:

| Case | Message |
|---|---|
| Busy / rate limited | Apple Intelligence is busy. Wait a moment and try again. |
| Too long / context too large | That's too much for Apple Intelligence at once. Try something shorter. *(callers can say "Choose fewer notes")* |
| Refused (guardrail) | Apple Intelligence can't help with this one. Try rewording it. |
| Timed out | Apple Intelligence took too long. Try again. |
| Still downloading | Apple Intelligence is still getting ready. Try again in a few minutes. |
| Off / not on this device | Apple Intelligence isn't available right now. |
| Private Cloud off and needed | This needs Private Cloud Compute, which is off. You can turn it on in Settings › Intelligence. |
| Unreadable answer | Apple Intelligence gave an answer the app couldn't use. Try again. |
| Anything else | Couldn't finish that. Try again in a moment. *(callers pass their own: "Couldn't make a plan…")* |

---

## Part 2 — iCloud sync, database and startup

| Where | Now | Proposed |
|---|---|---|
| Settings › iCloud error row (`Services/Sync/CloudKitSyncStatusService+EventHandlers.swift:398`) | "Notebook export failed [CKErrorDomain (2)]: <raw>" | Translate via `userMessage(context: "syncing with iCloud")`; raw form kept for Sync History only. Unknown: "iCloud sync didn't finish. It'll try again on its own." |
| Settings › iCloud status line + error row (`Services/Sync/CloudKitStoreHealth.swift:128–133`, `CloudKitStatusSettingsView.swift:209`) | "Classroom share export failed: "<server text>" (CKError 12). Nothing in the classroom share syncs until this is fixed." | "The classroom share can't send changes to iCloud right now. Your changes are safe on this device." (+ "iCloud will try again." when retrying). Server text + code → Details. |
| "Recent sync problems" (`CloudKitStatusSettingsView.swift:161`, `AppCore/Persistence/CloudKitConfigurationService.swift:110–126`) | "{title}: <raw> (retry after 30.0s)" | Title + plain advice; raw text in a separate field shown under Details. |
| Sync-stopped banner (`Services/Sync/SyncStoppedAdvice.swift:60–116`) | "iCloud refused to sync the classroom share: "…" (CKError 12). The fix is on the iCloud side: deploy the CloudKit schema to Production in CloudKit Console, then reopen the app." | "Sync for the classroom share is stopped because of a problem on iCloud's end. Your changes are kept on this device and will send once it's fixed. An app update may be needed." Developer fix + quote → Details. Title "Classroom sync is stopped". |
| Sync status failure (`CloudKitSyncStatusService.swift:363, 370`) | "Sync failed after 5 attempts. Please try again later." / toast "iCloud sync failed. Data may be out of date." | "iCloud sync keeps failing. Your changes are safe on this device. Try Sync Now in a little while." / "Couldn't sync with iCloud. Your changes are safe on this device." |
| Toolbar sync dot (`Components/Shared/SyncStatusIndicator.swift:59, 62`) | "3 pending" / "Sync error" | "3 changes waiting to send" / "Sync problem — see Settings" |
| Startup banner (`AppCore/RootView/WarningBanners.swift:111–121`, `AppBootstrapping+CloudKit.swift:57–61`, `CoreDataStack.swift:334`) | "⚠️ CloudKit Init Failed" / "CloudKit store failed to load: <raw>. Falling back to local storage." | "iCloud Sync Couldn't Start" / "Your notebook is on this device and syncs again once iCloud reconnects. Reopen the app to try again." |
| Safe-mode banner (`WarningBanners.swift:15–28`, `AppBootstrapping+CloudKit.swift:27, 95, 108`) | "⚠️ SAFE MODE: CHANGES WILL NOT BE SAVED" / "You are using an in-memory store… Create a backup immediately!" / "The persistent store could not be opened…" | "Changes Won't Be Saved" / "Your notebook couldn't be opened, so anything you change now will be lost when you quit. Back up now, then reopen the app." **First** replace the `isInMemoryMode` text search ("in-memory"/"temporary") with a stored flag, or the rewording breaks it. |
| Database error screen (`AppCore/Persistence/DatabaseErrorView.swift:22–140`) | "Database Error" / "The app could not initialize the database." / always-visible "Error Details:" raw text / "Reset Local Database" / "…CloudKit data is preserved…" / "Failed to reset database: <raw>" | "Couldn't Open Your Notebook" / "Cosmic Daybook couldn't open your notebook on this device." / raw text behind a Details disclosure / "Re-download from iCloud" / "This removes your notebook from this device only. Your notebook in iCloud stays safe and downloads again when the app reopens." / "Couldn't clear this device's copy. Quit and reopen the app, then try again." |
| `CoreDataStack.swift:330–343` messages | "Core Data model '…' not found in app bundle." / "Failed to load persistent store: <raw>" / "…(database format N; this copy understands M)…" / "…Use Settings → Database → Reset Local Cache…" | "This copy of Cosmic Daybook is damaged. Reinstall it." / "Cosmic Daybook couldn't open your notebook." / drop the numbers / "…Open Troubleshooting and choose "Re-download from iCloud…"." |
| `AppBootstrapping+ErrorHandling.swift:47`, `DatabaseInitializationService.swift:56, 66` | "Unexpected error during Core Data stack initialization: <raw>" | "Cosmic Daybook couldn't open your notebook." (raw → Details) |
| Launch screen (`AppCore/CosmicDaybookApp+MainWindow.swift:20, 22`) | "Initializing database…" / "Running migrations…" | "Opening your notebook…" / "Updating your notebook…" |
| Calendar/Reminders sync (`Services/Calendar/CalendarSyncService.swift:163, 313, 319`, `ReminderSyncService+Sync.swift:36`, `ReminderSyncService.swift:328, 334`; shown on Today's header tooltip `TodayViewRemindersSection.swift:154, 197`) | "Sync error: <raw EventKit>" / "Database context is not available. Please try again." / "…access has not been granted. Please authorize access in Settings." | Store `AppErrorMessages.syncMessage` at the source. "Couldn't reach your notebook to sync. Try again." / "Cosmic Daybook doesn't have access to Calendar. Turn it on in {Settings} › Privacy & Security." |
| Sync History (Troubleshooting, diagnostics) | "Export failed [NSCocoaErrorDomain (134406)]: …", "Setup completed", "Manual sync initiated" | Plain first line ("Sent changes to iCloud", "Got changes from iCloud", "Couldn't send changes — will try again", "You tapped Sync Now"), raw detail under it. |

## Part 3 — Backup & restore

| Where | Now | Proposed |
|---|---|---|
| Backup alert title (`Settings/DataManagement/DataManagementGrid.swift:150`) | "Error" | "Couldn't Save the Backup" / "Couldn't Restore" |
| `Backup/Core/AutoBackupManager.swift:321` | "Couldn't back up your notebook: Backup already in progress [domain=AutoBackupManager code=1]" | "A backup is already running. It'll finish in a moment." |
| Restore transaction (`Backup/Services/BackupTransactionManager.swift:25–35`) | "Failed to create safety checkpoint: <raw>" / "Rollback failed: <raw>" / "Import failed: <raw>. A safety backup was created at <file>." | "Couldn't make a safety copy before restoring, so nothing was changed. Try again." / "The restore didn't finish, and your notebook couldn't be put back on its own. Restore your most recent backup from Settings › Sync and backup." / "The restore didn't finish, so your notebook was put back the way it was. Nothing was lost." |
| `Backup/BackupService+Restoration.swift:18, 32` | "…existing LessonAssignment… could not be cleared…" / "…couldn't be saved first: <raw>" | "The restore stopped because some of your current notebook couldn't be cleared first. Your notebook was put back the way it was. Try again." / "The restore didn't start because your latest changes couldn't be saved first. Nothing was changed. Try again." |
| Archive errors (`Backup/Archive/BackupArchive.swift:62–89`, `BackupReader.swift:41–52`) | "Could not open backup file for write at /Users/…", "Failed to initialize AEA decryption stream…", "Backup manifest is malformed: <raw>", "Backup format version 40 is not supported (supported: v17–v36)", "Backup entry has an unexpected path…" | Write: "Couldn't write the backup. Try again." Read: "This backup file is damaged and can't be restored." Wrong key: "This backup couldn't be opened. It may be damaged, or it was made on a device signed in to a different Apple Account." Newer: "This backup was made by a newer version of Cosmic Daybook. Update the app, then try again." Older/not ours: "This file isn't a Cosmic Daybook backup, or it's from a much older version of the app." |
| `Backup/Archive/BackupWriter.swift:99–108` | "Backup aborted: could not encode StudentEntity records (<raw>)…", "…failed read-back verification…", "…note photo <file> could not be read…" | "The backup stopped because part of your notebook couldn't be read. No file was saved. Try again." / "The backup didn't check out after saving, so it was thrown away. Try again." / "A note photo couldn't be read, so the backup stopped. No file was saved. Try again." |
| Keychain (`BackupEncryptionKeyStore.swift:26–32`) | "Could not read the backup encryption key from the Keychain (error -25300)." / "Apple ID" | "Couldn't unlock this device's backup key. Restart the device and try again." / "Apple Account" |
| `BackupCoordinator.swift:27` | "Legacy .mtbbackup files are no longer supported…" | "This backup is from an old version of the app and can't be restored. Choose a newer backup." |
| Backup folder check (`Backup/Core/BackupDestination.swift:26–30`; move prompt `DataManagementGrid.swift:259–277`) | "…is inside a code repository. Backups would be tracked in version control." / "…saved in "/Users/…/Developer/…", which looks unsafe (code repo, app bundle, or system folder)" / "Couldn't move backups: <raw>" | "That folder belongs to another app or project, so backups could be lost there. Choose a folder in Documents or iCloud Drive." / "Your backups are in a folder that isn't safe for them ("{folder name}"). Move them to iCloud Drive › Cosmic Daybook › Backups?" / "Couldn't move the backups. They're still in the old folder." |
| Restore warnings (`BackupService+Restoration.swift:301`, `BackupImporter.swift:218–227`, `BackupPreviewAnalyzer.swift:241`) | "iCloud sync reported a failure: <raw>. …check Settings → iCloud to retry." / "Unknown entity 'X' in backup — skipped…" / "LessonAssignment records could not be read…: <raw>" / "N lesson assignments reference lessons missing…" | Translated **at display** (the frozen legacy-restore copy must keep producing the same raw warnings for the equivalence tests): "Your restored notebook is saved on this device but hasn't reached iCloud yet. It'll keep trying." / "Part of this backup was made by a newer version of the app and was skipped. Update Cosmic Daybook to restore all of it." / "Some planned lessons in this backup were damaged and were skipped." / "N planned lessons point to lessons that aren't in this backup or your notebook. They'll reconnect once those lessons are added." |
| Export "warning" (`BackupWriter.swift:198`) | red Warnings badge: "Note photos are included (N); imported documents and file attachments are not, by design." | Info, not a warning: "Includes N note photos. Imported documents and file attachments aren't in backups." |
| Restore preview + summary (`Backup/RestorePreviewView.swift:67–96`, `BackupSummaryView.swift:14–78`) | "Inserts / Deletes", "By Entity" with raw type names ("ProjectWeekRoleAssignment"), chip "update N" (actually skipped), "Backup Export Complete", "Format Version: 36", "Records" | "Adding / Removing", "What changes" with plain names (new type→plain-noun map, built from `ClassroomShareSetupReport.describe`), "already here N", "Backup Saved" / "Restore Complete", version under Details, "What's in it" |
| Clean Up Old Records + Remove Last Year backup check (`Settings/DataManagement/NotebookCleanupModel.swift:77, 130, 135`, `Sharing/ClassroomShareRelease+Live.swift:152, 157`) | raw error / "Couldn't count the notebook's WorkParticipantEntity records…" / "The backup holds 12 YearPlanEntry records, the notebook 14." | "The safety backup didn't hold all of your notebook, so nothing was changed. Try again." / "The backup before cleaning up didn't finish. Nothing was changed." |
| Clean Up labels (`NotebookCleanupSheet.swift`, `SettingsCopy.swift:94`, `Services/Migrations/NotebookJunkCleanup.swift:85–98`) | "Clean Up Old Records", "records that point at nothing, blank rows", "blank attendance row(s)", "presentation record(s) with no child or lesson" | "Clean Up Leftovers", "bits left over from older versions, blank entries and duplicates", "empty attendance entries", "lessons given with no child or lesson" |
| Notebook at a glance (`SettingsDatabaseComponents.swift:27, 45`) | "N records", "Records across your notebook" | "N items", "Everything in your notebook" |
| Restoring overlays (`WorksAgendaView.swift:183`, `TodayView.swift:198`, `AttendanceStandaloneView.swift:59`) | "Restoring data…" | "Restoring your backup…" |

## Part 4 — Sharing & classroom (Settings › Classroom, Daybook Assistant)

| Where | Now | Proposed |
|---|---|---|
| Set Up Sharing result (`ClassroomSharingView.swift:283–289`, `Sharing/ClassroomShareAttach.swift:194, 197`) | "Classroom share created. 214 records added. 3 couldn't be added (CloudKit mirroring stopped this session (code 134406)); try again later." | "Classroom shared. 214 items added. 3 couldn't be added because iCloud stopped syncing. Quit and reopen the app, then try again." ("CloudKit's share export timed out" → "iCloud took too long to answer") |
| Share status (`ClassroomSharingView.swift:128`, `Dashboard/SettingsAttention.swift:61`) | "12 classroom records aren't in the classroom share" | "12 classroom items aren't shared with your assistant yet" |
| Remove Last Year (`ClassroomReleaseModel.swift:49, 123, 135, 148`; `ClassroomReleaseSheet.swift:51–133`; `Sharing/ClassroomShareRelease+Run.swift:54–62`) | "Couldn't read what the share holds: <raw>" / "Stopped after 3 of 9 groups." / "Stopped: Classroom share export failed: "…" (CKError 12)" / "A shared record had no iCloud record to check." / "The notebook's store isn't open." / "…another device may be running an older build" / "attendance record(s) left the share" | "Couldn't read the classroom share from iCloud. Check you're online and try again." / "Stopped partway (3 of 9 steps). Nothing is lost; run it again to finish." / specific cause under Details / "Something unexpected happened, so it stopped. Nothing is lost. Try again later." / "Your notebook isn't open right now. Reopen the app and try again." / "Make sure every device has the latest Cosmic Daybook, then try again." / "N children and M attendance marks are no longer shared." |
| Release/cleanup blockers (`ClassroomShareRelease+Live.swift:54–73`) | "iCloud sync is off." / "A restore is running." / "There's no classroom share." / "…(it may be hidden, opened for Claude)…" | "iCloud sync is off. Turn it on in Settings › Sync and backup first." / "A restore is running. Try again when it finishes." / "Your classroom isn't shared yet, so there's nothing to remove." / "Cosmic Daybook is also open in the background (Claude may have opened it). Quit that copy first." |
| Joining / setup (`Sharing/ClassroomSharingService.swift:210, 357`, `+Setup.swift:214, 216`; Assistant invitation page `AssistantIntroPages.swift:266`) | "Couldn't join the classroom: its storage isn't available on this device." / join toast with no next step / "Shared classroom storage isn't available on this device." | "Couldn't join the classroom on this device. Quit and reopen the app, then open the invitation again." / add "Ask the lead guide for a new invitation." / "Classroom sharing can't start on this device right now. Quit and reopen the app, then try again." |
| Assistant Classroom sheet (`Daybook Assistant/Sync/AssistantClassroomSheet.swift:88–99`) | "Classroom ID" + 8-character hex code | "Class code", under a Details disclosure (open question Q3) |
| Assistant front desk (`Daybook Assistant/FrontDesk/AssistantFrontDesk.swift:98`) | "Couldn't save that the email went. Try again." | "Couldn't record that the email was sent. Try again." |
| Assistant Siri (`Daybook Assistant/Siri/AssistantSiriHost.swift:8–10`) | raw "Failed to load persistent store: …" / "…Settings → Database → Reset Local Cache…" | "Daybook Assistant couldn't open your class. Open the app to fix it." |
| Arrival notification (`Daybook Assistant/Reminders/ArrivalReminder.swift:27`) | title "Arrival closes" | "Time to close arrival" |
| Early-pickup notification (`EarlyPickupReminder.swift:141`) | "{note}. Mark Left Early…" → ".." when the note ends in punctuation | strip trailing punctuation first |

## Part 5 — Siri & Shortcuts

| Where | Now | Proposed |
|---|---|---|
| Every attendance intent (`Siri/SiriAttendance.swift:32–113`, `Daybook Assistant/Siri/AssistantSiriCommands.swift:31–64`), Mark Lesson Presented (`Siri/MarkLessonPresentedIntent.swift:83`) | uncaught database errors reach Siri raw ("The operation couldn't be completed. (NSCocoaErrorDomain …)") | wrap as "Something went wrong saving attendance. Try again." / "I couldn't open your class right now. Open the app and try again." |
| Undo dialog (`Siri/AttendanceIntents.swift:154`, `SiriAttendance.swift:236, 301`) | "Undid Maya Stone present." / "Undid closing arrival." / "The marks from Maya present have changed since, so I left them." | "Done. Maya Stone isn't marked present anymore." / "Done. Arrival is open again." / "Maya's mark has changed since then, so I left it alone." |
| Late vs tardy (`AttendanceIntents.swift:52–88`, `AssistantAttendanceIntents.swift:15`) | "…is marked tardy." / "Already tardy" | "late" everywhere, matching the tiles (open question Q5) |

## Part 6 — Feature screens

### Students
| Where | Now | Proposed |
|---|---|---|
| Empty roster (`Students/Roster/StudentsViewComponents.swift:17`) | "Click the plus button to add your first student." | "Add your first student to get started." |
| Delete Student (`Students/Detail/StudentDetailView.swift:290`) | "…every other record of theirs are deleted too. Records shared with other children stay…" | "Their attendance, lessons, meetings, work and notes about only them are deleted too. Anything shared with other children stays for those children. This can't be undone." |
| Departure alert (`StudentDetailView+Departure.swift:55, 66`) | "…the work generated when they are given will name her." / "Her year plan still pencils in N lessons, which will go on falling behind pace…" (always "her") | "If you leave {first} on them, {first} will get follow-up work when they're given." / "{first}'s year plan still has N lessons planned. Removing marks them skipped instead of deleting them, so the plan is still there if {first} comes back." |
| Header caption (`StudentDetailComponents.swift:37`) | "Student record" | "Student profile" |
| Not-found windows (`StudentDetailWindowHost.swift:15`, `ScheduledMeetingSessionSheet.swift:29`, `PresentationDetailWindowHost.swift:13`) | "Student Not Found" (no explanation) | add "This student may have been deleted. You can close this window." |
| Insights (`Students/Insights/StudentInsightsView.swift:73, 88–93`, `+Sections.swift:21, 265`) | "Couldn't load development snapshots…" / a save failure shown as "The AI feature encountered a problem" / title "Error" / "AI-powered analysis of X's recent progress" | "Couldn't load {first}'s past insights. Close this screen and open it again." / "Couldn't save the new insights. Try again." / "Couldn't Make Insights" / "Patterns in {name}'s recent notes and work" |
| Parent summary (`Students/Detail/ParentSummarySheet.swift:32`) | "…generated using AI-powered analysis…" | "This summary was drafted automatically from your classroom observations. Read it over before you share it." |
| Writing-help sheet (`Students/Notes/AppleIntelligenceSheet.swift`, `+Generation.swift:45–55`) | raw error written **into the note text** as "[Error: Generation failed: …]"; labels "AI Assistant", "Context Generators", "Raw Data Context", "Processing Data…", "Select Template"; editor shows "[DATA EXPORT START] Scope: N CDNote(s)" | Errors in a banner (shared AI wording), text untouched; "Writing Help", "Start From", "Notes Only", "Gathering notes…", "Choose a Draft"; header "N notes, {dates}", labels "Date:/Student:/About:/Note:" |
| Spreadsheet import (`Students/Import/*`) | "Import Failed" + raw error / "Could not access security scoped resource." / "Unsupported text encoding; please use UTF-8." / "Column mapping required. Please map CSV headers to student fields." / raw Core Data on commit / "Row N: Missing first or last name; row skipped." / "Imported N new and updated M existing student(s)." / "Potential duplicates detected: N." / "CSV Import Complete" / "Map Columns", "Total Rows", "Will Insert/Update", "DOB:" | "Couldn't Import Students" / "Couldn't open that file. Choose it again and try once more." / "This file's text can't be read. In your spreadsheet app, save it as "CSV UTF-8" and try again." / "Choose which column has the students' names (First and Last Name, or Full Name), then try again." / "Couldn't add the students. Nothing was imported. Try again." / "Line N skipped: it's missing a first or last name." / "Added N new students and updated M." / "N might already be in your class:" / "Students Imported" / "Match Columns", "Lines in File", "Will Add or Update", "Born" |
| Meetings insights (`StudentMeetingsTab+InsightsSection.swift:202–228`) | "Unable to identify student." / "No meetings found in this timeframe." / "Unable to generate insights. Please try again." | "Couldn't find this student. Close their page and open it again." / "No meetings in the last {period}. Choose a longer time." / shared AI wording, fallback "Couldn't look over the meetings right now. Try again." |
| Reports (`Students/Reports/ReportGeneratorView.swift:308, 321`) | "No flagged notes found in the selected date range." / "Failed to generate PDF. Please try again." | "No notes in these dates are marked for reports. Pick other dates, or mark notes with Include in Report." / "Couldn't make the report. Try again." |
| Removed-item names (`DayDetailPopover.swift:47`, `RecallQueueViewModel.swift:106, 119`, Today meetings sections) | "Unknown" | "Lesson removed" / "Student removed" |

### Presentations, Work, Today
| Where | Now | Proposed |
|---|---|---|
| Presentation sheet alert (`Students/Presentations/PresentationDetailView.swift:150`, `+Recording.swift:175–328`) | title "Couldn't Save Presentation" for every case; messages carry raw Core Data text + "(While: …)" | "Presentation Not Recorded"; "Couldn't record the presentation. Nothing was changed. Try again." / "Couldn't undo the recording. Try again." / "Couldn't save your notes. They're still here, so try again." / "Couldn't save how the presentation went. Your notes are still here. Try again." |
| `ImmediatePresentationRecordingService.swift:21`, `PresentationSessionCommit.swift:47`, `PresentationOutcomePersistenceService.swift:17–19`, `PresentationRecorder.swift:64` | "The presentation could not be recorded: <raw>" / "This presentation does not have a saved identity yet…" / "The presentation could not be found. Nothing was saved so your observations are not attached to the wrong lesson." / "The children who weren't there could not be moved." | "Couldn't record the presentation. Nothing was changed. Try again." / "This presentation hasn't finished saving yet. Close it, open it again, and try once more." / "Couldn't find this presentation. It may have been deleted. Nothing was saved." / "Couldn't keep the absent children on the plan. Nothing was recorded. Try again." |
| Quick "Presented" + undo (`ReadyToPresentSection+QuickRecord.swift:42, 51`) | raw error | "Couldn't record the presentation. Nothing was changed. Try again." / "Couldn't undo. Try again." |
| Retraction prompt (`PresentationDetailView+WorkRetraction.swift:41`) | "This presentation already generated work for a child you are removing. Take her off that work too, so the two records agree?" | "This presentation already gave follow-up work to a child you're taking off. Take them off that work too?" |
| Schedule sheet (`SchedulePresentationSheet.swift:108`) | "The new record says which of the two it is, and a second pass flags their earlier record for re-teaching." | "A second pass marks the earlier lesson to teach again. A review just adds a review." |
| Week plan (`WeekPlanSection.swift:213`, `DayBalanceService.swift:162`, `WeekPlanSection+Data.swift:149, 154`) | "This will move every scheduled, ungiven presentation back to On Deck." / "Two halves can't separate this day." / raw work-check errors | "Every planned presentation not yet given goes back to the Inbox." / "Morning and afternoon aren't enough to give everyone one lesson at a time." / "Couldn't log that work check. Try again." / "Couldn't undo that. Try again." |
| Work toasts (`WorksAgendaView+Actions.swift:47, 51`, `WorkLogService.swift:120`, `+Undo.swift:88`, `WorkDeletionService.swift:115`) | raw error / "The work check could not be saved." / "The undo could not be saved." / "The change could not be saved." | "Couldn't log that work. Try again." / "Couldn't save that work check. Try again." / "Couldn't undo that. Try again." / "Couldn't save the change. Try again." |
| Assign work to a departed child (`Work/Support/WorkRepository.swift:23`) | "{name} is withdrawn and cannot be given work. Only enrolled students can be assigned work." | "{name} has left the class, so they can't get new work." |
| Work deletes (`WorkDetailView.swift:218`, `OpenWorkGrid+Deletion.swift:51`) | alert "Delete?" with no message / "…N completion records… will be removed from every child's record." | "Delete This Work?" + "Its check-ins, notes and history go with it. This can't be undone." / "…and N completed-work entries on it will be deleted for every child. This can't be undone." |
| Work log footer (`WorksLogView.swift:242`) | "Showing X of Y works" | "Showing X of Y work items" |
| Today (`TodayView+AbsentMove.swift:102, 111`, `TodayViewAgendaSection.swift:255`, `TodayDataFetcher.swift:42`, `TodayViewDeadlinesSection.swift:58`) | raw errors / "Couldn't load some of today's data" / "Open the Todos surface to review" | "Couldn't move the absent children. Nothing changed. Try again." / "Couldn't undo the move. Try again." / "Couldn't log that work. Try again." / "Couldn't load part of today. Tap Retry." / "Open Todos to review them" |
| Front-desk email from Today (`Today/Views/Attendance/AttendanceExpandedView.swift:241`) | "Failed to send: <raw> / Unknown error" | "The email didn't send. Check your connection and try again." |

### Lessons, Notes, Stories, Book Club, Parsha, Command Bar, Planning, Resources, Todos
| Where | Now | Proposed |
|---|---|---|
| Stories + Book Club PDF import (`Stories/StoriesRootView.swift:72`, `StoryImportService.swift:24, 70, 109`, `BookClub/BookClubImportService.swift:22, 64, 87`, `BookClubPacketsListView.swift:83`, `Components/PDFLibraryListView.swift:164`) | "Couldn't copy the PDF: <raw>" (also shown when the *save* failed) | "There isn't enough space to add this PDF. Free up some space and try again." / "Cosmic Daybook can't open that file. Choose it again." / "Couldn't add this PDF. Try again." / save: "Couldn't save the new story. Try again." |
| Story analysis banner (`StoryImportService.swift:146–263`, `StoryAnalyzer.swift:32, 177–340`) — **stored in the notebook and synced** | raw error / "The story is too long for the on-device model." / "Apple Intelligence encountered an unexpected error." / "PDF file is missing." / "Analysis timed out." | shared AI wording; "Couldn't read this story. Try again, or add the details yourself." / "Couldn't find this story's PDF. Delete the story and add the PDF again." / "Couldn't open this PDF. Add the details yourself." / "This took too long. Try again." |
| Story cover + connections (`StoryDetailView.swift:513, 550`, `StoryCoverGenerator.swift:23–177`, `StoryLessonMatcher.swift:47`) | raw error / "Image Playground interpreted these themes as implying people…" / "The image provider didn't return an image." / "…too little metadata yet…" | "Couldn't make a cover. Try again." / "Image Playground can't draw people. Remove themes like "family" or "hero," then try again." / "Image Playground didn't make a picture. Try again." / "Add a few themes or a summary first, then try again." / "Couldn't look for connected lessons. Try again." |
| Book Club delete packet (`BookClubPacketDetailView.swift:54`) | "Sessions referencing this packet will remain but lose their link." | "Book clubs that use this packet will stay, but won't show the packet anymore." |
| Parsha AI (`Parsha/ThisWeeksParshaView.swift:362`, `ParshaSuggestionsDetailView.swift:46, 113`, `ParshaSuggestionService.swift:179`) | raw error / "Could not parse AI response: <JSON error>" / "AI did not find any strong album-lesson matches…" | shared AI wording, fallback "Couldn't find matching lessons. Try again." / "No album lessons stood out for this parsha." |
| Command bar (`CommandBar/Views/CommandBarSheet.swift:326, 355, 359`, `CommandBarViewModel+CapturePersistence.swift:15–129`) | raw error / "The presentation does not have a saved identity…" / "…Review the capture and try again." / "The classroom capture could not be saved." / "Classroom record saved" / "Save Records" | "Couldn't save what you wrote. Nothing was changed. Try again." / "One of these children is no longer in your class. Check the names and try again." / "Saved" / "Saved N entries" / "Save" |
| Dictation (`CommandBar/Services/SpeechRecognitionService.swift:36–120`) | raw Speech error / "Speech recognition permission denied." / "Microphone permission denied." / "Failed to start recording." | "Dictation stopped. Try again, or type instead." / "Cosmic Daybook isn't allowed to use dictation. Turn on Speech Recognition for it in {Settings} › Privacy & Security." / "…can't use the microphone. Turn it on in {Settings} › Privacy & Security › Microphone." / "Couldn't start dictation. Try again, or type instead." |
| AI lesson planning (`Planning/AIPlanning/LessonPlanning/LessonPlanningViewModel.swift:65–230`, `LessonPlanningTypes.swift:35–72`) | "Service not configured" / "Error: …" bubbles / save failure as an AI error / "Created N lesson assignment(s)." / "Gathering curriculum and guide records…" / "Gathering evidence…", "Awaiting input", "Creating assignments…" | "Lesson planning isn't ready yet. Close this and try again." / no "Error:" prefix, shown once / "Couldn't add these lessons to your plan. Try again." / "Added N lessons to the plan." / "Looking over {first}'s lessons and notes…" / "Looking at {first}'s work…", "Your turn", "Adding lessons to the plan…" |
| Notes AI alerts (`Notes/QuickCapture/QuickNoteSheet.swift:283, 413`, `QuickNoteViewModel.swift:355–366`, `Notes/Editor/UnifiedNoteEditor.swift:141`, `NoteEditorAISuggestion.swift:118–174`) | titles "AI Error" / "AI Suggestion Error"; "Too many requests…", "…too long for on-device processing…", "…content restrictions.", "Photo description needs a model with image understanding." | "Apple Intelligence Couldn't Help" / "Couldn't Suggest Tags"; shared AI wording; "Describing photos isn't available on this device." |
| Observation reflection (`Notes/Observations/ObservationsView+AI.swift:105–183`, `+AISummarySheet.swift:78–134`) | "These records do not fit in an on-device reflection…" / "…not sent to a cloud model." / "Reviewing records…" / "This is a record check, not an AI conclusion." / "Records Reviewed" | "That's too many notes for Apple Intelligence at once. Choose fewer observations and try again." / "Couldn't write the reflection. Try again. Your notes stayed on this device." / "Reading your notes…" / "These come straight from your notebook, not from Apple Intelligence." / "Notes Used" |
| Lessons (`Lessons/Detail/LessonDetailView.swift:245`, `LessonRelationshipsSection.swift:38`, `AddLessonView.swift:141, 223`, `Repositories/LessonRepository.swift:64`) | "Import Failed" / "Lessons not found" / "None (Root Story)" / any non-duplicate error shown raw under "Already in the Curriculum" / duplicate name with no next step | "Couldn't Add the Pages File" / "These lessons are no longer in your curriculum." / "None (this is a main story)" / "Couldn't add this lesson. Try again." / add "Choose a different name." |
| Resources drag-and-drop (`Resources/ResourceLibraryView+Actions.swift:88–130`) | new resource titled with a UUID ("3F2A…") | keep the dropped file's name (fallback "Untitled Resource") |
| Todo export (`Todos/Views/TodoExportView.swift:125, 147, 157`) | "Error generating JSON" / "Structured data format for developers" / file name "todos_export_1759512345.123" | "Couldn't prepare this export. Try another format." / "For moving todos into another app" / "Todos – Oct 3, 2026" |
| Small wording | "No slots configured" (`Schedules/SchedulesView.swift:183`) / "No start date on file — years counted from her first record" (`CurriculumMap/StudentCurriculumMapView.swift:137`) / "Switch the year lens to All Years" (`Projects/ProjectsRootView.swift:206`) / "…re-buckets which year past activity falls into…" (`SchoolYear/SchoolYearPicker.swift:137`) / "Couldn't Open Sample Class" + raw error (`AppCore/ClassroomWorkspaceStore.swift:105`) | "No days or times set yet" / "No start date yet, so years count from {first}'s first lesson" / "Choose All Years to see them" / "Changing the start changes which year past activity counts toward. Nothing is moved or deleted." / "The sample class couldn't be set up. Try again, or restart the app." |

### Albums, Chat, Settings copy, Parent reports, Attendance settings
| Where | Now | Proposed |
|---|---|---|
| Albums AI (`Albums/Detail/AlbumDetailView.swift:662`, `Albums/Search/AlbumsAskView.swift:160`, `AlbumIntelligence.swift:21, 69, 75`) | "Couldn't summarize: <raw>" / raw error / "…isn't available in this build." / "The on-device model is still getting ready…" / "…need an Apple Intelligence build of the app." | shared AI wording, fallbacks "Couldn't summarize this lesson. Try again." / "Couldn't answer that. Try asking another way." / "…isn't available in this version of the app." / "Ask and Summarize aren't in this version of the app. Search, bookmarks and notes still work." |
| Albums iCloud (`AlbumLibrary+ICloudShelf.swift:78`, `AlbumsLibraryView.swift:36, 93`) | "Couldn't remove X from iCloud: <raw>" / title "iCloud" / "Downloading N album(s)…" | "Couldn't remove {album} from iCloud. Check that iCloud Drive is on and try again." / "Couldn't Update iCloud Albums" / real plurals |
| Albums "index" wording (`AlbumsSidebar.swift:81`, `AlbumsLibraryView.swift:72`, `AlbumsAskView.swift:83`, `AlbumsSearchView.swift:75, 91`, `RelatedLessonsPanel.swift:57`, `AlbumsDataImporter.swift:80`; `Components/Shared/AppSearchView.swift:23`) | "Indexing for search…", "Rebuild Search Index", "…still indexing…", "…is indexed.", "Semantic lesson matching isn't available…", "Expected a JSON file…", "Building search index…" | "Getting search ready…", "Refresh Album Search", "…still reading the albums…", "…is ready to search.", "Related lessons aren't available on this device.", "That doesn't look like an Albums export. Choose the file you exported from the Albums app." |
| Chat (`Chat/ChatViewModel.swift:163`) | via `aiMessage` (S3) | shared AI wording, fallback "Couldn't get an answer right now. Try again in a moment." |
| Claude Desktop status (`Settings/Intelligence/ClaudeDesktopSettingsView.swift:36, 61`, `Services/MCPServer/MCPServerService.swift:126–160`) | "Not running: <raw "Address already in use" / Keychain OSStatus>" | "Another copy of Cosmic Daybook is already connected to Claude. Quit it, then turn this off and on." / "Couldn't set up the secure connection. Turn this off and on again." / "Claude Desktop can't connect right now. Turn this off and on again." |
| Private Cloud footer (`PrivateCloudSettingsView.swift:14`) | "…a request the on-device model can't finish stops." | "…anything Apple Intelligence on this device can't finish just stops." |
| Attendance email settings (`Attendance/Email/AttendanceEmail.swift:151–176`) | "Show 'Send Attendance Email' Button" / "Preferred 'From' Address (iOS)" / "Note: iOS uses the preferred address when possible. macOS uses your default Mail account." | "Show the attendance email button" / "Send from" / "Mail sends from this address when it can. On a Mac it uses your usual Mail account." |
| Parent report (`ParentReports/Views/ParentReportDraftEditorView.swift:130, 327`) | "No mail account is configured on this device." / "Adolescents may speak for themselves: weaves their own meeting reflection into the note. Regenerate the draft to apply." | "No email account is set up on this device. Add one in Mail, or copy the report and send it another way." / "Adds the student's own words from their meeting. Draft the note again to include them." |

## Part 7 — Silent failures (optional; open question Q4)

These catch an error, log it and show nothing, so the screen looks as if it worked. Each would get a toast
or alert with a plain message:

- Notebook attendance grid: Close Arrival, Mark Rest Absent, Reset Day, marking (`Attendance/AttendanceViewModel.swift:85–300`, `+Undo.swift:31`) — reuse the Assistant's lines ("Couldn't mark the rest absent. Try again.").
- Student attendance history load (`AttendanceStudentHistorySheet.swift:257`).
- Delete student (`StudentDetailView.swift:282`) — sheet closes as if it worked.
- Delete lesson (`LessonDetailView.swift:172`), lesson attachments import/delete/rename/drop/open/share (`LessonAttachmentsSection.swift`, `AttachmentRow.swift`).
- Student files add/delete (`DocumentImportSheet.swift:87`, `StudentFilesTab+FileOperations.swift:47`).
- Work delete (`WorkDetailViewModel.swift:340`), Children Working PDF on Mac (only beeps), Mark Presented on Today (`TodayViewAgendaSection.swift:189`), meeting decision cards (`MeetingDraftModel.swift:141`).
- Resource drop (`ResourceLibraryView+Actions.swift:130`), todo export save (`TodoExportView.swift:172`).
- Writing-help sheet's `generationError` is set but never shown (`AppleIntelligenceSheet.swift:38`).
- Assistant "Try a Sample Class" (`AssistantBootstrapper.swift:370`).
- Monthly parent-report reminder toggle stays on when notifications are denied (`ParentReportNotificationService.swift:27–83`): footer "Notifications are off for Cosmic Daybook, so this reminder can't show. Turn them on in Settings."

## Left alone on purpose

- Logs, `os_log`, assertions, and the MCP tool results Claude reads (they go to Claude, not Danny). Rewording
  `WorkRepository`, `WorkLogService`, `WorkDeletionService` and `RolloverService` errors **does** change what
  MCP tools return; that's fine, and no MCP test pins the text.
- DEBUG-only developer screens (AI connection test, lesson-planning prompt settings, "Use in-memory store").
- Backup progress text ("Encoding…", "Deduplicating records…"): not shown today (the bar shows a percentage),
  and pinned by the backup tests and the frozen legacy-restore copy.
- `Daybook Assistant/AssistantStartupProblem.swift` ("…from TestFlight…"): fine while the Assistant is a
  TestFlight app; a test pins it.
- Orders, front-desk notifications and most of the Assistant are already plain.

## How it will be built

Worktree branch off main; phases in this order, one commit each, so each can be reviewed alone:

1. **Shared translator** (Part 1): `AppErrorMessages` changes + the one Apple Intelligence translator;
   update `AppErrorMessagesTests`; add tests for the new AI mapping, the Cocoa split, the sharing fallback
   and "no (While:)".
2. **Sync, database, startup** (Part 2 + the sample-class alert) — **done 2026-10-03**, not yet seen on a
   device or the Mac UI; the Assistant's Siri now gets its own sentence from `CoreDataStackError`, and the
   stopped banner keeps its "don't re-download" warning. Safe-mode flag first; raw text kept separately for Details;
   update `SyncStoppedAdviceTests`, `CloudKitStoreHealthTests`, `ClassroomShareReleaseTests`.
3. **Backup & restore** (Part 3): error enums reworded; warnings translated at display (the frozen
   `BackupService+LegacyRestore.swift` stays as it is); plain-noun map with a test that every backed-up
   entity has a plain name; update `BackupPreviewDigestTests`, `BackupRestoreTransactionTests` if needed.
   **[x] Built 2026-10-03** (`BackupPlainNames`, `BackupWarningText`; tests `BackupPlainNamesTests`,
   `BackupErrorTextTests`, `NotebookJunkCleanupLinesTests`). `BackupRecordCheck` keeps its raw reasons for
   the log and Details; Clean Up maps them. Left for the merge: three more "Restoring data…" strings outside
   this phase (`AttendanceMacView`, `CosmicDaybookApp+MainWindow`, `DetailWindowScene`). Not seen on screen.
4. **Sharing, Assistant, Siri** (Parts 4–5): update `SettingsAttentionTests`, `SiriAttendanceTests`,
   `AssistantSiriTests`.
5. **Feature screens** (Part 6): update `AppleIntelligenceRoutingTests` (CaptureSaveError text),
   `ManagedPDFFileStorageTests`, `AlbumsDataImporterTests`.
6. **Silent failures** (Part 7), if approved.

Builds through `Scripts/locked_xcodebuild.sh` (iOS sim for the notebook, the Assistant scheme for its files,
plus a macOS build since several strings are Mac-only); tests with `-only-testing:` on the leased simulator
per phase, the full suite once at the end. A guard test scans the shipped sources for `localizedDescription`
reaching `Text`/alert/toast calls would be brittle, so instead a short checklist goes into CLAUDE.md under
Code Conventions: "user-facing errors go through `AppErrorMessages`; never interpolate `localizedDescription`."

## Decisions (all approved 2026-10-03 as recommended)

- **Q1** "(While: …)" on the Couldn't Save alert: drop it entirely (recommended), or keep it as a plain phrase?
- **Q2** Raw technical detail (sync errors, database error screen, sync-stopped banner): behind a "Details"
  disclosure (recommended), or log only?
- **Q3** The Assistant's 8-character Classroom ID: keep as "Class code" under Details (recommended), or remove?
- **Q4** Silent failures (Part 7): include in this pass (recommended), or a later session?
- **Q5** Siri says "tardy", the tiles say "late": switch Siri to "late"?
