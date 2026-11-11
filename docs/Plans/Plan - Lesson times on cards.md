# Lesson times on cards

> **Not started.** Written 2026-11-10. Came from four mockups of the Scheduled pane (canvas: https://claude.ai/artifact/4VuGazqBbJWkXGuGxuqom8); Danny picked idea A, "a time on the card".
> In short: a scheduled lesson can be given a start time from a chip on its card, and the time stays with it, shows on its sheet and on Today, and survives moves.

## Goal

In Lessons & Work, every card in the Scheduled pane gets a small time chip. A lesson with no time shows a dashed "Set time" chip; clicking it opens a small picker with quarter-hour buttons (8:45–11:00 and 1:00–3:15), a field for any other time, and "Remove Time". A lesson with a time shows it ("10:00"), sorts to the top of its half of the day in time order, and keeps that time when it is dragged to another day, moved forward, or pushed to tomorrow from Today. The lesson's own sheet gets the same control, and Today's lesson list shows the time and leads with timed lessons. Start time only: lessons still have no length, and nothing changes in the iCloud data layout, so there is nothing to deploy.

## Progress

Marks: `plan/lesson-times` (each phase tags the primary checkout `plan/lesson-times/phase-<N>` when it merges; see `~/.claude/bin/plan-wait`)
Primary checkout: `/Users/dannydeberry/Developer/Maria's Notebook`
Build board: https://claude.ai/artifact/WAKaFZGNPQsfKD4A5GbqsM

- [ ] Phase 1: The rules for a set time · runs as: session · needs: — · est. $18–32 (~1%)
- [ ] Phase 2: The picker itself · runs as: session · needs: — · est. $8–16 (~1%) ← 1 and 2 run at the same time
- [ ] Phase 3: The chip on Scheduled cards · runs as: session · needs: 1, 2 · est. $12–25 (~1%)
- [ ] Phase 4: The lesson's sheet and Today · runs as: session · needs: 1, 2 · est. $10–20 (~1%) ← 3 and 4 run at the same time
- [ ] Phase 5: Final check · runs as: session · needs: 3, 4 · est. $10–22 (~1%)

## Cost

About $75–145 at list prices, which is 3–6% of the weekly limit at this week's rate ($22.58 for 1%, measured 2026-11-10): five phase sessions on Opus 5.5 ($58–115) plus the conductor on Fable 5.2 with planning and the review ($17–30, about 2–4% of Fable's own window). On 2026-11-10 the week stood at 66% used with 34% left until Fri Nov 13, 11:59 AM EST, and Fable's window at 29%. Fits. The phase sizes come from the four Cosmic Daybook phase sessions in the cost log ($11–16 each); Phase 1 is sized above them because it touches about fourteen files.

## Before you go

- **Permission mode:** the conductor is already in bypass mode, so phase sessions won't stop to ask. Nothing to do.
- **Screen lock:** the Mac locks as soon as the display sleeps, which blinds any tapping on the Mac or a simulator. So nothing in this plan is driven by hand overnight: each phase draws pictures of the real views without a screen, and the things only a finger can prove (below) become rows in Tide under Check on a device.
- **Keep the Mac awake:** the app's keep-awake switches are on and the Mac is plugged in. Leave the lid open; a closed lid still sleeps.
- **Nothing to deploy:** no iCloud schema change, no backup format change, no upload. The run ends with everything merged into local main, not pushed and not rolled out.
- **Check on a device, in the morning** (each phase adds its own rows to Tide):
  - On the Mac and the iPad, clicking the chip opens the picker and doesn't start a drag; dragging the card by the rest of it still works.
  - On the iPhone, the picker comes up as a half-height sheet.
  - Dragging a timed card to another day keeps its time.
- **When you roll it out, update every device together.** A device still on the old build reads a lesson set for exactly 9:00 or 2:00 as an ordinary morning or afternoon lesson, and dragging or balancing that day there erases that time.

## Decisions

1. **Start time only, no length** (Danny, 2026-11-10). The card reads "10:00". Ruled out for now: a length ("10:00 – 10:20"), because it needs a new field in the iCloud data (schema 25, a new backup format, a Deploy in CloudKit Console). It can be added later without redoing this.
2. **Where the time shows** (Danny): the Scheduled cards, the lesson's own sheet, and Today's lesson list. The Schedules page and the Assistant's Schedule tab already show set times and are not changed.
3. **Quick times** (Danny): every quarter hour from 8:45 to 11:00 and from 1:00 to 3:15, ten buttons each, shown as two labelled groups (Morning, Afternoon) in one picker whatever half the card is in. Picking a time in the other half moves the lesson there. The hours live in one place in code (`LessonTimeChoices`); a setting for them was ruled out as scope nobody asked for.
4. **How a set time is stored: in `scheduledFor`, as today, with one marker.** No new field. Today `DayHalfPlanner.moment` reads any `9:00:xx` or `14:00:xx` as an ordering slot (the seconds are the rank), so a lesson set for exactly 9:00 or 2:00 forgets its time, and a slot dragged under a timed lesson is stored one second after it and would read as a time. The new reading:
   - midnight → morning slot (unchanged);
   - base hour (9 or 14), minute 0, second 0–58 → a slot in that half (unchanged);
   - base hour, minute 0, second 59 → a set time of exactly that hour (the marker);
   - any other time with second 0 → a set time;
   - any other time with seconds ≠ 0 → a slot in that half (an old "pushed below a timed lesson" value).
   The rule lives in pure functions on dates in `DayHalfPlanner` (`settingTime(hour:minute:on:)`, `removingTime(from:)`, `rebasing(_:onto:)`), because the lesson's sheet edits a plain date and saves it later. `CDLessonAssignment.setTime` and `removeTime` wrap them. Every place that sets a time goes through them, MCP's `time:` included; the picker hands back an hour and a minute, never a date, so stray seconds can't ride along. `removingTime` puts a lesson at the last slot of its half (second 58); the next reorder renumbers it. Slot ranks stop at 58. Ruled out: a "has a time" field (a schema change, against decision 1); storing times in a separate synced preference (a second source of truth).
   Checked in review: spacing has always been one second, backups keep seconds, Move All Forward keeps them, and Schedules and the Assistant read only the hour and minute, so stored data reads correctly under the new rule.
5. **A time stays with the lesson until Danny changes or removes it.** A drag never changes a time: a timed card dropped on another day keeps its clock time and its own half there, wherever in the column it was dropped. Also kept: Move All Forward (already), Today's "Tomorrow" and the absent-children move, renumbering when other cards move, Balance AM/PM (timed lessons are never moved by it), and MCP's `reschedule_presentation` with a new day and no `time:`. Removed only by: "Remove Time", Clear Schedule, choosing the other half in Half of Day (the right-click menu or the sheet, because 10:00 can't be in the afternoon), and MCP's `time: "none"`. This also fixes a present bug where the sheet's Morning/Afternoon choice turns 10:30 into 2:30.
6. **Order inside a half:** lessons with a time first, in time order; then the rest in the order Danny dragged them, under a thin "Any time" divider that appears only when a half has both kinds. A timed card can't be reordered by hand within its day (its time decides). Slots always count from the half's base hour and no longer "count on" from a timed lesson above them. A drop and its insertion bar place a card among the untimed cards only: the bar never draws between two timed cards. The same order is used wherever lessons of a day are listed: the strip, `TodayDataFetcher.fetchLessons` (which feeds Today, MCP's `schedule_for_range` and Schedules), and MCP reads.
7. **Clash warnings.** "Two lessons in one half" (a child twice in one half) stays exactly as it is. New: two lessons on one day set for the same start time get an amber chip and count in the day's clash badge as "Two lessons at the same time", whoever the children are, because Danny can give only one. In the picker, a quick time that already has a lesson that day is dimmed with a dot but can still be picked. Ruled out: striking it through and disabling it (a deliberate double-booking is rare but real, and the warning covers it).
8. **The picker applies as you go.** Picking a quick time sets it and closes the picker; the "Another time" field applies on change. No Done button on the Mac or iPad (Apple: a popover saves its work when it closes). On the iPhone the picker is a half-height sheet with Done.
9. **Today.** Each lesson row shows its time. Timed lessons lead the Lessons list in time order and can't be dragged; rows without a time keep the order they have now (the hand order where one was saved) beneath them.
10. **Words.** Chip with no time: "Set time". Menu items on a card: "Set Time…" or "Change Time…", and "Remove Time". Divider: "Any time". Legend: "Two lessons at the same time". VoiceOver: the card is one combined element, so its spoken label gains the time ("at 10:00 AM") and it gets a custom action "Set Time" or "Change Time", the way "work to show first" already does; the chip itself is not a separate stop.
11. **Against Apple's guidance, on purpose:** none. Where the Human Interface Guidelines advise against a popover on the iPhone, we use a sheet there.

## Apple guidance

Checked 2026-11-10 against Xcode 27.2 (27B52), iOS 27.2 and macOS 27.2 SDKs; targets are iOS 27.0 and macOS 27.0. A 27.3 beta exists; its notes change nothing here.

- **Time field.** SwiftUI's `DatePicker` has no minute-step option (none in the SDK; only UIKit's `minuteInterval`). Styles from the SDK: `.field` and `.stepperField` are Mac only, `.wheel` is iOS only, `.compact` is both. Use `.stepperField` on the Mac and `.wheel` on iOS and iPadOS behind `#if os(macOS)`. Avoid `.compact` inside the popover: it opens a second popover, and the HIG says never to stack them ([Pickers](https://developer.apple.com/design/human-interface-guidelines/pickers), [Popovers](https://developer.apple.com/design/human-interface-guidelines/popovers), both dated 2026-08-06). The Pickers page also suggests quarter-hour steps, which is what the quick buttons are.
- **Popover.** `popover(item:attachmentAnchor:arrowEdge:content:)` attached to the chip itself with a stable id (cards sit in a lazy container, so don't hang it on the grid). On the iPhone let it become a sheet; don't force `presentationCompactAdaptation(.popover)`. Give the content a fixed width. Popovers take Liquid Glass on their own: add no custom background.
- **iOS 27 release note 167448274.** Inside a popover `controlSize`, `buttonSizing` and `ButtonBorderShape` reset to defaults for apps built with the 27 SDKs. Set them again on the picker's content.
- **Buttons inside a draggable card.** Apple documents no conflict; forum reports (threads 841926, 653297) say taps on buttons in a horizontal scroll view misbehaved in an iOS 27 beta and were fixed. Not provable without a finger: it is a Check on a device row.
- **Time text.** `Date.FormatStyle` with `.dateTime.hour().minute()` follows the 12/24-hour setting. Don't use `Text(timerInterval:)` (a live countdown).
- **Accessibility.** Don't put "button" in a label; a short hint says what happens ([accessibilityHint](https://developer.apple.com/documentation/swiftui/view/accessibilityhint(_:))). A dimmed quick time needs `accessibilityValue("Already has a lesson")` so it isn't visual only. Hit area at least 28 pt on iOS and 20 pt on the Mac: pad the chip with `contentShape`. Dragging needs another way to do the same thing: the right-click menu's time items and Half of Day are that.
- **Gaps.** The HIG's date-picker and Liquid Glass pages could not be fetched, so nothing above rests on them.

## Phase 1: The rules for a set time

- Who: phase session (Opus 5.5, high). It rewrites how a stored moment is read, which every screen and tool that shows a schedule depends on, so it ends with a cold review by a subagent before merging. No views in this phase.
- Needs: —
- Steps (paths under `Cosmic Daybook/`; this phase must not create or edit `LessonTimeChoices.swift`, `LessonTimePicker.swift` or `LessonTimeText.swift`, which are Phase 2's):
  - `Presentations/Planning/DayHalfPlanner.swift`: `moment(of:)` reads seconds as in decision 4; add `settingTime(hour:minute:on:)`, `removingTime(from:)` and `rebasing(_:onto:)` (a set time moved to another day, same clock time, set on the clock so daylight-saving Sundays are right); `keptTime` follows the new reading; `times(for:on:using:spacingSeconds:)` always counts slots from the base hour, never past second 58, never "counts on" from a kept time, and returns a kept time re-based onto `day` (today it returns it verbatim, old day included, about lines 193–196). `inheritedPeriod` is not used for a timed card. Add `sameTimeClashes(in:)`: ids of a day's lessons that share a start minute with another (decision 7). Rewrite the header comment (it says a presentation has no time).
  - `Models/LessonAssignmentEntity.swift`: `setTime(hour:minute:using:)`, `removeTime(using:)` and `schedule(onDay:keepingTimeUsing:)` (new day, same set time; a slot stays a slot), all wrapping the pure functions.
  - `Presentations/Planning/LessonAssignmentOrdering.swift`: the shared order for a day: morning before afternoon; inside a half, timed first by clock time, then slots by rank, then the existing tie-breaks (decision 6).
  - `Today/Support/TodayDataFetcher.swift` (`fetchLessons`, about lines 102–114): sort with the shared order. Fix the stale comment at `Schedules/Services/ScheduleLessonPlan.swift` lines 28–30.
  - `Presentations/Planning/WeekDayColumnDropDelegate.swift`: pull the private `placements` (about line 196) out as a pure, testable function; a dragged timed card keeps its time and half on any drop (decision 5), an untimed one behaves as now. `WeekDayColumn+DayHalf.swift` (`move`, about line 35): choosing the other half removes the time (as now); choosing the same half changes nothing.
  - `Presentations/Planning/DayBalanceService.swift`, `DayHalfBalancer.swift`: Balance never moves a timed lesson; it still counts it where it is.
  - `Today/Views/Sections/TodayViewAgendaSection.swift` (about line 199) and `Today/Support/TodayAbsentMover.swift` (about line 176): "Tomorrow" and the absent move keep a set time (`schedule(onDay:keepingTimeUsing:)`). `Presentations/Overview/ReadyToPresentSection+Actions.swift` and `Presentations/Planning/CalendarForwardShiftService.swift`: confirm with a test that they still do the right thing; change only if it fails.
  - `Students/Presentations/DayHalfPicker.swift` and wherever it calls `DayPeriod.applied`: switching halves on a set time removes it (`removingTime`, then the other half's slot) instead of carrying its minutes across.
  - `Services/MCPServer/MCPNotebookTools+ScheduleWrites.swift` (about lines 86–100, 167–170, 244–293): `time:` writes through `setTime`, so `09:00` and `14:00` stick; `reschedule_presentation` with a new day and no `time:` keeps a set time; `time: "none"` removes it. Update the tool descriptions and `docs/Technical notes/MCP_SERVER.md`. No new tool, so the registry count doesn't change.
  - Tests: new `Planning/LessonTimeTests.swift`: every row of decision 4's table including 9:00 and 14:00 round trips; a pushed `10:30:01` reading as a slot; the rank-58 cap; re-basing onto another day, including across 2026-11-01 and 2027-03-14; each "kept" and "removed" case of decision 5 through the extracted `placements`, the entity methods and the MCP tools; the shared order; same-time clashes. Update `DayHalfTests`, `WithinDayOrderingTests`, `DayBalanceTests`, `PresentationsFix1011PrTests`, `MCPScheduleToolsTests`, `MCPPendingStudentsToolTests`, `TodayAbsentMoverTests` and `TodayFix1103D` where the old behavior was pinned; say in the final message which expectations changed and why.
  - Before merging: one `general-purpose` subagent (Opus) reads the diff cold, looking for any reader of `scheduledFor` that prints or compares a clock time without going through `moment(of:)`, any writer that sets a time without the new functions, and any sort of a day's lessons that isn't the shared order. Fix what holds up (one round).
- Cost: $18–32, ~1% (about fourteen source files and nine test files, plus one review subagent).
- Done when: the notebook scheme builds for the iOS simulator and for the Mac (build only on the Mac: its test host opens the live notebook); these suites pass with a test count above zero each (name the enclosing type, see the project's notes on nested suites): `LessonTimeTests`, `DayHalfTests`, `WithinDayOrderingTests`, `DayBalanceTests`, `CalendarWorkShiftTests`, `PresentationsFix1011PrTests`, `MCPScheduleToolsTests`, `MCPPendingStudentsToolTests`, `ScheduleBookingPublisherTests`, `TodayAbsentMoverTests`, `TodayFix1103D`.
- By hand: none.

## Phase 2: The picker itself

- Who: phase session (Opus 5.5, high). New files only, with no call sites, so it runs beside Phase 1.
- Needs: —
- Steps (all new, under `Cosmic Daybook/Presentations/Planning/`; this phase edits no existing source file):
  - `LessonTimeChoices.swift`: the two quick-time lists as minutes after midnight (decision 3) and which half a minute falls in (before noon is morning). Pure values.
  - `LessonTimeText.swift`: a set time as text from an hour and minute, following the 12/24-hour setting ("10:00" on a chip, "10:00 AM" spoken), and the sheet's status words ("Wednesday morning at 10:00").
  - `LessonTimePicker.swift`: the picker from mockup A without the length row: lesson title; Morning and Afternoon groups of quick-time buttons (the current time filled, taken times dimmed with a dot); "Another time" (`.stepperField` on the Mac, a row that expands to a `.wheel` on iOS and iPadOS); "Remove Time" when a time is set. Inputs: the current hour and minute or none, the day's taken minutes, and two closures, `set(hour, minute)` and `remove()`. It never sees a `Date` from outside and never touches Core Data. Follow the Apple guidance section (control sizes set again inside the popover, fixed width, no custom background, accessibility values).
  - `LessonTimePickerPresenter.swift`: one view modifier, `lessonTimePicker(item:…)`, that shows the picker as a popover on the Mac and iPad and as a medium-detent sheet with Done on the iPhone (decision 8), so Phases 3 and 4 present it the same way without editing it.
  - Tests in `Cosmic Daybook Tests/Presentations/`: `LessonTimePickerTests.swift` (the lists are exactly 8:45–11:00 and 1:00–3:15 by quarter hours; the half of each; text in a 12-hour and a 24-hour locale; the status words) and a small picture helper, `LessonTimePictures.swift`, that draws a view with `ImageRenderer` and saves a PNG into the folder named by a `TEST_RUNNER_` environment variable (follow `Services/Sync/SyncDotSlotTests.swift`, about line 52). Phases 3 and 4 use the helper and don't edit it.
  - Pictures: the picker in dark and light, with a time set and with none, saved to `docs/Pictures/Lesson times/`.
- Cost: $8–16, ~1% (four new files with a settled design; new SwiftUI surfaces on a settled model cost $5–13 in the log).
- Done when: the notebook scheme builds for the iOS simulator and for the Mac (build only); `LessonTimePickerTests` passes with a count above zero; the four pictures exist and show the two groups of ten buttons.
- By hand: none.

## Phase 3: The chip on Scheduled cards

- Who: phase session (Opus 5.5, high). A screen on top of rules and a picker that already landed.
- Needs: 1, 2
- Steps (paths under `Cosmic Daybook/Presentations/Planning/`):
  - `PresentationPlannerCard.swift` (`titleRow`, about lines 151–172): a time chip at the end of the title row, in the slot of the unused AM/PM badge: filled blue with the time when set, dashed "Set time" with a clock when not, amber when it is in a same-time clash. The chip is a `Button` that presents the picker with `lessonTimePicker(item:)`, anchored to the chip. The card stays one combined accessibility element (about lines 147–149): its label gains the time, and it gets a custom action for the time (decision 10).
  - `WeekDayColumn+Bands.swift`: in `presentationList` (about lines 41–58), inside each half, timed cards, then an "Any time" divider when both kinds exist, then the rest; the card's context menu (about lines 139–146) gains the time items; "Half of Day" stays. The insertion bar (about lines 281–290, and `WeekDayColumn+DayHalf.swift` about lines 94–102) and the drop index work among the untimed cards only (decision 6).
  - `WeekPlanSection.swift` (the sort at about line 351): use the shared order.
  - `WeekDayColumn+Balance.swift`, `WeekDayColumn.swift` (header badge, about line 166), `WeekPlanHeader.swift` (legend, about line 100): same-time clashes count in the day's badge, and the legend gains "Two lessons at the same time".
  - Only this phase may edit `LessonTimePicker.swift` or its presenter, and only if the card needs it.
  - Tests: new `Presentations/LessonTimeChipTests.swift` (the order and divider for mixed halves, the clash state and badge count, the menu's items for timed and untimed cards, the drop index among untimed cards, the card's spoken label); `WeekPlanLayoutTests` still passes.
  - Pictures (with Phase 2's helper) under `docs/Pictures/Lesson times/`: a day's list with timed, untimed and clashing cards, dark and light, at iPad width and at iPhone width. Draw `dayList` (`WeekDayColumn+Bands.swift`, about line 15), not the column: the column's body is a ScrollView, which draws blank.
  - Tide rows (Check on a device): the chip opens the picker and doesn't start a drag on the Mac and iPad; the iPhone sheet; a timed card dragged to another day keeps its time.
- Cost: $12–25, ~1%.
- Done when: the notebook scheme builds for the iOS simulator and for the Mac (build only); `LessonTimeChipTests` and `WeekPlanLayoutTests` pass with counts above zero; the four pictures exist and show the three chip states.
- By hand: none overnight (rows in Tide).

## Phase 4: The lesson's sheet and Today

- Who: phase session (Opus 5.5, high). Two small screens on the same rules; no file in common with Phase 3.
- Needs: 1, 2
- Steps (paths under `Cosmic Daybook/`; this phase must not edit anything under `Presentations/Planning/`):
  - `Students/Presentations/InboxStatusSection.swift` (about lines 44–52): next to the date and the Morning/Afternoon choice, a Time row showing the set time or "None" that presents the picker with `lessonTimePicker(item:)`. The section edits a `Date?` binding that is saved later (`PresentationDetailActions.swift`, about line 53), so set and remove go through `DayHalfPlanner.settingTime` and `removingTime` on that date. `Students/Presentations/PresentationDetailView+PlanningSections.swift` (status line, about line 33): "Wednesday morning at 10:00" when a time is set (`LessonTimeText`). Update the comment in `DayHalfPicker.swift` that says the time is hidden on purpose. If the picker or its presenter needs a change, don't edit them: say so in the final message.
  - Today's Lessons list (`Today/`: the lesson row view, `TodayAgendaBuilder`, `Today/ViewModels/TodayViewModel+Reordering.swift`): each lesson row shows its time; timed lessons lead in time order and can't be dragged (`moveDisabled`); the rest keep their present order beneath (decision 9). A saved hand order must never put an untimed row above a timed one.
  - Tests: new `Today/TodayLessonTimeTests.swift` (order with and without a saved hand order; a move among untimed rows keeps timed rows on top; set and remove through the sheet's date binding, including 9:00); existing Today suites that pin agenda order still pass (find them by `TodayAgendaBuilder`).
  - Pictures (with Phase 2's helper) under `docs/Pictures/Lesson times/`: the sheet's schedule section with a time set, and three Today rows (two timed, one not), dark.
  - Tide rows (Check on a device): setting and removing a time from the sheet on the iPhone; Today's order after setting a time.
- Cost: $10–20, ~1%.
- Done when: the notebook scheme builds for the iOS simulator and for the Mac (build only); `TodayLessonTimeTests` and the existing Today agenda suites pass with counts above zero; the two pictures exist.
- By hand: none overnight (rows in Tide).

## Phase 5: Final check

- Who: phase session (Opus 5.5, high).
- Needs: 3, 4
- Steps:
  - On main with every phase merged: build the notebook for the iOS simulator and the Mac, and the Daybook Assistant scheme for the iOS simulator; run the notebook's whole test suite once on the leased simulator (`-parallel-testing-enabled NO`, one simulator). Fix what fails; the errors name files and the files map to phases.
  - One `general-purpose` subagent (Opus) reviews the merged diffs cold against Decisions 4–10: a time lost or invented on any path, a place that still shows 9:00 or 2:00 for a lesson with no time, a list of a day's lessons in another order, words that aren't plain. One fix round.
  - Docs: `docs/Technical notes/DATA_MODELS.md` and `LESSON_PRESENTATION_WORK_INTEGRATION.md` where they describe `scheduledFor` (add decision 4's table), and `Cosmic Daybook/CLAUDE.md` if it describes the ordering slots. No new doc pages; the manual is not touched.
  - Check every Check on a device row from Phases 3 and 4 is in Tide under Cosmic Daybook › To do, plus one row: "Roll out lesson times to every device together".
- Cost: $10–22, ~1% (a final check that finds little costs $3–11 in the log; the review and a fix round are the rest).
- Done when: all three builds succeed, the whole suite passes (give the count), the review's findings are fixed or listed, and the docs are updated.
- By hand: none.

## Running a phase (phase sessions read this)

You were started by the conductor. Danny accepted this plan and is likely away. Don't ask him anything and don't wait on him. **Don't edit this plan file**: other phases are running beside you, and the conductor writes Progress and Decisions. Everything you'd add goes in your final message.

0. Get your session id: run `echo $CLAUDE_CODE_SESSION_ID` (it isn't filled in for you anywhere else). If your phase needs other phases, wait for them first: run `~/.claude/bin/plan-wait --repo "/Users/dannydeberry/Developer/Maria's Notebook" --prefix plan/lesson-times --needs <their numbers>` with `run_in_background`, and end your turn; you're woken when it exits. On "Go ahead" carry on. On anything else (a needed phase stopped, the run braked, a time-out), stop: mark yourself stopped (step 7) unless the run was braked, and report its line.
0b. Make sure your branch starts from local main, which holds every phase merged so far (nothing is pushed, so `origin/main` is behind): if `git merge-base --is-ancestor main HEAD` fails, run `git merge main`.
1. Read `Cosmic Daybook/CLAUDE.md`, then do the phase's steps, building only its smallest target and running only its `-only-testing:` suites (`~/.claude/CLAUDE.md` › Xcode builds), through `Scripts/locked_xcodebuild.sh`. Test on simulators headless (`xcodebuild test`, `xcrun simctl io <udid> screenshot`), on this checkout's leased simulator. Leave tapping, clicking and screen-driving alone: the screen is locked. List what to check under "By hand" in your final message.
2. If a decision comes up that the plan didn't settle, take the safer option that's easier to undo, add a `Review choices` row in Tide for Danny, and put it under "Decided" in your final message.
3. Check every "Done when" item. Before each fix round, run `~/.claude/bin/plan-cost session`. If one item still fails after two tries, or the phase has cost more than twice the top of its estimate, stop.
4. Make every "not verified", "for your review" or "check on a device" item from this phase a row in the app's list in Tide (`Areas/App Development/Cosmic Daybook/To do.md`, `add_action`), skipping ones already there. Any repo doc line about it keeps one plain sentence plus the row's `tide://` link.
5. Update the build board (`build-board` skill, then `~/.claude/bin/board-touch https://claude.ai/artifact/WAKaFZGNPQsfKD4A5GbqsM`).
6. Merge: read `~/.claude/skills/close-out/SKILL.md` and follow it (it can't be invoked as a skill). Danny's acceptance of the plan is his go-ahead. Make these changes to it:
   - In its step 2, bring the branch up to date with **local** `main` (`git merge main`), not `origin/main`.
   - Right after the squash commit, before releasing the lock, mark the phase merged: `~/.claude/bin/plan-wait --repo "/Users/dannydeberry/Developer/Maria's Notebook" --prefix plan/lesson-times --mark <N>`. Phases waiting on you start from that.
   - Before its step 4, take the merge lock: `~/.claude/bin/plan-merge-lock take "/Users/dannydeberry/Developer/Maria's Notebook"` (run it with `run_in_background` if it says it's waiting). Release it with `plan-merge-lock release "/Users/dannydeberry/Developer/Maria's Notebook"` right after the squash commit, and also if you stop before that commit.
   - Skip its step 4b (the conductor keeps the plan's status and the docs map) and its step 5 (no push).
   - Wherever it says "stop and ask", stop instead: release the lock, don't merge, and report it.
7. If you stopped without merging, mark it so the phases waiting on you stop too (`plan-wait … --mark <N> --stopped`), and shut down your simulators (`~/.claude/bin/sim-lease --done`). close-out releases them otherwise.
8. End with this line first, so the conductor's note shows it: `Phase <N> done (<commit>). Session <your id from step 0>. By hand: <list or none>.`, or `Phase <N> stopped: <plain reason>. Session <id>. Nothing merged.` Then, under it, any "Decided:" items and anything that differed from the plan.

## Open questions

None.
