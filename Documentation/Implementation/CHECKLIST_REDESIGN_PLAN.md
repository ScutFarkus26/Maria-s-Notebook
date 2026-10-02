# Checklist redesign

Planning › Checklist (`ClassAreaChecklistView`): the lesson × student grid for one curriculum area.
Mockups: canvas https://claude.ai/artifact/P8ZL7mvh3YvBEybm46Vvpe (boards: Before, After, After — Ready lens,
Status marks, cell detail, multi-select). Approved by Danny 2026-10-02 ("go with your recommendations, build
all five phases"). Branch `claude/checklist-view-analysis-5d42f6`, one commit per phase, nothing merged to
main until Danny has looked.

## Decisions (Danny, 2026-10-02)

1. **Green means a mastery mark.** A cell is Mastered when the child's `CDLessonPresentation` for the lesson
   is `.proficient` or has `masteredAt` set (`PresentationRecordIndex.given(...).mastered` reads the same
   thing). Closed practice work without a mark shows as **Reviewing** (◕), not Mastered. The Mastered action
   already writes the mark *and* closes the work (`markCompleteNoRecompute`,
   `ChecklistBatchActionExecutor.upsertLessonPresentation`); only the display changes. Never backfill marks.
2. **A click opens the cell card** (Phase 4). Until Phase 4 lands, the click keeps today's behavior.
   Add to Inbox becomes a button inside the card.
3. **Devices.** Mac and iPad (regular width) get everything. iPhone (compact width) gets the new marks,
   the legend and the cell card; it keeps its current header, 120-pt columns and no hover.

## The status ladder (Phase 2 onward)

One mark per cell that fills as the child goes. Blue = started, green = done, orange = act on it.

| State | Mark | Source |
|---|---|---|
| Not yet ready | 4–5 pt grey dot | not presented, `blockingReason != .none` |
| Ready | grey ring | not presented, not planned, `blockingReason == .none` |
| Planned | dashed orange ring | `isScheduled` (Inbox or dated plan) |
| Presented | blue ring, ¼ filled | `isPresented` |
| Practicing | ½ filled | open practice work |
| Reviewing | ¾ filled | work in review, or closed without a mastery mark |
| Mastered | solid green with white check | mastery mark (decision 1) |
| Needs a check-in | small amber dot on the mark | `isStale` |

The blocking reason (prerequisite / practice / confirmation) moves out of the cell into the hover text
(`.help`) and the VoiceOver value. Selection is an ink (primary-color) outline, never accent blue.
No hard-coded `Color.white`: use system backgrounds so dark mode works.

## Phases

### Phase 1 — Speed (no visible change)
- A click recomputes only the touched lesson's row and the rows whose preceding lesson it is
  (`BlockingAlgorithmEngine.buildNextLessonCache` / `buildPrecedingLessonCache`), fetching only those
  lessons' assignments, work and presentation rows. Full rebuild stays for area load, filters that need
  it, sheet dismissal and batch actions (batch may also go incremental over the touched lessons).
- `ChecklistMatrixBuilder.buildMatrix`: index assignments and work by (lessonID, studentKey) once instead
  of filtering each lesson's list per cell.
- `StickyLeftItem`: one scroll-offset reading per scroll view (`onScrollGeometryChange`) shared with every
  sticky cell through the environment, instead of `onGeometryChange` + `@State` + shadow in every row.
  Also used by `ClassCurriculumMapView` and `StudentCurriculumGrid`: update all three.
- `ClassChecklistSmartCell`: stop passing six closures per cell. Equatable inputs + one action handler
  (environment or a single `(CellAction) -> Void` owned by the grid) so unchanged cells skip redraws.
- `os_signpost` interval around a cell click (tap → matrix updated) using the project's existing signposter.
- Tests: incremental update produces exactly the matrix a full rebuild produces (present, plan, master,
  clear; for a lesson in the middle of a sequence so the next row's blocking changes).

### Phase 2 — Marks, legend, mastery display
- New `ChecklistMark` view (ladder above); `ChecklistDisplayStatus` gains `.ready`/`.notReady` or the cell
  derives them from `blockingReason`. Mastered/Reviewing per decision 1 (builder reads presentation rows
  — prefer `PresentationRecordIndex` over a new private fetch).
- Cell: no lock/hourglass/hand badges, no stale tint; `.help` text "Maya S · Division: Dynamic — Ready" /
  "— Not yet: Subtraction: Dynamic not presented"; accessibility value includes the reason; fix the
  accessibility hint (it says "Shows options" but a click toggles the Inbox — make it say what it does).
- Status bar at the bottom of the grid: legend with live counts over the visible rows × visible students.
- Remote changes: since Phase 1 a click no longer rebuilds the whole grid, so edits synced from another device
  only appear on the next full rebuild. If the app already has a remote-change / sync-applied notification
  that other screens observe, refresh the matrix on it (debounced ~1 s, only while the checklist is on screen).
- Tests: display-status derivation for every ladder state, including closed-work-without-mark = Reviewing.

### Phase 3 — Layout (Mac + iPad; iPhone keeps its header)
- Toolbar: area as a title menu ("Checklist · Math ▾"), a "Jump to sequence" menu, search moved into the
  toolbar, student filter as a toolbar menu ("All 22"). The `ChecklistFilterBar` row goes away on regular
  width (keep the chips row only while a student filter is on, or show it in the menu). Keep the Select
  button until Phase 4 replaces it.
- Columns 38 pt with names angled −55°, grouped by level with `AttendanceLevelGroups` (its order: Upper,
  Adolescent, Lower; birthday order inside each block), a level band above the names, a heavier rule
  between blocks. Age moves to the header's `.help`. Header click still opens the student.
- Lesson column ~268 pt, one line, ellipsized; a section's name is dropped from the front of its lessons'
  names for display ("Stamp Game: Static Addition" under Stamp Game → "Static Addition").
- Class column on the right of every lesson row: a 48-pt bar (green mastered, blue in progress, orange
  planned) + "17/22" over visible students.
- Sequence bands get a disclosure chevron + lesson count; collapsed state persisted per area
  (UserDefaultsKeys; check whether a test pins the key list / backup prefs list and update it).
  "Collapse all / Expand all" in the corner cell. Section rows become a light 24-pt caption, no tint.
- Rows 30 pt in regular width. Accent blue is no longer used for bands.
- The floating + / pie-menu button must not cover the grid on this screen: give the checklist its own bottom
  inset / status bar. Do NOT edit `AppCore/RootView*.swift`, `QuickNoteGlassButton` or any Commands file — the
  Today-redesign session (branch claude/today-view-analysis-275c3c) owns those.

### Phase 4 — Cell card, keyboard, hover, selection
- Click a cell → popover card: title (lesson), "Maya S · Stamp Game · age 9", a status line (Ready /
  Not yet + reason / Presented on <date>), the five ladder steps as buttons (Planned, Presented,
  Practicing, Reviewing, Mastered — map to existing actions; Practicing = open/assign work), buttons:
  "Present with N others ready…" (opens the present-a-lesson sheet / `PresentationSession` flow prefilled
  with this child + the other ready children for the lesson; just "Present…" when N = 0), Add to Inbox
  (or Remove from Inbox), Assign work, links Open lesson / Open student. Clear lives in the card too.
- Keys on a focused cell (Mac/iPad hardware keyboard): arrows move, Return/Space opens the card,
  P presented, M mastered, I Inbox toggle, Delete clear. ⌘Z undo if the context's undo manager allows it
  cheaply; otherwise skip and note it.
- Hover (pointer): highlight the row and column under the pointer, name cell + header emphasized.
- Selection without a mode: ⌘-click toggles, Shift-click extends along a row/column, drag across a row or
  down a column, and a "Select ready" button on a lesson's name on hover. Floating action bar at the
  bottom when ≥1 selected: "N selected", Present as a group… (same lesson only), Presented, Mastered,
  Add to Inbox, More (Previously Presented, Add Work, Clear), ✕. Remove the Select button and
  `isEditModeActive` on regular width; iPhone keeps long-press → Select from the context menu.
- The context menu stays (it is the iPhone path and an accessibility path).

- Carry-over from Phase 3 review: in an 1180-pt iPad window (268 + 22×38 + 116 = 1220 pt) the Class column is
  cut off at the right edge. Make it fit: let the lesson column shrink toward ~200 pt when the grid is
  narrower than its natural width (or pin the Class column at the trailing edge), so a full 22-student
  class plus Class fits at 1180 pt. Re-render the iPad screenshot to confirm.

### Phase 5 — Ready lens
- Segmented "All marks / Ready to present (N)" in the toolbar (iPhone: a menu item).
- Ready lens: ready cells get a tinted tile + blue ring, all other marks drop to ~20% opacity, rows with
  nothing ready grey their names, and the Class column shows "5 ready" + a Plan button that opens the
  present / plan flow for exactly those children. Status bar hint explains the rule.
- Ready = not presented, not planned, `blockingReason == .none` (same rule as the cell's Ready mark).
- Tests: ready set for first lesson of a sequence, after a gap, with practice/confirmation gates.

## Data fixes (live notebook — only when Danny says so, after a backup)
- File Math › Preliminary lessons 4–10 (Stamp Game Addition: Dynamic … Division: Dynamic) under section
  "Stamp Game".
- Give Math › Rehab "Work with the Golden Beads" (#1) a section so it sorts first.

## Rules for whoever builds this
- Shared files: another session is redesigning Today. Keep out of `Today/`, `Todos/`, `AppCore/RootView*.swift`,
  Commands files and the MCP tools. A new UserDefaults key goes as one line at the end of `UserDefaultsKeys.swift`.
  The checklist's keys are plain keys scoped to the focused grid; no ⌘ shortcuts, no menu commands.
- Build through `Scripts/locked_xcodebuild.sh` (recipes in `Cosmic Daybook/CLAUDE.md`), iOS Simulator
  destination for tests: **never** run the macOS test destination or launch a Debug Mac build — both open
  Danny's live store. macOS gets a compile-only `build` (`-destination "platform=macOS"`).
- `-only-testing:` for the suites a phase touches; the whole iOS suite once at the end.
- Swift Testing, tests under `Cosmic Daybook Tests/Planning/`. Watch for vacuous `#expect` on optional
  chains.
- Main-actor-default module: Core Data types and their extensions are `nonisolated`; see CLAUDE.md.
- Extensions in their own `<Type>+<Topic>.swift` files; previews hoisted into a private struct.
- American spelling. Commit messages match the log's style (plain sentence title), ending with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- After each phase tick it below and note anything deferred.

## Picking this up in a new session
Read this file, then `git log --oneline main..HEAD` in the worktree. Each remaining phase was run as ONE
background general-purpose agent working directly in this worktree (no `isolation`), briefed with: read
this plan + `Cosmic Daybook/CLAUDE.md` + the earlier phases' commits; do only phase N; build via
`Scripts/locked_xcodebuild.sh` with the worktree recipe; iOS-Simulator-only tests with `-only-testing:`;
compile macOS once; render the iPad layout with a throwaway hosting-window test, look at the PNG, delete
the test, save PNGs under the session scratchpad; tick the phase here; one commit with the
`Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` trailer; reply under 300 words.
Phase 3 screenshots (iPad, 1180×820): the grid matches the canvas; only the Class-column clipping above
was wrong.

## Status
- [x] Phase 1 — Speed. Batch actions still rebuild the whole grid. A click no longer refreshes rows it
  can't reach, so changes synced in from elsewhere show up on the next full rebuild (area switch, return
  to the screen), not on any click as before. Signposts: "Checklist" category, "Cell action" interval.
- [x] Phase 2 — Marks, legend, mastery display. Marks read in one extra scoped fetch
  (`PresentationRecordIndex.masteryMarks`), not a full scoped index. Remote refresh listens to the
  import signal for LessonAssignment, Lesson, Student and WorkModel; `LessonPresentation` isn't in
  `presentationEntityNames`, so a synced mark with no assignment or work change waits for the next full
  rebuild. Mastered's check is drawn in the window background color (dark on green in dark mode).
- [x] Phase 3 — Layout. Mac title is a navigation-area menu "Checklist · Math" with the plain title
  removed (no title menu outside document windows); iPad uses `toolbarTitleMenu`. Mac UI not seen (compiled
  only; iPad rendered). Bands are open while a search is on. The iPhone also gets the neutral bands with
  chevrons and the section-stripped names; it keeps its header, filter bar and 120-pt columns. The Class
  column scrolls with the grid (not pinned). `Checklist.collapsedSequences` is in backups.
- [x] Phase 4 — Cell card, keyboard, hover, selection. The card is the cell's popover (a sheet on the
  iPhone); its five steps only move a child up (a reached rung is shown done; Clear goes back), Practicing
  and Reviewing present first and then open or move her work. "Present…" makes a fresh draft for the child
  plus the others ready and opens `PresentationDetailView`; a draft closed without recording or scheduling
  is discarded, and recording releases the children from their other plans (the sheet's own rule). The
  keys also work inside the open card. ⌘Z skipped: the view context has no undo manager and Core Data
  undo after a save would need the snapshot work `ImmediatePresentationRecordingService` does. Drag to
  select is Mac only (a touch drag on the iPad scrolls); the iPad reads ⌘/Shift from a hardware keyboard
  via GameController, untested on a device. A plain click with a selection drops it and opens the card.
  The lesson column narrows to fit the window (min 200 pt), so 22 children + Class fit 1180 pt with a
  228-pt column (the corner then drops "· 3 sequences"). iPad grid, card and selection bar rendered at
  1180×820; the popover in place, hover and keys were not exercised in a UI run, and the Mac UI was not
  seen (compiled only).
- [x] Phase 5 — Ready lens. The lens isn't remembered (no new key): the grid opens on All Marks. Its count and
  each row's "5 ready" count the visible rows × visible children, so the student filter and search move them.
  Plan makes a draft for exactly the row's ready children and opens the same present-a-lesson sheet as the
  card (`makeReadyDraft` → `makePresentationDraft`; unused drafts are discarded as before). The status bar
  leads with the rule instead of ending with it (the trailing end sits under the floating button), and its
  key fades with the grid. The iPhone has no Class column, so its rows get a "Plan 5" button by the lesson
  name; the lens itself is a menu in its header. iPad rendered at 1180×820 (both lenses, Ready in dark mode)
  and the iPhone's Ready lens; Mac UI not seen (compiled only).
- [x] Full iOS suite + macOS build + iPad screenshots. Full iOS suite 2,341/2,342: the one failure,
  `TodayEngineTests/changeGate`, is Today's timing-flaky test and passes alone (3/3). macOS compile-only build
  succeeded with no warnings in checklist files. The status bar now puts the Ready lens's rule on its own line
  above the key, wrapping where the window is narrow: at 1180 pt the rule had pushed Mastered and Needs a
  check-in off the right edge, and on the iPhone the rule ran off the screen and hid the key (supersedes
  Phase 5's "leads with the rule"). After the fix the checklist suites passed (75/75, iOS Simulator), and
  iPad screenshots were taken at 1180×820 with 22 children in three level blocks: All Marks, Ready lens light and
  dark, the card's popover over the grid, and the selection bar. The iPhone's Ready lens was also rendered. All
  fit with nothing clipped.
- [x] Data fixes — done 2026-10-02 over MCP after a manual backup (ManualBackup-2026-10-02T17:42:55.922Z).
