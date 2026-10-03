# Restock: Supplies + Orders as one page, shared with the Daybook Assistant

Mockups: canvas https://claude.ai/artifact/BBSwXMHajtcQRK2rggK1Eo (Before ×3 with numbered findings,
After Mac ×4, Assistant iPhone ×4, interactive in Play). Analysis 2026-10-03 on
`claude/inventory-tracking-design-d3a470`. Built on `claude/restock-feature-build-ec3135` (worktree
`.claude/worktrees/groups-view-analysis-9432b3`). Nothing reaches main until Danny has looked.

## Progress
- [x] Phase 1: data layer (schema 15, backup v37, RestockService), `a97b3439` (session: build)
- [ ] Phase 2A: notebook Restock page, Today card, navigation (agent) ‖ 2B ‖ 2C
- [ ] Phase 2B: Assistant Restock tab and Siri (agent) ‖ 2A ‖ 2C
- [ ] Phase 2C: MCP (agent) ‖ 2A ‖ 2B
- [ ] Phase 3: merge, Mac-only level step, full suites, review, CLAUDE.md (session: build)
- [ ] Phase 4: schema deploy, roll-out, Danny's steps (session: fresh ship session)

## What Danny wants
Keep the classroom's inventory from both apps. **Staples** are things we always need and restock from the
office (toilet paper, paper towels). **One-offs** are things needed once, either fetched from the office or
ordered. The point is knowing when to walk to the office, and what to ask the office to order.

## Decisions (Danny, 2026-10-03)
1. **Assistants see everything**, including the To order list and its links. They can mark levels, check
   items off, and add one-offs. Only the guide sends the order email (it uses the guide's Settings ›
   Communication › Order Requests recipient).
2. **No notifications.** An assistant marking something Out shows on the guide's Today page, and nowhere else.
3. **Group by where things live** (the existing `location` field, shown as "place"). The category enum
   and its menu leave the UI; `categoryRaw` stays in the model and in backups for old data.
4. **The page is called "Restock".** The sidebar row, the title and the Siri open-section name all say
   Restock. Raw value `supplies` is kept.
5. **The count → level step runs on the Mac only** (2026-10-03, after Phase 1). On an iPad that hadn't yet
   caught up with the Mac, it could set a just-restocked staple back to Out. The iPad and iPhone get levels
   through sync. Ruled out: any guide device plus "open the Mac first", which only makes the race unlikely.

## The model, in one paragraph
A **staple** is a `CDSupply` with a **level** (Stocked, Low, Out) and a **source** (office or order). A
**need** is a `CDOrderItem`. A one-off is a need on its own. A staple that goes Low or Out gets exactly one
open need pointing back at it by `supplyID`. So the Office run is the open needs from the office, and To
order is the open needs to order. The existing order machinery (stage read from dates, request groups,
"waiting N days", Draft Request email) works for staples with no second code path. Checking a need off
marks it received. If the need has a `supplyID`, its staple goes back to Stocked. Marking a staple Stocked
from the shelf closes its open need: the need is deleted if it was never asked for, and marked received
if it was.

*Ruled out:* computing staple needs on the fly and tracking "asked for" on the staple through the dormant
`isOnOrder` / `orderDate` columns. That gives two request paths (staples and one-offs) for one email.

## Schema 15 / backup v37
The precedent for model and version bumps is schema 14, `1b9bdeb7`. The precedent for adding shared
types is schema 12, `b8097051`. Read both diffs first.

- **Share routing.** Move `Supply`, `SupplyTransaction` and `OrderItem` from `privateEntityNames` to
  `sharedEntityNames` (`CoreDataStack+Model.swift`). Bump the schema anyway, even though a configuration
  change doesn't move the model digest. An old build opening the shared store would otherwise down-migrate
  the new tables away. (Schema 3 bumped for the same reason when AttendanceRecord moved into the share.)
  Supply and SupplyTransaction were shared before schema 9; update the schema-9 comment so the history reads right.
- **CDSupply.** Declare accessors for the existing dormant columns `minimumThreshold` and `unit` (code only,
  deferred use). New attributes:
  - `levelRaw` String, default `"stocked"`
  - `sourceRaw` String, default `"office"`
  - `urlString` String, default `""` (a staple's product link, for order-source staples)
  - `levelChangedAt` Date, optional
  - `levelChangedByID` String, optional
  - `levelChangedByName` String, default `""`
- **CDOrderItem.** New attributes:
  - `sourceRaw` String, default `"order"` (every existing row is an order)
  - `supplyID` String, optional
  - `addedByID` String, optional
  - `addedByName` String, default `""`
  - A need from the office uses only To Request → Received. Requested and Confirmed are order-only.
- **Who and when.** Copy `CDAttendanceStore.stamp`: `ClassroomIdentity.currentUserRecordName` and
  `ClassroomIdentity.displayName`. Display: "You" when the ID is this user's, the name when there is one,
  "your guide" on an assistant's phone for the lead guide's marks.
- **History.** Every level change writes a `CDSupplyTransaction` with `quantityChange = 0` and a plain
  `reason` ("Low · Ana", "Out", "Restocked"). The Hold › History menu reads these.
- **Lists to extend.**
  - `ClassroomPermissions.assistantWritableEntities`: add the three types.
  - `ClassroomShareSetupReport.orderedEntityNames` and `describe(_:_:)`.
  - `PersistentHistoryProcessor.presentationEntityNames`.
  - The pinned tests: `Phase8PreTests`, `Phase5PostTests`, `StoreMigrationTests`, `BackupCoverageTests`,
    `PersistentHistoryEntityNotificationTests`, `AssistantSplitStoreTests`.
  - `CoreDataSchemaVersionTests` digest.
  - Shared/private counts in `Cosmic Daybook/CLAUDE.md`.
- **Where inserts land.** On an assistant's phone, assign inserts to the shared store, the way
  `CDAttendanceStore.destinationStore` does, then save through `AssistantSave`, which calls
  `AssistantShareAttacher`. On the guide's devices, inserts land in the private store and
  `SharedStoreOrphanGuard` attaches them; Supply and OrderItem fall under "always belongs".
- **Backup v37.** `SupplyDTO` is hand-written: add the new fields and the two declared dormant ones to
  `SupplyDTO`, `toDTO(_:)` and `importSupplies`, and drop those two from the "orphaned schema" list in
  `BackupFieldCoverageTests`. OrderItem and SupplyTransaction are model-driven `ModelRow`s, so their new
  columns come along automatically. Bump `BackupWriter.formatVersion` and the reader's supported range.
  Archive paths become `shared/Supply.ndjson` etc.; restore matches on the entity name, so old backups
  still restore. Add a round-trip test for a staple with an open need.
- **Existing data (live).**
  - 3 supplies and 2 orders. Their rows reach the share through Set Up / "Add Them to the Share" once
    `orderedEntityNames` lists the three types. Never call `share(_:to:)` on records already shared.
  - A one-time launch step maps `currentQuantity` to a level: 0 → Out, else Stocked. It creates the open
    needs for Out staples. It is gated by a done-flag, and runs on the Mac only (decision 5).
  - Live today: Paper Towels 0, Toilet Paper 0 (Bathrooms), Air Dry Clay 1.

## RestockService: the only writer
One `nonisolated enum RestockService`, called by the notebook screen, the Assistant, Siri and MCP alike.
`SupplyService` goes away, and `OrderService` keeps its stage moves but is reached through RestockService
for anything staple-related.
- `setLevel(_ supply:, to:, by:)` updates the level and history, and opens or closes the need.
  Low → Out keeps the same need.
- `addOneOff(title:, link:, quantity:, source:, note:)` takes a link or not. A link defaults the source
  to order.
- `addStaple(...)`.
- `checkOff(_ need:)` marks it received; a staple goes back to Stocked.
- `undoCheckOff`.
- Existing stage moves pass through to `OrderService`.
- **`reconcile()`.** Two devices can each open a need for the same staple at once. Keep the oldest by
  (`createdAt`, `id`), so every device picks the same survivor, and delete the rest. Run it after
  remote-change imports and on page appear, never in a loop.
- **Link cleaner** (`OrderLinkCleaner`). Amazon `/dp/ASIN` and `/gp/product/ASIN` links become
  `https://www.amazon.com/dp/ASIN`; elsewhere, only `utm_*` and similar tracking parameters are stripped.
  It runs on add and when the email is built, so the two existing 560-character links print clean.
- **Short title.** The text before the first " | ". If that is still over 60 characters, cut at the last
  ", " or " - " before 60. The result stays editable. Pin the existing email wording tests: only the
  link and title change.
- **Saves.** Batched like Orders' −/+ (one save per burst), through `SaveCoordinator` on screen and
  `AssistantSave` on the phone. Follow the efficiency-pass rules: no polling, no whole-table refetch per tap.
## Phases
Phase 1 landed first. Phases 2A, 2B and 2C run in parallel, each in its own worktree off the plan-revision commit
(see "Running it"). Phase 3 merges them and checks everything. Phase 4 ships.

### Phase 1: Data layer (done, `a97b3439`)
Everything in "Schema 15 / backup v37" and "RestockService", with tests. What later phases need from it:
- **API.** `RestockService{,+Staples,+Needs}.swift` in `Supplies/Services/`. Writers: `addStaple(_ StapleDetails,
  level:by:at:in:)`, `addOneOff(title:link:quantity:source:note:by:at:in:)` (both return `Added<T>`, `isNew == false`
  when it was already listed), `setLevel(_:to:by:at:in:)`, `checkOff(_:by:at:in:)` → `CheckOff`,
  `undoCheckOff(_:at:in:)`, `updateStaple`, `setNote`, `deleteStaple`, `setCount`, `removeNeeds`,
  `applyFetchedTitle`, `reconcile(in:store:)`. Readers: `openNeeds`, `openNeedCounts`, `history`, `shelf`
  (place groups), `staples(in:store:)`. Stage moves pass through to `OrderService`. `by:` takes a
  `RestockAuthor` (`.current(in:)`); `reads(changedByID:name:)` gives "You" / the name / "your guide".
  Callers save.
- **Not wired in Phase 1:** `reconcile()` on page appear and after another device's changes arrive. 2A and 2B
  each wire it for their own app.
- **Decided in Phase 1 beyond the plan:** pre-v37 order items restore as orders (an `addedLater` backup-row
  option); `ClassroomShareAttach` re-checks what's already shared before each `share(_:to:)` after the
  first (a staple takes its history along); deleting a staple's open need sets the staple back to Stocked;
  restoring a pre-v37 backup runs the count → level step.
- **Unchecked until a real share:** a new staple's history row joining the share beside its staple (Phase 4).
- **Amazon fixtures** were rebuilt from the canvas, not the live URLs (Phase 4 looks at the real email).

### Phase 2A: Notebook Restock page
- **Who:** `feature-phase` (Opus · high): large UI surface plus Today and navigation; design-fidelity calls.
- **Worktree:** `.claude/worktrees/restock-2a`, branch `claude/restock-2a`.
- **Files:** `Supplies/` (except `Supplies/Services/`, `RestockModels.swift`, `Supply.swift` and the two entity
  files, which are Phase 1's), `Orders/Views`, `Orders/Services/OrderLinkTitleFetcher.swift` (paste-to-fetch), `Today/`, `AppCore/RootView*`,
  `AppCore/AppIntents.swift`, and the tests these pin: `Cosmic Daybook Tests/AppCore/NavigationGroupTests.swift`,
  `Cosmic Daybook Tests/Today/`, and new Restock-page tests.

Canvas boards "After · Supplies (Mac)", "We need… sheet", "Restock card on Today" and "Draft Request".
- **One page.**
  - **Needs:** an Office run card and a To order card. The To order card has Draft Request, the
    "Requests go to: not set — Set Up…" nudge, and "Asked for" / "Received" folds reusing today's
    request groups.
  - **The shelf:** tiles grouped by place ("No place yet" last), plus "Add a staple" and common-staple chips.
- **Tiles.** Radius 14, level shown by shape (three bars, one, none; Out solid) so color is never the only
  signal. A click goes Stocked → Low → Out; a click on Out shows a "Right-click for more" hint, like the
  attendance hold hint. The context menu has the three levels, Edit…, Add a Note…, History, and Delete
  with a confirm. Edit is an inline sheet with name, place, source, link and note; no read-only detail sheet.
- **Rows.** The checkbox checks off (with Undo). A link button opens the link. Quantity −/+ shows while the
  need is still To Request.
- **"We need…" sheet.** Type a name or paste a link (pasting switches the source to Needs ordering and
  fetches the title), choose a source, set a quantity, and optionally turn on "Keep it stocked" (with Place).
- **Live updates.** The page listens with `onPresentationDataChange(WhenVisible)` (the three types are
  already in `presentationEntityNames`) and calls `RestockService.reconcile` on appear and on each change,
  never in a loop. Saves batch per burst through `SaveCoordinator`.
- **Navigation.** In `aliases`, `.orders` → `.supplies`; remove it from the Classroom group and from
  `RootDetailContent`. `.supplies` displays as "Restock" (icon `shippingbox`) with a sidebar badge for the
  open-need count where the sidebar supports `.badge`. Add a Restock case to `NotebookSection` and route
  it in `OpenSectionIntent` (the notebook is at the 10-shortcut cap; add no new shortcut).
- **Today.** A `.restock` DayCard ("Restock: 3 for the office run, 3 to order"), shown only when
  something is needed. Generalize the DayCard action, which today always opens Lessons & Work. Keep
  "Hide until tomorrow".
- **Retire.** `SuppliesListView(+Sections)`, `SupplyDetailView`, `SupplyEditableDetailsSection`,
  `QuickAdjustSheet`, `AddSupplySheet`, `SupplyRow`, `OrdersView(+Sections)`, `OrderItemRow` (fold it into the
  new row), and the stat cards. Keep `OrderRequestDraftSheet`, `OrderRequestSettingsView`,
  `OrderQuantityControl` and `OrderLinkTitleFetcher`. Before deleting a file, check the Assistant's by-path
  entries in `project.pbxproj` don't name it (2B owns that file; report a hit instead).
- **Devices.** The iPhone gets the same page as one column: Needs, then the shelf in two-column tiles.
- **Done when:**
  - iOS Simulator build of the `Cosmic Daybook` scheme and a macOS compile-only build are clean (2A is the
    only phase with Mac-only UI, so it catches its own Mac errors).
  - `-only-testing:` `TodaySectionVisibilityTests`, the Restock service suites under
    `Cosmic Daybook Tests/Supplies/`, `OrderServiceTests`, `NavigationGroupTests`, all passing, with counts.
  - `grep -rw` per retired type name finds no reference.
  - iPad and iPhone renders of the page (with a staple Out, one Low, an office one-off and an ordered one)
    and of the Today card, through a throwaway hosting-window test: PNGs to the session scratchpad, test
    deleted before the commit. Mac is compile-only.
- **Hand off:** no (an agent; reports back to the build session).

### Phase 2B: Daybook Assistant
- **Who:** `feature-phase` (Opus · high): new tab shell, Siri intents, hand-edited `project.pbxproj`.
- **Worktree:** `.claude/worktrees/restock-2b`, branch `claude/restock-2b`.
- **Files:** `Daybook Assistant/`, `Daybook Assistant Tests/`, `project.pbxproj` (Siri routes through
  `Daybook Assistant/Siri/AssistantSiriHost.swift`; the notebook's `Siri/SiriHost.swift` is not the Assistant's). Compile-only fixes (availability, iOS 18 API fallbacks, classic notifications) are
  allowed in Phase 1's files that the Assistant now compiles, with no behavior change; list every one in
  the reply. Anything more to `RestockService` goes back to the build session.

Canvas boards "Assistant · Shelf", "Office run", "We need…" and "Hold a tile". Accent `#4A3B6B`.
- **Tabs.** `AssistantRootView` `.ready` becomes a `TabView`: Attendance (unchanged) and Restock, with
  a badge for the office-run count.
- **Shelf.** Two-column tiles grouped by place, using the same tile grammar as attendance. A tap goes
  Stocked → Low → Out; a tap on Out shows "Hold for more". The Office run banner pushes to the run.
- **Office run.** Big check rows; checking an item off restocks it for everyone. A read-only "Your guide is
  ordering" list shows stage and links ("Asked Sep 30 · waiting 3 days").
- **"We need…" sheet.** Name, source, quantity. No Draft Request on the phone.
- **Hold menu.** A header line with who and when. Then We have plenty / Running low / Out, Add a Note…,
  History.
- **Live updates.** Call `RestockService.reconcile` on the tab's appear and after the Assistant's
  remote-change imports, using whatever the attendance grid already listens to. Saves go through
  `AssistantSave` with the inserted objects.
- **Siri.** Three new AppShortcuts, which brings the Assistant from 6 to 9 (cap 10):
  - "We're out of ‹supply›"
  - "We're low on ‹supply›"
  - "Add ‹thing› to the office run"
  Each phrase ends "in \(.applicationName)" like the existing six. A `SupplyAppEntity` (file
  `SupplyAppEntity.swift`, named like `StudentAppEntity`; `SupplyEntity.swift` is already the `CDSupply` file) matches names. Routing goes through `AssistantSiriHost` / `SiriHost.didSave`.
  Names reach Siri only through `updateAppShortcutParameters()`; call it when the staple list changes.
- **Plumbing.**
  - Add the notebook files the Assistant now compiles to `project.pbxproj` by hand, as the ~89 existing
    entries are. Phase 1's list: `RestockService.swift`, `RestockService+Staples.swift`,
    `RestockService+Needs.swift`, `RestockModels.swift`, `SupplyEntity.swift`, `SupplyTransactionEntity.swift`,
    `OrderItemEntity.swift`, `Supply.swift`, `OrderService.swift`, `OrderLinkCleaner.swift`, `Utils/Formatting/DateFormatters.swift`,
    `Utils/CoreData/NSManagedObjectContext+SafeFetch.swift`, plus whatever those pull in. Not
    `RestockLevelBackfill`. Everything must build for iOS 18.
  - `CDSupply` and `CDOrderItem` get `Identifiable` from `Models/CoreDataIdentifiable.swift`, which the Assistant
    can't compile. Use `ForEach(…, id: \.objectID)` or add the two conformances in an Assistant file.
  - Seed sample supplies in `AssistantSampleClass.fill`: two places and five staples, with Toilet Paper
    Out and Paper Towels Low.
- **Done when:**
  - The `Daybook Assistant` scheme and the `Cosmic Daybook` scheme both build clean for the iOS Simulator
    (2B's pbxproj and compile-only edits feed the notebook too), and `Cosmic Daybook Tests/Supplies/` passes.
  - The full Assistant test target passes on a leased iPhone simulator (it's small), including new tests for
    the tab's level cycle, check-off and the three intents' routing, and `AssistantSiriTests` pinning 9 shortcuts, with counts.
  - Screenshots with `-AssistantSampleClass` of the shelf, the office run, the "We need…" sheet and the hold
    menu, via `simctl io` or the scratchpad XCUITest walker (the simulator tool's tap has failed here before).
- **Hand off:** no.

### Phase 2C: MCP
- **Who:** `feature-phase-light` (Sonnet · medium): extends established tool patterns with good existing tests.
- **Worktree:** `.claude/worktrees/restock-2c`, branch `claude/restock-2c`.
- **Files:** `Services/MCPServer/`, its tests under `Cosmic Daybook Tests/Services/MCPServer/`, and the MCP tool
  table in `Documentation/Architecture/MCP_SERVER.md`.
- `list_supplies` reports level, place, source, who and when, and drops "no reorder threshold" from its
  description.
- New `mark_supplies` tool for batch level changes through `RestockService.setLevel` (resolve every name
  first, one save).
- `adjust_supply` stays for counts but writes through `RestockService.setCount`, and its comment stops
  claiming the screen writes history.
- `list_orders` shows the office run and to-order separately, with staple needs labeled.
- `add_order_items` accepts a title with no link plus `source: office|order`, through `RestockService.addOneOff`.
- **Done when:**
  - iOS Simulator build of the `Cosmic Daybook` scheme is clean.
  - `-only-testing:` `MCPToolRegistryTests` (tool count 89 → 90, `mark_supplies` in the non-read-only set),
    `MCPSupplyAndResourceToolsTests` and `MCPOrderToolsTests`, all passing, with counts. New tests: `mark_supplies`
    with one unknown name writes nothing; `adjust_supply` changes the count and leaves the level and its
    history alone.
  - Follows CLAUDE.md's MCP rules: annotations, `rollingBackOnFailure`, `markNothingWritten`, checked saves.
- **Hand off:** no.

### Phase 3: Merge, full checks, review
- **Who:** the build session (Opus · medium): merging and judging agents' work; no deep coding.
- **Steps:**
  1. Merge `claude/restock-2c`, then `-2b`, then `-2a` into `claude/restock-feature-build-ec3135`. If two
     branches clash, the file boundary says whose side wins.
  2. **Level step on the Mac only** (decision 5): wrap the `RestockLevelBackfill.runIfNeeded` call in
     `AppBootstrapper` in `#if os(macOS)` and fix the type's doc comment. Check: `grep -rn runIfNeeded` shows
     the only call site inside that block. Restoring a pre-v37 backup still runs the step on any device:
     a restore is a deliberate act, and the restored rows are the truth at that moment.
  3. Full notebook iOS suite, full Assistant suite, a macOS compile-only build, and a macOS Release
     compile-only build (`#if !DEBUG` code is invisible to Debug builds). If the build fails, the files
     map to a phase; if unclear, re-merge the branches one at a time.
  4. Update `Cosmic Daybook/CLAUDE.md`: Restock replaces the Orders notes; shared/private counts
     (10 shared, 70 private); schema 15; backup v37 (reads v17–v37); the Assistant's tab and 9 shortcuts.
  5. `/code-review high` on the branch against `f6ff0b0e`; fix what holds up, re-run the touched suites.
  6. Remove the three worktrees, `~/.claude/bin/sim-lease --release <path>` for each, and trash their
     DerivedData (the loop in CLAUDE.md).
- **Done when:** all of step 3 is green with counts, the review's kept findings are fixed, the worktrees
  are gone, and Danny has the iPad/iPhone renders and Assistant screenshots to look at.
- **Hand off:** yes. Phase 4 is a fresh ship session; nothing from this one helps it.

### Phase 4: Ship (fresh session; Danny's steps go in Tide's Cosmic Daybook TODO)
- **Who:** a fresh session (Opus · medium) with the `roll-out` skill. Mechanical, but the order matters.
1. Danny backs up the live notebook.
2. CloudKit: Claude runs the schema-15 Development init (a Debug build with
   `CLOUDKIT_ENVIRONMENT=Development` and `-InitializeCloudKitSchema` on the usual simulator); Danny checks
   CD_Supply, CD_SupplyTransaction and CD_OrderItem in the Console and clicks **Deploy to Production**.
   **Nothing built from this branch may run on a Production device before that deploy**: schema 12 broke
   classroom sync until it was deployed.
3. Merge to main (with Danny's OK), then roll out the notebook and an Assistant TestFlight together.
4. Open the Mac first after the update (the level step runs there).
5. On the Mac: Restock › Set Up… (order recipient). Settings › Sharing › "Add Them to the Share" for the
   existing 3 supplies and 2 orders. Give places to Paper Towels and Air Dry Clay.
6. Device checks: mark a staple Out on the Assistant and see it on the Mac's Today card; confirm its
   history row reached the guide (the share-attach path Phase 1 couldn't test); open Draft Request and
   check the two Amazon links print as short `/dp/ASIN` links.
- **Done when:** schema deployed, both builds installed or on TestFlight, the step-6 checks pass.

## Running it

### Who runs each phase
Effort can only be set in an agent definition, so the phases use three user-level agents in
`~/.claude/agents/`: `feature-phase-deep`, `feature-phase` and `feature-phase-light`. Launch with
`subagent_type` and don't pass `model`, which would override the definition. A phase agent that stalls or
reports a design question comes back to the build session, never to a bigger model on retry.

| Phase | Runs as | Model · effort | Parallel with |
|---|---|---|---|
| 1, data layer | `feature-phase-deep` | Opus · xhigh | — (done) |
| 2A, notebook page | `feature-phase` | Opus · high | 2B, 2C |
| 2B, Assistant | `feature-phase` | Opus · high | 2A, 2C |
| 2C, MCP | `feature-phase-light` | Sonnet · medium | 2A, 2B |
| 3, merge + review | the build session | Opus · medium | — |
| 4, ship | fresh session | Opus · medium | — |

### The build session's steps
1. **Phases 2A, 2B, 2C:** make three worktrees from the plan-revision commit (Phase 1 plus this plan) with
   `git worktree add .claude/worktrees/restock-2x -b claude/restock-2x <that commit>`. Don't use the Agent
   tool's `isolation: worktree`: it starts at the last-pushed main, which lacks Phase 1. Launch the three
   agents in one message, each told its worktree path, its section of this plan and its file boundary.
   Builds queue on the shared lock, so the parallel gain is writing while another agent builds.
2. **Phase 3** here, when all three report.
3. Print Phase 4's starter prompt.

### Every agent brief includes
- read this plan (its own phase section, Phase 1's notes, "Schema 15 / backup v37" and "RestockService"),
  `Cosmic Daybook/CLAUDE.md` and commit `a97b3439`
- in a new worktree, build once before editing, with the three prefix-mapping settings
- build only through `Scripts/locked_xcodebuild.sh`; only the phase's own scheme and `-only-testing:` suites
  (the full suites are Phase 3's)
- test on the iOS Simulator with `-destination "platform=iOS Simulator,id=$(~/.claude/bin/sim-lease)"`; never
  the macOS test destination or a Debug Mac launch (both open Danny's live store)
- Swift Testing, and watch for vacuous `#expect` on optional chains
- main-actor-default: Core Data types and their extensions are `nonisolated`
- American spelling and plain-English UI copy
- nobody edits `Cosmic Daybook/CLAUDE.md`, this plan or `RestockService` (2B's compile-only exception aside)
- one commit with the `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` trailer
- reply in at most 15 lines: commit, files changed, build and test results with counts, anything decided
  differently from the plan or left unresolved

## Ending a phase
1. Check every "Done when" item for the phase.
2. Tick the phase under Progress (the build session ticks 2A–2C when it merges them) and note anything
   that differed from the plan.
3. Update the build board, if this plan lists one.
4. Run /close-out at the end of a session (Phase 3 and Phase 4), not after each agent.
5. After Phase 3, print Phase 4's starter prompt: "Model: Opus 5.5, effort: medium" on the first line,
   then "In Maria's Notebook, read Documentation/Implementation/RESTOCK_PLAN.md and do Phase 4. Follow its
   Ending a phase steps when done."

## Deferred
- Counted staples (a number, with Low at `minimumThreshold`).
- Notifications (decision 2).
- iPad- or Mac-specific Assistant.
- Barcode scanning.
- A Restock widget.

## Open questions
None.
