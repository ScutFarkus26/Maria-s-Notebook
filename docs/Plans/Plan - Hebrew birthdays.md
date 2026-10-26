# Hebrew birthdays

> **Working on it.** Written 2026-10-14 from Danny's ask: "add a Hebrew birthday field to each child and calculate their Hebrew birthday based on their date of birth" (session on branch `claude/hebrew-birthday-field-96c8b9`). He asked for it to run autonomously once approved.
> In short: each child's page shows their Hebrew birthday in English and Hebrew, worked out from their date of birth and a new "Born after sunset" switch, and it also appears in the roster table, Birthdays This Week and the MCP student list.

Build board: https://claude.ai/artifact/WAKaFZGNPQsfKD4A5GbqsM (add one milestone, "Hebrew birthdays", with the four phases as its steps).

## Goal

Every child has a Hebrew birthday that Danny never has to type. The app works it out from the date of birth. A new "Born after sunset" switch on the child's page moves it one day, since a Hebrew date begins at sunset. It shows:
- on the child's page under Birthday, as "14 Adar II 5784 · י״ד באדר ב׳ ה׳תשפ״ד", with the switch under it when editing;
- as an optional Hebrew Birthday column in the Students table (hidden by default, like Age);
- in Birthdays This Week, which also lists children whose Hebrew birthday falls this week, with its Gregorian date;
- in the MCP `list_students` answer, and `update_student` can set the sunset switch.

## Progress
- [x] Phase 1 (started at 53%): Born-after-sunset field: schema 21, backup v43 (agent) ‖ Phase 2 · est. ~1.5–2% weekly · 951deda7: 50 tests in 14 suites + the whole Assistant suite (514) pass. Differed: two Schedules tests pinned schema 20 / v42 and now say `>=`; the dedup case is its own suite; `ClassroomShareRelease.copyAttributes` carries the flag (tested); sample class: Ezra born 14 Adar II 5776, Tamar after sunset.
- [x] Phase 2 (started at 53%): Hebrew birthday calculator (agent) ‖ Phase 1 · est. ~0.5% weekly · a94fab24: 17 tests (26 cases) pass in the default zone and GMT-10; the naive version failed the zone tests. Differed: added `englishDayAndMonth(on:)` for Phase 3; `nextOccurrence` builds the 1st of the month and adds days rather than `nextDate`; 30 Heshvan test uses 5785→5786 per Hebcal. Phases 1 + 2 together: 53→64% (~11%, far over the ~2–2.5% estimate; possibly noisy).
- [x] Phase 3 (started at 64%): Show it: child's page, roster column, Birthdays This Week, MCP (agent, after 1 and 2 are combined) · est. ~0.5–1% weekly · 8ab8c938: iOS + macOS compile + Assistant builds clean; 60 tests in 6 suites pass; actual ~6% (64→70, possibly noisy). Differed: the simulator panel was declined, so screens were checked as rendered images (Ezra 14 Adar II 5776 with the Hebrew under it; Tamar 8 → 9 Elul with the switch); the real switch on a device is a Tide check. The two views live in a new `Students/Detail/HebrewBirthdayViews.swift` (lint length); on a phone the date shows on two lines; the note under the switch shows the date as it will be saved; the sample class has no launch argument.
- [ ] Phase 4 (started at 70%): Review, fixes, full builds and suites, land on main (main session) · est. ~1–2% weekly

All four run from this session without stopping for Danny (he asked for an autonomous run). Phases 1 and 2 run at once in agent worktrees. They share no files, but both builds wait on the one Mac build lock, so this saves only a little time.

## Cost

About 3.5–5.5% of the weekly all-models limit on Max. Planned at 94% used (tight); approved and started 2026-10-25 at 53% used, with 47% left until Thu Oct 30, 1 pm (EDT). **Fits.** Recent Cosmic Daybook phases have come in well under their estimates (the 2026-10-13 Lessons and Work plan: 11–19% estimated, ~3% actual), so it should fit. Check usage after Phase 1 and before Phase 4. If the weekly limit has passed 99%, the next phase waits for the reset rather than running on extra usage (only ~$10 is left in this month's extra-usage cap).

## Decisions

- **Born after sunset is stored** (Danny's choice). It's a new optional attribute, `Student.bornAfterSunset` (Bool, default NO), on the shared `Student` entity. That's schema 21 and backup v43 (main reached schema 20 / v42 on 2026-10-24, after this plan was first written). It's additive, which CloudKit allows. It is ruled out to assume a daytime birth (Danny chose the switch) and to store the Hebrew date itself, which would go stale when the birth date is corrected.
- **The Hebrew date is computed, never stored.** It's worked out from `birthday` plus `bornAfterSunset` wherever it's shown, so correcting either one updates it everywhere. A born-after-sunset child gets the Hebrew date of the next Gregorian day.
- **Both writings** (Danny's choice). English uses Foundation's month names ("14 Adar II 5784", "3 Heshvan 5787"). Hebrew script uses `he_IL@numbers=hebr` ("י״ד באדר ב׳ ה׳תשפ״ד"). A hand-written month-name table (e.g. "Cheshvan", "Tammuz") is ruled out: it's more code to keep right, and Apple's spellings are standard.
- **Where it shows** (Danny's choice): the child's page, an optional roster table column, Birthdays This Week and MCP `list_students`. Ruled out: the attendance-tile cake and the roster row's birthday-soon tag. Both stay Gregorian, because neither was asked for and the Assistant shares the cake code.
- **When a Hebrew birthday falls in a later year** (settled here, as the common customs):
  - Born in Adar of a regular year: Adar II in a leap year.
  - Born in Adar I: Adar I in a leap year, Adar in a regular year.
  - Born in Adar II: Adar II in a leap year, Adar in a regular year.
  - Born on 30 Heshvan or 30 Kislev: 1 Kislev or 1 Tevet in a year where that month has 29 days.
  - Born on 30 Adar I: 1 Nisan in a regular year, the day after 29 Adar.
- **The Assistant shows nothing new.** It has no child page. It does share the model, so its scheme must build and its tests must pass with schema 21.
- **No schema-21 build is ever run on the Mac before the roll-out.** Mac builds are compile-only and every test runs on the iOS simulator. A Debug Mac run opens Danny's live notebook, and the installed Release copy can't open it afterward (`coredata-model-version-edited-in-place`; the ParentLocker plan learned this with schema 18).
- **Skip `Scripts/install_release.sh` until the roll-out.** `Cosmic Daybook/CLAUDE.md:54` says to run it after any merge to main, which would move Danny's live Mac notebook to schema 21 before Production has the field. Phase 4 adds a dated line under it ("Schema 21 not rolled out yet: don't run this until the Hebrew birthdays roll-out row in Tide is done"), and the roll-out Tide row says to remove that line.
- **The child's "when" fields are read with `AppCalendar.shared`** (Gregorian, device zone), never `Calendar.current`. `Calendar.current` follows the device's calendar setting, so on a device set to the Hebrew or Buddhist calendar it would read the wrong year (`AppCore/AppCalendar.swift`).
- **The Assistant's shared files stay free of Hebrew code.** The Assistant compiles `StudentEntity.swift`, `StudentModel.swift`, `StudentEntity+CoreData.swift` and `AttendanceBirthday.swift` by name. `HebrewBirthday.swift` stays notebook-only. Those four files get only the plain `bornAfterSunset` property, which the Assistant needs anyway for the shared model.
- **Ruled out for now:** the CSV import (no sunset column). It wasn't asked for and can take the field later without schema work. (The in-app Chat was removed by the 2026-10-18 simplify plan.)
- **The CloudKit Production deploy and the roll-out are Danny's steps,** as Tide rows, unless he says at approval that this run should do them. Phase 4 does the one Debug Development `-InitializeCloudKitSchema` run on the test-account simulator, if that simulator is still signed in. If it isn't, that becomes a Tide row too.

## Apple guidance

Checked 2026-10-14 against Xcode 27.0 (27A266a), iOS/macOS SDK 27.0. The sdk-verifier ran probe programs against the SDK. Xcode 27.1 RC and 27.2 beta 3 exist, and neither changes anything here, so there's no need to update first.

- **G1 `Calendar(identifier: .hebrew)`** ([docs](https://developer.apple.com/documentation/foundation/calendar/identifier-swift.enum/hebrew), iOS 8+). Months are numbered Tishri=1 … Shevat=5, **Adar I=6 (leap years only), Adar/Adar II=7**, Nisan=8 … Elul=13. `isLeapMonth` is always false for Hebrew; never set it to true, because matching then returns nothing. Don't use `range(of: .month, in: .year)` (it says 13 months every year). Test for a leap year by building month 6, day 1 and reading the month back (6 means leap, 7 means regular). The app's Parsha code already does this (`HebrewParshaService+YearSchedules.swift:237`).
- **G2 Time zones.** Foundation turns the day at midnight, not sunset. A date of birth read in the wrong zone gives the day before (a UTC-midnight birthday read in New York was off by one). Read the stored birthday's year, month and day with `AppCalendar.shared` (Gregorian, device zone; see Decisions). Rebuild noon of that day in one fixed zone, then convert to Hebrew in that same zone. Turn any Hebrew-calendar result back into a local day through `AppCalendar` before comparing it with "today" or a week window.
- **G3 Formatting.** Use `Date.VerbatimFormatStyle` (or `Date.FormatStyle` with its `calendar`, `locale` and `timeZone` properties set). `.month(.wide)` names Adar / Adar I / Adar II correctly. Never index `monthSymbols[month-1]`, because Adar II is last in that 14-entry list. `Date.FormatStyle` ignores `@calendar=hebrew` on a locale, so set the calendar property. `he_IL@numbers=hebr` gives Hebrew numerals. Available from iOS 15, so it's fine for the iOS 18 Assistant too ([Date.FormatStyle](https://developer.apple.com/documentation/foundation/date/formatstyle)).
- **G4 Next occurrence.** `nextDate(after:matching:matchingPolicy:)` (iOS 8+) with `.nextTime` gives 1 Kislev / 1 Tevet for a missing 30th and 1 Nisan for month 7 day 30. Month 6 (Adar I) never matches in a regular year under any policy, so map 6 → 7 for those years yourself. Results land at 00:00 in the calendar's zone. `Calendar.RecurrenceRule` is avoided: it's untested with Hebrew, and [swift-foundation #2224](https://github.com/swiftlang/swift-foundation/issues/2224) shows yearly rules going wrong.
- **G5 Core Data + CloudKit.** Schema changes must be additive. Add an optional attribute or one with a default, then do one Debug Development `-InitializeCloudKitSchema` run before the Production deploy (project `CLAUDE.md` › CloudKit Notes).

## Phase 1: Born-after-sunset field (schema 21, backup v43)
- Who: `feature-phase-deep` (Opus, xhigh). It's a shared-entity schema change plus a backup format bump. A slip loses data or breaks sync on every device, so it needs the strongest setting. It runs in its own worktree, at the same time as Phase 2.
- Steps (template: commit 55117e19, which added `Student.parentLockerID` for schema 18 / v40; follow the same files):
  - `Cosmic Daybook/CosmicDaybook.xcdatamodeld/CosmicDaybook 2.xcdatamodel/contents`: `Student` gets `bornAfterSunset`, Boolean, optional, default NO (G5).
  - `Students/Models/StudentEntity.swift`: `@NSManaged public var bornAfterSunset: Bool`, defaulted for new students.
  - `AppCore/Persistence/CoreDataStack+SchemaVersion.swift`: `currentSchemaVersion = 21`, plus a history line. `Cosmic Daybook Tests/.../CoreDataSchemaVersionTests.swift`: the new hash.
  - Backup: `BackupTypes+Core.swift` (`StudentDTO.bornAfterSunset`, optional so older backups decode), `BackupServiceHelpers.swift` (export), `Import/BackupEntityImporter+Students.swift` (import; an older backup leaves a child's own value), `BackupWriter.swift` (`formatVersion = 43` + a history line), `BackupReader.swift`, `BackupPredatedValues.swift`, `BackupEntityTable.swift` / `ModelRowKinds.swift` as the template did, and the golden/sparse JSON fixtures.
  - `Services/Migrations/DataCleanupService+DeduplicateStudents.swift`: a merged duplicate keeps `bornAfterSunset` if either copy has it.
  - `Repositories/StudentRepository.swift`:
    - Add `bornAfterSunset` to `editableKeys` (~line 100), so changing only the toggle stamps `modifiedAt`. `ClassroomShareRelease` keeps the copy with the newer `modifiedAt`.
    - Add a `bornAfterSunset` parameter to `updateStudent` and `createStudent`. Phase 3's UI and MCP use them.
  - `Cosmic Daybook Tests/.../StoreMigrationTests.swift`: add `bornAfterSunset` to the Student "added later" list.
  - Docs that name the schema and backup version: `Cosmic Daybook/CLAUDE.md` (~166, 240, and the Student line of the classroom-share list ~173), `docs/Technical notes/DATA_MODELS.md`, `docs/Technical notes/BACKUP_SYSTEM.md` (~231).
  - `AppCore/SampleClassroom/SampleClassroomSeeder+FakeRecords.swift`: one sample child born after sunset and one with an Adar II birthday, so Phase 3's simulator check has something to show.
  - The model is edited in place (one version), as always. Add nothing but the plain property to the four Assistant-shared files (Decisions).
- Cost: ~1.5–2% (deep xhigh agent on ~15 files, two fixture rewrites and two new suites).
- Done when:
  - `Cosmic Daybook` scheme builds for the leased iOS simulator; the `Daybook Assistant` scheme builds.
  - These pass on the iOS simulator: `-only-testing:` `CoreDataSchemaVersionTests`, `StoreMigrationTests`, the backup round-trip/golden suites the template touched (`BackupSendMethodRoundTripTests`, the golden and sparse-row suites), a new `BackupBornAfterSunsetRoundTripTests` (v43 round trip; a v42 backup restores with NO), the student dedup tests (`DedupStudentParentLockerTests` and a new case for the flag), and a `StudentRepository` test that changing only the toggle sets `modifiedAt`.
  - The whole `Daybook Assistant Tests` suite passes on `sim-lease --type "iPhone SE (3rd generation)" --os 26.5`. It's small, and it's the only check that the shared model still opens there.
  - No Mac run, no Mac tests.
- Hand off: no (agent; reports back to this session).

## Phase 2: Hebrew birthday calculator
- Who: `feature-phase` (Opus, high). The code is small and pure, but the calendar rules are easy to get subtly wrong (wrong-day errors, Adar). It runs in its own worktree, at the same time as Phase 1.
- Steps:
  - New `Cosmic Daybook/Students/Shared/HebrewBirthday.swift`: a `Sendable` value built from `(birthday: Date, bornAfterSunset: Bool, calendar: Calendar)` with no Core Data dependency.
    - `hebrewComponents`: year, month, day (G1, G2).
    - `english` ("14 Adar II 5784") and `hebrew` ("י״ד באדר ב׳ ה׳תשפ״ד") strings, plus a combined `display` joined with " · " (G3).
    - `nextOccurrence(onOrAfter: Date) -> Date`, following the Adar and 30th rules under Decisions (G4).
  - Formatters are cached statics, following the efficiency rules (shared formatters; `efficiency-hot-spots`).
  - New `Cosmic Daybook Tests/Students/HebrewBirthdayTests.swift`. Expected answers are written in as literals. Never derive them from Foundation in the test: that checks the code against itself. The checked answers are:
    - 2024-03-24 → 14 Adar II 5784 (Purim)
    - 2025-03-14 → 14 Adar 5785 (Purim)
    - 2015-03-04 → 13 Adar 5775

    The agent looks up the rest on Hebcal's converter (`https://www.hebcal.com/converter?cfg=json&gy=YYYY&gm=M&gd=D&g2h=1`, and `h2g=1` the other way) and writes them in with a comment naming the source:
    - an Adar I birth
    - a 30 Heshvan birth and a following year where Heshvan has 29 days
    - a 30 Adar I birth
    - each next-occurrence rule under Decisions
    - a born-after-sunset shift across a month end
  - Next-occurrence edges: the Hebrew birthday is today (it counts; `nextDate(after:)` skips its start date, so start from yesterday), and the birthday falls on the last day of a seven-day window.
  - Zone tests use fixed instants, not dates built in the test's own zone:
    - a UTC-midnight birthday (as an old backup or the MCP may have stored it), read with a calendar in America/New_York and in Pacific/Honolulu;
    - the same day read under `TEST_RUNNER_TZ=GMT-1000` (`unit-test-clock-shift`).

    Before the real code goes in, run these tests once against a naive version (convert `birthday` straight to the Hebrew calendar with `Calendar.current`) and confirm they fail. Note that in the reply.
- Cost: ~0.5% (feature-phase high on one new file and its tests).
- Done when: the `Cosmic Daybook` scheme builds for the iOS simulator. `-only-testing:Cosmic Daybook Tests/HebrewBirthdayTests` passes once in the default zone and once under `TEST_RUNNER_TZ=GMT-1000`. The reply says the zone tests failed against the naive version.
- Hand off: no (agent).

## Phase 3: Show it
- Who: `feature-phase` (Opus, high). It's screens and an MCP read on top of the Phase 1 field and the Phase 2 calculator. It starts in a worktree branched from the combined Phase 1 + 2 tip (`git checkout -B <name> <tip>`, because `isolation: worktree` starts at the last-pushed main; `agent-worktree-stale-base`).
- Steps:
  - Child's page, `Students/Detail/StudentDetailComponents.swift`:
    - A "Hebrew birthday" `InfoRowView` under Birthday (~line 242) showing `display`. It's hidden when there's no birthday.
    - When editing, a "Born after sunset" `Toggle` under the Birthday `DatePicker` (~line 101), with the footnote "A Hebrew date begins at sunset."
    - Draft state goes through `StudentDetailView.swift`, `StudentDetailView+Drafts.swift` and `StudentOverviewTab.swift` (~16, 143) the way `draftBirthday` does, so Cancel discards it. Saving goes through `StudentRepository.updateStudent`'s new parameter.
  - `Students/Roster/AddStudentView.swift`: the same toggle next to the birthday picker, saved through `createStudent`'s new parameter.
  - `StudentsTableView.swift`: a "Hebrew Birthday" column, hidden by default like Age and Birthday, sorting by Hebrew month then day.
  - `ClassGlanceView.swift` "Birthdays This Week" (~50–54, 255) and `RosterBirthday.swift`: also list a child whose Hebrew birthday's `nextOccurrence` falls in the same window (`RosterSignalRules.birthdaySoonDays`), compared as local days through `AppCalendar` (G2). It shows as "Hebrew birthday · 14 Adar II" with its weekday. A child whose two birthdays fall in the same week shows on two lines.
  - MCP:
    - `MCPNotebookTools+Reads.swift` `list_students` (~42–44) appends the Hebrew date: "born 2015-03-04 (13 Adar 5775), age 11". Its tool description (~21) says so.
    - `MCPNotebookTools+Writes.swift` `update_student` takes an optional `born_after_sunset` boolean, stamped and journaled like the other fields, and its schema description says what it does.
    - `docs/Technical notes/MCP_SERVER.md` gets the same two changes.
  - Every new word is plain English (project `CLAUDE.md` › Plain English).
  - The User Manual's student page section (`Documentation/Manuals/UserManual.md`) gets two sentences.
- Cost: ~0.5–1% (feature-phase high; both platforms in one SwiftUI codebase).
- Done when:
  - The `Cosmic Daybook` scheme builds for the iOS simulator and compiles for macOS (build only, no run).
  - These pass on the iOS simulator: `-only-testing:` `RosterBirthdayTests` (new cases: a Hebrew birthday today and on the window's last day), `StudentsRosterSignalsTests`, `MCPNotebookToolsTests`, `MCPUpdateStudentStampTests` (new cases: `list_students` shows the Hebrew date, and `update_student` sets and clears the flag), `MCPToolRegistryTests` and `HebrewBirthdayTests`.
  - The `Daybook Assistant` scheme still builds (no Hebrew code leaked into its shared files).
  - On the leased iPhone simulator with sample data: the child's page shows the row and the toggle, and flipping the toggle moves the date by one day. Take screenshots at 0.4 scale, then run `sim-lease --done`.
- Hand off: no (agent).

## Phase 4: Review, fixes, full builds and suites, land
- Who: main session (Opus, high). One Opus `Plan` agent reviews the combined diff for correctness (schema/backup, zone off-by-one, Adar rules, Cancel discarding the toggle, MCP stamping). Fixes are made in the main session, or by one `feature-phase` agent if there are many.
- Steps:
  - Combine Phase 3's branch onto this branch.
  - Review, then fix.
  - Full builds: `Cosmic Daybook` for iOS, `Cosmic Daybook` for macOS (compile only), `Daybook Assistant`.
  - The whole `Cosmic Daybook Tests` suite (leased iPhone 17) and the whole `Daybook Assistant Tests` suite (`sim-lease --type "iPhone SE (3rd generation)" --os 26.5`), each with `-parallel-testing-enabled NO`, one simulator at a time, `sim-lease --done` after.
  - Add the "don't install yet" line under `Scripts/install_release.sh` in `Cosmic Daybook/CLAUDE.md` (Decisions).
  - Squash-merge to main with `update-ref` if the main checkout is on another branch (`merge-when-checkout-shared`), then push. Don't run `install_release.sh`.
  - If the test-account simulator is still signed in, do one Debug Development `-InitializeCloudKitSchema` run on it (G5).
- Cost: ~1–2% (final phase with one review; recent Cosmic Daybook final phases have run ~1–2%).
- Done when:
  - All three builds are clean, and both whole suites pass (counts recorded in Progress).
  - Main has the squash and is pushed.
  - Tide rows exist for Danny's steps:
    - Deploy schema 21 to CloudKit Production (after the Development run).
    - Roll out to every device together, with the Assistant updated too, then remove the "don't install yet" line from `Cosmic Daybook/CLAUDE.md`.
    - On a device, check one child's Hebrew birthday against a known date.
    - The Development run, if this phase couldn't do it.
  - The build board and plan are updated.
- Hand off: no.

## Starting a phase
Read the plan usage (`get_usage`) and note the weekly % used next to the phase under Progress ("started at N%").

## Ending a phase
1. Check every "Done when" item for the phase.
2. Tick the phase under Progress and note anything that differed from the plan. Read the plan usage again and note the actual cost (end % minus start %).
3. Add a row to the log in `~/.claude/skills/plan-efficiently/references/cost-estimates.md`.
4. Update the build board (https://claude.ai/artifact/WAKaFZGNPQsfKD4A5GbqsM) with the `build-board` skill, then `~/.claude/bin/board-touch <url>`.
5. Make every "not verified", "for your review" or "check on a device" item from this phase a row in Tide (`Areas/App Development/Cosmic Daybook/To do.md`, `add_action`), skipping ones already there. The repo line keeps one plain sentence plus the row's `tide://` link.
6. Run /close-out. It sets this plan's status line (`> **Working on it.**` after a phase, `> **Done <date>** (<commit>).` after the last, checked against main) and runs `docs-index`.
7. The next phase runs in this session (no fresh session in this plan).

## Open questions
- Should this run also deploy schema 21 to CloudKit Production and roll out to TestFlight, as the ParentLocker run did? The plan leaves both to Danny as Tide rows unless he says so at approval.
