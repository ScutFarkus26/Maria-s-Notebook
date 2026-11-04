# Daybook Assistant bugs and efficiency 2026-11-03 fixes

> **Done 2026-11-04** (9038f7525). Written 2026-11-03 from the read-only hunt in <../Reviews/Daybook Assistant bugs and efficiency 2026-11-03.md> (30 findings plus five groups of smaller ones, over main 19cfecc1). Danny approved fixing all of them ("Yes, fix them").
> In short: fix every finding without changing what the Assistant does or how it looks, with five fix agents in their own worktrees, each owning its files, then merge, build the Assistant and the notebook, run the whole Assistant suite once, and land it.

Finding numbers (#n) are the report's.

## Goal

Every finding in the report is fixed, the "Smaller" items included, except the one the report marks as not a code fix (#24's Undo-line question). Behavior and look stay exactly as they are: these are correctness fixes that restore what was meant, and waste removed where nobody can see it. When it's done, the Assistant builds clean, the notebook builds clean for iOS and Mac (shared files changed), and the whole Assistant test suite passes.

## Progress
- [x] Phase 1: Five fix agents in worktrees (Gr grid, Sy sync, FD front desk and ParentLocker, SR Siri/Restock/Schedule, Sh shell), each building the `Daybook Assistant` scheme (and `Cosmic Daybook` when it touched a shared file) and running its own `-only-testing:` suites. Each ran twice: the first run could only write a patch (see Decided during the run), the second applied, built, tested and committed it. Gr 170 tests / 21 suites; Sy 85 / 10; FD Assistant 101 / 14 and notebook 125 / 16; SR 110 / 13; Sh 51 / 8; all passing, every notebook iOS and Mac build clean. Every fix except #15's target-membership item and #31's `currentAuthor()` landed; #6's extra loads in `AssistantFrontDeskMail.reminderActionAfterCatchUp` and the store's second per-mutation lock check (#23) stayed as they were.
- [x] Phase 2: Merge the five branches here, read the combined diff, build both apps, run the whole Assistant suite once. Merged with no conflicts (86 files); every agent's diff read; the Assistant builds clean and its whole suite passes, **585 tests in 84 suites**; the notebook builds clean for iOS and Mac and its whole iOS suite passes, **4,624 tests in 758 suites**. One cleanup of the main session's own: three `await`s on the now-plain container read dropped (047fd7604), compiled into the Mac build; the Assistant and notebook iOS test products were built just before it, a warning-only difference.
- [x] Phase 3: Mark the report fixed, land on main, memory. Main had moved meanwhile (the track-entity retirement, notebook-only, no overlapping files); merged in, all three builds and both whole suites run again on the combined tree with the same results, then squashed to main as 9038f7525 (unsquashed history on `claude/daybook-bugs-efficiency-cc9513`) and pushed. The five agent worktrees were removed.

## File ownership

Every source file is owned by one agent; an agent edits only its own files. If a fix needs a change elsewhere, the agent says so in its reply and the main session does it after the merge. Calling another owner's existing API is fine; changing it isn't. New tests go in new test files named `…Fix1103<agent>.swift` in `Daybook Assistant Tests/` (notebook tests in `Cosmic Daybook Tests/`); an existing test file belongs to the agent owning the code it tests.

- **Gr** (#3, #4, #5, #6, #22, #23, #24): `Daybook Assistant/Attendance/*`, `Daybook Assistant/Sync/AssistantReloadOnReturn.swift`, `Cosmic Daybook/Attendance/Store/CDAttendanceStore.swift` (the `canWrite` region only), `Cosmic Daybook/Attendance/Views/AttendanceRow.swift`, `Cosmic Daybook/Attendance/Delight/AttendanceWelcomeBack.swift`, `Cosmic Daybook/Work/Support/SchoolDayChecker*.swift`, `Cosmic Daybook/Sharing/RemoteImportReloader.swift`, `Cosmic Daybook/Sharing/ClassroomIdentity.swift` (read-side caching only).
- **Sy** (#2, #9, #10, #11, #12, #13, #15): `Daybook Assistant/Sync/AssistantFilingHold.swift`, `AssistantStack.swift`, `AssistantShareAttacher*.swift`, `AssistantBootstrapper.swift` (the `phase` assignment only), `AssistantBootstrapper+Class.swift`, `AssistantBootstrapper+AccountDecision.swift`, `AssistantSendingReport.swift`, `Cosmic Daybook/Services/Sync/UnsentChangesKeepAlive.swift`, `Cosmic Daybook/AppCore/Persistence/CloudKitConfigurationService.swift`, `Cosmic Daybook/Sharing/ClassroomSharingService.swift`, `ClassroomNames+Arrival.swift`, `Cosmic Daybook/Utils/CoreData/NSManagedObjectContext+SafeFetch.swift`, the project file (dropping `PersistentHistoryProcessor+StoreHistory.swift` from the Assistant target). Not the polling loops in `+Rebuild.swift` and `+Leave.swift` (left as they are; bounded and short).
- **FD** (#1, #16, #17, #18, #19, #20, #21): `Daybook Assistant/FrontDesk/*`, `Daybook Assistant/Reminders/*`, `Daybook Assistant/Sync/AssistantBootstrapper+ParentLocker.swift`, `AssistantBootstrapper+Rebuild.swift`, `AssistantBootstrapper+Leave.swift`, `AssistantBootstrapper+Observers.swift`, `Cosmic Daybook/Attendance/Email/*`, `Cosmic Daybook/Attendance/ParentLocker/*`, the notebook's `AttendanceEmail.swift` deadline picker (#17).
- **SR** (#7, #25, #26, #27, #28, #29, #30, #31): `Daybook Assistant/Siri/*`, `Daybook Assistant/Restock/*`, `Daybook Assistant/Schedule/*`, `Cosmic Daybook/Siri/*`, `Cosmic Daybook/Sharing/ClassroomPermissions.swift`, `Cosmic Daybook/Supplies/**`, `Cosmic Daybook/Attendance/Store/CDAttendanceStore.swift` (the `discard` region only, #29), `Daybook Assistant/AssistantSampleClass.swift` (the Siri name refresh only).
- **Sh** (#8, #14, #32, #33, #34, #35): `Daybook Assistant/AssistantApp.swift`, `AssistantRootView.swift`, `AssistantTabs.swift`, `AssistantSampleClass.swift` (`seedHistory` only), `Daybook Assistant/Onboarding/*`, `Daybook Assistant/Wallpaper/*`, `Daybook Assistant/Sync/AssistantClassroomSheet*.swift`, `AssistantBootstrapper.swift` (line 178 and the protected-data retry only).

## Decisions

- **D1. Behavior and look unchanged.** A fix that would change what she sees is not made; it's noted for Danny instead.
- **D2. #7's view-only memory lives in `ClassroomPermissions`'s setter**, so the Leave path that already sets the flag false clears it too and no agent but SR touches the flag.
- **D3. #11 makes `container` a `static let`**, notebook-wide; the identifier doesn't change.
- **D4. The two Bootstrapper polling loops stay** (#15); they're bounded and a continuation would be more code than the gain.
- **D5. Each agent builds the smallest scheme covering its change** and runs only its suites on its leased simulator; the main session does the one full build of both apps and the one whole-suite run.

## Decided during the run

- **Hand-made sibling worktrees can't be written by this session's agents.** A hook refuses Edit/Write into `.claude/worktrees/daybook-fix-*` ("Do not write to other worktrees' files from this session"). Each first-run agent wrote its fixes as a patch in the scratchpad instead; a second run per agent in a harness-made worktree (`isolation: worktree`, which starts at the pushed main, 19cfecc1 at the time) applies, builds, tests and commits it. The five empty `daybook-fix-*` worktrees are removed at the end.
- **No simulator named plain "iPhone 17" exists any more** (every one is a leased, renamed copy), so `CLAUDE.md`'s `-destination "platform=iOS Simulator,name=iPhone 17,OS=27.0"` fails; builds go by the leased id, `-destination "platform=iOS Simulator,id=$(~/.claude/bin/sim-lease)"`. The recipe in `Cosmic Daybook/CLAUDE.md` gets the same change in Phase 3.
- **#15's target-membership item is dropped**: `PersistentHistoryProcessor+StoreHistory.swift` is needed by `PersistentHistoryProcessor.swift`, which the Assistant compiles for `CoreDataStack`; the "never called" is because the processor is made inside `#if !ASSISTANT_APP`.
- **#8's `.task(id:)` stays on its Section**: moving it to the Form changed when the notifications prompt appears on small phones.
- **#31's `currentAuthor()` stays per change**: the model's comment says the author is read fresh before every change so a name set in the Classroom sheet counts at once.
- **#32's child count stays the roster's**: a store count would include test, duplicate and departed children.
- **Sy's #2 has one visible effect** by design: while the container can't share, the sync line and Leave's Wait now say iCloud isn't ready (or "quit and reopen" after a dead delegate) instead of showing the hold lifted; that is what the report's fix intends.

## Open questions

(none yet)
