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
| `search_albums` | `AlbumCorpusLookup.search` — teaching-album PDFs |
| `get_album_page` | `AlbumCorpusLookup.page` — one album page's full text |
| **Observations & presentations** | |
| `student_observations` | `CDNote` fetch + `NoteScope` filter |
| `student_presentation_history` | presented `CDLessonAssignment`s |
| `presentations_missing_observations` | `PresentationObservationCoverageService` |
| `create_observation` (write) | `CDNote` + `syncStudentLinks` + `safeSave`, mirroring `LogObservationIntent` |
| `update_observation` (write) | `NoteRepository.updateNote` + `safeSave` — body, tags, follow-up and report flags, by note id |
| `record_presentation` (write) | `LifecycleService.recordPresentation` + `PresentationOutcomePersistenceService.persistObservations` + `safeSave`, mirroring the command bar's `saveCaptureProposal` — completes a planned presentation when one matches, and re-recording the same lesson/students/day edits that presentation instead of duplicating it |
| `update_student` (write) | `StudentRepository.updateStudent` + `safeSave` — nickname, names, birthday, level; accepts a name or a student id |
| **Schedule** | |
| `schedule_for_range` | `TodayDataFetcher.fetchLessons` / `fetchCalendarEvents` + `CDWorkCheckIn` + `CDCalendarNote` + `SchoolCalendarService.isNonSchoolDaySync`; capped at 60 days |
| `schedule_presentation` (write) | `PresentationFactory.makeDraft` + `schedule(onDay:)` — reuses an existing unpresented plan for the same lesson and exact student set rather than duplicating it |
| `reschedule_presentation` (write) | the assignment's own `schedule(onDay:)` / `unschedule()`; refuses presentations already given |
| **Work** | |
| `student_work` | `CDWorkModel` owned by or participated in by the student |
| `work_detail` | one work item: steps, check-ins, participants, linked notes |
| `assign_work` (write) | `WorkRepository.createWork` + participant cross-links + optional `CDWorkCheckIn`, mirroring the Quick New Work sheet |
| `update_work` (write) | `WorkRepository.markWorkCompleted` / `WorkCompletionService.markCompleted`; status, due date, per-student completion, check-in completion |
| **Attendance** | |
| `attendance_for_day` | `attendanceStatuses(for:on:)` — deduplicated per student/day |
| `student_attendance` | `CDAttendanceRecord` + `deduplicatedPerStudentDay()`, with a tally |
| `mark_attendance` (write) | `CDAttendanceStore` — the permission + attribution + store-assignment chokepoint |
| **Todos & follow-ups** | |
| `list_open_follow_ups` | open `CDTodoItem`s + active `CDStudentFocusItem`s + `needsFollowUp` notes, optionally filtered to one student |
| `list_todos` | `CDTodoItem` filtered by status, student, due window, someday, tag |
| `add_follow_up` (write) | `CDTodoItem` + `TodoTagHelper.syncStudentTags` + `safeSave`, mirroring `NewTodoForm.createTodo` |
| `update_todo` (write) | title, notes, dates, priority, someday, students (+ retagging via `TodoTagHelper`) |
| `resolve_follow_up` (write) | completes a `CDTodoItem` (refusing recurring todos, whose next occurrence only the app schedules) or resolves a `CDStudentFocusItem` by id |
| **Meetings** | |
| `create_meeting_entry` (write) | `CDStudentMeeting` + `FocusItemService` + `safeSave`, mirroring `MeetingFormPane.saveAndContinue` — reflection, lesson requests, guide notes, goals-as-focus-items |
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
| **Reference & progression** | |
| `list_procedures` | `CDProcedure`; a single match returns its full text |
| `list_stories` | `CDStory` metadata (the PDFs themselves are not returned) |
| `student_tracks` | `TrackProgressResolver` over the student's `CDStudentTrackEnrollmentEntity`s |

Deletes are deliberately not exposed; edits change only the fields provided
and report exactly what changed.

**Coverage is deliberate and near-total.** The guide asked for the whole
notebook to be reachable — reads *and* writes, with nothing held back — so
guardian contact details, parent communications and meeting notes are all in
scope. Two boundaries survive that decision, and neither is a gap to close:
no tool deletes anything, and `record_parent_communication` files a letter
without sending it, because delivery to families is a step the guide reviews
in the app. `mark_attendance` writes only through `CDAttendanceStore`, which
enforces `ClassroomPermissions` — an assistant's MCP session cannot write
what an assistant's app session could not.

Where the Core Data model carries columns the app never adopted, the tools
follow the app rather than the schema. `CDSupply` has `minimumThreshold`,
`unit` and `isOnOrder` in the model, but no Swift property declares them and
nothing writes them, so `list_supplies` reports no reorder threshold and
takes a `below` argument instead of inventing one.

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
  inbox, student links all behave as if entered in-app), and none can
  delete.

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
- End-to-end smoke test from a shell (app running, toggle on):

  ```bash
  printf '%s\n%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"smoke","version":"0"}}}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
    | MARIAS_NOTEBOOK_NO_AUTOLAUNCH=1 "/Users/dannydeberry/Developer/Maria's Notebook/Scripts/mcp/marias-notebook-mcp"
  ```
