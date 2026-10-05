# Names you set yourself

> **Not started.** Written 2026-10-05, after the who-made-a-change fix (main 826a8214); Danny wants his own name, not "your guide", and everyone's name changeable.
> In short: A small shared list of each person's current name, set by that person, so the Assistant says "Danny" instead of "your guide" and a rename shows everywhere, old entries included.

## Goal

Danny sets his name once in Settings › Classroom, and each assistant sets hers in the Assistant, as now. Either can change it at any time. Her phone then says "Marked Out by Danny", "Danny is ordering" and "Present · by Danny" instead of "your guide". Danny's devices show each assistant's current name. A rename shows on every device, on old entries too, because names are looked up when shown, not frozen when stamped.

## Progress
- [x] Phase 1: The shared name list: record type, schema 16, share, backup, lookup (agent `feature-phase-deep`) · est. ~3–5% weekly · started at 10% · f8cf505b. Notebook 253 focused + Assistant 235 tests green; iOS, Assistant and Mac build. Differed: a name an assistant set on an older build counts as waiting and joins the list at launch; the guide's per-device copy is cleared once his row is written. Launch wiring left outside its files: notebook done in the main session; the Assistant's goes to Phase 3. Docs counts (DATA_MODELS, BACKUP_SYSTEM) for Phase 4.
- [ ] Phase 2: The notebook: "Your name" in Settings › Classroom, and names on its screens (agent `feature-phase`) ‖ Phase 3 · est. ~1–2% weekly (parallel because Phase 1 makes every shared signature change)
- [ ] Phase 3: The Assistant: her name sheet writes the list, and Restock and attendance say your name (agent `feature-phase`) ‖ Phase 2 · est. ~1–2% weekly
- [ ] Phase 4: Combine, full build, whole suites, simulator look, review, Development schema init, merge (session: here) · est. ~2–3% weekly
- [ ] Phase 5: Danny's steps: deploy schema 16 to Production, roll out everything together, set names, check (Tide rows, no session)

## Cost

About 7–12% of the weekly all-models limit (Max). 10% used, 90% left until Sun Oct 11, 4 pm. Fits easily.

## Decisions

- **A shared list, looked up when shown.** (Danny, 2026-10-05: "Can I set it myself and have it changeable? Same for them." He chose the shared list over stamping names.) Stamps keep what they hold today; screens look up the current name by the stamp's record name. So a rename reaches old entries, and the fixed Restock sentences can name the guide.
- **Everywhere in Restock** (Danny). On her phone, the who-lines and the fixed sentences use the guide's name: "Danny is ordering", "Danny orders it", "Danny adds the things the class always needs", "Danny sends the order", and Siri's "It's on Danny's order list". Without a name: today's "your guide" wording, unchanged.
- **Attendance and the front-desk email use the same lookup.** Her phone says "Present · by Danny" and "Sent by Danny"; your devices show her current name. That's one source for every name, so no two screens disagree.
- **The guide's name, in order:** the name he typed, then Apple's name for the share's owner (`AssistantBootstrapper.guideName`, as today, display only), then "your guide". An assistant's name: the one she typed (current, from the list), then the name stamped on the entry, then "an assistant" / "another assistant".
- **The record: `ClassroomPerson`**, a new shared type, one row per person.
  - Fields: `id`, `recordName` (the person's real CloudKit record name from `ClassroomIdentity`), `roleRaw`, `displayName`, `createdAt`, `modifiedAt`.
  - Each person writes only their own row, upserted by `recordName`. His Mac and iPad will each write one before the other's arrives, so reads take the newest `modifiedAt`.
  - Cleanup keeps a fixed survivor every device agrees on: the oldest by (`createdAt`, `id`), as Restock's `reconcile` does, with the newest name copied onto it. Only the row's owner runs it.
  - Clearing a name stores an empty name rather than deleting the row; a delete would let the other device's duplicate bring the old name back.
  - The guide's row lives in the private store and joins the share through `SharedStoreOrphanGuard`, which only sees view-context saves. So every write, the waiting one included, saves on the view context.
  - An assistant's row goes straight into the shared store, as her marks do.
- **Where a name lives.**
  - A person's row is the truth. The Settings field on any of his devices loads from his row, not from that device's own stored value.
  - A name typed before the real record name is known waits in `ClassroomIdentity.displayName` (per device) and is written once `refreshRecordName()` returns.
  - Her phone keeps using `ClassroomIdentity.displayName` for her own stamps, as now.
- **An assistant who leaves:** her row stays in the share, so her name still shows on her old entries. There's no way to remove it, and none is needed for now.
- **Privacy:** the share gives assistants read-write access, so nothing in the app stops one editing someone else's row. Accepted: the app only ever writes your own.
- **It needs the real record name** from the who-made-a-change fix. A row is written only once `ClassroomIdentity.currentUserRecordName` is known. A name set before then is written as soon as `refreshRecordName()` returns.
- **The names are what people typed.** That's allowed to be stored, unlike Apple's name for the owner, which stays display only. They're shown as typed: a first name, or whatever the person prefers.
- **Your own name** appears only in Settings and to others. Your own changes still read "you" to you.
- **Schema 16 is a CloudKit schema change.**
  - The new type must reach the Development schema (Claude, with a `-InitializeCloudKitSchema` Development build on a simulator, as for Restock) and then be deployed to Production by Danny **before any device runs a build that has it**.
  - With schema 12, skipping that order stopped classroom sync. All devices update together.
- **Backup.** It's a model-driven `ModelRow` type in `Cosmic Daybook/Backup/ModelRowKinds.swift`, with the format version bumped and a round-trip test. Restore matches on `id`, like every `ModelRow`; any duplicates a restore makes are folded by the same cleanup.
- **Ruled out:**
  - Reusing `AttendanceEmailSettings` for the guide's name: it's still a schema change, ties names to the email feature, and doesn't cover assistants.
  - Stamping names on entries: a rename wouldn't reach old entries (Danny's choice).
  - Storing Apple's owner name: Apple's terms forbid it.

## Phase 1: The shared name list

- Who: `feature-phase-deep` agent (Opus, xhigh), `isolation: worktree` from main 826a8214 or later. A new shared record type and schema change: the kind of change where a subtle mistake breaks sync.
- Steps:
  1. Model: add `ClassroomPerson` (fields above) to `CosmicDaybook 2.xcdatamodel`, plus the managed class beside the other sharing entities (`Cosmic Daybook/Sharing/`).
  2. Schema 15 → 16 (`CoreDataStack.currentSchemaVersion` and its comment in `CoreDataStack+SchemaVersion.swift`), and every list a shared type must join. Grep each Restock type name (`"Supply"`, `"OrderItem"`) to catch any not named here.
     - Sharing: `CoreDataStack.sharedEntityNames` (`CoreDataStack+Model.swift`); `ClassroomShareSetupReport.orderedEntityNames`, its record-name wording and `describe` (`ClassroomSharingService+Setup.swift`); `ClassroomSharingService+Contents`.
     - **`ClassroomPermissions.assistantWritableEntities`**, or her phone can't write her row.
     - Refresh: `PersistentHistoryProcessor.presentationEntityNames`.
     - The Assistant target's Sources in `project.pbxproj`, for the new entity class and `ClassroomNames.swift` (it lists its files one by one).
     - Backup: `ModelRowKinds`, `BackupEntityTable`, `BackupPlainNames`, `BackupPreviewAnalyzer`, `BackupTypes`, `BackupWriter.formatVersion` and the reader's range, `BackupRestoreRun+LaterTypes`.
     - Pinned tests: `Phase8PreTests`, `Phase5PostTests`, `StoreMigrationTests`, `RestockShareMigrationTests`, `ClassroomShareShrinkMigrationTests`, `PersistentHistoryEntityNotificationTests`, `AssistantSplitStoreTests`, the `CoreDataSchemaVersionTests` digest, and the counts in `Cosmic Daybook/CLAUDE.md`.
  3. `ClassroomNames` (new, `Cosmic Daybook/Sharing/ClassroomNames.swift`):
     - `setMyName(_:role:in:)` upserts this person's row, or removes it on an empty name.
     - `name(forRecordName:in:)`, `guideName(in:)`, and a small snapshot type that screens pass into wording, so a list of rows isn't fetched per row.
     - Reads take the newest row per record name, and only from the store the screen reads (the shared store on the Assistant, as `AttendanceEmailLog.scopeToClassroom` does).
     - Store choice by role via `RestockService.destinationStore`'s rule.
  4. After `ClassroomIdentity.refreshRecordName()` succeeds, write a name that's waiting, on the view context.
  5. Every shared signature change, made here so Phases 2 and 3 only wire callers:
     - `RestockAuthor` (`RestockModels.swift`) carries a display-only names snapshot. `reads` uses the guide's name where it now says "your guide" (including for old stand-in or no-ID stamps reached by the role fallback), and an assistant's current name before her stamped one.
     - `AttendanceRules.markerName` and `AttendanceEmailLog.Send.senderName` take a names snapshot as a defaulted parameter, so no caller in either app breaks.
  6. Backup: a `ModelRow` kind, the format version bump, `BackupFieldCoverageTests`, and a round-trip test.
  7. Tests (new `Cosmic Daybook Tests/Sharing/ClassroomNamesTests.swift`):
     - upsert by record name; newest name wins; the cleanup's survivor is the same from either side;
     - clearing stores an empty name;
     - guide lookup; store scoping;
     - a waiting name is written after the record name arrives, by a view-context save;
     - the guide's row is inserted where `SharedStoreOrphanGuard` sees it;
     - `reads`, `markerName` and `senderName` with a snapshot: an old guide stamp with no ID reads the guide's name on her phone, and her rename reaches her old entry on the guide's devices.
- Cost: ~3–5% (data model and sharing at xhigh; log actuals for agents have come in lower).
- Done when:
  - The notebook (iOS and Mac) and Assistant schemes build through `Scripts/locked_xcodebuild.sh`, the iOS ones aimed at the leased simulator's id.
  - `-only-testing:` green: `ClassroomNamesTests`, `ClassroomIdentityTests`, `BackupFieldCoverageTests`, the backup round-trip suite, every pinned test named in step 2, `AttendanceRulesTests`, `AttendanceEmailLogTests`, `RestockNeedTests` and `RestockWhoLineTests`.
  - The whole Assistant test suite green: it is small, and the shared files compile into it.
  - `sim-lease --done` run.
  - Reply in at most 15 lines.
- Hand off: no. The main session merges it and launches Phases 2 and 3 from it.

## Phase 2: The notebook: your name in Settings, and names on its screens

- Who: `feature-phase` agent (Opus, high), worktree from Phase 1's commit (merged into this branch first). Settings UI plus wiring a lookup into existing wording.
- Steps:
  1. Settings › Classroom: a "Your name" field for the lead guide ("Your assistants see this name"), saving through `ClassroomNames.setMyName`. Copy goes in `SettingsCopy`.
  2. Restock on the guide's devices (`RestockView+Needs.swift`, `RestockView+Shelf.swift`, `StapleHistorySheet.swift`): give `RestockAuthor` the names snapshot (Phase 1 added it). Add `"ClassroomPerson"` to the page's watch list so a rename redraws.
  3. Attendance (`AttendanceGrid`, `AttendanceExpandedView+FrontDesk`, and `TodayViewModel+Refresh`'s watch list): pass the snapshot to `markerName` / `senderName`.
  4. The MCP lines that name people (`MCPNotebookTools+Supplies.swift`) pass the snapshot too.
  5. Tests: the wording functions with a names snapshot (current name beats stamped name; no row → stamped name).
- Owns: `Cosmic Daybook/Settings/…`, `Cosmic Daybook/Supplies/RestockView*`, `StapleHistorySheet.swift`, the notebook's attendance views and `TodayViewModel+Refresh`, `MCPNotebookTools+Supplies.swift`, and a new test file. Neither phase edits `RestockModels.swift`, `AttendanceRules.swift`, `AttendanceEmailLog.swift` or `ClassroomNames.swift` (Phase 1's).
- Cost: ~1–2%.
- Done when:
  - The notebook (iOS) and the Assistant build; `-only-testing:` green for the new tests, `AttendanceRulesTests`, `AttendanceEmailLogTests`, `RestockWhoLineTests` and `MCPSupplyAndResourceToolsTests`.
  - `sim-lease --done` run.
  - Reply in at most 15 lines.
- Hand off: no.

## Phase 3: The Assistant: her name writes the list, Restock and attendance say your name

- Who: `feature-phase` agent (Opus, high), worktree from Phase 1's commit. Wording across several screens plus one write path.
- Steps:
  1. `Daybook Assistant/Onboarding/AssistantNameSheet.swift` (and setup): saving her name also calls `ClassroomNames.setMyName(role: .assistant)`. The sample class writes nothing to the share.
  2. `AssistantRestockModel.live(...)` builds its author with the names snapshot (Phase 1's), the guide's name taken from the list first and then `AssistantBootstrapper.guideName`. `AssistantTabs` passes it. Add `"ClassroomPerson"` to `AssistantRestockModel.restockEntities` and the attendance views' watch lists, so a rename redraws.
  3. (Folded into step 2.)
  4. Restock's fixed sentences, with today's wording as the fallback:
     - `AssistantOfficeRunView` ("… is ordering"),
     - `AssistantRestockModel+Wording` ("… orders it"),
     - `AssistantRestockView` ("… adds the things the class always needs"),
     - `AssistantWeNeedSheet` ("… sends the order"),
     - `AssistantSiriRestock` ("It's on …'s order list"; Siri reads the list itself).
  5. Attendance and the front-desk row on her phone pass the list's guide name as `guideName`, before Apple's.
  6. Tests in `AssistantRestockTests` / `AssistantRestockWordingTests`: each sentence with and without a guide name, her rename reaching an old entry, and a second assistant's current name.
- Owns: `Daybook Assistant/…` and the Assistant test files.
- Cost: ~1–2%.
- Done when:
  - The Assistant and the notebook (iOS) build; `-only-testing:` green for `AssistantRestockTests`, `AssistantRestockWordingTests`, `AssistantSiriRestockTests` and `AssistantMenuTests`, plus the attendance and front-desk suites it touches.
  - `sim-lease --done` run.
  - Reply in at most 15 lines.
- Hand off: no.

## Phase 4: Combine, check, schema init, merge

- Who: main session (Opus 5.5, high).
- Steps:
  1. Merge Phases 2 and 3.
  2. One full build: notebook iOS and Mac, and the Assistant.
  3. One whole-suite run each, on the leased simulator, aimed by id.
  4. On the simulator, with the Assistant's Sample Class seeded with a guide name, screenshot the office run's "… is ordering", a held row, and a shelf tile.
  5. `/code-review`; fix what holds up.
  6. Development schema init for schema 16: a Debug build with `CLOUDKIT_ENVIRONMENT=Development` and `-InitializeCloudKitSchema`, on a leased simulator, as in `docs/Plans/Plan - Restock.md` Phase 4. Danny's developer account is signed in in the built-in browser pane (2026-10-05): open CloudKit Console there, confirm `CD_ClassroomPerson` and its fields in Development, then ask Danny in chat before clicking Deploy Schema Changes to Production (a hard-to-undo change, his yes each time).
  7. Merge to main and push, with Danny's OK. **Don't roll out** until Danny has deployed schema 16 to Production.
- Cost: ~2–3%.
- Done when:
  - All builds clean; both whole suites green.
  - The screenshots show the name.
  - The Development init logged no CloudKit error.
  - On main and pushed.
  - Tide rows made (Phase 5).
- Hand off: no.

## Phase 5: Danny's steps (Tide rows)

1. CloudKit Console (container iCloud.DanielSDeBerry.MariasNoteBook): check `CD_ClassroomPerson` in Development, then **Deploy Schema Changes to Production**. Nothing with schema 16 may run on any device before this.
2. Roll out (Mac first, iPhone, iPad). This also carries the who-made-a-change fix, if it isn't out yet. **The Assistant TestFlight goes to internal testers only** (Danny, 2026-10-05: "you can upload it and send to internal"); no external group until he says so.
3. Set your name in Settings › Classroom; have her check hers in the Assistant (person button › Your name).
4. Check on her phone: the office run says "Danny is ordering", holding your item says "Marked Out by Danny", and attendance says "by Danny". Rename yourself and see her phone follow. On the Mac, her current name shows on her marks and Restock changes.

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
None.
