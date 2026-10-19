# Simplify the app

> **Working on it.** Written 2026-10-18 from the app-structure review session (2026-10-10 to 2026-10-18): Danny's map of the app, a screen-by-screen overlap survey, live usage counts, and his answers.
> In short: fewer, fuller screens (one class grid, Logs folded into the screens it repeats, one Library, one Clubs & Projects), two levels of readiness, one day note, a to-do list shared with Tide, no Ask AI, and a six-group sidebar, without losing anything Danny uses.

The map behind this plan: https://claude.ai/artifact/Dw5P6Q19JrawCyq2f2CyFH (the teaching loop, the parts around it, the first sidebar proposal).

## Goal

The sidebar drops from 30 rows in eight groups to 21 rows in six, and every screen that stays does one job. Screens that showed the same thing twice become one screen with views; screens that only repeated another screen become a view inside it. Readiness reads the same everywhere and says, before Danny gives the next lesson, whether the child still has work open or needs more practice. The notebook's to-dos and his classroom to-dos in Tide become one list he can see in either app. Nothing he uses is lost; the four screens he hasn't started using yet (Going Out, Procedures, Schedules, Book Club) stay.

## Progress

- [x] Phase 1: Removals and one Parsha screen (session: fresh) ‖ Phases 2, 3, 6, 7, 9 · est. ~1–2% weekly · started at 48%, ended at 65% (~1%, a Sonnet agent; the meter went 54→65 with Phases 1, 2 and 6 and another session's Phase 7 running together). Ask AI is gone (~5,200 lines); `classroom_snapshot` moved into `MCPNotebookTools+Reads.swift`, pinned by `MCPClassroomSnapshotTests` (passed before and after the move). One Parsha screen: This Week's Parsha with the year list as its index; `ParshaBrowseView` points to it; `ParshaLessonListView` deleted (there was only ever one editor and one schedule sheet). Notes opens `ObservationsView` directly. Differed: `.askAI` stays in `pagesWithOwnStack` (it opens Today, which has its own stack); the Ask-AI-only `NotebookToolStudentResolver`, `NotebookToolText` and `HistoryKind` went too; the saved `ChatSession.saved` keys linger on devices (a later `RetiredAIKeysCleanup` could clear them). Device checks: [Notes and Logs](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=After%20the%20next%20roll-out%2C%20tap%20Notes%20and%20then%20Logs%20in%20Cosmic%20Daybook%20and%20check%20Logs%20still%20opens%20on%20the%20tab%20you%20left%20it%20on), [the Parsha screen](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=After%20the%20next%20roll-out%2C%20check%20This%20Week%27s%20Parsha%20in%20Cosmic%20Daybook%3A%20the%20year%20list%20beside%20this%20week%20on%20the%20Mac%2C%20and%20behind%20the%20Year%20button%20on%20iPhone).
- [x] Phase 2: Logs folded into Meetings, Attendance, Notes and Lessons & Work (session: same as 1) ‖ · est. ~2–3% · started at 48%, ended at 65% (~2%, shared meter as Phase 1). Meetings has Queue / History, Attendance has Roll / List (a List button on iPhone), and each half of Lessons & Work has a History choice; the empty-state line reads "Finished work is under History." New saved settings `MeetingsWorkflow.screenView` and `Attendance.screenView`; `logsMenuRootViewMode` kept (Logs still reads it). The Mac look is unchecked ([Tide](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=After%20the%20next%20roll-out%2C%20check%20on%20the%20Mac%20that%20the%20Queue%2FHistory%2C%20Roll%2FList%20and%20History%20switches%20in%20Meetings%2C%20Attendance%20and%20Lessons%20%26%20Work%20sit%20well%20in%20the%20toolbar)).
- [x] Phase 3: Two levels of readiness, one rule (session: same as 1) ‖ · est. ~2–3% · started at 48%, ended at 54% (~2%; the meter is shared with Phases 1, 2, 6 and other sessions). Landed alone, ahead of 1 and 2, so Phase 5 can start. `ReadyForNextEngine.readiness(of:)` (`ReadyForNextEngine+PreviousLesson.swift`) with a previous-lesson line; Groups, the ladder, Today and the Checklist read it; one `DaysSinceLastLesson` (all four screens now leave Parsha out and count school days; the planner's copy counted Parsha and calendar days). Whole suite 4,019 passed. Differed from the plan: a forgotten recall check also counts as check first; sequence settings no longer skip the checks on the Checklist; a mastery mark alone is Ready; undated "given earlier" marks no longer count for days since. Danny to review those choices ([Tide](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=Review%20the%20readiness%20choices%20Claude%20made%20in%20Cosmic%20Daybook%27s%20one%20readiness%20rule)); the Mac look is unchecked ([Tide](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=After%20the%20next%20roll-out%2C%20check%20on%20the%20Mac%20that%20Groups%2C%20a%20sequence%20ladder%20and%20the%20Checklist%20show%20Ready%20and%20%22Ready%2C%20check%20first%22%20with%20readable%20reasons)). The build board couldn't be updated (other organization).
- [x] Phase 4: Class grid design on a canvas, Danny approves (session: fresh, needs Danny) · est. ~1–2% · started at 48%, ended at 49% (~1%). Approved 2026-10-18 as drawn, named **Class Grid** (canvas and decisions under Decisions › Class Grid). The view names became Checklist, Three Years, Children, Recall. The build board couldn't be updated: it sits in Danny's other claude.ai organization.
- [ ] Phase 5: Build the class grid (session: fresh, after 3 and 4) · est. ~3–5%
- [x] Phase 6: One Library, Clubs & Projects, one Files section on a lesson (session: same as 1) ‖ · est. ~2–4% · started at 53%, ended at 65% (~3%, shared meter as Phase 1). `Resources/Library/`: one Resources screen (Stories, Packets, Files, Procedures) on `PDFLibraryListView`; one `LibraryImportService`, `LibraryThumbnailGenerator` and `LibraryFileStorage` (folder names unchanged, tested); Clubs & Projects in `ProjectsRootView`; one lesson Files section; one `LessonLinkPicker`. Old root views are thin wrappers so navigation is untouched until Phase 11. Differed: Files dropped its list layout, so `UserDefaultsKeys.resourceLibraryViewMode` went (the backup's preference list still names it, harmlessly). The Mac look is unchecked ([Tide](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=After%20the%20next%20roll-out%2C%20open%20Resources%20and%20Clubs%20%26%20Projects%20on%20the%20Mac%20and%20check%20the%20toolbar%20filter%20and%20that%20a%20selected%20item%27s%20detail%20fits%20its%20side%20column)).
- [ ] Phase 7: One day note, today's schedule on Today (session: same as 1) ‖ · est. ~2–3%, plus its own review
- [x] Phase 8: To-do cleanup with Danny (session: fresh, needs Danny, before Phase 10's switch is turned on) · est. ~1% · started at 49%, ended at 49% (<1%). Done 2026-10-18: of 39 open to-dos (not 40), 15 kept, 24 closed. 7 went to Restock (5 to order, 2 office run) and their 5 Tide Room Setup copies were ticked; 3 lessons were planned on their dates (Part B 10-19 for Etty K., Common Multiples 10-20 for Dalia and Lucy, Pegboard LCM 11-02 for Naomi), and Variety of Leaves was already planned, so it moved to 10-20; 2 algebra to-dos were already covered by the 10-20 Solving for an Unknown group; 3 "watch" to-dos became flagged notes; 8 stale ones were closed, plus Tide's copy of the Etty K. algebra check-in. Kept as to-dos: constellations and pin maps (no lesson in the library) and "watch who stalls on algebra" (names no child). The notebook's Claude connection was dead at the start: its hidden Claude-only copy had frozen while quitting, and was stopped by hand.
- [ ] Phase 9: Apple Reminders doubles fixed (session: same as 1, after Phase 7) · est. ~2–3%, plus its own review
- [x] Phase 10: To-dos shared with Tide (session: fresh) · est. ~4–6%, plus its own review · started at 60%, ended at 79%, on main as d1b4164b (~7–8% by agent tokens: a feature-phase-deep Opus xhigh agent, ~1.4M tokens over the build and a fix round, and an Opus review, ~250k; the meter went 60→79 with Phase 5 and other sessions running). Schema 19 (optional `tideLink` on to-dos), backup v41; `Services/Tide/` (client, sync engine and service, Keychain address); Settings › Connections › Tide; a "From Tide" section in Todos and on a child's page. 151 focused tests passed (30+ against a fake Tide); macOS (compile only), iOS and Assistant builds pass. The review found 2 high and 4 medium problems (a tick lost on repeated words, a run cut off on going to the background, dedup dropping the link, Tide-made to-dos with no notebook line, a moved action closed here, first-run matching missing check-ins), all fixed with tests. Differed from the plan: no `changes_since` (an unfiltered call moves the one bookmark Claude sessions read from), so each run compares a `get_area` snapshot; only the Release Mac app talks to Tide; to-dos planned for a later day go with Tide's start date, Someday ones stay here; Tide-made to-dos follow Tide's words; Today needed no change (a due Tide to-do shows by Todos' own rule); Tide can't tick an action whose words appear twice in its list, so that tick is retried and said plainly ([Tide row for Tide](tide://box/Areas/App%20Development/Tide/To%20do.md?text=Let%20Tide%27s%20complete_action%20take%20a%20position%20and%20revision%2C%20as%20delete_action%20does%2C%20so%20Cosmic%20Daybook%20can%20tick%20an%20action%20whose%20words%20appear%20twice%20in%20its%20list)). Danny to review those choices ([Tide](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=Review%20the%20choices%20Claude%20made%20in%20Cosmic%20Daybook%27s%20Tide%20sharing%20where%20it%20differs%20from%20the%20Simplify%20plan)). Schema 19 was deployed to Production on 2026-10-19 (the two fields added in the CloudKit Console's Development schema, then deployed by Danny). The Mac look and a live round trip with Tide are unchecked ([Tide](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=After%20the%20schema%2019%20roll-out%2C%20turn%20on%20Tide%20sharing%20in%20Cosmic%20Daybook%27s%20Settings%20on%20the%20Mac%20with%20Tide%20open%2C%20check%20the%20first-run%20matches%20and%20how%20it%20looks%2C%20then%20tick%20a%20to-do%20on%20each%20side%20and%20see%20the%20other%20follow)). The not-yet-started Hebrew birthdays plan also wanted schema 19 and backup v41; it now needs 20 and v42. The build board couldn't be updated (other organization).
- [ ] Phase 11: Six-group sidebar and retired destinations (session: final, main) · est. ~1%
- [ ] Phase 12: Combine, full build, whole suite, review, land (session: final, main) · est. ~3–5%

Phases 1, 2, 3, 6 and 7 touch separate folders and can run as parallel agents from one session, **at most three at a time** (more than three Opus agents at once fills a 5-hour window; start the next as one finishes). Phase 9 waits for Phase 7, since both edit `Services/Migrations/`. `UserDefaultsKeys.swift` may be edited by Phases 1, 2 and 7: each adds or removes only its own keys, and a merge keeps both sides. Navigation files (`AppCore/RootView/*`, `NavigationGroupTests`, `NotebookCommands`) are left alone by every phase except 1 (the Ask AI and Notes lines in `RootDetailContent.swift`) and 11, so they never collide. Today's section files are edited only in Phase 7 (Phase 3 touches only `TodayViewReadyForNextSection.swift`).

## Cost

About **25–37% of the weekly all-models limit** (Max plan), including a review and fix round for Phases 7, 9 and 10 as each merges (recent runs needed fix rounds worth ~40% of the agent work). On 2026-10-18 the week is 48% used, with 52% left until **Fri 2026-10-23, 10 am Pacific**. **Fits.** Estimates use the log's recent Cosmic Daybook numbers: UI phases on existing data have come in at ~0.5–3% each, deep agents at ~2–2.5% each when they wait in the build queue (2026-10-18 bug-hunt row). If the week gets tight, Phase 10 (the largest) moves past the reset; nothing else depends on it except Phase 11's Todos wording.

## Decisions

**Danny's answers (2026-10-14 and 2026-10-18)**
- All free wins approved, but **Today's Recent notes stays** (it shows yesterday's notes for the morning reread and hides itself when there are none; Watching is a different thing).
- **Going Out, Procedures, Schedules and Book Club stay**: he plans to use them.
- All merges approved: one class grid, Logs dissolved, one readiness rule, Projects + Book Club, one Library, lesson attachments vs linked resources made one.
- **Ask AI is removed.**
- **To-dos are shared with Tide**, and his classroom to-dos in Tide show in the notebook. Every notebook to-do goes to Tide **except the automatic work check-ins** ("Check in with Maya on …").
- **Apple Reminders sync stays a Settings option** (it already is: Settings › Sync, list picker with "None"); its doubles get fixed.
- **Clean up the to-dos**: move the misplaced ones to their homes and close the stale September ones, after Danny sees the list.
- **Readiness: the previous lesson confirmed**, with **two levels**: Ready, and Ready, check first (the row says why). Before giving the next lesson he sees the previous lesson's status: open work, last check-in result, practice needed, mastered or not.
- **Sidebar**: the six-group order proposed on the map, adjusted for the merges (below).

**Settled here, with why**
- **No data-model change except one optional field** (Phase 10's link from a to-do to its Tide item). Every other merge is done in the screens: Projects and Book Club keep their own records; lesson attachments and linked Resources keep theirs; calendar notes are copied into day pads, not deleted. Additive optional fields are safe for older builds; removals are not. Phase 10's field still needs the schema-version bump and a Production deploy (see its steps).
- **The old Projects roles and templates stay** (`CDProjectRole`, `CDProjectTemplateWeek`, `CDProjectAssignmentTemplate`, `CDProjectWeekRoleAssignment`). Removing them is a schema change (`Project.sharedTemplates` still points at one) and a backup-format change, for no visible gain. Won't do.
- **Retired destinations are aliased, never deleted.** Their raw values are saved with each window; the case stays, joins `NavigationItem.aliases`, and leaves `NavigationGroup.all`. `allCases.count == 34` stays.
- **The iPhone tab bar doesn't change**: Today, Students, Attendance, Lessons & Work, More. Apple's tab-bar guidance prefers five or fewer, and the iOS 27 SDK can crash when a TabView's selection points at a hidden tab, so the saved-selection restore must land every retired item on a visible one.
- **The class grid gets a canvas first** (Phase 4). It replaces four screens Danny uses, and the Checklist's last redesign (2026-10-02) also started on a canvas.
- **Class Grid (Phase 4, approved by Danny 2026-10-18, "approved as drawn, including the five points in the orange note").** Canvas: https://claude.ai/artifact/5zGC9J7nQn6u5xxTVPhfqs (Mac: all four views; iPad: Ready lens with a cell card open; iPhone: all four views under More; one set of marks). Phase 5 builds it as drawn:
  - **Name**: Class Grid. **Views**: Checklist, Three Years, Children, Recall (a toolbar segmented control on Mac, `.tabs` under the title on iPad/iPhone). The area menu ("All areas" or one area), search and the children filter carry across views.
  - **Readiness on cells**: Ready = grey ring; Ready, check first = grey ring with the amber dot (the same dot as "needs a check-in": amber always means look before you act); Not yet = small grey dot. The Ready lens lights Ready cells blue and check-first cells amber; the Class column reads "4 ready · 1 check first" with Plan. The cell card shows the reason ("2 pieces of work still open") and a Previous lesson box: name and date given, open work, last check-in, mastered or not.
  - **One palette**: the Checklist's ladder everywhere (grey, blue quarter/half/three-quarter fill, green with a check only for a mastery mark, dashed orange for planned). The Map's presented/chosen/repeated/mastered become Presented/Practicing/Reviewing/Mastered; the Progress pills' yellow Reviewing goes. Area color stays on row labels and area headings only.
  - **Recall rings** (Three Years and Recall): solid green = still has it, dashed orange = shaky, dotted red = forgotten, drawn as an outline outside the mark.
  - **Three Years**: children grouped by year in class (Year 3 first), Great Lessons rows then one row per area (furthest mark per child), Key / All lessons once an area is picked, a "N not yet" column.
  - **Children**: one row per child (grouped by level), each started sequence a strip of the same marks with "4/8"; clicking a strip opens the sequence sheet (Work, Presentations, Notes).
  - **Recall**: a list, not lit grid cells (frontier lessons cross areas): retention tiles (Held, Checked, To present again, Faded over summer, Due), By child, the due queue grouped by child, and the recall check beside it on Mac/iPad (a sheet on iPhone).
  - **iPhone columns**: 44-pt columns with angled names (5 children fit), replacing today's 120-pt columns; rows stay 44 pt.
- **The class grid lives at the Checklist's destination** (`.planningChecklist`), which is the screen with the editing tools. Three-Year View, Progress Dashboard and Lesson Recall alias to it and open on their view.
- **Logs' pieces go to the screens they repeat**: meetings history becomes a History view in Meetings; the attendance log becomes a List view in Attendance (keeping its date range, status filters and totals); Observations is Notes, opened directly; the all-time Presentations list and the Works list (the only list of finished work) become a History choice in each half of Lessons & Work. Its empty-state line "Finished work lives under Logs." changes with it.
- **The class-wide `classroom_snapshot` builder survives Ask AI.** `ChatContextAssembler.buildClassroomSnapshot()` feeds the Claude tool `classroom_snapshot` (`MCPNotebookTools+Reads.swift:269`); it moves into `Services/MCPServer`. `AIClientRouter`, `generateText`/`generateStructuredJSON` and `EvidenceReference` stay (Parsha suggestions, Stories, parent reports, insights, note summaries use them).
- **One day note is the Today Pad** (`CDDayPad`). A one-time, repeatable copy at launch moves each Calendar note (`CDCalendarNote`, keyed by year/month/day) into that day's pad (appending if both exist), then the Calendar grid reads and writes pads. Old rows stay. Both are private-store entities and both are backed up; the Claude tools `day_pad` and the schedule tool follow the pad.
- **Schedules feeds Today**: a section showing today's slots, grouped by schedule, shown only when a schedule exists. Needs a small `Weekday(date:)` helper.
- **One Library screen**: Stories, Book Club packets, Resources and Procedures under type filters, on the shared `Components/PDFLibraryListView`. Procedures appear as written pages. One import service replaces the near-identical `StoryImportService`/`BookClubImportService`; one thumbnail generator. Albums stays its own screen (a reader, not a file list). The screen is called **Resources**, the group **Library**.
- **Clubs & Projects**: one screen listing Projects and Book Club sessions, each kept as what it is (projects make work; clubs have packets, a schedule and rotating leaders). Packets themselves live in the Library.
- **One Files section on a lesson**: lesson attachments (by lesson, sequence, area) plus linked Resources as rows that open the resource. New files keep going in as attachments.
- **One readiness rule** (`ReadyForNextEngine`, the one Groups and Today already share) replaces the Checklist's "Ready to Present" use of `BlockingAlgorithmEngine` for unplanned cells. Lessons & Work keeps its own check on drafts already in the Inbox (a different job). Reuse the "work to show first" logic from `Plan - Lessons and Work changes 2026-10-13.md`.
- **"Days since last lesson" is computed once.** Today there are four copies (`PresentationsViewModel+DaysSince`, `StudentsViewModel+Caches`, `DaysSinceLastLessonView`, `StudentReadinessAssessor`); Phase 3 makes one shared function and settles whether Parsha lessons count (two copies leave them out; keep that).
- **Tide sharing runs from the Mac.** Tide accepts writes from another app only through its own Mac connection (`localhost:4877`, a token in the URL; `Tide/MCP/MCPServerManager.swift`), while Tide is running. Tide's URL scheme only navigates, its App Intents can't be called from code, and its App Group drop box lands bare captures in the Inbox, so none of those work. The notebook's Mac copy does all sending and reading; things made on iPhone or iPad reach Tide when the Mac is on. One pusher, as Tide's own Reminders rule says, to avoid doubles.
  - **Where to-dos land**: `Areas/My Classrooms/Upper Elementary/To do.md`, heading chosen in Settings (default: the list's first heading). **What shows in the notebook**: every open action in the Tide lists Danny picks in Settings, default all of My Classrooms (Upper Elementary, Room Setup, Adolescents Program, Shared Environments & Community, and the area's own list).
  - **Link**: a new optional `tideLink` string on `CDTodoItem` (schema 19, a Production deploy step for Danny), plus `notebook:<uuid>` in the Tide action's note so a crash mid-push can be recognized. Tide's link is built from the action's words, so rewording in Tide breaks it; re-match by the uuid in the note.
  - **Both ways**: ticking off on either side ticks off the other (Tide's `complete_action`; read back with `changes_since` and a saved cursor). Un-ticking is not carried across. Once pushed, Tide owns the wording; notebook edits to a pushed to-do's title don't travel (said plainly in the to-do's detail).
  - **Doesn't travel**: subtasks, someday, linked work, recurrence. Linked students are named in the Tide note.
  - **Student pages**: Tide to-dos that name a child (full name, or the short "Maya S" form) show on that child's page. A bare first name shared by two children (two Ettys, two Sarahs) doesn't match.
  - **First run**: 10 to-dos already exist on both sides (the 7 Room Setup orders, two check-ins, MAP testing). The first sync matches by words before pushing, and the cleanup (Phase 8) runs before the switch is turned on.
  - **Connection**: Danny copies Tide's connection address from Tide into the notebook's Settings once, on the Mac. Plain-English states: "Tide isn't open on this Mac. To-dos will go across when it is."
- **Reminders doubles**: a restored backup brings reminders back without their Apple Reminders link (backups leave the ids out on purpose), so the next sync inserts a linked copy beside each one. The sync takes over the unlinked row instead (Phase 9). Matching reminders across devices was tried in the 2026-10-17 bug hunt (#13) and backed out because it doubled every reminder, so it's ruled out here.

**Ruled out**
- Merging Lessons and Albums (different jobs; already cross-linked).
- Deleting unused screens (Danny will use them).
- Writing Tide's `To do.md` files directly (loses fields, raises Inbox questions in Tide, needs a folder bookmark on every device). Kept only as a last resort if Tide's connection proves unusable.
- Joining Tide's App Group (per device, no fields or ids without Tide changes).
- A per-Tide-action entity in the notebook (a bigger schema change; shared to-dos reuse `CDTodoItem`).

**Final sidebar (Phase 11)**

| Group | Rows | Opens |
|---|---|---|
| Today | Today, Attendance, Todos | open |
| Children | Students, Meetings, Notes, Parent Reports | open |
| Plan | Lessons & Work, Groups, Class Grid, Calendar, This Week's Parsha | open |
| Classroom | Restock, Community, Clubs & Projects, Going Out, Schedules | closed |
| Library | Lessons, Albums, Resources | open |
| System | Settings | open |

Retired rows and where they land: Logs → Notes; Three-Year View, Progress Dashboard, Lesson Recall → Class Grid on that view; Parsha Calendar → This Week's Parsha with the year list showing; Stories, Procedures → Resources filtered to that type; Book Club → Clubs & Projects; Ask AI → Today.

## Apple guidance

Checked 2026-10-10 against Xcode 27.0 (27A266a); targets iOS 27.0 / macOS 27.0 (notebook) and iOS 18.0 (Assistant, untouched here). Xcode 27.1 RC and 27.2 beta 2 exist; their notes change nothing this plan uses.
- **Tabs and sidebar**: `TabView` with `Tab`/`TabSection`, `.tabViewStyle(.sidebarAdaptable)` (iOS 18 / macOS 15). Apps built with the iOS 27 SDK enforce that the selection is a visible tab and may crash otherwise ([iOS 27 release notes](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes)); every retired destination's saved selection must restore to a visible tab (Phase 11). HIG [Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars) (2026-08-20): two levels at most. [Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars) (2026-09-07): five or fewer, don't hide tab buttons. No `TabViewCustomization` is used today, so nothing persisted breaks; Apple documents nothing about removed tab IDs (gap).
- **The class grid**: `PinnedScrollableViews` pins section headers and footers only, so a grid pinned on both axes is hand-built (lazy rows inside a two-axis `ScrollView`, a pinned header row and a pinned name column synced by `ScrollPosition`/`onScrollGeometryChange`, iOS 18 / macOS 15). [WWDC26 321](https://developer.apple.com/videos/play/wwdc2026/321/): do setup in `init`, keep state out of scrolled-away views, avoid layout driven by `onAppear`/`onGeometryChange`; "sometimes a custom Layout is the better solution". `Table` hides all but the first column at compact width, so it doesn't fit. Profile with the SwiftUI instrument ([WWDC25 306](https://developer.apple.com/videos/play/wwdc2025/306/)).
- **Switching views inside a screen** (class grid, Resources types, Meetings History, Attendance List): HIG [Segmented controls](https://developer.apple.com/design/human-interface-guidelines/segmented-controls) (2026-08-06): on macOS a segmented control belongs in the toolbar; five to seven segments at most, five on iPhone; text or icons, not both; noun labels. `.pickerStyle(.tabs)` is new in iOS/macOS 27 and reads as tabs to VoiceOver; fine here (notebook only). Don't use `.searchScopes` as a view switch (it filters search results and only shows while searching).
- **Talking to Tide**: there's no Apple API for one app to call another app's App Intents; Siri and Shortcuts orchestrate across apps ([WWDC26 8011](https://developer.apple.com/videos/play/wwdc2026/8011/), panel answer). App Groups are per device. So the loopback connection to Tide's own server on the Mac is the route; the Mac notebook is sandboxed with outgoing network allowed. If an App Intent is ever added, use `SyncableEntity` with a UUID ([WWDC26 345](https://developer.apple.com/videos/play/wwdc2026/345/)). `canOpenURL` is deprecated in iOS 27; not used.
- **Reminders**: `requestFullAccessToReminders` (iOS 17 / macOS 14); `EKEventStoreChanged` says nothing about which items changed, so refetch; there's no API to revoke access, so "off" means stop observing, drop reminder objects before releasing the store, and clear saved identifiers. `calendarItemExternalIdentifier` can differ per device for Exchange reminders.

## Testing rules for every phase

- **Never open Danny's live notebook.** A macOS `xcodebuild test` launches the real app, and its startup runs against his live store (`test-host-opens-live-store`). So: tests run on the leased iOS simulator only (`-destination "platform=iOS Simulator,id=$(~/.claude/bin/sim-lease)"`, `-parallel-testing-enabled NO`, one simulator); macOS is built (compile only), not run. Screenshots are taken on the iPad simulator. Anything that can only be checked by running the Mac app (Mac look, Mac scrolling smoothness, the live Tide round trip) becomes a Tide row for Danny.
- **Never run a schema-19 build on the Mac** before Danny has deployed schema 19 to Production and is ready to roll out (from Phase 10 on). The newer-build guard would lock his installed copy out of his store.
- **Never point a test at Tide's real server.** A simulator app reaches the Mac's `localhost`, which is Danny's live Tide on port 4877; tests use an injected fake.
- Builds and test runs wait their turn in the build queue (`Scripts/locked_xcodebuild.sh`); each agent builds only its smallest target and runs only its `-only-testing:` suites, and runs `~/.claude/bin/sim-lease --done` before it reports back.

## What Danny approved, and where it's done

| Approved | Phase |
|---|---|
| Notes and Logs were the same screen: one row | 1 (Notes opens directly), 11 (Logs row retired) |
| One Parsha screen | 1 |
| Delete Today's unused Deadlines section | Already gone (ba5c5e15); nothing to do |
| Keep Today's Recent notes | Untouched |
| Old Projects roles and templates | Won't do (see Decisions) |
| Keep Going Out, Procedures, Schedules, Book Club | Untouched (Book Club sessions join Clubs & Projects in 6) |
| One class grid (Checklist, Three-Year View, Progress Dashboard, Lesson Recall) | 4, 5 |
| Logs folded into Meetings, Attendance, Notes, Lessons & Work | 1, 2, 11 |
| One readiness rule, two levels, previous-lesson status | 3 |
| Projects and Book Club as one screen | 6 |
| One Library screen | 6 |
| Lesson attachments and linked resources as one | 6 |
| Day notes made one; Schedules feeds Today | 7 |
| Clean up the to-dos | 8 |
| Reminders sync as a setting; doubles fixed | 9 |
| To-dos shared with Tide both ways (not work check-ins); Tide classroom to-dos in the notebook | 10 |
| Remove Ask AI | 1, 11 |
| Six-group sidebar | 11 |

## Phase 1: Removals and one Parsha screen

- Who: `refactor-standard` (Sonnet, high): mostly deletions and one screen merge in an established pattern.
- Steps:
  - **Ask AI**: delete `Chat/` (9 files, ~1,730 lines), `Services/AI/NotebookTools.swift`, `NotebookTools+Meetings.swift`, `ChatToolContext.swift`, `EvidenceSourceCollector`, the chat-only methods (`streamConversation`, `consumeEvidenceSources`, `makeChatSession` in `LocalModelClient`, `AIClientRouter`, `MCPClient`), `AIPrompts.chatAssistant`, `AppRouter.navigateToHistory`, and the chat tests (`Cosmic Daybook Tests/Chat/*`, `Cosmic Daybook Tests/Services/AI/ChatGroundingTests`, `ChatFix1017AI.swift`, `ChatFix1011Q.swift`; trim `MCPClientDispatchTests`). First move `ChatContextAssembler.buildClassroomSnapshot()` into `Services/MCPServer/` and point `MCPNotebookTools+Reads.swift:269` at it. In `RootDetailContent.swift`, route `.askAI` to Today (the alias itself is Phase 11). Remove `.askAI` from `RootAdaptiveTabs.swift:93`'s `pagesWithOwnStack`.
  - **One Parsha screen**: `Parsha/ThisWeeksParshaView.swift` opens on this week and shows the year list (`ParshaCalendarView`'s content) as its index (a toolbar list on iPhone, a side column on Mac/iPad). `Lessons/Parsha/ParshaBrowseView.swift` links to it instead of repeating it. Each sheet pair becomes one: `ParshaLessonEditorSheet`, `ScheduleParshaLessonSheet`, and one parsha lesson row (`ThisWeeksParshaView`'s private `ParshaLessonRow` vs `ParshaLessonListView`'s rows). Lesson counts come from one function. Keep festival-displaced Shabbatot.
  - **Notes opens directly**: in `RootDetailContent.swift` (lines ~147–148), `.notes` shows `ObservationsView` itself instead of `LogsMenuRootView(initialMode: .observations)`, so it stops overwriting Logs' remembered tab. (Done here, not in Phase 2, because it sits next to the `.askAI` line and two branches editing neighboring lines would collide.)
- Cost: ~1–2% (Sonnet; mostly deletions).
- Done when: the notebook scheme builds for macOS and iOS; `-only-testing:` the MCP read-tool suite covering `classroom_snapshot`, the Parsha suites, pass; a grep for every deleted type (`ChatView`, `ChatContextAssembler`, `NotebookTools`, `ChatToolContext`, `EvidenceSourceCollector`, `streamConversation`, `makeChatSession`, `chatAssistant`, `navigateToHistory`) finds nothing outside the moved snapshot builder; Notes opens on observations without changing Logs' saved tab; a new golden test, written against the old code first, pins `classroom_snapshot`'s text over a fixture classroom and still passes after the move.
- Hand off: no (same session as 2, 3, 6, 7, 9).

## Phase 2: Logs folded into the screens it repeats

- Who: `feature-phase` (Opus, high): four screens on both platforms.
- Steps:
  - **Meetings**: a History view in `MeetingsWorkflowView` hosting the meetings log (`Logs/MeetingsLogView.swift`): every child's meetings by day, filters (child, age, done/pending, search), toggle done, delete.
  - **Attendance**: a List view beside the roll on Mac/iPad (and from the iPhone screen's toolbar) hosting the attendance log (`Logs/AttendanceLogView*.swift`) with its date range, status filter and totals.
  - **Lessons & Work**: a History choice in the Presentations half (hosting `LessonAssignmentHistoryView`, all given presentations, paged) and in the Work half (hosting `WorksLogView`, finished work). Both views already take `embeddedSearchText` and a focus ID. Change the empty-state line at `LessonsAndWorkWorkView.swift:288`.
  - Leave `LogsMenuRootView` building (Phase 11 retires its row); drop `UserDefaultsKeys.logsMenuRootViewMode` only when nothing reads it.
- Cost: ~2–3%.
- Done when: notebook builds for macOS and iOS; the Meetings, Attendance, Work and Presentations view-model suites pass `-only-testing:`; an iPad-simulator screenshot of each new view shows the old Logs content in its new home; the Mac look is a Tide row.
- Hand off: no.

## Phase 3: Two levels of readiness, one rule

- Who: `feature-phase` (Opus, high): shared logic that three screens read; a wrong rule misleads every planning screen.
- Steps:
  - One readiness function on `ReadyForNextEngine` (`Planning/Services/`): **Ready** when the previous lesson is confirmed or mastered, no work from it is open, and the last check-in didn't ask for more practice; **Ready, check first** when confirmed but work is open, the last check-in asked for practice, or the last recall check was Shaky (each a plain reason: "2 pieces of work still open", "Last check-in: needs more practice", "Recall check was shaky"); **Not ready yet** when not confirmed. Confirmation is not mastery (project rule); never infer or backfill mastery marks.
  - A **previous lesson** summary any row can show: when it was given, open work count, last check-in result, mastered or not.
  - Groups (`Groups/GroupsView.swift`, `SequenceLadderView.swift`), Today's Ready for next (`TodayViewReadyForNextSection.swift`) and the Checklist's Ready to Present lens use it. The Checklist stops using `BlockingAlgorithmEngine` for unplanned cells; Lessons & Work keeps it for drafts.
  - One "days since last lesson" function replacing the four copies (see Decisions).
- Cost: ~2–3%.
- Done when: notebook builds; new Swift Testing suite pins each level and reason (open work, practice asked, shaky recall, confirmation vs mastery) and the Parsha exclusion in days-since; `-only-testing:` Groups, ReadyForNext, Checklist and days-since suites pass.
- Hand off: no.

## Phase 4: Class grid design on a canvas

- Who: main session with Danny (Opus, high), Design artifact type via the Artifact tool's quickstart.
- Steps: artboards for Mac, iPad and iPhone showing one grid with four views: **Area checklist** (today's Checklist: marks ladder, batch tools, Plan N), **Three years** (the Map's columns by year, chosen/repeated levels, recall rings, All areas / Great Lessons), **By child** (the Progress Dashboard's one-card-per-child sequences), **Recall due** (Lesson Recall's queue and retention summary as a filter). The view switch is a toolbar segmented control on Mac and a `.tabs` picker on iPad/iPhone. Readiness levels from Phase 3 show on cells. Settle the screen's name (working name "Class Grid").
- Cost: ~1–2%.
- Done when: Danny approves the canvas; its URL and the name go into this plan under Decisions.
- Hand off: yes, fresh session for Phase 5.

## Phase 5: Build the class grid

- Who: `feature-phase` (Opus, high), size +50% (four screens, both platforms).
- Steps: build the approved canvas (Decisions › Class Grid) at `.planningChecklist`, reusing `ClassAreaChecklistView`'s tools and one status model and one glyph (retire the duplicate `CurriculumMapEngine`/`ChecklistMatrixBuilder` and `CurriculumCellGlyph`/`ChecklistMark` pairs into one each, keeping the Map's chosen/repeated levels and recall ring). The By child view replaces `ProgressDashboard/` and uses the shared status function (fixed on main as c40fa961, "only a mastery mark is Mastered"). Recall due hosts `Students/Recall/RecallQueueView`'s content. The grid pins its header row and name column per the Apple guidance. The child's own Three-Year View on the student page stays.
- Cost: ~3–5%.
- Done when: notebook builds for macOS and iOS; Checklist, curriculum-map and recall suites pass `-only-testing:` (rewritten where the model merged); scrolling a full area (every lesson × every child) on the iPad simulator stays smooth in the SwiftUI instrument; iPad screenshots of all four views match the canvas; the Mac look and Mac scrolling are a Tide row.
- Hand off: no.

## Phase 6: One Library, Clubs & Projects, one Files section

- Who: `feature-phase` (Opus, high).
- Steps:
  - **Resources screen** (`Resources/`): type filter for Stories, Packets, Files, Procedures; Resources moves onto `Components/PDFLibraryListView` (its own 1.4k-line `ResourceLibraryView*` goes); Procedures listed as written pages that open the existing editor. Keep Stories' AI analysis and covers, packets' reading items, Resources' categories, tags, favorites, lesson/area links and non-PDF files.
  - One import service from `StoryImportService` + `BookClubImportService`; one thumbnail generator; one `*FileStorage` wrapper over `ManagedPDFFileStorage`. Files are found by folder name (`ManagedPDFFileStorage.swift:9`), so every existing folder ("Story Files" and the rest) keeps its name.
  - **Clubs & Projects** (`Projects/ProjectsRootView.swift` becomes the host): Projects and Book Club sessions in one list, each opening its own detail. Book Club's Packets tab moves to Resources.
  - **Lesson Files section**: one section on `LessonDetailView` listing attachments (grouped lesson / sequence / area, via `LessonFileStorage.getAttachments(forLesson:includeInherited:true)`) and linked Resources (rows that open `ResourceDetailView`); `RelatedResourcesSection` goes.
  - One lesson picker for Resources, Going Out and Projects (`ResourceLessonPicker`, Going Out's private `LessonPickerList`, `ProjectLessonPickerSheet`).
- Cost: ~2–4%.
- Done when: notebook builds for both platforms; Stories, Book Club, Resources, Projects and lesson-attachment suites pass `-only-testing:`; importing a PDF as a story and as a packet both still work (the import service tests); a new test opens a story and a packet saved under the old folder names; screenshots of Resources (each filter), Clubs & Projects and a lesson's Files section.
- Hand off: no.

## Phase 7: One day note, today's schedule on Today

- Who: `feature-phase-deep` (Opus, xhigh): a one-time data copy that must be repeatable and lose nothing. An Opus reviewer looks at its diff as it merges.
- Steps:
  - A launch step in `Services/Migrations/MigrationRunner.swift`, after the first iCloud download, that copies each `CDCalendarNote` into the `CDDayPad` for that day (convert year/month/day with `AppCalendar`), writing through `TodayDataFetcher.fetchDayPad`/`savePadText` (`Today/Support/TodayDataFetcher+DayPad.swift`, which joins duplicate pads for a day). It appends only when the pad doesn't already contain the note's text, so a second run, a second device, or a note written later by a device on an older build never adds the same text twice. Old rows stay.
  - `PerpetualCalendar/PlanningCalendarView.swift` and `CalendarNoteEditor.swift` read and write the pad. `TodayRetentionCleanup` must not delete a pad that carries a calendar note's text (it deletes empty pads older than 30 days; keep that rule).
  - The Claude tools follow: the schedule tool (`MCPNotebookTools+Schedule.swift:219`) reads pads; `day_pad` already writes them.
  - A Today section for today's schedule slots (`Schedules/`, `schedule.slots(for:)`), grouped by schedule, shown only when one exists; add `Weekday(date:)` in `Models/Schedule.swift`.
- Cost: ~2–3%.
- Done when: notebook builds; a new migration suite pins copy, append, rerun-is-a-no-op, two devices running it, and a note written later by an older build; Today section-visibility tests updated and passing; backup golden still matches (no format change).
- Hand off: no.

## Phase 8: To-do cleanup with Danny

- Who: main session (Opus, high) with Danny, through the notebook's and Tide's Claude tools; no code.
- Steps: show Danny the list first (from the 2026-10-14 sort: 7 orders, 8 lessons to plan, 4 "watch", 6 stale check-ins, 5 September follow-ups; the ~15 true to-dos stay), then on his yes: orders → Restock's to-order (`add_order_items`), and ask whether to close their Tide Room Setup copies; lessons → planned presentations or year-plan entries (`schedule_presentation`, `update_year_plan_entry`), group moves → Groups; "watch" → Watching; close the stale ones (`update_todo`). Nothing is deleted.
- Cost: ~1%.
- Done when: every one of the 40 open to-dos is either kept, moved (with its new home named), or closed, and Danny has seen the list; `list_todos` shows only the kept ones open.
- Hand off: yes (needs Danny; can run any time before Phase 10's switch is turned on).

## Phase 9: Apple Reminders doubles fixed

- Who: `feature-phase-deep` (Opus, xhigh): reminder rows sync across devices, and the last attempt at this (bug hunt 2026-10-17 #13, keying reminders across devices) doubled every reminder and was backed out (`Plan - Bug hunt 2026-10-17 fixes.md`, "Decided during the run"). An Opus reviewer looks at its diff as it merges.
- Background: backups leave out the Apple Reminders ids on purpose (`ReminderDTO`, `BackupTypes+CalendarAdmin.swift:25`), so a restored reminder has no link, and the next sync inserts a linked copy beside it. `NotebookJunkCleanup.duplicateReminders` already removes existing doubles (Settings' clean-up button). Whether Reminders sync is on for more than one device is an open question in Tide.
- Steps: in `Services/Calendar/EventKitMirror.reconcileReminders`, before inserting a row for a reminder, take over an unlinked row with the same title and due date (set its id) instead of inserting a new one. No external-id matching, no backup or restore change, no new field. `Settings/Sync/ReminderSyncSettingsView.swift`: the picker reads "Show reminders from" with "Off" instead of "None (don't sync)"; turning it off on this device stops observing and drops reminder objects before releasing the store, and leaves the rows and their ids alone (they're shared with other devices). The setting stays per device.
- Cost: ~2–3%.
- Done when: notebook builds; reminder-sync suites pass `-only-testing:`, including new tests for restore-then-sync ending with one row per reminder, two devices syncing the same list, and turning sync off leaving every row in place; backup golden unchanged.
- Hand off: no.

## Phase 10: To-dos shared with Tide

- Who: `feature-phase-deep` (Opus, xhigh), size +50%: a schema field, a two-way link with another app, and first-run matching against existing doubles. An Opus reviewer looks at its diff as it merges.
- Steps:
  - **Schema 19**: optional `tideLink` (String) on `CDTodoItem` in `CosmicDaybook.xcdatamodeld` (edited in place, the project's one model version); `currentSchemaVersion = 19` (`AppCore/Persistence/CoreDataStack+SchemaVersion.swift:121`); update the model-digest test; build the Daybook Assistant too, since it compiles the same model; backup carries the field (the model-driven backup picks it up; bump the golden). Danny deploys schema 19 to Production before rolling out (a Tide row). No schema-19 build runs on the Mac until then (Testing rules).
  - **Connection** (Mac only): Settings › Sync › Tide: paste Tide's connection address once (stored in the keychain); pick the destination list and heading, and which Tide lists show in the notebook (default all of My Classrooms). Plain-English status lines.
  - **Tide client** (`Services/Tide/`, new): a small HTTP JSON-RPC client for Tide's server, reusing the message types in `Services/MCPServer/JSONRPCMessage.swift` (the notebook has no MCP client today; `Services/AI/MCPClient.swift` is the language-model client). When Tide refuses the saved address (its token changed), Settings says so plainly and asks for the new one.
  - **Sync engine** (`Services/Tide/`): compiled for every platform, switched on only on the Mac; everything it calls goes through a protocol so tests inject a fake Tide. Push every open to-do without a `tideLink` and without a linked work item (`add_action`, with `notebook:<uuid>` and the children's names in the note); pull open actions from the chosen lists into `CDTodoItem` rows with `tideLink` set; completion both ways (`complete_action`; `changes_since` with a saved cursor); an action that is dropped, deleted or moved out of the chosen lists closes its notebook copy. The first run matches existing to-dos by words, then shows Danny the matches and waits for his OK before linking or pushing anything. Runs when the notebook opens, when a to-do changes, and every few minutes while Tide is reachable; nothing runs on iPhone/iPad.
  - **Screens**: Todos gets a "From Tide" grouping by Tide list; a student's page shows Tide to-dos that name the child (full name or short form; ambiguous first names don't match); Today shows Tide to-dos due today with the rest.
- Cost: ~4–6%.
- Done when: notebook builds for both platforms; a new sync suite against a fake Tide (pins push, pull, both-way completion, no-push for work check-ins, first-run matching shown before linking, an action dropped in Tide closing its notebook copy, a changed token, crash-mid-push recovery by the note's uuid, reworded-in-Tide re-match, name matching with two Ettys) passes on the iOS simulator; the model-digest test and an Assistant build pass; backup golden updated; one live round trip on Danny's Mac with Tide open is a Tide row for Danny (the test host opens the live store, so agents never run the Mac app against it).
- Hand off: yes (fresh session; after Phase 8 for turning the switch on).

## Phase 11: Six-group sidebar and retired destinations

- Who: main session (Opus, high): one table, its tests and the manual, after every screen exists.
- Steps: `AppCore/RootView/RootView+NavigationGroup.swift` gets the six groups (table under Decisions; Classroom starts closed, Library open). `RootView+NavigationItem.swift`: alias `.logs` → `.notes`, `.curriculumMap`/`.progressDashboard`/`.lessonRecall` → `.planningChecklist`, `.parshaCalendar` → `.thisWeeksParsha`, `.stories`/`.procedures` → `.resourceLibrary`, `.bookClub` → `.planningProjects`, `.askAI` → `.today`; display names for Class Grid, Resources, Clubs & Projects; `init(fromLegacyTab:)` maps `.logs` to `.notes`. An aliased destination opens on its view or filter (pass the intent through the restorer). `RootDetailContent.swift` routes aliases through `.canonical`. `NotebookCommands.swift:99–118` Go menu matches. `NavigationGroupTests.swift`: group order, expansion defaults, alias rows in the saved-item test, Settings still last; `allCases.count` stays 34. Every retired item restores to a visible tab on iPhone (iOS 27 SDK rule). `Documentation/Manuals/UserManual.md`: the group table (lines ~39–43), drop the AI Assistant chapter (~743–772) and the AI / Chat settings section (~838), add Class Grid, Resources, Clubs & Projects, the History and List views, readiness levels and Tide sharing.
- Cost: ~1%.
- Done when: `NavigationGroupTests` pass; every retired raw value restores to the right screen and view (test per alias); manual updated.
- Hand off: no.

## Phase 12: Combine, full build, whole suite, review, land

- Who: main session (Opus, high) plus an Opus reviewer over the combined diff (Phases 7, 9 and 10 were already reviewed as they merged).
- Steps: merge the phase branches one at a time; one full-app build (macOS and iOS); one whole-suite run on the leased simulator (`-parallel-testing-enabled NO`, one simulator); the reviewer looks for lost features, data loss in Phases 7, 9 and 10, and plain-English text; fix what holds up; squash to main via close-out. Device checks and the schema 19 Production deploy become Tide rows in `Areas/App Development/Cosmic Daybook/To do.md`.
- Cost: ~3–5%.
- Done when: full build and whole suite pass; review findings fixed or answered; main pushed; this plan's status line set by close-out; `docs-index --check` passes.
- Hand off: no.

## Starting a phase

Read the plan usage (`get_usage`) and note the weekly % used next to the phase under Progress ("started at N%").

## Ending a phase

1. Check every "Done when" item for the phase.
2. Tick the phase under Progress and note anything that differed from the plan. Read the plan usage again and note the actual cost (end % minus start %).
3. Add a row to the log in `~/.claude/skills/plan-efficiently/references/cost-estimates.md`.
4. Update the build board (https://claude.ai/artifact/WAKaFZGNPQsfKD4A5GbqsM) and run `~/.claude/bin/board-touch <url>`.
5. Make every "not verified", "for your review" or "check on a device" item from this phase a row in Tide (`Areas/App Development/Cosmic Daybook/To do.md`, `add_action`), skipping ones already there. The repo line keeps one plain sentence plus the row's `tide://` link.
6. Run /close-out. It sets this plan's status line and runs `docs-index`.
7. If the next phase is a fresh session, print its starter prompt: "Model: <from its Who line>" on the first line, then "In /Users/dannydeberry/Developer/Maria's Notebook, read docs/Plans/Plan - Simplify the app.md and do Phase <N>. Follow its Starting a phase and Ending a phase steps."

## Open questions

- Whether to close the Tide Room Setup copies of the 7 orders once they're in Restock (Phase 8, asked with the cleanup list).
- Whether Apple Reminders sync is on for more than one device (already a question in Tide; Phase 9's tests cover both cases either way).
