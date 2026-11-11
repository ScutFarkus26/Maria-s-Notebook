# Co-teacher times when scheduling

> **Not started.** Written 2026-11-11 from Danny's two co-teacher schedules (Morah Devora's kodesh groups and Miss Nicole's Book Club) and two mockups he approved in the planning session.
> In short: when Danny gives a lesson a time, the app shows which of its children are away with a co-teacher then, suggests times when everyone is free, and marks a clashing card; the Schedules sheet gets an end time and a field for typing names.

## Goal

Both co-teachers' weekly groups are already in the live notebook's Schedules page (entered 2026-11-11 over MCP, from Thursday 2026-11-12 on: Morah Devora's 8 kodesh groups on Mon+Wed and Tue+Thu, Miss Nicole's 3 Book Clubs on Mon, Tue and Wed). Today that data only produces a loose "this morning" warning on the Schedules page. After this plan, the time picker on a Scheduled card lists who is away that day and when, marks the quick times that overlap, and offers "Everyone's free" times; a card whose set time overlaps a group turns its chip amber with one line saying who leaves and when; an untimed card gets a quiet note; the day's clash badge counts it; the Schedules page's own warning becomes exact for timed lessons; and MCP's scheduling replies say the same thing. In Schedules, the group sheet shows when a group ends and takes typed or pasted names. Warnings never block anything. No iCloud data change, no backup change, nothing to deploy.

## Progress

Marks: `plan/coteacher-times` (each phase tags the primary checkout `plan/coteacher-times/phase-<N>` when it merges; see `~/.claude/bin/plan-wait`)
Primary checkout: `/Users/dannydeberry/Developer/Maria's Notebook`
Build board: https://claude.ai/artifact/WAKaFZGNPQsfKD4A5GbqsM

- [ ] Phase 1: The rules for who is away · runs as: session · needs: — · est. $8–16 (~1%)
- [ ] Phase 2: The picker shows it · runs as: session · needs: — · est. $5–10 (~0.5%) ← 1, 2 and 4 run at the same time
- [ ] Phase 3: Cards, the day badge and the lesson's sheet · runs as: session · needs: 1, 2 · est. $10–20 (~1%)
- [ ] Phase 4: The Schedules group sheet · runs as: session · needs: — · est. $6–12 (~0.5%)
- [ ] Phase 5: Final check · runs as: session · needs: 3, 4 · est. $8–18 (~1%)

## Cost

About $57–108 at list prices, which is 3–5% of the weekly limit at this week's rate ($22.00 for 1%, measured 2026-11-11): five phase sessions on Opus 5.5 ($37–76) plus the conductor on Fable 5.2 with the mockups, planning and review ($20–32, about 3–4% of Fable's own window). On 2026-11-11 the week stood at 72% used with 28% left until Fri Nov 13, 12:00 PM EST, and Fable's window at 35%. Fits. The phase sizes come from the five Cosmic Daybook lesson-times phases in the cost log ($5–13 each, all on the same files), with their top ends kept because Phase 3 touches both the planner and the sheet.

## Before you go

- **Permission mode:** the conductor is in bypass mode, so phase sessions won't stop to ask. Nothing to do.
- **Screen lock:** the Mac locks as soon as the display sleeps, which blinds tapping on the Mac or a simulator. So nothing here is driven by hand: each phase draws pictures of the real views in a test, and what only a finger can prove becomes a row in Tide under Check on a device.
- **Keep the Mac awake:** the app's keep-awake switches are on (checked 2026-11-11) and the Mac is plugged in. Leave the lid open; a closed lid still sleeps.
- **Nothing to deploy:** no iCloud schema change, no backup format change, no upload. The run ends with everything merged into local main, not pushed and not rolled out. It rides the same roll-out as lesson times (already a Release row in Tide).
- **Local main is ahead of origin** (lesson times is not pushed). Phase sessions start from local main, as that plan's did.

## Decisions

1. **A lesson is treated as 30 minutes long** (Danny, 2026-11-11) when checking for overlap, because lessons have a start time and no length (lesson-times decision 1). One constant, `LessonLength.assumedMinutes`, in `Schedules/Model/TimetableValues.swift` so the notebook and the Assistant's copy of the resolver read the same number. Ruled out for now: a Settings row for it (nobody has needed to change it yet; it is one line to add later), and a real per-lesson length (schema 25, a new backup format and a CloudKit deploy).
2. **The overlap rule.** A lesson starting at minute `s` clashes with a block `[b, e)` when `s < e` and `s + 30 > b`. A group that ends exactly when the lesson starts, or starts exactly when it ends, is not a clash.
3. **Who counts as away.** A child named in a block of a person lane other than Danny's own, on the day as the Schedules page resolves it: Only This Day changes, cancelled blocks, Out Today and no-school days are all respected, because the away list is built from the resolved day. Room blocks and turns in the adolescent room are untouched (their rules stay as they are): a person's turn shows in their lane as an item too, and it must not count.
4. **The picker lists who is away up front.** Picking a quick time sets it and closes the picker (lesson-times decision 8), so a line that appears after a tap, as the mockup had it, would never be read. Instead the picker shows, only when one of the lesson's children is away that day:
   - an **Away** list, one row per group in time order: "9:15–9:45 · Lucy T, Ora P · Miss Nicole";
   - a mark on each quick time whose 30 minutes overlap a group: secondary text plus a small symbol in the top leading corner (the orange "already has a lesson" dot keeps the top trailing corner). The symbol is not `person.slash`, which already means Absent on cards; use `figure.walk.departure` if the SDK has it, else the nearest "leaving" symbol. Marked times stay enabled (dimming a control reads as "can't pick"; Danny may book over a flexible group on purpose);
   - an **Everyone's free** row above the grid: up to four time chips, and "Free all morning" or "Free all afternoon" when a half has no group for these children. A chip sets that time, quarter hour or not.
   With nobody away that day the picker looks exactly as it does now.
5. **What "free" means.** A start, every 5 minutes inside the quick-time hours (8:45–11:00 and 1:00–3:15, from `LessonTimeChoices`), where no child of the lesson is in a group during the next 30 minutes and none of Danny's other timed lessons that day starts within 30 minutes either side. Consecutive free starts form a stretch; a chip is the first start of each stretch, morning first, four at most. A half with no group for these children gets the "Free all…" words and no chips.
6. **Cards.** Short names as the app writes them ("Lucy T").
   - A timed lesson that clashes: the chip takes the existing amber clash style, and one caption line sits under the children, where "work to show first" goes: "Lucy T leaves at 9:50 for Morah Devora" (the group starts during the lesson), "Lucy T is with Morah Devora until 10:20" (already there when it starts), "Lucy T and Ora P are with Miss Nicole until 9:45" (two children, one group), "3 children are away during this lesson" (more than two children or more than one group).
   - An untimed lesson with a child away in its half: a quiet secondary line, no amber: "Lucy T is away 9:50–10:20", "Leora F and Naomi F are away 9:50–10:20", or "2 children are away part of the morning". It is not a clash, since the lesson may be given around the group.
   - The day's badge adds one for each timed lesson with an away clash. A day whose only clashes are of this kind (or same-time ones) shows the plain badge, not Rearrange, because rearranging never moves a timed lesson. The legend gains "A child is with another teacher".
   - This is its own kind of clash, not the same-time one: the chip and the badge only borrow the amber look. The chip's spoken words are "a child is with another teacher then" (never "another lesson at the same time"), and the plain badge's help and spoken label count each kind it holds ("1 lesson at the same time, 2 with a child away").
   - VoiceOver: the card's spoken label gains the line.
7. **The Schedules page's warning becomes exact for timed lessons.** `ScheduleDayResolver.childWarnings` matches by half today. With a set time it uses decision 2 and reads "Lucy T is with Morah Devora 9:50–10:20, during your 9:45 lesson."; a timed lesson that doesn't overlap gets no warning. An untimed lesson keeps the half rule and its "…this morning." wording. Every lesson is checked against every block: today the resolver keeps only a child's first lesson in a half, which would let a clear timed lesson hide a clashing one. This reaches the Schedules Day view and MCP's `weekly_schedules` with a date; the Assistant compiles the resolver and must still build for iOS 18.
8. **MCP.** `schedule_presentation` and `reschedule_presentation` add the same sentences to their replies for the day they schedule ("Lucy T is with Morah Devora 9:50–10:20." for a timed overlap; "Lucy T is away 9:50–10:20 that morning." for an untimed lesson). No new tool, so the registry count stays. Ruled out for now: a "when is everyone free" read tool.
9. **The group sheet (Schedules).** The Length row reads "30 min · ends 10:20", so an entry can be checked against a paper sheet that gives ranges. The Children section gains a field for typing or pasting names ("Lucy, Leora, Naomi"): on a comma or Return each name is matched to an enrolled child and joins the list; a name that matches nobody, or more than one child, stays in the field under a plain line ("Two children are called Sarah. Add a last initial."). Save sorts whatever is still in the field first, and the sheet stays open if a name is left unmatched, so a last name typed without a comma is never dropped. Apple has no token field on iPhone or iPad and none in SwiftUI outside search, so this is a plain text field over the existing list of chosen children, with Choose Children… kept. (The Week view already lists a block's children; nothing changes there.)
10. **Left for later** (not in this plan): "Not this time" on a warning (Only This Day already cancels a group for a day); day columns tinting during a drag; "who's leaving next" on Today; the Settings row for the length; the free-times MCP tool.
11. **Against Apple's guidance, on purpose:** none. Where Apple is silent (discouraged-but-allowed choices, suggestions in a popover, names into chips) the choices above are ours and are marked as such under Apple guidance.

## Apple guidance

Checked 2026-11-11 against Xcode 27.2 (27B52), iOS 27.2 and macOS 27.2 SDKs; targets are iOS 27.0 and macOS 27.0 (the Assistant builds for iOS 18). Xcode 27.3 is a beta; its notes change nothing here. The lesson-times plan's guidance (popover or sheet, control sizes reset inside a popover, time text) still applies and is not repeated.

- **Not by color alone.** "Convey information with more than color alone… distinct shapes or icons" ([Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility), 2026-08-06). So a marked time carries a symbol as well as secondary text, and the amber chip keeps its triangle.
- **VoiceOver.** The label is the time, the state goes in the value, the hint says what happens ([accessibilityValue](https://developer.apple.com/documentation/swiftui/view/accessibilityvalue(_:)), 2026-10-08; WWDC26 session 220). A marked time's value is the sentence ("Lucy T is with Morah Devora until 10:20"); a time that is both taken and marked joins the two.
- **Keep discouraged choices enabled.** Apple says nothing either way; the nearest text is Menus, where dimmed means unavailable ([Menus](https://developer.apple.com/design/human-interface-guidelines/menus), 2026-08-06). Ours: marked times stay enabled and are not drawn as disabled.
- **Suggestions.** Nothing for pickers or popovers; Entering data says to "offer choices instead of requiring text entry" ([Entering data](https://developer.apple.com/design/human-interface-guidelines/entering-data), 2026-08-06), and Popovers to keep to a few related tasks. Ours: one short row above the grid, four chips at most.
- **Names into a list.** No SwiftUI token field: the SDK's only token APIs are `searchable(text:tokens:)` and `searchable(text:editableTokens:)`, bound to a search field. The HIG's token fields are Mac only ("Not supported in iOS, iPadOS…"; [Token fields](https://developer.apple.com/design/human-interface-guidelines/token-fields), 2026-08-06), where a comma makes a token. Ours: a `TextField` with `.onSubmit` and comma handling over our own list, the same on every platform; no `NSTokenField` wrapper.
- **Length with an end.** A stepper shows no value of its own, so its label must ([Steppers](https://developer.apple.com/design/human-interface-guidelines/steppers), 2026-08-06). Put the text in the `Stepper`'s label, as the sheet does now. The sheet's existing `lengthText` already writes "30 min" and "1 hr 15 min", so keep it; for the end use the app's own `TimetableDay.clockText` (`Schedules/Model/TimetableValues.swift:254`), which writes "10:20" the way the rest of Schedules does (`Date.FormatStyle().hour().minute()` would add "AM").
- **Gaps.** HIG pages are dated 2026-08-06 and the docs 2026-10-08, both before Xcode 27.2. The docs list `accessibilityValue(_:)` as iOS 16; the SDK says iOS 14; the SDK wins.

## Phase 1: The rules for who is away

- Who: phase session (Opus 5.5, high). Pure rules that three screens and two tools will read, plus a change to a resolver the Assistant shares; it ends with a cold review by a subagent. No views.
- Needs: —
- Steps (paths under `Cosmic Daybook/`; this phase must not edit anything under `Presentations/`, `Students/` or `Schedules/Views/`):
  - `Schedules/Model/TimetableValues.swift`: `LessonLength.assumedMinutes = 30` (decision 1) and a pure `overlaps(lessonStart:block:)` on `TimetableBlockValues` (decision 2).
  - New `Schedules/Services/AwayTimes.swift`, no Core Data in the value types:
    - `AwayBlock` (`blockID`, `personName`, `title`, `startMinute`, `endMinute`, `studentIDs` uppercased) and `AwayDay` (`blocks`, in time order): `nonisolated` values with the pure rules on them.
    - `AwayDay.clashes(children:start:)`, `away(children:in half:)`, `freeStarts(children:ownStarts:)` and `freeHalves(children:)` per decisions 2 and 5.
    - `AwayTimes.day(from: ScheduleDay, guideLaneID:)`: pure and `nonisolated`. It takes only a person lane's own `.block` items that name children, in lanes other than the guide's; a turn in the adolescent room also appears in a person's lane (`Schedules/Model/ScheduleDay.swift:94-99`) and is left out (decision 3).
    - `AwayTimes.days(from:through:in:calendar:) -> [Date: AwayDay]`, keyed by start of day, on the main actor, as `TimetableService` (`Schedules/Services/TimetableService.swift:28`) and `TodayScheduleRows.day` (`Today/Support/TodayScheduleRows.swift:38`) are: one `TimetableService.timetable(from:through:…)` fetch and one `SchoolDayChecker.nonSchoolDaySet` for the whole range, then `ScheduleDayResolver` per day with no lessons, so there is no fetch per day.
  - New `Schedules/Services/AwayText.swift`: every sentence in decisions 4, 6 and 8 from clashes plus a name lookup: the picker's Away row, a quick time's sentence, the card line (timed and untimed), the "Free all…" words, and MCP's lines. Times through `TimetableDay.rangeText` and `clockText` (`Schedules/Model/TimetableValues.swift`), not `ScheduleText`, which is main-actor and lives in Views.
  - `Schedules/Services/ScheduleDayResolver.swift` (`childWarnings`, about lines 264–293) and `Schedules/Model/ScheduleDay.swift` (`Warning`, about lines 136–165): decision 7. `.childWithPerson` carries the lesson's minute when it has one; the text follows. Replace the "first lesson per child per half" table (about lines 268–274) with a check of every lesson against every block.
  - `Services/MCPServer/MCPNotebookTools+ScheduleWrites.swift` (replies at about lines 120–125 and 325–358): decision 8, through `AwayTimes.days` for the one day and `AwayText`. Update the two tool descriptions and `docs/Technical notes/MCP_SERVER.md`.
  - Tests in `Cosmic Daybook Tests/Schedules/`: new `AwayTimesTests` (the overlap rule at both edges; a child in two groups; free starts for a Monday shaped like the real one: groups 9:15–9:45, 9:50–10:20 and 10:40–11:10 leave 8:45 as the only morning start and the afternoon free; own lessons block a start; a cancelled group, Out Today and a no-school day give no away times; a person's turn in the adolescent room gives none; every sentence in decision 6). Update `ScheduleDayResolverTests` (adding one child in two lessons in one half, the first clear and timed, the second clashing: the warning still shows), `SchedulesPageWeekTests`, `MCPScheduleToolsTests` and `MCPTimetableDayChecksTests` where the half-only wording was pinned. Fixtures use first names with made-up last names, never the real roster's, and live in this phase's own new test files: don't edit `TimetableTestSupport.swift` (Phase 4 is running beside you).
  - Before merging: one `general-purpose` subagent (Opus) reads the diff cold for an off-by-one at either edge of the overlap, a path where a cancelled or changed block still counts, and anything that would not build for iOS 18 in the files the Assistant compiles. One fix round.
- Cost: $8–16, ~1% (lesson-times Phase 1, the same kind of rules change with a review, cost $13 across 17 files; this is about 6).
- Done when: the `Cosmic Daybook` scheme builds for the iOS simulator and for the Mac (build only: the Mac test host opens the live notebook), and the `Daybook Assistant` scheme builds; these suites pass with a count above zero each: `AwayTimesTests`, `ScheduleDayResolverTests`, `ScheduleDayTurnsAndCancelsTests`, `SchedulesPageWeekTests`, `MCPScheduleToolsTests`, `MCPTimetableDayChecksTests`, `MCPToolRegistryTests`; and, because the Assistant runs the same resolver, `AssistantScheduleTests` in `Daybook Assistant Tests` passes on a simulator leased for the Assistant (the Schedules plan used an iPhone SE on iOS 26.5; one simulator at a time).
- By hand: none.

## Phase 2: The picker shows it

- Who: phase session (Opus 5.5, high). One view and its tests, with no call site changed, so it runs beside Phase 1.
- Needs: —
- Steps (paths under `Cosmic Daybook/Presentations/Planning/`; this phase edits only `LessonTimePicker.swift`, and `LessonTimePickerPresenter.swift` if the taller content needs it):
  - `LessonTimePicker.swift`: a new optional input, `away: LessonTimeAway? = nil`, declared in this file as plain values so the picker still never sees a `Date` or Core Data: `rows: [String]` (the Away list, ready-made sentences), `sentences: [Int: String]` (minute after midnight → that start's sentence), `suggestions: [Int]` (minutes) and `freeWords: String?`. Phase 3 fills it from Phase 1's types; this phase uses hand-made values.
  - Draw decision 4: the Everyone's free row (chips call `set(hour, minute)`), the mark on each quick time that has a sentence, the Away list under the grid, and one legend line beside the existing dot line. Each marked time gets `.accessibilityValue` with its sentence (joined with "Already has a lesson" when both apply) and `.help` with the same sentence on the Mac. Follow the Apple guidance section; set control sizes again inside the popover as the file already does.
  - With `away == nil`, or all four parts empty, the picker must draw exactly as it does on main.
  - Tests in `Cosmic Daybook Tests/Presentations/`: extend `LessonTimePickerTests` (which times are marked; a time both taken and marked; chips set the right hour and minute, including 10:20; nothing new shows for `nil`; the chosen symbol exists, `UIImage(systemName:) != nil`).
  - Pictures with the lesson-times helper (`LessonTimePictures`) into `docs/Pictures/Co-teacher times/`: the picker with away times, dark and light, and one with `nil` to compare against `docs/Pictures/Lesson times/picker-time-set-light.png`.
- Cost: $5–10, ~0.5% (lesson-times Phase 2, the whole picker from nothing, cost $4.59).
- Done when: the `Cosmic Daybook` scheme builds for the iOS simulator and for the Mac (build only); `LessonTimePickerTests` passes with more than the 10 tests it has on main, the new ones named in the final message; the three pictures exist. Compare the `nil` picture's bytes with `docs/Pictures/Lesson times/picker-time-set-light.png` drawn from the same inputs; if drawing isn't byte-stable, say so and compare by eye instead of failing.
- By hand: none.

## Phase 3: Cards, the day badge and the lesson's sheet

- Who: phase session (Opus 5.5, high). Wiring rules and a picker that already landed into the planner and the sheet.
- Needs: 1, 2
- Steps (paths under `Cosmic Daybook/`; this phase must not edit anything under `Schedules/`):
  - `Presentations/Planning/WeekPlanSection.swift` (and its `+Data` file): hold `[Date: AwayDay]` for the planner's days, loaded by its own `refreshAwayDays()` with `AwayTimes.days`. Drive it from the planner's `days`, so it also runs when the window grows as the strip scrolls (`settleStrip`, `+Data.swift` about lines 117–128). Don't hang it on `refreshCheckIns`, which returns early when work is hidden (about line 234). Reload through `onPresentationDataChangeWhenVisible` (`Utils/SwiftUI/View+PresentationDataChangeWhenVisible.swift:33`), as the planner's own listener does (`WeekPlanSection.swift:137`), for `TimetableLane`, `TimetableBlock` and `TimetableChange`, with the same short wait the Schedules page uses. Each `WeekDayColumn` gets its day's `AwayDay`. No fetch inside a card or a column body.
  - `WeekDayColumn+Time.swift` (`timePicker(for:)`, about line 131): build `LessonTimeAway` for the card's children from the day's `AwayDay`, `AwayText` and the column's other timed lessons, and pass it to the picker.
  - `PresentationPlannerCard.swift` and `PresentationPlannerCard+TimeChip.swift`: decision 6. `TimeChip` gets its own away field beside `isClash`: the amber look is shared, but `isClash` alone makes VoiceOver say "another lesson at the same time" (`+TimeChip.swift`, about line 191), so the away case has its own words. The caption line goes in the card's stack after the children, in the style of `showFirstLine` (`+ShowFirst.swift`, about lines 94–106), amber for a clash and secondary for the untimed note; `spokenLabel` gains it.
  - `WeekDayColumn+Balance.swift` (`DayClashes`, about lines 30–74 and the badge's help at about 102), `WeekDayColumn.swift` (badge, about line 168), `WeekPlanHeader.swift` (legend, about lines 98–125): `DayClashes` gains an away count; the badge total, its help and spoken label, the plain-badge rule and the legend follow decision 6.
  - The lesson's sheet: `Students/Presentations/ScheduledDateEdits.swift` gains a `@MainActor` `awayInfo(on:children:excluding:in:using:)` beside `takenMinutes` (about line 58; the enum is `nonisolated`, `AwayTimes.days` is not), one day's `AwayTimes.days` at tap time; `InboxStatusSection.swift` (`ScheduledTimeRow`, about lines 120–173) takes the children and passes `LessonTimeAway` to the picker, and shows the card's clash line as a caption under the Time row when the set time clashes; `PresentationDetailView+PlanningSections.swift` (about line 370) hands it `vm.selectedStudentIDs` (the sheet's unsaved roster, `PresentationDetailViewModel.swift:34`), not the saved lesson's children.
  - Only this phase may edit `LessonTimePicker.swift` after Phase 2, and only if wiring needs it.
  - Tests in `Cosmic Daybook Tests/Presentations/`: new `AwayOnCardsTests` (chip state and line for timed, untimed and clear lessons; the badge count; the plain badge when only away clashes exist, with its help words; the chip's and the card's spoken words; the picker value built for a card; a timetable change reloads the days; a day scrolled into the strip gets its away times; they still load with Show set to presentations only). `LessonTimeChipTests`, `WeekPlanLayoutTests` and `TodayLessonTimeTests` still pass.
  - Pictures into `docs/Pictures/Co-teacher times/`: a day's list (draw `dayList`, not the column, whose scroll view draws blank) with a clashing card, an untimed card with its note and a clear card, dark and light, at iPad width and iPhone width.
  - Tide rows (Check on a device): open the picker on a card whose child is in a Monday group and read the Away list and the marks; set a clashing time and see the amber chip and line; change a group in Schedules and see the card follow.
- Cost: $10–20, ~1% (lesson-times Phases 3 and 4, the same files, cost $6.92 and $5.02).
- Done when: the `Cosmic Daybook` scheme builds for the iOS simulator and for the Mac (build only); `AwayOnCardsTests`, `LessonTimeChipTests`, `WeekPlanLayoutTests`, `LessonTimePickerTests` and `TodayLessonTimeTests` pass with counts above zero; the four pictures exist and show the three card states.
- By hand: none overnight (rows in Tide).

## Phase 4: The Schedules group sheet

- Who: phase session (Opus 5.5, high). One sheet and one list view in Schedules, with no file in common with the other phases.
- Needs: —
- Steps (paths under `Cosmic Daybook/`; this phase edits only `Schedules/Views/`. It reads `Siri/StudentNameMatcher.swift` and must not edit it: Siri and the Assistant compile it. If a listed name can't be matched without changing it, leave that test out and say so in the final message):
  - `Schedules/Views/ScheduleBlockSheet.swift` (`timeSection`, about lines 153–164): the Length row reads "30 min · ends 10:20" (decision 9), keeping `lengthText` and the 5-minute steps, the end written with `TimetableDay.clockText`.
  - New `Schedules/Views/ScheduleNameEntry.swift`: a pure `sort(_ text: String, students:) -> (matched: [UUID], unmatched: [Unmatched])` that splits on commas and new lines and matches each name through `StudentNameMatcher.matches(for:in:)` (`Siri/StudentNameMatcher.swift:54`) among enrolled children: a single best candidate is a match; none, or several, is unmatched with which it was. Then the field itself in `childrenSection` (about lines 189–206), above Choose Children…, with the plain lines of decision 9.
  - Save (`askOrSave`, the sheet's confirmation action at about lines 101–104) sorts any text still in the field first; if a name is left unmatched the sheet stays open with its line showing.
  - Tests in `Cosmic Daybook Tests/Schedules/`, with fixtures in this phase's own new files (don't edit `TimetableTestSupport.swift`; Phase 1 is running beside you): new `ScheduleNameEntryTests` against a made-up roster with the real one's shape (two children called Etty and two called Sarah with different last initials, a two-word first name like "Leiba Ruchama", a nickname like "Tiffy"): "Etty D.", "Etty K", "Sarah M.", "Leiba R.", the two-word first name alone, and the nickname each match one child; bare "Sarah" and "Etty" are unmatched as "more than one"; "Vivi" with no such nickname is unmatched as "nobody"; a pasted line of six names with stray spaces sorts all six. Extend `ScheduleBlockSheetTests` for the end-time words (a length that crosses noon, and 1 hr 15 min) and for Save with text still in the field (a last name with no comma is added; an unmatched one keeps the sheet open and saves nothing).
  - Pictures into `docs/Pictures/Co-teacher times/`: the Length row and the Children section with one unmatched name, drawn outside the form if the form itself draws blank; say so if a picture can't be drawn.
  - Tide rows (Check on a device): paste a line of names into a new group and save; read the end time while stepping the length; on the Mac, press Return in the names field and check it adds the name and doesn't save the sheet.
- Cost: $6–12, ~0.5% (a small surface on a settled model costs $5–7 in the log).
- Done when: the `Cosmic Daybook` scheme builds for the iOS simulator and for the Mac (build only); `ScheduleNameEntryTests` passes with a count above zero and `ScheduleBlockSheetTests` with more than the 6 tests it has on main (name the new ones in the final message); `SchedulesPageModelTests` and `SchedulesPageWeekTests` still pass; the pictures exist or the final message says which couldn't be drawn.
- By hand: none overnight (rows in Tide).

## Phase 5: Final check

- Who: phase session (Opus 5.5, high).
- Needs: 3, 4
- Steps:
  - On main with every phase merged: build the notebook for the iOS simulator and the Mac, and the `Daybook Assistant` scheme for the iOS simulator; run the notebook's whole test suite once on the leased simulator (`-parallel-testing-enabled NO`, one simulator). Fix what fails; the errors name files and the files map to phases.
  - One `general-purpose` subagent (Opus) reviews the merged diffs cold against Decisions 2–9: a clash shown or missed at an edge, a card and its picker disagreeing about the same time, a group change that doesn't reach an open planner, a fetch inside a view body, words that aren't plain. One fix round.
  - Docs: `docs/Technical notes/LESSON_PRESENTATION_WORK_INTEGRATION.md` where it describes a lesson's set time and its clashes (add the overlap rule and the assumed 30 minutes); `docs/Technical notes/MCP_SERVER.md` if Phase 1 left anything; `Cosmic Daybook/CLAUDE.md` only if it describes the Schedules warnings. No new doc pages. Tick "Warnings in the Lessons & Work planner itself" in `docs/Plans/Plan - Schedules.md` › Deferred with a pointer here. The manual is not touched.
  - Check every Check on a device row from Phases 3 and 4 is in Tide under Cosmic Daybook › To do, and add to the existing lesson-times Release row's note that this rides the same roll-out (don't reword the row; its link is built from its words).
- Cost: $8–18, ~1% (lesson-times Phase 5 cost $8.78, half of it the reviewer).
- Done when: all three builds succeed, the whole suite passes (give the count), the review's findings are fixed or listed, and the docs are updated.
- By hand: none.

## Running a phase (phase sessions read this)

You were started by the conductor. Danny accepted this plan and is likely away. Don't ask him anything and don't wait on him. **Don't edit this plan file**: other phases are running beside you, and the conductor writes Progress and Decisions. Everything you'd add goes in your final message.

0. Get your session id: run `echo $CLAUDE_CODE_SESSION_ID` (it isn't filled in for you anywhere else). If your phase needs other phases, wait for them first: run `~/.claude/bin/plan-wait --repo "/Users/dannydeberry/Developer/Maria's Notebook" --prefix plan/coteacher-times --needs <their numbers>` with `run_in_background`, and end your turn; you're woken when it exits. On "Go ahead" carry on. On anything else (a needed phase stopped, the run braked, a time-out), stop: mark yourself stopped (step 7) unless the run was braked, and report its line.
0b. Make sure your branch starts from local main, which holds every phase merged so far (nothing is pushed, so `origin/main` is behind): if `git merge-base --is-ancestor main HEAD` fails, run `git merge main`.
1. Read `Cosmic Daybook/CLAUDE.md`, then do the phase's steps, building only its smallest target and running only its `-only-testing:` suites (`~/.claude/CLAUDE.md` › Xcode builds), through `Scripts/locked_xcodebuild.sh`. Test on simulators headless (`xcodebuild test`, `xcrun simctl io <udid> screenshot`), on this checkout's leased simulator; never the macOS test destination or a Debug Mac launch (both open Danny's live notebook). Leave tapping, clicking and screen-driving alone: the screen is locked. List what to check under "By hand" in your final message.
2. If a decision comes up that the plan didn't settle, take the safer option that's easier to undo, add a `Review choices` row in Tide for Danny, and put it under "Decided" in your final message.
3. Check every "Done when" item. Before each fix round, run `~/.claude/bin/plan-cost session`. If one item still fails after two tries, or the phase has cost more than twice the top of its estimate, stop.
4. Make every "not verified", "for your review" or "check on a device" item from this phase a row in the app's list in Tide (`Areas/App Development/Cosmic Daybook/To do.md`, `add_action`), skipping ones already there. Any repo doc line about it keeps one plain sentence plus the row's `tide://` link.
5. Update the build board (`build-board` skill, then `~/.claude/bin/board-touch https://claude.ai/artifact/WAKaFZGNPQsfKD4A5GbqsM`). If the board can't be reached from your sign-in, say so in your final message and go on.
6. Merge: read `~/.claude/skills/close-out/SKILL.md` and follow it (it can't be invoked as a skill). Danny's acceptance of the plan is his go-ahead. Make these changes to it:
   - In its step 2, bring the branch up to date with **local** `main` (`git merge main`), not `origin/main`.
   - Right after the squash commit, before releasing the lock, mark the phase merged: `~/.claude/bin/plan-wait --repo "/Users/dannydeberry/Developer/Maria's Notebook" --prefix plan/coteacher-times --mark <N>`. Phases waiting on you start from that.
   - Before its step 4, take the merge lock: `~/.claude/bin/plan-merge-lock take "/Users/dannydeberry/Developer/Maria's Notebook"` (run it with `run_in_background` if it says it's waiting). Release it with `plan-merge-lock release "/Users/dannydeberry/Developer/Maria's Notebook"` right after the squash commit, and also if you stop before that commit.
   - Skip its step 4b (the conductor keeps the plan's status and the docs map) and its step 5 (no push).
   - Wherever it says "stop and ask", stop instead: release the lock, don't merge, and report it.
7. If you stopped without merging, mark it so the phases waiting on you stop too (`plan-wait … --mark <N> --stopped`), and shut down your simulators (`~/.claude/bin/sim-lease --done`). close-out releases them otherwise.
8. End with this line first, so the conductor's note shows it: `Phase <N> done (<commit>). Session <your id from step 0>. By hand: <list or none>.`, or `Phase <N> stopped: <plain reason>. Session <id>. Nothing merged.` Then, under it, any "Decided:" items and anything that differed from the plan.

Every phase also keeps to the project's rules: Swift Testing, and watch for an `#expect` on an optional chain that asserts nothing; Core Data types and their extensions are `nonisolated` under the main-actor default; American spelling and plain-English words on screen; `-only-testing:` names the enclosing type for a nested suite; `~/.claude/bin/sim-lease --done` before the final message.

## Open questions

None.
