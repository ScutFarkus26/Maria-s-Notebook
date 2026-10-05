# Who made a change: every device thinks it is "you"

> **Not started.** Written 2026-10-04, from Danny's screenshot of his assistant's office run.
> In short: Each device saves CloudKit's stand-in name for "the person using this device" as its own ID, so the guide's changes read "you" on the assistant's phone; save the real ID instead and read the stand-in as no ID.

## Goal

On the assistant's phone, what Danny added reads "Added by your guide", and on Danny's devices what she did reads with her name, never "you". Records already stamped the wrong way read correctly too, with no data change.

## What happened (the investigation)

The screenshot: the Assistant's office run showed Toilet Paper and Paper Towels as "One-off · Added by you". Danny added them, not her. Two separate things went wrong.

1. **"One-off".** Both are shelf items (staples) that went Out when the Mac's count-to-level launch step ran (`RestockLevelBackfill`). Their open needs reached her phone, but the staples did not. The old staples are still only in Danny's private store, waiting for the Mac setup step "Add Them to the Share" (Tide row "After the Restock update, on the Mac: set the order recipient, add the old supplies and orders to the share…", still open). Without the staple, `runDetail` and the tag treat the need as a one-off. This is Danny's step, not a bug. The plan adds a small fallback so a need from a staple she can't see doesn't claim to be a one-off.
2. **"Added by you".** The launch step stamped each need with `RestockAuthor.current(role: .leadGuide)`: `addedByID` = the Mac's `ClassroomIdentity.currentUserRecordName` and no name. On her phone, `RestockAuthor.reads` (`Cosmic Daybook/Supplies/RestockModels.swift`) returns "You" only when that ID equals her own saved ID. With no ID match, a nameless change reads "your guide". So **both devices had saved the same ID.** Danny confirmed she uses her own Apple Account.
   - Why: `ClassroomSharingService.publishParticipants` (`Cosmic Daybook/Sharing/ClassroomSharingService.swift`, ≈line 197) saves `share.currentUserParticipant?.userIdentity.userRecordID?.recordName`. For the person using the device, CloudKit gives that as the stand-in `__defaultOwner__` (`CKCurrentUserDefaultName`), not the account's real record name, so every device saves the same value. The bug-fix branch already treats `__defaultOwner__` as "no record name" for the owner's ID (`RestockAuthor.assistant(in:)`), which fits.
   - It also only gets saved when a members screen refreshes participants, so a device that never opened one has no ID at all.

**Everything that compares these IDs, and what goes wrong today:**

| Where | Wrong today |
|---|---|
| `RestockAuthor.reads` (Restock, notebook + Assistant, MCP `list_supplies`) | The guide's changes read "you" on her phone; her named changes read "You" on the Mac |
| `AttendanceRules.markerName` (assistant-role marks only; guide marks use the role, so they are fine) | On the Mac, her marks read "you"; on her phone, a second assistant's marks read "you" |
| `AttendanceEmailLog.Send.senderName` (front-desk email) | Checks the ID before the role, so the guide's send reads "you" on her phone |
| `ClassroomMembersCard` "isYou" (`ClassroomSharingViewParts.swift` ≈line 258) | Works by accident, since only your own entry carries the stand-in |
| `AttendanceDayLocks` `lockedByID` | Written, never compared; nothing shows wrong |

## Progress
- [ ] Phase 1: Real IDs, the stand-in read as no ID, the shelf-item fallback (session: here, once the bug-fix merge is on main) · est. ~2–3% weekly
- [ ] Phase 2: Danny's steps (Tide rows, no session)

## Cost

About 2–3% of the weekly all-models limit (Max). 8% is used, 92% left until Sun Oct 11, 4 pm. Fits easily.

## Decisions

- **Wait for the bug-fix merge.** `claude/bug-hunt-report-ad32c2` (bc349eaf, not on main yet) changes `RestockModels.swift`, `AttendanceRules.swift`, `AttendanceEmailLog.swift`, `ClassroomSharingService.swift` and the Assistant's Restock model, and already fixes bug-hunt item 4 (the Restock tab now reads its author at each change). Danny asked to wait for that session to merge to main. Phase 1 starts with `sync_with_base_branch` and works on top of it.
- **The real ID comes from `CKContainer.userRecordID()`**, fetched once per launch in both apps (the container the sharing service already uses) and saved in `ClassroomIdentity.currentUserRecordName`. It is the account's real record name in this container, the same one other people see on its share participant entry, and it doesn't wait for a members screen. A failed fetch (offline) keeps what was saved.
- **The stand-in is never saved and is read as no ID.** One helper (`ClassroomIdentity.realRecordName(_:)`: nil for empty, `CKCurrentUserDefaultName`, "unknown", "self") is used wherever an ID is saved, stamped or compared. The getter also drops a stand-in already saved, so devices heal on the next launch.
- **No data repair.** Records already stamped with the stand-in fall through to the role and the name, which already read correctly. Restock: nameless = the guide ("your guide" on her phone, "You" on the guide's devices). Attendance and email: by the stamped role, then her name. The only case still read wrong is a stand-in-stamped Restock change by an assistant who never gave a name, which would read as the guide's. That's rare (the Assistant asks for a name at setup), so it's left alone.
- **The members list** marks your own row by `participant == share.currentUserParticipant`, not by comparing IDs. `publishParticipants` stops writing `ClassroomIdentity`.
- **A need from a staple she can't see** (it has a `supplyID` but no staple on this phone) reads "From the shelf" and no longer gets the "One-off" tag; the tag becomes a neutral "Shelf". The real fix is Danny's "Add Them to the Share" step.
- **Ruled out:** stamping a role on Restock records (a schema change and a CloudKit deploy, for a case the name already settles), and a migration that rewrites old stamps (whose they were can't be known).

## Phase 1: Real IDs, the stand-in read as no ID, the shelf-item fallback

- Who: main session (Opus 5.5, high). Small and interlocking across shared files, with the context already built here; no agent needed.
- Steps:
  1. Bring the branch up to date: `sync_with_base_branch`, once main has the bug-fix merge (check `git log origin/main` for bc349eaf or its merge).
  2. `Cosmic Daybook/Sharing/ClassroomIdentity.swift`: `realRecordName(_:)`; the getter returns the real one only; a `refreshRecordName(container:)` async that calls `userRecordID()` and saves its `recordName`.
  3. Call it once at launch in both apps: the notebook's `AppBootstrapper` (after CloudKit is up), and the Assistant's `AssistantBootstrapper` (`Daybook Assistant/Sync/AssistantBootstrapper.swift`). The Sample Class and Debug's fake notebook skip it.
  4. `ClassroomSharingService.publishParticipants`: keep `currentUserRecordName` for itself only if real; stop writing `ClassroomIdentity`. `ClassroomMembersCard`: `isYou` by `currentUserParticipant`.
  5. Read the stand-in as no ID in `RestockAuthor.reads` and `RestockAuthor.current`, `AttendanceRules.markerName`, `AttendanceEmailLog.Send.senderName`, and the stamps (`CDAttendanceStore` `recordedByID`, `AttendanceEmailLog` `sentByID`, `RestockService.stampAdded`/`stampLevel`, day-lock `lockedByID`).
  6. `Daybook Assistant/Restock/AssistantRestockModel+Wording.swift` `runDetail`, and the tag in `AssistantRestockStyle.swift`: a need with a `supplyID` whose staple isn't here reads "From the shelf" with a "Shelf" tag.
  7. Tests: `RestockAuthor.reads` (the guide's stand-in-stamped need reads "your guide" on her phone and "You" on the Mac; her named stand-in change reads her name on the Mac), `realRecordName`, `markerName` and `senderName` with stand-in IDs, and the shelf-item fallback in `AssistantRestockTests`.
- Cost: ~2–3% (a small feature across both apps; adds 50% for two schemes and their test suites).
- Done when:
  - `Scripts/locked_xcodebuild.sh` builds the notebook (iOS) and the Assistant cleanly.
  - `-only-testing:` green on the leased simulator (`-parallel-testing-enabled NO`): `Cosmic Daybook Tests/AttendanceRulesTests`, `AttendanceEmailLogTests`, `RestockNeedTests`, `MCPSupplyAndResourceToolsTests`, `MCPOrderToolsTests`, and the Assistant's `AssistantRestockTests`, `AssistantSiriRestockTests`, `AssistantMenuTests`.
  - Then the one full build (notebook iOS + Mac, Assistant) and the whole notebook and Assistant suites, green; simulator shut down with `sim-lease --done`.
  - `grep -rn "currentUserParticipant" "Cosmic Daybook"` shows no write to `ClassroomIdentity`.
  - Merged to main and pushed (Danny's OK at close-out).
- Hand off: no.

## Phase 2: Danny's steps (Tide rows)

- Mac first: the open Tide row "After the Restock update, on the Mac: … Settings › Sharing › Add Them to the Share". That alone turns her "One-off" rows back into Toilet Paper (Out, Bathrooms) and Paper Towels (Out).
- Roll out the fix (Mac, iPhone, iPad, and an Assistant TestFlight), using the `roll-out` skill when Danny asks.
- Device check (new Tide row): on her phone, the office run shows your items as "your guide"'s. Mark a child on her phone, then check the Mac reads it with her name, not "you".

## Starting a phase
Read the plan usage (`get_usage`) and note the weekly % used next to the phase under Progress ("started at N%").

## Ending a phase
1. Check every "Done when" item for the phase.
2. Tick the phase under Progress and note anything that differed from the plan. Read the plan usage again and note the actual cost (end % minus start %).
3. Add a row to the log in `~/.claude/skills/plan-efficiently/references/cost-estimates.md`.
4. No build board for this plan.
5. Make every "not verified", "for your review" or "check on a device" item from this phase a row in `Areas/App Development/Cosmic Daybook/TODO.md` (`add_action`), skipping ones already there; the plan keeps one plain line plus the row's `tide://` link.
6. Run /close-out. It sets the plan's status line and runs `docs-index`.
7. Phase 2 is Danny's; no starter prompt.

## Open questions
None. One thing a device will settle: that `userRecordID()` gives the same real name other devices see on the share. If her phone still reads your items as "you" after the roll-out, that's the place to look.
