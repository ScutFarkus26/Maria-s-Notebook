# Sharing to-dos with Tide

**Last Updated:** 2026-10-19 (plan "Simplify the app", Phase 10, and its review fixes)

The notebook's to-dos and Danny's classroom to-dos in Tide are one list: every open notebook to-do goes to Tide except the automatic work check-ins and Someday ones, the to-dos in the Tide lists he picks show in the notebook, and a tick on either side ticks the other. Code: `Services/Tide/`; Settings › Connections › Tide (`Settings/Sync/TideSyncSettingsView.swift`).

## Where it runs

- **Only the Mac app, Release build, outside a test run** (`TideSyncPolicy`). Tide takes writes from other apps only through its own server on the Mac, `http://localhost:4877/<token>/mcp`, while Tide is open. iPhone and iPad copies sync their to-dos to the Mac through iCloud; Settings there says so. A Debug build or a test run never talks to Tide: a simulator's `localhost` is the Mac's, which is Danny's live Tide. Tests use `FakeTide`.
- **When**: on launch (not an MCP-only launch), when the notebook comes to the front (unless a run ended in the last minute), about 30 seconds after a to-do changes (here or from iCloud), and every 3 minutes while the notebook is the active app (10 while Tide doesn't answer). Self-started runs skip while `EnergyPolicy` defers maintenance; Sync Now doesn't.
- **One run at a time** (`TideSyncService.runOnce`), since two could send the same to-do twice. Sync Now or Link and Start pressed during a run makes one more run after it; a to-do changed during a run starts another after the usual wait. The sync's own changes to the notebook never start a run (`NotebookTideTodoStore.isWriting`, heard as the context posts them).
- **Only the waits are cancelled.** A run, once started, runs in a task of its own and finishes: cut off between `add_action` and saving its link, it would leave an action in Tide that only its notebook line ties back. Going to the background, Sync Now, Link and Start and Settings changes replace the wait, never the run.

## The connection

- Danny pastes the address from Tide's Settings › Claude once. It is kept in the Keychain only, this Mac only (`TideKeychain`), never in backups or preferences.
- The host is always stored as `localhost`: App Transport Security allows plain HTTP to an unqualified host name by default, but not to an IP address since macOS 14 (`NSAllowsLocalNetworking`, checked 2026-10-18), so `127.0.0.1` is rewritten rather than given an exception.
- Wire: MCP Streamable HTTP, stateless. Each POST is one JSON-RPC `tools/call` with `Content-Type: application/json`, `Accept: application/json, text/event-stream` and `MCP-Protocol-Version: 2025-06-18`, and gets one JSON reply. No `initialize` is sent (Tide answers it itself and needs none). Every request id is unique (`daybook-<uuid>`): Tide's transport matches replies to requests by id across all its clients.
- HTTP 401 means Tide made a new token: the status says to paste the address again, and nothing is written.

## Tools used, and the one never used

- `get_area` (My Classrooms): every list under it with whether it feeds Next Actions, and every unfinished action (open, waiting, someday) of the feeding lists, with file, heading, position, `of`, revision and link. One call per run; Settings' pickers are filled from the same read.
- `add_action` with `file`, `heading`, `position` (last: the section's `of` + 1), `revision`, and `due` (today or later) and `start` (a planned day after today). Revisions are chained from each reply, and from the ticks made earlier in the run.
- `complete_action` by file and words. A repeat in Tide rolls instead of finishing (`outcome: rolled`), and the copy reopens with the new due date.
- `update_action` with a note only: adds the `notebook:` line after the note's own paragraphs. Tide refuses a note that loses or moves Danny's `Me:` paragraphs, checked when the write lands.
- `list_actions` only to find a revision when the destination list holds closed actions and no open ones.
- **Never `changes_since`**: a call without an `author` or `device` filter moves Tide's single saved cursor, the one Danny's Claude sessions read "what changed since you last asked" from (`StoreTools+Changes.swift`). The plan said "changes_since with a saved cursor"; the sync compares snapshots instead. `TideSyncFirstRunTests.neverCallsChangesSince` pins it.

## The link and the notebook line

- `CDTodoItem.tideLink` (schema 19): Tide's `tide://box/<workspace path>?text=<words>`, built exactly as Tide builds it (`TideActionLink`). Tide makes it from the action's words, so rewording in Tide breaks it, and two actions with the same words in one list share it.
- **Every linked action carries `notebook:<uuid>` in its Tide note.** One sent from here gets it from `add_action`, after a "For Maya Smith and Etty Klein." line naming its children. One made in Tide, or matched at the first run, gets it from `update_action` after it is linked, after Danny's own paragraphs. A to-do finds its action **by that line first**, anywhere in the area's lists, and by its address only when the action there names no other to-do. So a reword or a move in Tide keeps the link (and the to-do takes Tide's new address and words), two to-dos with the same words keep an action each, and an action carrying an unlinked to-do's line is taken as that to-do (it was sent and the notebook stopped before saving the link): a crash mid-send never sends twice.
- An action whose note Tide won't take the line in (two with the same words, or a note Danny changed under the read) keeps its link by address; it isn't asked again until the notebook restarts.

## How a run decides

Order: read; first-run matches; take sent actions back; judge each linked to-do; **ticks**; sends; Tide's new actions come in; notebook lines. Ticks go before sends: a repeat that rolls in Tide reopens its copy here, and reopening would delete a next occurrence sent a moment earlier and leave its action orphaned in Tide (the notebook is read again after such a reopen, and `TodoCompletionService.reopen` no longer deletes a next occurrence that is already linked).

Per linked to-do the sync remembers only whether both apps last agreed it was open (`TideSyncState.agreedOpen`, UserDefaults, per CloudKit environment, `true` entries only, so it stays as small as the open to-dos):

| Here | In Tide's read | Agreed open | Does |
|---|---|---|---|
| open | there | any | agree open |
| ticked | there | yes | `complete_action` |
| ticked | there | no | nothing (Tide reopened it; unticks aren't carried) |
| open | gone | yes | tick the copy here |
| open | gone | no | nothing (unticked here after both closed, or a link the sync knows nothing about) |

"Gone" is ticked, dropped, deleted or moved out of the area's lists; all four close the copy, judged only for the lists the sharing covers (the picked ones and the one new to-dos go to). An action moved in Tide to a list the notebook doesn't show is still found by its line: the copy stays open with its new address. A list Danny unpicks, or one gone from Tide, leaves its to-dos alone. A to-do whose state was lost (restored from a backup, say) is never ticked on either side.

- **Sent**: open, no link, no linked work, not Someday, not refused before with the same title. Subtasks, Someday, repeats and linked work don't travel; a notebook repeat's next occurrence goes as a new action. A due date goes only when it is today or later (Tide refuses a past one); a day the to-do is planned for after today goes as Tide's `start`, so it waits out of Next Actions until then, as it waits in Upcoming here.
- **Shown**: open actions of the picked lists that no to-do holds and that didn't come from the notebook. Title, note and due date are copied; afterwards the to-do follows Tide's words and due date (`TideSyncState.fromTide`), and a note or children added here stay.
- **Wording**: once sent, Tide keeps the wording; a title edit here doesn't travel (said in the to-do's editor). A first-run match keeps the notebook's own words, note and date.
- **First run**: until Danny confirms, a run only reads and proposes word matches (`TideWordMatch`) between open notebook to-dos and unfinished Tide actions (open, waiting or someday) in the shared lists. A work check-in can be matched: it is linked, never sent, and its tick goes across both ways. Nothing is linked, sent or shown until Link and Start. The matched to-dos are kept in `Tide.firstRunLinked`.

## Refusals

- **Can't be aimed**: Tide names an action by its words, among every row of its list, ticked ones included (`MCPQueue.namedAction`, exact match, else a unique close one), and only `delete_action` takes a position as well. So a tick of an action whose words appear twice in its list (a weekly to-do sent each week, say) is refused as ambiguous. The sync asks again every run and says so plainly ("Tide can't tell which … to tick off … Tick it off in Tide"); once Danny ticks it there, the copy here is already closed and the sync stops asking. A positional `complete_action` in Tide would fix it ([Tide row](tide://box/Areas/App%20Development/Tide/To%20do.md?text=Let%20Tide%27s%20complete_action%20take%20a%20position%20and%20revision%2C%20as%20delete_action%20does%2C%20so%20Cosmic%20Daybook%20can%20tick%20an%20action%20whose%20words%20appear%20twice%20in%20its%20list)).
- **Passing by**: "isn't in Tide's store yet" and "Tide is still opening" are tried again next run, never reported as Tide not taking a to-do.
- **The heading gone**: the saved heading isn't checked against the read (it shows only headings that hold an unfinished action). Tide refuses a heading the list doesn't have, and the status says "The heading … isn't in Tide's … list any more. Pick another in Settings."; sending resumes once one is picked.
- **Anything else** a send meets is named in the status ("Tide wouldn't take …"), with Tide's words under Details, and not sent again until its title changes.
- A stale revision stops the sending for the run; the next run reads again. Never retried blindly.

## Duplicates of one to-do

Two CloudKit copies of a to-do with the same id: the sync uses the linked one, and the dedup merge (`DataCleanupService.mergeTodoItem`) keeps the link on the kept copy, so neither sends it to Tide a second time.

## Screens

- Todos: a "From Tide" section in the sidebar, one row per Tide list.
- A child's page: open shared to-dos that name her (`TideNameMatcher`: full name, the short "Maya S" form, or a first name no other child has; two Ettys make "Etty" name nobody) or list her as a child.
- Today: no change; a Tide to-do with a due date shows with the rest by the Todos screen's own Today rule.

## Not checked by an agent

The Mac look of Settings and the sidebar section, and one live round trip with Tide open, are Danny's (agents never run the Mac app: its startup opens the live notebook). They wait for schema 19 in Production ([Tide](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=Deploy%20Cosmic%20Daybook%27s%20schema%2019%20%28the%20to-do%20Tide%20link%29%20to%20CloudKit%20Production%2C%20after%20one%20Debug%20Development%20schema%20run%2C%20before%20the%20next%20roll-out%20or%20Release%20install)), then the round trip ([Tide](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=After%20the%20schema%2019%20roll-out%2C%20turn%20on%20Tide%20sharing%20in%20Cosmic%20Daybook%27s%20Settings%20on%20the%20Mac%20with%20Tide%20open%2C%20check%20the%20first-run%20matches%20and%20how%20it%20looks%2C%20then%20tick%20a%20to-do%20on%20each%20side%20and%20see%20the%20other%20follow)).
