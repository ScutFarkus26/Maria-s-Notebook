# Restock: Supplies + Orders as one page, shared with the Daybook Assistant

Mockups: canvas https://claude.ai/artifact/BBSwXMHajtcQRK2rggK1Eo (Before ×3 with numbered findings,
After Mac ×4, Assistant iPhone ×4, interactive in Play). Analysis session 2026-10-03, branch
`claude/inventory-tracking-design-d3a470` (worktree `.claude/worktrees/inventory-tracking-design-d3a470`).
Nothing built yet. Build on this branch; nothing reaches main until Danny has looked.

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
    needs for Out staples. It is gated by a done-flag, and runs on the lead guide only.
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
Phase 1 must land before the rest. Phases 2A, 2B and 2C then run in parallel, each in its own worktree
(see "Running it"). Phase 3 merges them and checks everything.

### Phase 1: Data layer (one agent, delicate)
Everything in "Schema 15 / backup v37" and "RestockService", with tests:
- level transitions and need open/close
- `checkOff` restocks the staple
- `reconcile` keeps the oldest need
- an assistant's insert is assigned to the shared store
- link cleaner and short title, using the two live Amazon URLs as fixtures
- backup round trip
- the one-time quantity → level step
- updated routing pins

Build the notebook and the Assistant, run the touched suites (iOS Simulator), and do a macOS compile-only
build. Old UI may keep compiling against the new service; Phase 2A replaces it.

### Phase 2A: Notebook Restock page (one agent)
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
- **Rows.** The checkbox checks off. A link button opens the link. Quantity −/+ shows while the need is
  still To Request.
- **"We need…" sheet.** Type a name or paste a link (pasting switches the source to Needs ordering and
  fetches the title), choose a source, set a quantity, and optionally turn on "Keep it stocked" (with Place).
- **Navigation.** In `aliases`, `.orders` → `.supplies`; remove it from the Classroom group and from
  `RootDetailContent`. `.supplies` displays as "Restock" (icon `shippingbox`) with a sidebar badge for the
  open-need count where the sidebar supports `.badge`. Add a Restock case to `NotebookSection` and route
  it in `OpenSectionIntent` (the notebook is at the 10-shortcut cap; add no new shortcut).
- **Today.** A `.restock` DayCard ("Restock: 3 for the office run, 3 to order"), shown only when
  something is needed. Generalise the DayCard action, which today always opens Lessons & Work. Keep
  "Hide until tomorrow". Keep `TodaySectionVisibilityTests` passing.
- **Retire.** `SuppliesListView(+Sections)`, `SupplyDetailView`, `SupplyEditableDetailsSection`,
  `QuickAdjustSheet`, `AddSupplySheet`, `OrdersView(+Sections)`, `OrderItemRow` (fold it into the new row),
  and the stat cards. Keep `OrderRequestDraftSheet`, `OrderRequestSettingsView`, `OrderQuantityControl`
  and `OrderLinkTitleFetcher`.
- **Devices.** The iPhone gets the same page as one column: Needs, then the shelf in two-column tiles.
- **Renders.** iPad and iPhone through a throwaway hosting-window test (PNG to the scratchpad, then
  delete the test). Mac is compile-only.

### Phase 2B: Daybook Assistant (one agent)
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
- **Siri.** Three new AppShortcuts, which brings the Assistant from 6 to 9 (cap 10):
  - "We're out of ‹supply›"
  - "We're low on ‹supply›"
  - "Add ‹thing› to the office run"
  A `SupplyEntity` AppEntity matches names. Routing goes through `AssistantSiriHost` / `SiriHost.didSave`.
- **Plumbing.**
  - Add the notebook files the Assistant now compiles (entities, `RestockService`, `OrderService`,
    `OrderLinkCleaner`, shared tile views if any) to `project.pbxproj` by hand, as the ~89 existing
    entries are.
  - Seed sample supplies in `AssistantSampleClass.fill`: two places and five staples, with Toilet Paper
    Out and Paper Towels Low.
- **Tests and screenshots.** Assistant tests run on a leased iPhone simulator. Take screenshots with
  `-AssistantSampleClass` via `simctl io` or the scratchpad XCUITest walker (the simulator tool's tap
  has failed here before).

### Phase 2C: MCP (one `feature-phase-light` agent)
- `list_supplies` reports level, place, source, who and when, and drops "no reorder threshold" from its
  description.
- New `mark_supplies` tool for batch level changes through `RestockService`.
- `adjust_supply` stays for counts, but its comment stops claiming the screen writes history.
- `list_orders` shows the office run and to-order separately, with staple needs labeled.
- `add_order_items` accepts a title with no link plus `source: office|order`.
- Update `MCPToolRegistryTests` (89 → 90) and the MCP tests for supplies and orders.

### Phase 3: Merge, full checks, review (orchestrator)
- Merge 2A, 2B and 2C into the branch.
- Run the full notebook iOS suite and the full Assistant suite, plus a macOS compile-only build.
- Update `Cosmic Daybook/CLAUDE.md`: Restock replaces the Orders/Supplies notes, plus the
  shared-type counts.
- Run `/code-review` on the branch.
- Tick the status list below.

### Phase 4: Danny's steps (in order; put them in Tide's Cosmic Daybook TODO)
1. Back up the live notebook.
2. CloudKit: Claude runs the schema-15 Development init (a Debug build with
   `CLOUDKIT_ENVIRONMENT=Development` and `-InitializeCloudKitSchema` on the usual simulator); Danny checks
   CD_Supply and CD_OrderItem in the Console and clicks **Deploy to Production**. **Nothing built from this
   branch may run on a Production device before that deploy**: schema 12 broke classroom sync until it was
   deployed.
3. Roll out the notebook and an Assistant TestFlight together.
4. On the Mac: Restock › Set Up… (order recipient). Settings › Sharing › "Add Them to the Share" for the
   existing 3 supplies and 2 orders. Give places to Paper Towels and Air Dry Clay.

## Running it (token plan)

### Who runs each phase
Effort can only be set in an agent definition, so the phases use three user-level agents in
`~/.claude/agents/`: `feature-phase-deep`, `feature-phase` and `feature-phase-light`. They share one body:
read the plan, stay inside your file boundary, build through the lock, tick Status, one commit, reply in
under 300 words. Launch with `subagent_type`, and don't pass `model`, which would override the definition.

| Work | Runs as | Model · effort | Why |
|---|---|---|---|
| Phase 1, data layer | `feature-phase-deep` | Opus · xhigh | Schema bump, share routing, backup format, one-time migration: a mistake here breaks sync on every device |
| Phase 2A, notebook page | `feature-phase` | Opus · high | Large UI surface plus Today and navigation; design fidelity calls |
| Phase 2B, Assistant | `feature-phase` | Opus · high | New tab shell, Siri intents, hand-edited `project.pbxproj` |
| Phase 2C, MCP | `feature-phase-light` | Sonnet · medium | Extends established tool patterns with good existing tests |
| Build session (orchestrates 1–3) | the session itself | Opus · medium | It mostly briefs agents and reads short replies; merging and conflicts need judgment, not depth |
| Phase 3 review | `/code-review high` in the build session | — | Broader coverage before anything ships |
| Ship session (Phase 4) | the session itself | Opus · medium | Mechanical roll-out skill, but the CloudKit deploy order matters |

Set a session's effort when it is opened (or with the session effort control). A phase agent that
stalls or reports a design question comes back to the build session, never to a bigger model on retry.

- **This session** (analysis) ends once Danny approves this plan: it commits this file and stops.
- **Build session** (new, opened on this worktree): reads this file and `Cosmic Daybook/CLAUDE.md`, then
  orchestrates. It stays light: agents do the work, and it holds only their short replies.
  1. **Phase 1:** one background `feature-phase-deep` agent working directly in this worktree. Wait for
     it. Review its commit.
  2. **Phases 2A, 2B, 2C:** make three worktrees from the Phase 1 commit with
     `git worktree add .claude/worktrees/restock-2x -b claude/restock-2x <phase-1 commit>`. Don't use the
     Agent tool's `isolation: worktree`: it starts at the last-pushed main, which lacks Phase 1. Launch the
     three agents in one message, each told its worktree path and its file boundary:
     - 2A: `Supplies/`, `Orders/Views`, `Today/`, `AppCore/RootView*`, `AppIntents.swift`
     - 2B: `Daybook Assistant/` and `project.pbxproj`
     - 2C: `Services/MCPServer/` and its tests
     Nobody edits `CLAUDE.md` or `RestockService` (send service changes back to the orchestrator). Builds
     queue on the shared lock, so the parallel gain is writing while another agent builds.
  3. **Phase 3** in the build session. Remove the three worktrees afterwards and release their simulators
     with `sim-lease --release`.
  4. A **ship session** (new) runs Phase 4 with the `roll-out` skill when Danny is ready to deploy.
- **Every agent brief includes:**
  - read this plan, `Cosmic Daybook/CLAUDE.md` and the earlier phases' commits
  - build only through `Scripts/locked_xcodebuild.sh`
  - test on the iOS Simulator with `-only-testing:`; never the macOS test destination or a Debug Mac
    launch (both open Danny's live store)
  - Swift Testing, and watch for vacuous `#expect` on optional chains
  - main-actor-default: Core Data types and their extensions are `nonisolated`
  - American spelling and plain-English UI copy
  - one commit with the `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` trailer
  - tick its phase below
  - reply in under 300 words

## Deferred
- Counted staples (a number, with Low at `minimumThreshold`).
- Notifications (decision 2).
- iPad- or Mac-specific Assistant.
- Barcode scanning.
- A Restock widget.

## Status
- [x] Phase 1: data layer (schema 15, backup v37, RestockService). Not wired here: `reconcile()` after imports and on
  appear is for the pages (2A/2B). Unchecked until a real share: a new staple's history attaching beside its staple.
- [ ] Phase 2A: notebook Restock page, Today card, navigation
- [ ] Phase 2B: Assistant Restock tab and Siri
- [ ] Phase 2C: MCP
- [ ] Phase 3: merge, full suites, macOS compile, review, CLAUDE.md
- [ ] Phase 4: Danny: backup, schema deploy, roll-out, share existing items, recipient, places
