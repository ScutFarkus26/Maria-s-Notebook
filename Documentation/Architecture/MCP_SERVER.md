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
| `list_students` | `DataQueryService.fetchAllStudents` |
| `search_notebook` | `SearchIndexService.shared.search` |
| `student_observations` | `CDNote` fetch + `NoteScope` filter |
| `student_presentation_history` | presented `CDLessonAssignment`s |
| `presentations_missing_observations` | `PresentationObservationCoverageService` |
| `classroom_snapshot` | `ChatContextAssembler.buildClassroomSnapshot` |
| `search_albums` | `AlbumCorpusLookup.search` — teaching-album PDFs |
| `get_album_page` | `AlbumCorpusLookup.page` — one album page's full text |
| `create_observation` (write) | `CDNote` + `syncStudentLinks` + `safeSave`, mirroring `LogObservationIntent` |
| `update_student` (write) | `StudentRepository.updateStudent` + `safeSave` — nickname, names, birthday, level; accepts a name or a student id |
| `update_observation` (write) | `NoteRepository.updateNote` + `safeSave` — body, tags, follow-up and report flags, by note id |
| `create_meeting_entry` (write) | `CDStudentMeeting` + `FocusItemService` + `safeSave`, mirroring `MeetingFormPane.saveAndContinue` — reflection, lesson requests, guide notes, goals-as-focus-items |
| `add_follow_up` (write) | `CDTodoItem` + `TodoTagHelper.syncStudentTags` + `safeSave`, mirroring `NewTodoForm.createTodo` |
| `resolve_follow_up` (write) | completes a `CDTodoItem` (refusing recurring todos, whose next occurrence only the app schedules) or resolves a `CDStudentFocusItem` by id |
| `list_open_follow_ups` | open `CDTodoItem`s + active `CDStudentFocusItem`s + `needsFollowUp` notes, optionally filtered to one student |

Deletes are deliberately not exposed; edits change only the fields provided
and report exactly what changed.

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
- End-to-end smoke test from a shell (app running, toggle on):

  ```bash
  printf '%s\n%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"smoke","version":"0"}}}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
    | MARIAS_NOTEBOOK_NO_AUTOLAUNCH=1 "/Users/dannydeberry/Developer/Maria's Notebook/Scripts/mcp/marias-notebook-mcp"
  ```
