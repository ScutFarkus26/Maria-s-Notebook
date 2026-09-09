# MCP Server (Claude Desktop Integration)

The app embeds a Model Context Protocol server on macOS so MCP clients —
primarily Claude Desktop — can read the notebook and record observations
through the running app. The app stays the sole owner of the Core Data +
CloudKit stores; nothing touches the SQLite files from outside.

## Architecture

```
Claude Desktop ──stdio──▶ Scripts/mcp/marias-notebook-mcp (nc relay)
                                   │ AUTH <token> preamble, then MCP bytes
                                   ▼
                            127.0.0.1:43117
                                   │
                     MCPSocketServer (NWListener, actor)
                                   │ newline-delimited JSON-RPC 2.0
                     MCPRequestHandler (protocol dispatch)
                                   │ @MainActor tool handlers
                     MCPNotebookTools ──▶ shared CoreDataStack.viewContext
```

- **Transport.** MCP stdio framing (newline-delimited UTF-8 JSON-RPC 2.0,
  spec revision 2025-06-18) carried over loopback TCP. The bridge script
  sends one `AUTH <token>` line, then relays bytes verbatim with `nc`, so
  the whole protocol lives in the app.
- **Why TCP, not a Unix socket.** Tried and rejected empirically: the App
  Sandbox only permits *binding* Unix sockets inside the app's own (group)
  container — a `temporary-exception.files...read-write` entitlement grants
  file I/O but not the sandbox's `network-bind` operation, so binding in
  `~/.marias-notebook/` fails with EPERM. And every path the app *can* bind
  (container, group container) is TCC-gated by macOS container protection
  for external processes, which would break or prompt every MCP client.
  Loopback TCP via `ENABLE_INCOMING_NETWORK_CONNECTIONS = YES` is the
  sanctioned route; the listener binds strictly to `127.0.0.1` (port
  43117, mirrored in the bridge script) and is never reachable from the
  network.
- **Auth token.** Because any local process may connect to loopback, the
  server requires a preamble line `AUTH <token>` before any MCP traffic;
  otherwise it drops the connection. The per-install random token lives at
  `~/.marias-notebook/mcp.token` (`0600` in a `0700` dir) — written by the
  app via a scoped home-relative entitlement exception (the app resolves
  the real home via `getpwuid`, since `NSHomeDirectory()` is the container
  under sandboxing) and read by the bridge script.
- **Protocol layer** (`Services/MCPServer/`): `JSONValue` (Codable/Sendable
  JSON), `JSONRPCMessage` (requests, ids, responses, error codes),
  `MCPRequestHandler` (initialize/version negotiation, ping, tools/list,
  tools/call; notifications are consumed silently; tool failures return
  `isError: true` results, protocol failures return JSON-RPC errors).
  Platform-neutral and covered by unit tests.
- **Socket layer**: `MCPSocketServer` (macOS-only actor) owns the
  `NWListener`, accepts any number of concurrent clients, buffers lines
  per connection, and answers sequentially per connection.
- **Lifecycle**: `MCPServerService.shared` (macOS-only, `@Observable`)
  starts/stops the socket server from `performStartupBootstrap()` and from
  the Settings toggle (Settings → AI Features → Claude Desktop, backed by
  `UserDefaultsKeys.aiMCPServerEnabled`, default **off**).

## Tools

Read tools mirror the on-device `NotebookTools` (Services/AI/) in query
logic and output conventions — entities are cited `[kind id=<uuid>]`, dates
are ISO 8601, student names resolve diacritic-insensitively with explicit
ambiguity errors:

| Tool | Backing path |
|---|---|
| **Roster & search** | |
| `list_students` | `DataQueryService.fetchAllStudents` |
| `search_notebook` | `SearchIndexService.shared.search` |
| `classroom_snapshot` | `ChatContextAssembler.buildClassroomSnapshot` |
| **Lessons & albums** | |
| `find_lessons` | `CDLesson` fetch ranked exact name > partial name > area/sequence |
| `list_lessons_by_area` | one area or sub-area in taught order, no cap — `orderInSequence` then name within a sub-area, sub-areas in the scope map's saved order (`LessonsViewModel.groups`) |
| `create_lesson` (write) | `LessonRepository.createLesson` + the sub-area renumbered and the area's `sortIndex` rebuilt the way `LessonsRootViewReordering` does after a drag, then AddLessonView's best-effort `SequenceTrackService.getOrCreateTrack`; idempotent on name within a sub-area, creates a sub-area but never an area |
| `update_lesson` (write) | the lesson detail's Save path (fields set in place, one save); a sub-area move mirrors `moveLessonToSequence` — end of the target, both areas' `sortIndex` rebuilt |
| `reorder_lessons` (write) | `moveLessonsInArea`'s write — `orderInSequence` renumbered across the sub-area, `sortIndex` rebuilt across the area; unlisted lessons keep their relative order after the listed ones |
| `search_albums` | `AlbumCorpusLookup.search` — teaching-album PDFs |
| `get_album_page` | `AlbumCorpusLookup.page` — one album page's full text |
| **Observations & presentations** | |
| `student_observations` | `CDNote` fetch + `NoteScope` filter |
| `student_presentation_history` | presented `CDLessonAssignment`s |
| `presentations_missing_observations` | `PresentationObservationCoverageService` |
| `create_observation` (write) | `CDNote` + `syncStudentLinks` + `safeSave`, mirroring `LogObservationIntent`; an optional `date` back-dates the note the way `create_meeting_entry` does |
| `update_observation` (write) | `NoteRepository.updateNote` + `safeSave` — body, tags, follow-up and report flags, and the children the note is about, by note id. `student_names` replaces the note's scope rather than adding to it (`.all` on an empty list, as `UnifiedNoteEditor.determineScope` reads an empty selection) and re-syncs the link rows; the presentation relationship is left alone, matching the in-app editor, which attaches a note to its context only at creation |
| `record_presentation` (write) | `LifecycleService.recordPresentation` + `PresentationOutcomePersistenceService.persistObservations` + `safeSave`, mirroring the command bar's `saveCaptureProposal` — completes a planned presentation when one matches, and re-recording the same lesson/students/day edits that presentation instead of duplicating it |
| `update_student` (write) | `StudentRepository.updateStudent` + `safeSave` — nickname, names, birthday, level; accepts a name or a student id |
| **Schedule** | |
| `schedule_for_range` | `TodayDataFetcher.fetchLessons` / `fetchCalendarEvents` + `CDWorkCheckIn` + `CDCalendarNote` + `SchoolCalendarService.isNonSchoolDaySync`; capped at 60 days |
| `schedule_presentation` (write) | `PresentationFactory.makeDraft` + `schedule(onDay:)` — reuses an existing unpresented plan for the same lesson and exact student set rather than duplicating it |
| `reschedule_presentation` (write) | the assignment's own `schedule(onDay:)` / `unschedule()`; refuses presentations already given |
| `discard_presentation` (write) | the planning list's context-menu delete — `context.delete` + save, notes cascading — two-step like `remove_student_from_work` (no `confirm` = report only: lesson, day, roster, note count); a year-plan entry promoted into the plan goes back to `planned`; refuses presentations already given |
| `update_presentation_roster` (write) | the detail view's Save shape — `studentIDs` rewritten in place, `modifiedAt` stamped, confirmed ids pruned; refuses an empty group and presentations already given |
| **Work** | |
| `student_work` | `CDWorkModel` owned by or participated in by the student |
| `work_detail` | one work item: steps, check-ins, participants, linked notes |
| `assign_work` (write) | `WorkRepository.createWork` + participant cross-links + optional `CDWorkCheckIn`, mirroring the Quick New Work sheet |
| `update_work` (write) | `WorkRepository.markWorkCompleted` / `WorkCompletionService.markCompleted`; status, due date, per-student completion, check-in completion |
| `remove_student_from_work` (write) | `WorkDeletionService.removalPlan` / `apply`; refuses until called with `confirm: true`, and reports owner promotion, passenger drops and linked-copy deletion before doing any of it |
| **Attendance** | |
| `attendance_for_day` | `attendanceStatuses(for:on:)` — deduplicated per student/day |
| `student_attendance` | `CDAttendanceRecord` + `deduplicatedPerStudentDay()`, with a tally |
| `mark_attendance` (write) | `CDAttendanceStore` — the permission + attribution + store-assignment chokepoint |
| **Todos & follow-ups** | |
| `list_open_follow_ups` | open `CDTodoItem`s + active `CDStudentFocusItem`s + `needsFollowUp` notes, optionally filtered to one student |
| `list_todos` | `CDTodoItem` filtered by status, student, due window, someday, tag |
| `add_follow_up` (write) | `CDTodoItem` + `TodoTagHelper.syncStudentTags` + `safeSave`, mirroring `NewTodoForm.createTodo`; takes priority, scheduled date and the someday flag at creation, so a follow-up no longer needs a second `update_todo` |
| `update_todo` (write) | title, notes, dates, priority, someday, students (+ retagging via `TodoTagHelper`) |
| `resolve_follow_up` (write) | completes a `CDTodoItem` (refusing recurring todos, whose next occurrence only the app schedules) or resolves a `CDStudentFocusItem` by id |
| **Meetings** | |
| `create_meeting_entry` (write) | `CDStudentMeeting` + `FocusItemService` + `safeSave`, mirroring `MeetingFormPane.saveAndContinue` — reflection, lesson requests, guide notes, goals-as-focus-items; then `MeetingScheduler.completeBooking` deletes the student's booking for that day (or an earlier one still pending), as the Today agenda does when a started meeting is completed |
| `student_meetings` | `CDStudentMeeting` history with its work reviews and linked notes — the read side of `create_meeting_entry` |
| `scheduled_meetings` | `CDScheduledMeeting`; uses `allStudentIDs`, so a group sitting lists its whole party; shows each booking's `purpose` and the work it is about |
| `schedule_meeting` (write) | `CDScheduledMeeting` via `MeetingScheduler.bookMeeting`, the meetings tab's date-picker path: one individual booking per student (another day moves it, the same day keeps it), group sittings untouched; refuses a day `SchoolCalendarService.isNonSchoolDaySync` says school is out |
| **Observation depth** | |
| `practice_sessions` | `CDPracticeSession` — duration, quality, independence, and the flagged behaviours (`activeBehaviours`), filterable by signal |
| `recall_checks` | `CDLessonRecallCheck` — retained / shaky / forgotten, weeks after mastery |
| **Families** | |
| `list_guardians` | `CDGuardian`, optionally only those flagged `receivesReports` |
| `update_guardian` (write) | adds or edits a `CDGuardian` — name, email, relationship, report flag, notes |
| `parent_communications` | `CDParentCommunication` by student, month, or status |
| `record_parent_communication` (write) | files or updates a `CDParentCommunication`; marking it sent stamps `sentAt`. **Never sends mail** — delivery stays in the app |
| **Classroom operations** | |
| `list_going_outs` / `update_going_out` (write) | `CDGoingOut` — status, permissions, date, party |
| `classroom_jobs` / `assign_job` (write) | `CDClassroomJob` + `CDJobAssignment`, keyed to the week's Monday; honours `maxStudents` (0 = uncapped) |
| `list_supplies` / `adjust_supply` (write) | `CDSupply`; every change also writes a `CDSupplyTransaction` and stock cannot go negative |
| **Projects** | |
| `list_projects` / `project_detail` | `CDProject` + `CDProjectSession` with agendas and session notes |
| `update_project` (write) | title, book, members, active flag |
| `add_project_session` (write) | `CDProjectSession` with meeting date, reading, and agenda |
| **Issues & community** | |
| `list_issues` | `CDIssue`, urgent first; unresolved only unless a status is asked for |
| `update_issue` (write) | raises or updates a `CDIssue`; resolving or closing stamps `resolvedAt` |
| `community_topics` | `CDCommunityTopicEntity` + proposed solutions |
| `update_community_topic` (write) | raises or updates a `CDCommunityTopicEntity`, following `TopicDetailViewModel.applyFields`: `addressedDate` is the discussed state (clearing it reopens the topic), and `proposed_solutions` appends `CDProposedSolutionEntity` rows rather than replacing them |
| **Library & shelves** | |
| `list_resources` | `CDResource` — printables, charts and forms; metadata only, the files stay on disk |
| `book_club` | `CDBookClubSession` + its `orderedMeetings`, with packet titles resolved |
| `list_reminders` | `CDReminder`, including any synced from Apple Reminders |
| `day_pad` (read + write) | `CDDayPad` for one day; writing replaces the day's text |
| `album_marks` | `CDAlbumBookmark` / `CDAlbumPageNote` / `CDAlbumHighlight`, cited as `[albumPage …]` so a mark can be followed with `get_album_page`. Pencil ink is excluded — it has no text |
| **Planning structures** | |
| `weekly_schedules` | `CDSchedule` + `CDScheduleSlot`, ordered Sunday-first by `Weekday` |
| `year_plan` | `CDYearPlanEntry` — intentions with target dates, not calendar entries |
| `update_year_plan_entry` (write) | one `CDYearPlanEntry`'s status and target date. Refuses promoted entries — the presentation carries the date once an entry reaches the calendar, so `reschedule_presentation` moves those — and refuses `promoted` as a status to set by hand, since promotion is `schedule_presentation` linking a real assignment |
| `skip_year_plan_entries` (write) | `StudentDeparturePlans.plannedEntries` + `skip` for one student, the same call the roster makes when a child is withdrawn; skips only `planned` entries and deletes nothing |
| `clear_year_plan` (write) | the same `StudentDeparturePlans.plannedEntries` + `skip`, scoped to one track (`sequenceGroupKey`, matched as `Area::Sequence`, `Area › Sequence`, or the sequence alone) and/or entries targeted before a day, two-step: without `confirm` it reports the count and lists the entries by track and writes nothing |
| `list_templates` | meeting / note / todo templates and sample work with steps, in one tool keyed by `kind` |
| **Operations** | |
| `sync_status` | `CloudKitSyncStatusService.shared` — health, last sync, pending uploads, and the terminal mirroring-delegate failure |
| **Reference & progression** | |
| `list_procedures` | `CDProcedure`; a single match returns its full text |
| `list_stories` | `CDStory` metadata (the PDFs themselves are not returned) |
| `student_tracks` | `TrackProgressResolver` over the student's `CDStudentTrackEnrollmentEntity`s |

Deletes are deliberately not exposed, with one exception:
`remove_student_from_work` takes a child off a work item, which on a linked
copy she owns means deleting that row. It is one of two tools that destroy
rows, so it is two-step — a call without `confirm` only reports the plan —
and it never touches another child's completion. `discard_presentation` is
the other: `reschedule_presentation(unschedule: true)` only returns a plan
to the planning list, so a regrouped presentation used to leave its
original behind; discarding is the planning list's own delete (notes
cascade with it), previewed first the same way, refused for anything
already given, and it returns any year-plan entry promoted into the plan to
`planned` rather than leaving it pointing at nothing. Regrouping itself is
`update_presentation_roster`, which edits the group in place and refuses to
empty it. Edits change only the fields provided and report exactly what
changed.

Retiring, not deleting, is the pattern elsewhere: `skip_year_plan_entries`
can change hundreds of rows in one call and is deliberately *not*
confirm-gated, because every one of them is recoverable — the entries move
to `skipped`, `year_plan` still reads them back, and
`update_year_plan_entry` puts any of them to `planned` again. A girl who
re-enrols finds her year plan intact.
`clear_year_plan` is the scoped, previewed form of the same retirement —
one track, or everything targeted before a day — for a plan generated
against a sequence position a child never reached: a call without `confirm`
lists what would be skipped by track, and a second call with `confirm: true`
skips exactly that. Promoted entries are never touched by either.

**Coverage is deliberate and near-total.** The guide asked for the whole
notebook to be reachable — reads *and* writes, with nothing held back — so
guardian contact details, parent communications and meeting notes are all in
scope. Two boundaries survive that decision, and neither is a gap to close:
no tool deletes a record outright except `remove_student_from_work` (above,
and confirm-gated), and `record_parent_communication` files a letter
without sending it, because delivery to families is a step the guide reviews
in the app. `mark_attendance` writes only through `CDAttendanceStore`, which
enforces `ClassroomPermissions` — an assistant's MCP session cannot write
what an assistant's app session could not.

Where the Core Data model carries columns the app never adopted, the tools
follow the app rather than the schema. `CDSupply` has `minimumThreshold`,
`unit` and `isOnOrder` in the model, but no Swift property declares them and
nothing writes them, so `list_supplies` reports no reorder threshold and
takes a `below` argument instead of inventing one.

**Entities deliberately not exposed.** `TransitionPlan`,
`TransitionChecklistItem`, `PrepChecklist`, `PrepChecklistItem`,
`PrepChecklistCompletion`, `Initiative`, `WorkCycleSession` and
`WorkCycleEntry` exist in the `.xcdatamodel` with **no Swift class and no app
code at all** — schema without a feature. There is nothing to fetch and
nothing that would ever write a row. `DevelopmentSnapshot` has an entity
class but nothing generates snapshots. Expose these only if and when the
features behind them are built. `NoteStudentLink`, `TodayAgendaOrder` and
`ClassroomMembership` are internal plumbing, and `WorkStep`,
`GoingOutChecklistItem` and `IssueAction` already surface through their
parents.

**Not exposed for want of an entry point, not by policy.** Triggering a
backup (`AutoBackupManager`) and generating an AI parent-report draft
(`MonthlyReportDraftService`) are both reached through `AppDependencies`,
which is injected into the SwiftUI environment rather than resolvable from a
static tool handler. Wiring either up means giving the MCP layer a way to
reach app-level services — a small service locator populated at bootstrap —
not a new tool. `sync_status` works today only because
`CloudKitSyncStatusService` is a singleton.

`find_lessons` + `record_presentation` are the pair that lets a guide
describe a presentation in prose and have it filed: the model names the
lesson from the curriculum, then writes the presentation with the group and
per-student observations linked to it. `record_presentation` takes the same
lifecycle path as the in-app capture review, so what it writes is
indistinguishable from a command bar capture — a plan waiting to be given is
completed rather than duplicated, and observations are deduplicated by body
and scope against the presentation they hang off. Its one divergence from
the in-app flow is deliberate: notes are stamped with the presentation's
date, not the moment they were written, because presentations filed this way
are often caught up in the evening or a day later. The per-student
follow-up outcomes the capture review offers (practice, follow-up work,
re-present, ready for the next lesson) are not exposed yet — only the
`needs_follow_up` flag that puts an observation in the follow-up inbox.

The four curriculum tools exist so an AMI album can be reconciled with the
notebook without opening the app: `list_lessons_by_area` reads a whole
area or sub-area uncapped (`find_lessons` stops at 25 because it answers a
different question), `create_lesson` adds what is missing, `update_lesson`
renames or refiles, and `reorder_lessons` makes the sub-area run in album
order. They all settle the two ordering columns exactly as a drag in the
scope map does — `orderInSequence` is the truth within a sub-area and
`sortIndex` is an area-wide index rebuilt from the sub-areas' saved order —
so nothing added this way floats to the top the way the single Add Lesson
form's zero-indexed lessons do. Three boundaries: an area is never created
(a typo would fork the map, so the refusal lists the areas that exist), a
lesson already filed under that sub-area with the same name is returned
rather than duplicated, and nothing is deleted — `reorder_lessons` carries
every unlisted lesson along after the listed ones. Renames are safe because
every presentation, plan, work item, note and track step holds the lesson's
id; `CDLessonAssignment.lessonTitleSnapshot` keeps the old name, as it does
after an in-app rename. The sub-area order itself lives in `FilterOrderStore`
(UserDefaults, device-local), which is why a whole-area listing groups in
this Mac's map order.

The two album tools are the exception to the `[kind id=<uuid>]` convention:
album pages aren't Core Data records and have no id, so they cite
`[albumPage album="<file>" page=<n>]`. `get_album_page` takes that same
album/page pair, so a citation can be followed without re-searching. Both
share `Albums/AlbumCorpusLookup.swift` with the on-device
`SearchTeachingAlbumsTool`, which is what keeps the two surfaces' wording
and results identical. They read the album index rather than Core Data, so
they don't take the context provider; if the guide hasn't chosen an albums
folder yet they say so instead of returning an empty result.

All handlers run on the main actor against
`AppBootstrapping.getSharedCoreDataStack().viewContext` (the sanctioned
entry point for non-SwiftUI code), taking an injectable context provider so
tests use an in-memory stack.

## Claude Desktop setup

1. In the app: Settings → AI Features → Claude Desktop → enable
   **Allow Claude Desktop Access**.
2. In `~/Library/Application Support/Claude/claude_desktop_config.json`:

   ```json
   {
     "mcpServers": {
       "marias-notebook": {
         "command": "/Users/dannydeberry/Developer/Maria's Notebook/Scripts/mcp/marias-notebook-mcp"
       }
     }
   }
   ```

3. Restart Claude Desktop. The bridge launches the app (backgrounded) if it
   isn't running; set `MARIAS_NOTEBOOK_NO_AUTOLAUNCH=1` in the server's
   `env` to disable that.

The same bridge works for Claude Code:
`claude mcp add marias-notebook -- "/Users/dannydeberry/Developer/Maria's Notebook/Scripts/mcp/marias-notebook-mcp"`.
The repo also carries a project-scope registration in `.mcp.json`, so Claude
Code sessions opened in this repository pick the server up automatically
(each client asks once for approval to use a project-scope server). The
app-side toggle in step 1 must still be on, or every client sees the
bridge's "not listening" error.

Note that Claude Desktop re-writes `claude_desktop_config.json` while it
runs; edit it only while Claude Desktop is quit, or the `mcpServers` entry
can be lost.

## Security posture

- Default off; enabling it is an explicit choice in Settings, and the pane
  states that discussed data reaches Anthropic.
- The listener binds `127.0.0.1` only and rejects any connection whose
  first line is not the correct `AUTH` token, so other local users and
  processes that cannot read `~/.marias-notebook/mcp.token` (`0600`) get
  nothing. Same-user processes could read the token — but they already
  have equivalent reach on a single-user Mac; this is not a new boundary.
- Claude Desktop prompts the teacher before each tool call; the write
  tools (observations, student edits, meeting entries, follow-ups) all go
  through the app's normal save paths (CloudKit mirroring, follow-up
  inbox, student links all behave as if entered in-app); the only
  destructive tool, `remove_student_from_work`, refuses until re-called
  with `confirm: true`.

## Testing

- `Maria's Notebook Tests/Services/MCPServer/MCPRequestHandlerTests.swift`
  — protocol conformance (version negotiation, ping, tool listing/calls,
  error taxonomy, parse errors).
- `Maria's Notebook Tests/Services/MCPServer/MCPNotebookToolsTests.swift`
  — tools against an in-memory stack (roster, scoped note reads, the
  observation write path, ambiguity handling).
- `Maria's Notebook Tests/Services/MCPServer/MCPMeetingToolsTests.swift`
  — meeting entries, follow-up todos, goal resolution, and the open
  follow-ups listing.
- `Maria's Notebook Tests/Services/MCPServer/MCPPresentationToolsTests.swift`
  — lesson lookup ranking, the presentation write (planned-lesson reuse,
  same-day idempotency, observation linking and dating), and its refusals.
- `Maria's Notebook Tests/Services/MCPServer/MCPCurriculumToolsTests.swift`
  — the curriculum tools: uncapped listing, create (append, after-anchor,
  idempotency, area refusal, track refresh), rename and move, partial
  reorder carrying unlisted lessons, and store routing on a split stack.
- `Maria's Notebook Tests/Services/MCPServer/MCPPlanningEditToolsTests.swift`
  — discard (preview, confirmed delete with note cascade and year-plan
  entry restored, refusal when given), roster edits and their refusals,
  and `clear_year_plan` scoped by track and date, previewed then applied.
- End-to-end smoke test from a shell (app running, toggle on):

  ```bash
  printf '%s\n%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"smoke","version":"0"}}}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
    | MARIAS_NOTEBOOK_NO_AUTOLAUNCH=1 "/Users/dannydeberry/Developer/Maria's Notebook/Scripts/mcp/marias-notebook-mcp"
  ```
