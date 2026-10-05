# Who made a change: every device thinks it is "you"

> **Working on it.** Phases 1–4 on main 2026-10-05; Phase 5 (Danny's roll-out and device check) left. Written 2026-10-04, from Danny's screenshot of his assistant's office run; revised the same evening after the design review and mockups.
> In short: Save each device's real CloudKit ID instead of the shared stand-in, show who added something only when it isn't you, and make the office run a plain errand list (what, how urgent, where it goes).

## Goal

On the assistant's phone, the office run shows only what to grab, how urgent it is and where it goes; holding a row says who asked for it. On Danny's devices, Restock shows a name only on what an assistant did, and a banner says when shelf items haven't reached the share yet. Underneath, every device knows its own real ID, so "you" is never someone else, on any screen, including records already stamped the wrong way.

## What happened (the investigation)

The screenshot: the Assistant's office run showed Toilet Paper and Paper Towels as "One-off · Added by you". Danny added them. Two separate things went wrong.

1. **"One-off".** Both are shelf items (staples) that went Out when the Mac's count-to-level launch step ran (`RestockLevelBackfill`). Their open needs reached her phone, but the staples did not. The old staples are still only in Danny's private store, waiting for the Mac setup step "Add them to the share" (Tide row "After the Restock update, on the Mac: set the order recipient, add the old supplies and orders to the share…", still open). Without the staple, the row falls back to one-off wording.
2. **"Added by you".** The launch step stamped each need with `RestockAuthor.current(role: .leadGuide)`: `addedByID` = the Mac's `ClassroomIdentity.currentUserRecordName`, no name. On her phone, `RestockAuthor.reads` (`Cosmic Daybook/Supplies/RestockModels.swift`) returns "You" only when that ID equals her own saved ID; a nameless change with no ID match reads "your guide". So both devices had saved the same ID. Danny confirmed she uses her own Apple Account.
   - Why: `ClassroomSharingService.publishParticipants` (`Cosmic Daybook/Sharing/ClassroomSharingService.swift`) saves `share.currentUserParticipant?.userIdentity.userRecordID?.recordName`. For the person using the device, CloudKit gives that as the stand-in `__defaultOwner__` (`CKCurrentUserDefaultName`), so every device saves the same value. Main already treats `__defaultOwner__` as "no record name" for the owner's ID (`RestockAuthor.assistant(in:)`), which fits.
   - It is also saved only when a members screen refreshes participants, so some devices have no ID at all.

**Everything that compares these IDs, and what goes wrong today:**

| Where | Wrong today |
|---|---|
| `RestockAuthor.reads` (Restock in both apps, MCP `list_supplies`) | The guide's changes read "you" on her phone; her named changes read "You" on the Mac |
| `AttendanceRules.markerName` (assistant-role marks; guide marks go by role and are fine) | On the Mac, her marks read "you"; on her phone, a second assistant's marks read "you" |
| `AttendanceEmailLog.Send.senderName` (front-desk email) | Checks the ID before the role, so the guide's send reads "you" on her phone |
| `ClassroomMembersCard` "isYou" (`ClassroomSharingViewParts.swift`) | Works by accident |
| `AttendanceDayLocks` `lockedByID` | Written, never compared |

## Progress
- [x] Phase 1: Real IDs, the stand-in read as no ID (session: here) ‖ Phases 2 and 3 · est. ~1–2% weekly · started at 8% · actual ~1% (8→9, noisy: two agents and other sessions running). Differed: the generic-simulator build compiled twice (Intel and Apple simulators); the CLAUDE.md recipe's "iPhone 17, OS=27.0" destination no longer exists. 52 notebook + 21 Assistant tests green.
- [x] Phase 2: The Assistant's office run as an errand list (agent `feature-phase` on Sonnet) ‖ Phases 1 and 3 · est. ~1% weekly · started at 8% · 04a92d53. Differed: also fixed `AssistantRestockOfficeRunTests` (tags are optional now); a ticked row keeps its rank until the tick is undone or forgotten (ticks already survive `load()`); a ticked row's hold menu says "Put it back".
- [x] Phase 3: Restock on the guide's devices: names only for others, the share banner (agent `feature-phase`) ‖ Phases 1 and 2 · est. ~1–2% weekly · started at 8% · 7964647d. Differed: the banner opens Settings › Classroom (there is no separate Sharing category; on iPhone it lands on the Settings list, one tap away); its wording also covers list items and history-only gaps. Phases 1–3 together: 8→10%, noisy.
- [x] Phase 4: Combine, full build, whole suites, simulator look, merge (session: here) · est. ~2% weekly · started at 10%. Combined cleanly; notebook iOS + Mac and Assistant build; notebook 2,469 and Assistant 234 tests green; code review found nothing; office run and hold menu screenshots match the mockups. Merged to main 2026-10-05 with Danny's OK. Actual ~0–1% (10→10).
- [ ] Phase 5: Danny's steps (Tide rows, no session)

## Cost

About 5–7% of the weekly all-models limit (Max). 8% used, 92% left until Sun Oct 11, 4 pm. Fits easily. The three parallel phases share one build queue, so they finish about as fast as they would one after another, but none waits on another's code.

## Decisions

- **Builds on main f8c0bade** (the Assistant bug fixes, merged 2026-10-04 evening). It already reads the Restock author at each change (bug-hunt item 4) and treats `__defaultOwner__` as no owner ID.
- **Who-added rule: show who only when it isn't the person looking.** (Danny, from the mockups.) The data is still stamped on every record; only what rows show changes.
  - Her phone's office run: no who line on rows. Holding a row shows it ("Added by your guide · Oct 3", "Marked Out by your guide · Oct 3").
  - Guide's devices (Restock needs, shelf by-lines): no label on your own; "Added by Rivka" / "Rivka · 8:12 AM" on an assistant's.
  - History sheets and hold menus keep the full who-and-when, as now.
  - MCP tool output is unchanged (Claude reads the full record).
- **Office run as an errand list.** (Danny, from the mockups.)
  - Row: name (with ×quantity), second line = the staple's place when it has one, else nothing.
  - Tag: urgency only, Out (red) or Low (amber). No tag for one-offs, a staple she can't see, or a stray Stocked staple's need. This replaces the earlier "One-off"/"Shelf"/"From the shelf" idea.
  - Order: Out, then Low, then the rest, oldest first within each. A row ticked off keeps its place until the list is reloaded, rather than jumping when its staple turns Stocked.
  - Header: just "4 to grab" (or "All done. Thank you!"); the "Grab these" heading goes; footer becomes "Checked-off shelf items go back to Stocked for everyone."
  - Hold menu: the who-line as its header, then "Got it" (the same as tapping). No "Copy name".
- **Share banner on the guide's Restock page**: "2 shelf items aren't shared with your assistant yet." Its button opens Settings › Classroom Sharing, where "Add them to the share" already lives. It doesn't share anything itself: sharing already-shared records caused the 2026-09-28 incident, and one path to it is enough. Shown only to the lead guide while the classroom is shared, counting only Restock's types (staples, needs, staple history), checked at most once per page visit and not on every save.
- **The real ID comes from `userRecordID()` on the classroom's container**, `CloudKitConfigurationService.container`, never `CKContainer.default()`: record names differ per container, and the notebook's default container is not the shared one. Fetched once per launch in both apps and saved in `ClassroomIdentity.currentUserRecordName`. It is the account's real record name in this container, the same one other people see on its share participant entry, and it doesn't wait for a members screen. A failed fetch (offline) keeps what was saved.
- **The stand-in is never saved and is read as no ID.** One helper, `ClassroomIdentity.realRecordName(_:)`, returns nil for empty, `CKCurrentUserDefaultName`, "unknown" and "self". It's used wherever an ID is saved, stamped or compared, and the getter drops a stand-in already saved, so devices heal on their next launch.
- **`reads` and every compare clean both sides**: the incoming stamped ID as well as this device's, since history sheets, MCP and the Assistant's wording all pass old stamps straight in.
- **First launch after the update:** a screen opened before `userRecordID()` answers has no ID yet and falls back to role and name, which read correctly. Screens don't need to watch for the ID arriving.
- **No data repair.** Stand-in-stamped records fall through to role and name, which read correctly. The one case still read wrong: a stand-in-stamped Restock change by an assistant who never gave a name reads as the guide's. Rare (the Assistant asks for a name at setup); left alone.
- **Members list** marks your own row by `participant == share.currentUserParticipant`. `publishParticipants` stops writing `ClassroomIdentity`.
- **Ruled out:** stamping a role on Restock records (a schema change and CloudKit deploy for a case the name already settles); a migration that rewrites old stamps (whose they were can't be known); a banner button that shares directly (see above); "who added" on every row (Danny's call).
- **Why agents for 2 and 3:** they touch separate files (the Assistant's Restock screen; the notebook's Restock view) and don't need Phase 1's code; Phase 1 stays here because it's subtle and this session has the investigation loaded. Phase 2 runs on Sonnet: wording, a sort and a menu on one screen. Phase 3 stays on Opus for the share-contents read.
- **File ownership, so the parallel phases can't collide:** Phase 1 owns `RestockModels.swift`, `RestockService*`, `ClassroomIdentity.swift`, `ClassroomSharingService.swift`, `ClassroomSharingViewParts.swift`, the attendance and email files, and `RestockNeedTests.swift`. Phase 2 owns `Daybook Assistant/Restock/AssistantRestock*` and `AssistantOfficeRunView.swift`. Phase 3 owns `RestockView*.swift`, `ClassroomSharingService+Contents.swift` and a new test file.

## Phase 1: Real IDs, the stand-in read as no ID

- Who: main session (Opus 5.5, high). Small but subtle, touching sharing identity; the investigation is loaded here.
- Steps:
  1. Bring the branch up to date with main (f8c0bade): `sync_with_base_branch`.
  2. `Cosmic Daybook/Sharing/ClassroomIdentity.swift`: add `realRecordName(_:)`; make the getter return only a real name; add `refreshRecordName(container:)` (async; calls `userRecordID()` and saves its `recordName`).
  3. Call it once per launch in both apps: the notebook's `AppBootstrapper` once CloudKit is up, and the Assistant's `Daybook Assistant/Sync/AssistantBootstrapper.swift`. The Sample Class, tests and Debug's fake notebook skip it.
  4. `ClassroomSharingService.publishParticipants`: keep its own `currentUserRecordName` only if real, and stop writing `ClassroomIdentity`. `ClassroomMembersCard`: work out `isYou` from `currentUserParticipant`.
  5. Read the stand-in as no ID:
     - when reading: `RestockAuthor.reads` / `current` / `assistant(in:)`, `AttendanceRules.markerName`, `AttendanceEmailLog.Send.senderName`;
     - when stamping: `CDAttendanceStore` `recordedByID`, `AttendanceEmailLog` `sentByID`, `RestockService.stampAdded` / `stampLevel`, day-lock `lockedByID`.
  6. Tests:
     - a guide-stamped need carrying the stand-in reads "your guide" on her phone and "You" on the guide's;
     - her named, stand-in-stamped change reads her name on the guide's devices;
     - `realRecordName` (empty, `__defaultOwner__`, "unknown", "self"), including through `RestockAuthor.assistant(in:)` with each `ownerIdentity` stand-in;
     - `reads` cleaning an incoming stand-in ID (history sheets, MCP and wording pass stamps straight in);
     - the backfill path (`RestockService+Needs.swift`, which rebuilds an author from `levelChangedByID`) stamps no stand-in;
     - `markerName` and `senderName` with stand-in IDs.
- Cost: ~1–2% (small, both apps; main session).
- Done when:
  - `Scripts/locked_xcodebuild.sh` builds the notebook (iOS) and the Assistant scheme cleanly.
  - `-only-testing:` green on the leased simulator (`-parallel-testing-enabled NO`): `AttendanceRulesTests`, `AttendanceEmailLogTests`, `RestockNeedTests`, `MCPSupplyAndResourceToolsTests`, plus the new identity tests.
  - `grep -rn "ClassroomIdentity.currentUserRecordName =" "Cosmic Daybook" "Daybook Assistant"` finds writes only inside `ClassroomIdentity` itself (tests excepted).
  - Committed on this branch.
- Hand off: no.

## Phase 2: The Assistant's office run as an errand list

- Who: `feature-phase` agent with `model: "sonnet"` (Sonnet, high), `isolation: worktree` from main f8c0bade or later. Wording, a sort and a menu on one screen.
- Steps (read Decisions › Office run and Who-added rule first):
  1. `Daybook Assistant/Restock/AssistantRestockModel+Wording.swift`: `runDetail` becomes the place line only (empty when none). A new `runWho(_:)` gives the hold menu's header: one-off "Added by …", staple "Marked Out/Low by …", from `author.reads`, with the date.
  2. `Daybook Assistant/Restock/AssistantRestockStyle.swift`: `tag(for:)` returns a tag only for Out and Low; nil otherwise.
  3. `Daybook Assistant/Restock/AssistantRestockModel.swift`: order the run Out → Low → rest, oldest first within each. A ticked row keeps its place until the next `load()`.
  4. `Daybook Assistant/Restock/AssistantOfficeRunView.swift`:
     - header line only, with no "Grab these";
     - the new footer text;
     - no second line when it's empty;
     - a `.contextMenu` with the who-line as header plus "Got it";
     - accessibility: the spoken label drops the tag when there's none, the value is the place, and the who-line is available through the hold menu.
  5. Tests in `Daybook Assistant Tests/AssistantRestockTests.swift`: the sort, the tag, `runDetail`, `runWho` (guide, her own, another assistant), and a ticked row keeping its place.
- Cost: ~1% (small screen change, one scheme, Sonnet).
- Done when:
  - The Assistant scheme builds through `Scripts/locked_xcodebuild.sh`.
  - `-only-testing:` green on the leased simulator: `AssistantRestockTests`, `AssistantSiriRestockTests`, `AssistantMenuTests`.
  - `sim-lease --done` run.
  - Reply in at most 15 lines: files changed, test counts, anything decided differently.
- Hand off: no (the main session combines it).

## Phase 3: Restock on the guide's devices: names only for others, the share banner

- Who: `feature-phase` agent (Opus, high), `isolation: worktree` from main f8c0bade or later. A screen change plus one small read of the share's contents.
- Steps (read Decisions › Who-added rule and Share banner first):
  1. `Cosmic Daybook/Supplies/RestockView+Needs.swift` `detail(for:staple:)`: drop "added by you"; keep "added by <name>" when it isn't you. Make the decision a static, testable function in `RestockView+Needs.swift` (not `RestockModels.swift`, which Phase 1 owns).
  2. `Cosmic Daybook/Supplies/RestockView+Shelf.swift` `byLine(for:)`: empty when it's yours, so your own Out/Low staples show no by-line; an assistant's reads "Rivka · 8:12 AM". History sheets unchanged.
  3. The banner on the Restock page (`Cosmic Daybook/Supplies/RestockView.swift`):
     - Lead guide only, and only while the classroom is shared.
     - Counts the Restock types missing from the share: `ClassroomSharingService.shareContents`, filtered by entity name (`inScope` minus `inScopeAndShared` for the staple, need and staple-history types). Not the dashboard's cached check, which is private and counts every type.
     - Checked once per page appearance, never on saves.
     - Plain-English title: "2 shelf items aren't shared with your assistant yet."
     - Its button opens Settings › Classroom Sharing (`SettingsPaneRoute(category: .classroomSharing)` or the app's existing way to open a pane).
  4. Tests in a new file, `Cosmic Daybook Tests/Supplies/RestockWhoLineTests.swift`: the detail and by-line rule (yours, an assistant's, a nameless one), and the banner's count and wording from a fake contents value.
- Cost: ~1–2% (small, notebook only; adds the contents read).
- Done when:
  - The notebook (iOS) scheme builds through `Scripts/locked_xcodebuild.sh`.
  - `-only-testing:` green on the leased simulator: `RestockNeedTests` and `RestockWhoLineTests`.
  - `sim-lease --done` run.
  - Reply in at most 15 lines: files changed, test counts, how the banner counts, anything decided differently.
- Hand off: no.

## Phase 4: Combine, full build, whole suites, simulator look, merge

- Who: main session (Opus 5.5, high).
- Steps:
  1. Merge the Phase 2 and 3 branches into this branch; resolve any conflicts.
  2. One full build: notebook iOS and Mac, and the Assistant.
  3. One whole-suite run each for the notebook and the Assistant, on the leased simulator.
  4. Launch the Assistant on the simulator with `-AssistantSampleClass`, open the office run, and screenshot it: the list, then a held row. Compare against the mockups and fix anything off.
  5. Code review of the combined diff (`/code-review`), and fix what holds up.
  6. Merge to main and push, with Danny's OK at close-out.
- Cost: ~2% (combine, full build, suites, one sim look).
- Done when:
  - All builds clean; both whole suites green.
  - The office run screenshots match the mockups (Out first, place lines, no who lines, the hold menu header).
  - `sim-lease --done` run.
  - On main and pushed.
- Hand off: no.

## Phase 5: Danny's steps (Tide rows)

Checks after the roll-out: [Check "who added it" on my assistant's phone and the Mac](tide://box/Areas/App%20Development/Cosmic%20Daybook/TODO.md?text=Check%20%22who%20added%20it%22%20on%20my%20assistant%27s%20phone%20and%20the%20Mac%3A%20no%20more%20%22you%22%20for%20my%20changes).

- **Mac first**, the open Tide row: Settings › Classroom Sharing › "Add them to the share". This alone turns her "One-off" rows back into Toilet Paper (Out, Bathrooms) and Paper Towels (Out).
- **Roll out the fix**: Mac, iPhone, iPad, and an Assistant TestFlight, with the `roll-out` skill when Danny asks.
- **Device check** (new Tide row): on her phone, the office run shows Out items first with no "you"; holding one of your items says "your guide". Mark a child on her phone and check the Mac names her, not "you". On the Mac, the Restock banner is gone once everything is shared.

## Starting a phase
Read the plan usage (`get_usage`) and note the weekly % used next to the phase under Progress ("started at N%").

## Ending a phase
1. Check every "Done when" item for the phase.
2. Tick the phase under Progress and note anything that differed from the plan. Read the plan usage again and note the actual cost (end % minus start %).
3. Add a row to the log in `~/.claude/skills/plan-efficiently/references/cost-estimates.md`.
4. No build board for this plan.
5. Make every "not verified", "for your review" or "check on a device" item from this phase a row in `Areas/App Development/Cosmic Daybook/TODO.md` (`add_action`), skipping ones already there; the plan keeps one plain line plus the row's `tide://` link.
6. Run /close-out. It sets the plan's status line and runs `docs-index`.
7. Every phase runs in this session or as its agent; no starter prompts.

## Open questions
None. A device will settle one thing: that `userRecordID()` gives the same real name other devices see on the share. If her phone still reads your items as "you" after the roll-out, that's the place to look.
