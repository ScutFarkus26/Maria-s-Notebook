# Cut unused features and close the lesson loop

> **Done 2026-11-22** (02e1eea2d). Written 2026-11-21 from a usage analysis of the live notebook (Aug 25 – Nov 21) and a talk-through with Danny (session "Maria's Notebook feature analysis", branch `claude/marias-notebook-analysis-106de8`).
> In short: take out fourteen features Danny doesn't use (keeping all their data), and make the lesson loop close itself: a quick note at the lesson, a 3:45 chat that asks what happened to the day's lessons, and practice that comes back before the next lesson.

## Goal

When this is done the app has fewer screens and fewer Claude tools, and nothing Danny ever wrote is lost: every removed feature's records stay in the notebook and in backups, and each has a Tide note saying how to bring it back. Lessons stop going unrecorded. On the MacBook in the classroom, Danny can mark a lesson given and type a quick note in one step. Every school day at 3:45 pm a Claude chat lists what's still open (planned lessons not recorded, quick notes waiting for detail) and records his answers. Practice set after a lesson, including practice recorded through chat, comes back on Today the school day before the next lesson in that sequence. He is warned wherever he schedules or gives that next lesson while a child still has practice open. Groups is easier to reach.

What the analysis found (live notebook, read 2026-11-21):

| Feature | Use since Aug 25 |
|---|---|
| Attendance | every day, all 24 children; Nicole sends ParentLocker by about 8:20 |
| Lessons recorded | heavy (one child: 25), mostly batch-recorded later through chat |
| Lesson catalog | 99 lessons created, 103 edited, 140 album files attached since Nov 4 |
| Lessons with a child who has no note | about 40 |
| Planned lessons left behind | Nov 12–20 plans still "planned"; nothing flags a past day's plan |
| Practice recorded through chat | gets no check-in, so it never comes back (only "Gone quiet" later) |
| Meetings | a handful in Aug–Sep; three Nov 2 bookings never held |
| Parent Reports (monthly letters) | 0 ever |
| Spaced recall checks | 0 in 120 days |
| Projects | 4, all dormant, 0–2 sessions each |
| Community topics / Issues | 4 topics (1 discussed, Aug 27) / 2 issues |
| Resources / Stories | 2 files (one titled with an id) / 1 story |
| Restock | 1 staple (Nicole) — **kept** |
| Going Out, Book Club, Procedures | 0 records on 2026-11-03 |
| Day pad, custom meeting templates | empty; built-in templates only |
| In-app to-dos | moved to Tide Oct 2; 15 open, all from Sep–Oct |

## Progress

Marks: `plan/cuts-loop` (each phase tags the primary checkout `plan/cuts-loop/phase-<N>` when it merges; see `~/.claude/bin/plan-wait`)
The last version with every feature in it is the tag `retired/2026-11-cuts`: at the go-ahead the conductor fast-forwards main to this plan's commit and tags it there, before Phase 1 starts.

- [x] Phase 1: Cut Parent Reports, recall checks, Projects and Book Club, Community topics, Issues · done 2026-11-22 (30bf2e6f6) · session 4dd54666-95a3-4afb-bf9e-24b4020d48ea · actual $21.29 (~1%)
- [x] Phase 2: Cut Resources, Stories, Procedures, Going Out, Today's pad card, custom templates, the To-dos screen · done 2026-11-22 (87658f085) · session eb7e5815-b7fa-4eef-8167-2585f7885f15 · actual $15.71 (~1%)
- [x] Phase 3: The lesson loop in chat (services and Claude tools) · done 2026-11-22 (f8f1a077d) · session b0e4a456-8c53-4913-b354-3f77a11cf1e3 · actual $14.76 (~1%)
- [x] Phase 4: The lesson loop on the Mac (screens) and ways into Groups · done 2026-11-22 (af83dfbf1) · session 992fe2ba-7c37-428f-bd7e-75ca67ab7a47 · actual $13.27 (~1%)
- [x] Phase 5: A Tide note for each cut feature, and four Tide rows · done 2026-11-22 (no commit; Tide only) · session 857e43e6-d745-4fcc-ad9e-a7deffb43cca · actual $4.34 (<1%)
- [x] Phase 6: Final check · done 2026-11-22 (02e1eea2d) · session 2cb0b7fc-7df5-4ddb-9422-38c8d52d7106 · actual $19.09 (~1%)
- [x] Conductor: the 3:45 pm scheduled chat · made 2026-11-22 (task `daybook-end-of-day`, weekdays 3:45) · whole run, conductor included: $113.90 (~5%), against $150–265

## Cost

About $150–265 in all: the phases $120–220, the conductor $30–45 (this planning so far about $20 with the reviews, and about six wakes on a large context). At this week's rate (1% ≈ $22, calibrated 2026-11-21) that is **7–12% of the weekly limit**. You have 56% left until Fri Nov 27, 12 pm. **Fits.** The run brakes itself if a phase costs more than twice the top of its estimate, or the week passes 90%.

## Before you go

- **Keep the Mac plugged in and awake; leave Tide open** (Phase 5 writes Tide notes, and every phase may add Tide rows). Nothing in this run drives the screen, so a locked screen is fine.
- **The primary checkout has an uncommitted change to `Cosmic Daybook.xcodeproj/project.pbxproj`** (149 lines moved, nothing added or lost, likely Xcode reordering the Assistant's file list). A phase that touches the project file would stop at merge. Keep it, discard it, or commit it — your call before the run starts.
- **The build queue is busy** with another session's build; the run's builds wait their turn.
- **Nothing needs your sign-in, CloudKit or a deploy:** no data model change, no backup format change.
- **Permission mode** is already Bypass for this session, and the phase sessions inherit it.
- **After the run (a Tide row):** the new Claude tools only work once the Mac runs the new build (`Scripts/install_release.sh`, your step). Until then the 3:45 chat falls back to today's plan alone.
- **Tide notes wait for you.** The fourteen notes Phase 5 writes land in Tide's To Confirm until you check them.
- **Not verified ahead of time:** that the scheduled-task and Tide tools run without a prompt in Bypass mode. If one asks, that step waits for you in the morning; nothing else stops.
- **The 3:45 chat is a scheduled task in the Claude app.** It runs while the app is open; if the app is closed at 3:45 it runs when the app next opens. Your go-ahead covers making it.

## Decisions

**How a feature is cut** (Phases 1 and 2):
- **Data stays, whole.** Every entity class, its model entry and its backup row stay. Only screens, view models, services used by nothing else, Claude tools, Today sections, Settings rows and notifications go. So there is no schema change, no backup format bump, and the backup golden and sparse reference must pass **unchanged** — that is the proof nothing was dropped. Ruled out: the round-two "retired entities" pattern (`CoreDataStack.retiredEntities`), because it stops backing those rows up and a Replace restore would drop notes' links to project sessions and issues.
- **Navigation:** never delete a `NavigationItem` case (raw values are saved). A cut row becomes an alias that lands on a staying screen, and every existing one-hop alias (`.stories`, `.procedures`, `.bookClub`, `.lessonRecall`) is re-aimed so none points at a removed row.
- **Claude tools:** each removed tool gets a plain retired sentence in `MCPRetiredTools` ("Taken out of the app on 2026-11-2x; its records are kept."), and the existing retired sentences that point at a removed tool or say a feature "stays in the app" are reworded.
- **One commit per feature**, titled `Cut: <feature>`, so any one can be reverted on its own.
- **Code that protects kept data stays:** launch repairs, dedup merges, `StudentDeletion`'s cleanup of kept entities, note link fields.
- **Entity files inside a removed folder move, they don't go:** to `Models/` (or `Students/Guardians/` for guardians), with `git mv`. This covers `ParentReports/` (`GuardianEntity`, `ParentCommunicationEntity`, `CommunicationType`; `GuardianEditSheet` too, since the child's Overview edits guardians), `Projects/`, `BookClub/`, `Topics/Models/`, `GoingOut/`, `Procedures/`, `Resources/` and Stories.
- **Preference keys stay**, with their lines on the backed-up preferences list (`recallSpacedIntervalDays`, `parentReportsReminderEnabled`, `todayDayPadExpanded`, `todoTagOrder`, `todoHideCompleted`), so a settings backup and its tests don't change. Only the code that read them goes.
- **Build after each `Cut:` commit** (iOS build for testing at least), so each one can be reverted alone and still build.
- Restock stays (Danny: keep for now). Guardians stay (the child's Overview shows them; attendance groups siblings by guardian email).
- Recall: the recording screens and queue go; the reads stay, so old checks still show in rings and the curriculum map and still count in readiness and mastery evidence. No new checks can be made, and there were none in 120 days, so readiness doesn't change in practice.
- Removing the To-dos screen keeps the to-do records, Tide sharing, Today's to-do section, meetings' "For Me to Do", `NewTodoForm` and `EditTodoForm`. `EditTodoForm` gains Delete (with a confirmation), since the screen was the only place to delete one. Someday to-dos and ones tied to work don't go to Tide; they stay visible on their work rows or are reachable through chat (`list_todos`). That is a Review choices row, not a change to Tide sharing.
- The day note stays in the Calendar (it is the same `CDDayPad` record); only Today's pad card, its button and its menu item go.
- Custom meeting templates: the Settings › Templates pane goes; the built-in templates and their seeder stay. Meetings read "the active built-in, else the first built-in". No custom templates exist today.

**The lesson loop:**
- The end-of-day check runs **in chat** (Danny's choice), at **3:45 pm on school days**, as a Claude scheduled task, not as an app notification.
- A quick note is an ordinary note linked to the presentation and its children, carrying the tag **`to fill in`**. No new field, so no schema change. `CDNote.needsFollowUp` was ruled out (it already means the follow-up inbox). Replacing the note's words through `update_observation` drops the tag.
- **Practice comes back before the next lesson** (Danny's choice): its check-in is the school day before the next lesson planned for that child in the same sequence, never earlier than tomorrow; with nothing planned, 3 school days after the lesson. When a later lesson is planned or moved, earlier open practice check-ins for that child in that sequence move to the school day before it. A new check-in is never earlier than the next school day after the lesson; a moved one is never earlier than today. Check-ins already done are left alone. This lives in the shared planning path, so the app and chat both get it.
- `WorkToShowFirst` today needs a strictly lower `orderInSequence`, so sequences left at 0 never warn. When orders tie, it falls back to the lessons' order in their sub-area.
- A planned lesson recorded with a slightly different group currently leaves the plan behind. `record_presentation` gains `planned_presentation_id`: the record takes that plan over, adds any extra children, and children on the plan who weren't there stay planned on it (the existing split).
- A day with an all-day calendar event whose title contains "No School", which the school calendar still counts as in session, is pointed out in the end-of-day list with the `set_school_days` call to fix it. The app's school-day rule is not changed to read calendar events.
- "Untitled work": creators that pass no title now pass "Practice: <lesson>" or "Follow up: <lesson>", and Claude's reads print the lesson name when a title is empty.

**Ruled out or later:**
- One note covering several lessons (the Oct 13 note saved five times) needs a note to link to several presentations, which is a schema change. Not now: a Review choices row.
- The meetings screen: Danny will look at what makes write-ups hard at his next meetings (a Tide row). Nothing changes in this plan.
- This Week's Parsha stays; revisit it at the next feature review (a Tide row).
- Class Grid cells get no practice mark in this plan (the Brewing mark already covers the gated sequences).
- A system-wide hotkey for quick notes: Apple offers none for SwiftUI (see Apple guidance), and a menu bar item wasn't asked for.

**Decided in Phase 1** (the first four have Tide Review choices rows):
- The old monthly parent-report reminder is cleared at every launch, not once.
- The school-year rollover still lists who is leaving, without the report button or the flagged-notes count.
- An old Lesson Recall link opens the Class Grid on its usual view; the legacy "Projects" planning mode opens Lessons & Work.
- Claude's `families` tool shows guardians when no view is given.
- Kept in `Models/`, now unused: the project year-overlap rule, the matching Book Club rule, and the `LibraryFileStorage.packets` folder name (the storage tests check it). Only the packet import went.
- The Claude tool count's test range moved from 58–64 to 50–58 (56 now). The Progress tab's empty state reads "No open reports or lessons in progress." The removed project-work service's tests went with it.
- Two whole-suite failures left by cut 1 were fixed in 87cc322e9; reverting cut 1 alone means reverting that commit too.
- Phase 1 saw a build report success when it had failed, so a test run used an old build. The script itself passes on xcodebuild's own exit code; piping its output (`| tail`, `| tee`) without `pipefail` hides it. Later phases check the log's `** BUILD SUCCEEDED **` / `** TEST SUCCEEDED **` line, not only the exit code.

**Decided in Phase 2** (each has a Tide Review choices row):
- A window last left on Settings › Templates opens on School Year.
- Meetings use only the built-in prompts; a hand-made template stays in the notebook but isn't shown.
- The rule that hides an empty sidebar row stays, though no row uses it now. `TodoScheduling` stays, unused. `TodoWhenPopover` stays: the to-do forms use its schedule picker.
- The to-do editor gained Delete To-do (the only way to delete one now).
- Removed as unused: the lesson link picker and `LessonFilesSectionTests`, the status pill's compact size, and the test files `SmallerFeaturesFix1010J1Tests` and `TemplateFix1017St`.
- ⌘7 → Groups went into the To-dos commit. The Mac wasn't rebuilt at Phase 2's tip (Phase 6's full builds cover it).

**Decided in Phase 3** (Tide Review choices rows): open practice check-ins only move earlier, never later, when a later lesson is planned (hooked into five planning paths in the app and three Claude tools; moves to a later day left out on purpose). Ties in a sequence go to the lesson earlier in its sub-area. New untitled work is named "Practice: <lesson>" / "Follow up: <lesson>" everywhere, not only in chat. `planned_presentation_id` refuses a plan already recorded.

**Decided in Phase 4** (Tide Review choices rows): a child held at "check first" stays in the picker's Ready group, unticked, with the reason. Given — Quick Note shows on the Next card; other rows have it in their menu. ⌃⌘J is Mac-only; on the iPad the note opens from Today. The Lessons & Work Groups link shows on Presentations › Upcoming. No picture of the quick note itself (the headless renderer draws text boxes blank).

**Decided in Phase 5:** the three shared commits (Parent Reports + per-child report, Projects + Book Club, Resources + Stories + Procedures) are reverted together; each Tide note says so.

**Decided in Phase 6** (from the Fable review; Tide rows): only the earliest open check-in moves, and only if none already falls by the day before the lesson; a due-date check never moves. Practice set today isn't pulled back; on a weekend "today" is the next school day. Editing a plan's notes or only its time moves nothing. Deleting a child keeps an issue left with nobody on it (deleting it would cascade to its notes). Left as Build & fix rows: planning paths that don't move practice yet (merging presentations, moving a child into a planned group, Parsha scheduling), five smaller lesson-loop gaps, tidying leftovers.

## Apple guidance

Checked 2026-11-21 against Xcode 27.2 (27B52), iOS and macOS 27.2 SDKs. The app targets iOS 27.0 and macOS 27.0 (the Assistant iOS 18.0). Xcode 27.3 beta 2 changes nothing here.

- **Quick note window (macOS), Phase 4:** use a plain `Window("Quick Note", id:)` scene, opened with `openWindow(id:)`, with `.windowResizability(.contentSize)`, `.defaultSize`, `.windowLevel(.floating)` and `.defaultFocus` on its text field (all macOS 13–15). Avoid `UtilityWindow`: it hides when the app is inactive, and Apple doesn't say a text field gets focus on open. Avoid a panel (HIG Panels: no typing controls in panels) and a sheet (modal on macOS). `defaultFocus` is evaluated "when the window first appears"; re-opening an open window isn't documented, so test it. Sources: [UtilityWindow](https://developer.apple.com/documentation/swiftui/utilitywindow), [defaultFocus](https://developer.apple.com/documentation/swiftui/view/defaultfocus(_:_:priority:)) (2026-10-08); [HIG Panels](https://developer.apple.com/design/human-interface-guidelines/panels), [HIG Windows](https://developer.apple.com/design/human-interface-guidelines/windows) (Aug 2026).
- **Keyboard shortcut, Phase 4:** SwiftUI shortcuts work only while the app is active; there is no system-wide hotkey API. HIG Keyboards: custom shortcuts only for frequent commands, modifier order ⌃⌥⇧⌘, never repurpose a standard one. `AppCommands.swift` already uses ⌘N, ⇧⌘N, ⌥⌘N, ⌃⌘N, ⌃⌘P, ⌃⌘R, ⌃⌘T, ⌃⌘K and ⌘F, so pick a free combination. macOS 27 hides menu icons by default; use `labelStyle(.titleAndIcon)` if an icon matters.
- **Practice warning in pickers, Phase 4:** `.badge(Text(…))` on `List` rows (iOS 15 / macOS 12 in the SDK) is Apple's way to show short supplementary status. Whether a menu-style `Picker` row shows a badge isn't documented, so test macOS and iPad, and prefer text over an icon in menus.
- **iPad:** `Window` scenes are macOS-only; the iPad uses a sheet for the quick note.
- Not used: notifications (the end-of-day check is a chat).

## Phase 1: Cut Parent Reports, recall checks, Projects and Book Club, Community topics, Issues
- Who: phase session (Opus 5.5, high). Many files and some care around kept data.
- Needs: —
- Steps (one `Cut:` commit each, following "How a feature is cut"):
  1. **Parent Reports and the per-child report.**
     - Remove `ParentReports/` (after moving its entity files and `GuardianEditSheet` out, per Decisions), `Students/Reports/ReportGeneratorView.swift` and `ReportGeneratorService`, and their entry points in `StudentNotesTab` and `SchoolYearRolloverView` (drop the rollover's flagged-notes count line if nothing else uses `ReportNotes.flagged`).
     - Remove `Today/Views/Sections/TodayViewParentReportsSection.swift` and `TodaySection.parentReports`, plus its places in `TodaySectionVisibility.swift` and `TodayViewSectionOrder.swift`.
     - Remove `SettingsCopy.parentReports` and `ParentReportsSettingsView` (in `ParentReportNotificationService.swift`), `AIPrompts.monthlyParentReport*` and `AppErrorMessages`' parent-report section. The `parentReportsReminderEnabled` key and its backup line stay.
     - Remove the monthly notification's scheduling in `AppBootstrapper.swift:241`. Add a one-time removal of the pending `parentReports.monthly` request at launch.
     - Remove Claude's `draft_parent_report` (keep `create_backup` in `+AppServices.swift`), `record_parent_communication` and the `families` view `communications`. Keep the `guardians` view and `update_guardian`.
     - Keep `GuardianPeople` (launch fill and restore aftercare), moved out of `ParentReports/` to `Students/Guardians/`. Keep `GuardianListSection`.
     - `.parentReports` becomes an alias to Students.
     - `MonthlyReportContextBuilder` goes. If `LevelHistoryTests` or `StudentInClassTests` test pieces staying code uses, move those pieces; otherwise delete those test lines.
  2. **Recall checks.** Remove `Students/Recall/`, `ClassGrid/Recall/`, `RecallQueueView`, `ClassGridViewKind.recall`, `MCPNotebookTools+RecallChecks.swift`, `class_progress`'s `recall` view, and `RecallService`'s practice creation. The `recallSpacedIntervalDays` key and its backup line stay. `.lessonRecall` lands on the Class Grid's default view. Keep every read: `ReadyForNextEngine+PreviousLesson`, Class Grid rings and legend, the curriculum map's recall section, `mastery_candidates` evidence, `student_record`/`class_curriculum_map` output, and the lesson-merge id rewrite.
  3. **Projects and Book Club.**
     - Remove the `Projects/` screens (`ProjectsRootView`, `ClubsAndProjects*`, project and session detail), the `BookClub/` screens, `Resources/Library/PacketsLibrary.swift` and `LibraryKind.packets`, the packet import in `LibraryImportService`, `MCPNotebookTools+Projects.swift` (`list_projects`), and the project sections on the child's History and Progress tabs.
     - `.planningProjects` and `.bookClub` become aliases to Today. Drop the legacy "Projects" planning mode in `NavigationSelectionRestorer`.
     - Keep the six project entity classes and three Book Club entity classes (move any that live in a removed folder to `Models/`), and `CDProject.overlaps` used by `SchoolYearScoping`.
     - Keep `WorkSourceContextType.projectSession` and the work code reading it, `WorkTypes` `.bookClubSession`, the note links, the launch repairs and dedups, and `Logger.bookClub` if still referenced.
     - Leave `Documents/Book Club Files/` on disk untouched.
  4. **Community topics.** Remove the `Topics/` screens, the `CommunityTopicWindow` scene (`CosmicDaybookApp.swift:196`), legacy `Tab.community`, `community_topics` and `update_community_topic` (`MCPNotebookTools+CommunityTopics.swift`). Keep the three entity classes (moved to `Models/` if needed), `Note.communityTopicID`, the context-note rule in `Models/NoteAboutStudent.swift`, the note editor's topic context, and the dedup. `.community` becomes an alias to Today.
  5. **Issues.** Remove `list_issues` and `update_issue` (`MCPNotebookTools+Issues.swift`). Keep the entities, `IssueModels`, note links and `StudentDeletion`'s cleanup.
  - Update `NavigationGroupTests`, `AppRouterHiddenRowTests`, `MCPToolRegistryTests` (expected list and write-tool list), `TodaySectionVisibilityTests`, `ClassGridViewsTests`, `ClassGridViewSwitchTests` and `ReadinessRuleTests`. Delete the tests of removed code. Leave the manuals, `CLAUDE.md` and `docs/Technical notes/` to Phase 6.
- Cost: $35–60, ~2–3% (Opus high session, five features, about 12,000 lines and their tests, a build per commit).
- Done when:
  - iOS app build for testing, Mac app build and Daybook Assistant build all succeed with no new warnings.
  - These suites pass: `NavigationGroupTests`, `AppRouterHiddenRowTests`, `MCPToolRegistryTests`, `TodaySectionVisibilityTests`, `ClassGridViewsTests`, `ClassGridViewSwitchTests`, `ReadinessRuleTests`, `BackupCoverageTests`, the backup golden and sparse-reference suites (with **no** re-recording), the student-deletion suites, and the guardian and attendance-insights suites.
  - `BackupPreferencesServiceTests` and `SettingsExportServiceTests` pass unchanged.
  - Every `Cut:` commit built on its own (say so in the final message).
  - `git grep` finds no reference to a removed type or tool outside tests of retired tools.
- By hand: none (sidebar and Today look become Tide device-check rows).

## Phase 2: Cut Resources, Stories, Procedures, Going Out, Today's pad card, custom templates, the To-dos screen
- Who: phase session (Opus 5.5, high).
- Needs: 1
- Steps (one `Cut:` commit each):
  1. **Resources, Stories and Procedures.**
     - Remove `Resources/Library/ResourcesView.swift` and the Files, Stories and Procedures libraries, `Procedures/`, `ProceduresLibrary.swift`, `ResourceRepository`, and the `ResourceDetailWindow` scene (`CosmicDaybookApp.swift:204`).
     - Remove the linked-resources group in `Lessons/Attachments/LessonAttachmentsSection.swift` (lesson attachments stay), `list_resources` (keep `day_pad` in `MCPNotebookTools+Library.swift`), `NavigationRowVisibility.hiddenLibraryKinds` and `procedureEntity`, and `LibraryImportService`, `LibraryFileStorage` and `LibraryThumbnailGenerator` if nothing staying uses them.
     - `.resourceLibrary`, `.stories` and `.procedures` become aliases to Lessons.
     - Keep the Resource, Story, Procedure and packet entity classes and their files on disk.
  2. **Going Out.** Remove the `GoingOut/` screens and the note editor's `.goingOut` context if only Going Out reaches it. Keep the two entity classes (moved to `Models/`), `Note.goingOutID`, and `StudentDeletion` and dedup handling. `.goingOut` becomes an alias to Today.
  3. **Today's pad card.**
     - Remove `TodayViewDayPadSection.swift`, `Components/DayPad/DayPadEditor.swift`, the Day Pad button (`TodayViewHeader.swift:42-52`), "Today's Pad" in `TodayViewToolbarPlusMenu.swift`, `dayPadListSection`, `isDayPadExpanded` and `TodaySection.dayPad`. The `todayDayPadExpanded` key and its backup line stay.
     - Move `Today/Support/TodayDataFetcher+DayPad.swift` beside the Calendar (it stays).
     - Reword `day_pad`'s description (it no longer appears on Today).
     - Keep `TodayRetentionCleanup` and the pad tests.
  4. **Custom meeting templates.** Remove the Settings › Templates pane (`Settings/Templates/`, `MeetingTemplateRepository`, its `SettingsCopy`, `SettingsCategory.templates` → an alias). Keep `BuiltInTemplateSeeder`, the entity and its dedup. Meetings read "the active built-in, else the first built-in" (`MeetingSessionView.swift:309`, `StudentMeetingsTab.swift:55`).
  5. **The To-dos screen.**
     - Remove `TodoMainView` and its extensions, `TodoRowCard`, `TodoRowComponents`, `TodoDateChip`, `TodoWhenPopover`, `TodoListScope` and `TodoSortOption`. The `todoTagOrder`/`todoHideCompleted` keys and their backup lines stay.
     - Split `TodoListFilter`: keep `isOnToday`, `isDueOrPlanned` and `isDue`.
     - Keep `EditTodoForm` (add Delete with a confirmation), `NewTodoForm`, `TodoCompletionService`, `TodoRepeatRule`, `TodoScheduling`, Tide sharing and the Claude to-do tools.
     - `.todos` becomes an alias to Today.
  6. **⌘7 opens Groups** instead of To-dos (`AppCore/NotebookCommands.swift`, `KeyboardShortcutsHelpView.swift`, `WindowGoMenuTests`).
  - Reword the retired sentences for `list_going_outs`, `update_going_out`, `list_procedures` and `book_club`. Update `NavigationGroupTests` (19 rows or fewer), `AppRouterHiddenRowTests`, `WindowGoMenuTests`, `MCPToolRegistryTests`, `TodaySectionVisibilityTests`, `SettingsSearchTests`, and the remaining to-do and template suites; delete the tests of removed code.
- Cost: $30–50, ~1–2% (Opus high, six changes, about 10,000 lines, a build per commit).
- Done when:
  - iOS build for testing, Mac build and Assistant build succeed with no new warnings.
  - These suites pass: `NavigationGroupTests`, `AppRouterHiddenRowTests`, `WindowGoMenuTests`, `MCPToolRegistryTests`, `TodaySectionVisibilityTests`, `SettingsSearchTests`, `LessonFilesSectionTests`, the `DayPadJoin`/`DayPadOpenEditor` suites, `BuiltInTemplateSeederTests`, the remaining Todo suites, `BackupCoverageTests`, `BackupPreferencesServiceTests`, `SettingsExportServiceTests`, and the golden and sparse-reference suites unchanged.
  - Every `Cut:` commit built on its own.
  - `git grep` finds no reference to a removed type.
- By hand: none (the iPhone Calendar's day note as the only place to write one is a Tide device-check row).

## Phase 3: The lesson loop in chat (services and Claude tools)
- Who: phase session (Opus 5.5, high).
- Needs: 2
- Steps:
  1. **Quick note helper** `Notes/QuickNote.swift`: the tag constant `to fill in` and `QuickNote.save(text:presentation:students:context:)`, which files a note linked to the presentation and its children with that tag. `update_observation` drops the tag when it replaces a note's words.
  2. **Practice timing** in a new `Work/Support/PracticeCheckInTiming.swift`, following the Decisions rule and using `SchoolDayChecker`.
     - `record_presentation`'s practice and follow-up decisions get a check-in on that day (`CaptureFollowUpPersistence` with `reviewAt`).
     - Hook the move-earlier rule into the shared plan and reschedule path (`PresentationPlanner`, and wherever `reschedule_presentation` and the app's reschedule write `scheduledFor`), so the app and chat both use it.
  3. **`WorkToShowFirst`** falls back to sub-area order when `orderInSequence` ties.
  4. **Warnings in chat.** `schedule_presentation`, `record_presentation` and `update_presentation_roster` (when adding children) print one plain line per child still practicing an earlier lesson in the sequence: "Ora still has practice open on The Distributive Law (since Nov 2)."
  5. **`record_presentation` takes `planned_presentation_id`** (per filing), as in Decisions.
  6. **New view `schedule_for_range` › `unrecorded`** (default: the last 14 school days through today).
     - It lists, day by day:
       - planned lessons not given, with their children;
       - each child's open-practice line;
       - quick notes tagged `to fill in`, with their ids;
       - "No School" event days the school calendar counts as in session.
     - It closes with the calls that settle each item: `record_presentation` with `planned_presentation_id`, `reschedule_presentation`, `discard_presentation`, `update_observation`.
     - Children's names in the short form ("Maya S").
  7. **Work titles.** The Class Grid ladder steps, recap practice and `WorkAssignmentService` pass "Practice: <lesson>" or "Follow up: <lesson>". `MCPNotebookTools+Schedule.swift:235` and `+StudentRecordWork.swift:123` print the lesson name when a title is empty.
  - Update `MCP_SERVER.md` only in Phase 6.
- Cost: $15–30, ~1% (Opus high; services plus four tools and their tests).
- Done when:
  - iOS build for testing, Mac build and Assistant build succeed (the Assistant compiles many notebook services by path).
  - New tests pass:
    - `PracticeCheckInTimingTests`: the day before the next planned lesson; 3 school days with none planned; skips non-school days; never earlier than tomorrow; moves an open check-in earlier when a lesson is planned, and leaves a done one.
    - The `unrecorded` view: a past day's plan is listed, a given lesson isn't, a quick note is listed, a "No School" day is flagged.
    - `record_presentation` with `planned_presentation_id` and a different group closes the plan and keeps the missing child planned.
    - The warning lines.
    - Titled work and the empty-title read.
  - Existing suites pass: `MCPToolRegistryTests`, the presentation recorder and resolve-plan suites, the `WorkToShowFirst` suite, the capture follow-up suites.
- By hand: none.

## Phase 4: The lesson loop on the Mac (screens) and ways into Groups
- Who: phase session (Opus 5.5, high).
- Needs: 3
- Steps:
  1. **Quick note.**
     - Add a "Given — quick note" action on Today's lesson rows and Next card (Mac and iPad). It records the lesson as given through the existing `TodayMarkPresented` path, then opens the quick note.
     - On the Mac, the quick note is a `Window("Quick Note", id: "quick-note")` (see Apple guidance): one text field, focused on open, saved through `QuickNote.save`. On the iPad it's a sheet.
     - A command with a free shortcut opens the window for the lesson just given or in progress.
  2. **Practice warnings on screen,** from `WorkToShowFirst`:
     - In `SchedulePresentationSheet` and `StudentPickerPopover` rows, a short `.badge(Text("Practicing <lesson>"))` or a caption.
     - A child dropped from the Ready band to check-first shows the reason instead of vanishing silently.
     - Today's lesson rows and Next card show "Still practicing: …".
  3. **Ways into Groups:** a "Groups" button beside the Class Grid's Ready lens, opening the matching `SequenceLadderRoute`, and a "Groups" link in Lessons & Work's Ready and Upcoming toolbar.
- Cost: $20–35, ~1–2% (Opus high UI phase across Mac and iPad, on a finished service layer).
- Done when:
  - iOS build for testing and Mac build succeed.
  - The touched views' suites pass, plus a test that `QuickNote.save` is called from the action.
  - Pictures, rendered headless on the iOS simulator by a scratch test, are saved to `docs/Pictures/`: the Today row with the action, the quick note's content view (the Mac `Window` itself can't be drawn in a test, and a Mac Debug run would open the live notebook), the picker badges and the Class Grid button.
- By hand: none (the real Mac window and its focus on re-open, the picker badge on macOS and iPad, and the Groups button become Tide device-check rows).

## Phase 5: A Tide note for each cut feature, and two Tide rows
- Who: phase session (Sonnet 5.5, high). Writing from the code and this plan, with some code tracing for what depended on each feature; no repo files change.
- Needs: 2
- Steps:
  1. For each of the fourteen cuts, write a Tide note with `create_note`. The cuts are: Parent Reports (monthly letters), the per-child report, Spaced recall checks, Projects, Book Club, Community topics, Issues, Resources library, Stories, Procedures, Going Out, Today's day pad card, Custom meeting templates, and the To-dos screen.
     - Put each note in the Cosmic Daybook area's folder (`list_folders`; else `Notes`), titled `Retired: <feature>`.
     - Each note says:
       - what the feature did and who used it;
       - its live use at the cut (from this plan's table);
       - where its code lived, with paths and line counts (from `git show --stat <its Cut: commit>`);
       - which records it kept and where they still live;
       - the Claude tools it had;
       - what it depended on and what depended on it;
       - the `Cut:` commit that removed it on main;
       - how to bring it back (`git revert <commit>`, or read files with `git show retired/2026-11-cuts:<path>`);
       - anything to watch for (from this plan's Decisions).
     - Plain English; American spelling.
  2. Add Tide rows (`add_action` into `Areas/App Development/Cosmic Daybook/To do.md`), skipping any already there:
     - "At the next feature review, decide whether to keep This Week's Parsha" (Review choices);
     - "At your next student meetings, notice what makes writing them up hard, then ask Claude to rework the meeting screen" (Review choices);
     - "Decide whether a note should be able to cover several lessons given together (needs a data change)" (Review choices);
     - "Someday and work-linked to-dos no longer have their own screen: check you can still find them" (Review choices).
- Cost: $4–10, <1% (Sonnet high, fourteen notes).
- Done when: `create_note` returned a path for all fourteen (new notes wait in To Confirm, so check by the returned paths with `read_note`, not `list_notes`), each names its `Cut:` commit and the tag, and the four rows exist.
- Merge: none. This phase changes no repo files, so it skips "Running a phase" step 6 and only marks itself merged (`plan-wait … --mark 5`).
- By hand: none.

## Phase 6: Final check
- Who: phase session (Opus 5.5, high), with a cold reviewer agent (Plan, Fable 5.2) on the whole diff since `retired/2026-11-cuts`.
- Needs: 4,5
- Steps:
  1. On main with every phase merged:
     - the full iOS app build, Mac build and Assistant build, plus one Release build of the iOS app (Debug never compiles `#if !DEBUG` code);
     - the whole iOS suite once (`-parallel-testing-enabled NO`, one leased simulator);
     - the Assistant's suite.
     Fix what fails; the errors name files, and the files map to phases.
  2. Cold review: correctness, kept data (no entity, backup row, preference key or note link lost), Claude tool text that names a removed tool, aliases that land nowhere. The reviewer also greps for any remaining code path that deletes an `Issue`, `ProjectSession` or `CommunityTopic` (their deletes cascade to notes) and checks the dedup merges for those three. Fix what holds up.
  3. Docs:
     - `Cosmic Daybook/CLAUDE.md` (tool count, sidebar rows, project tree, the kept-entities note);
     - `docs/Technical notes/MCP_SERVER.md`, `TODOS.md`, `TIDE_SHARING.md` and `DATA_MODELS.md` (a "kept, no screen" list);
     - `Documentation/Manuals/UserManual.md` and `DeveloperManual.md` (remove the cut features; add the quick note, the 3:45 chat and practice timing);
     - `docs/Old names.md` for any moved doc.
  4. Tide rows: "Install the new build on the Mac (`Scripts/install_release.sh`) so the 3:45 chat can use the new tools" (Release), plus any device checks the phases listed and haven't added.
- Cost: $15–30, ~1% (full builds, whole suite, a Fable review and its fixes, docs).
- Done when:
  - All three builds succeed with no new warnings.
  - The whole iOS suite and the Assistant suite pass, with counts reported.
  - The review's fixes are in.
  - Docs are updated.
  - `~/.claude/bin/docs-index --check` passes after the conductor runs `docs-index`.
- By hand: none.

## Conductor: the 3:45 pm scheduled chat (after Phase 6)
`create_scheduled_task`: taskId `daybook-end-of-day`, title "End of the school day", cron `45 15 * * 1-5`. Prompt (self-contained):

> It's the end of the school day for Danny, a Montessori upper-elementary guide. Use the cosmic-daybook connector. First check `school_calendar` for today; if school is not in session, say so in one line and stop. Otherwise call `schedule_for_range` with view `unrecorded` (if that view doesn't exist yet, use view `plan` for today). If nothing is open, say "Nothing left from today's lessons." and stop. Otherwise list what's open, grouped by day: each planned lesson not yet recorded (lesson, children in short form like "Maya S"), each quick note marked "to fill in", and any day flagged as possibly no school. Ask Danny what happened to each lesson: given (and, ideally, one sentence per child on how it went, plus ready / practice / present again), moved (to when), or not given. Encourage a sentence per child but accept less. Record only what he says: `record_presentation` with `planned_presentation_id` for given lessons, `reschedule_presentation` for moved ones, `discard_presentation` for ones not given, `update_observation` to fill in quick notes. Confirm before writing anything he didn't say. Plain English, American spelling, no ids in what you show him.

## Running a phase (phase sessions read this)
You were started by the conductor. Danny accepted this plan and is likely away. Don't ask him anything and don't wait on him. **Don't edit this plan file**: other phases are running beside you, and the conductor writes Progress and Decisions. Everything you'd add goes in your final message.
0. Get your session id: run `echo $CLAUDE_CODE_SESSION_ID` (it isn't filled in for you anywhere else). If your phase needs other phases, wait for them first: run `~/.claude/bin/plan-wait --repo "/Users/dannydeberry/Developer/Maria's Notebook" --prefix plan/cuts-loop --needs <their numbers, comma-separated like 4,5> --timeout 86400` with `run_in_background`, and end your turn; you're woken when it exits. On "Go ahead" carry on. On anything else (a needed phase stopped, the run braked, a time-out), stop: mark yourself stopped (step 7) unless the run was braked, and report its line.
0b. Make sure your branch starts from local main, which holds every phase merged so far (nothing is pushed, so `origin/main` is behind): if `git merge-base --is-ancestor main HEAD` fails, run `git merge main`.
1. Read `Cosmic Daybook/CLAUDE.md` (and the repo root `CLAUDE.md`). Do the phase's steps, building only its smallest target and running only its `-only-testing:` suites (`~/.claude/CLAUDE.md` › Xcode builds; use `Scripts/locked_xcodebuild.sh`; `-only-testing:` names the enclosing type of nested suites). If `locked_xcodebuild.sh` exits 75, the build never started because the queue was busy: run it again, as many times as it takes, and never skip a build. Test on simulators headless (`xcodebuild test` on your leased simulator, `xcrun simctl io <udid> screenshot`). Leave tapping, clicking and screen-driving to the conductor: list what to check under "By hand" in your final message.
2. If a decision comes up that the plan didn't settle, take the safer option that's easier to undo, add a `Review choices` row in Tide for Danny, and put it under "Decided" in your final message.
3. Check every "Done when" item. Before each fix round, run `~/.claude/bin/plan-cost session`. If one item still fails after two tries, or the phase has cost more than twice the top of its estimate, stop.
4. Make every "not verified", "for your review" or "check on a device" item from this phase a row in the app's list in Tide (`Areas/App Development/Cosmic Daybook/To do.md`, `add_action`), skipping ones already there. Any repo doc line about it keeps one plain sentence plus the row's `tide://` link.
5. Update the build board, if the plan lists one (`build-board` skill, then `~/.claude/bin/board-touch <url>`).
6. Merge: read `~/.claude/skills/close-out/SKILL.md` and follow it (it can't be invoked as a skill). Danny's acceptance of the plan is his go-ahead. Make these changes to it:
   - In its step 2, bring the branch up to date with **local** `main` (`git merge main`), not `origin/main`.
   - Right after the squash commit, before releasing the lock, mark the phase merged: `~/.claude/bin/plan-wait --repo "/Users/dannydeberry/Developer/Maria's Notebook" --prefix plan/cuts-loop --mark <N>`. Phases waiting on you start from that.
   - Before its step 4, take the merge lock: `~/.claude/bin/plan-merge-lock take "/Users/dannydeberry/Developer/Maria's Notebook"` (run it with `run_in_background` if it says it's waiting). Release it with `plan-merge-lock release "/Users/dannydeberry/Developer/Maria's Notebook"` right after the squash commit, and also if you stop before that commit.
   - Phases 1 and 2: merge with a normal merge commit instead of a squash, so each `Cut:` commit stays on main and can be reverted alone.
   - Skip its step 4b (the conductor keeps the plan's status and the docs map) and its step 5 (no push).
   - Wherever it says "stop and ask", stop instead: release the lock, don't merge, and report it.
7. If you stopped without merging, mark it so the phases waiting on you stop too (`plan-wait … --mark <N> --stopped`), and shut down your simulators (`~/.claude/bin/sim-lease --done`). close-out releases them otherwise.
8. End with this line first, so the conductor's note shows it: `Phase <N> done (<commit>). Session <your id from step 0>. By hand: <list or none>.`, or `Phase <N> stopped: <plain reason>. Session <id>. Nothing merged.` Then, under it, any "Decided:" items and anything that differed from the plan.

## Open questions
None.
