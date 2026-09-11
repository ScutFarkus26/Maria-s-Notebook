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
- **Annotations.** Every `MCPToolDefinition` declares an
  `MCPToolAnnotations` value — the spec's `readOnlyHint`, `destructiveHint`,
  `idempotentHint`, `openWorldHint` — and `tools/list` emits it as the
  descriptor's `annotations` object, so a client can tell a read from a
  write before prompting and the model knows which calls are safe to make
  freely. Four presets: `.readOnly` (the 45 reads), `.write` (creates — a
  second call may create again), `.idempotentWrite` (edits in place —
  `update_*`, `mark_*`, `reschedule_presentation`, `resolve_follow_up`,
  `day_pad`), and `.destructive` (`discard_presentation`,
  `remove_student_from_work`, `skip_year_plan_entries`, `clear_year_plan`).
  The field has no default, so a new tool cannot forget it, and
  `MCPToolRegistryTests.annotationsClassifyEveryTool` pins the exact
  non-read-only and destructive sets as literals — a misclassified tool is a
  red test, not a silent change to what a client prompts for. `openWorldHint`
  is false everywhere: every tool reads the local notebook.
- **Write journal.** A record filed over MCP is otherwise indistinguishable
  from one the guide typed, and the note entity's `reportedBy` /
  `reporterName` cannot carry the distinction — they mean guide-versus-
  assistant in the classroom and the speaker label in exports. So
  provenance is a device-local, append-only journal instead:
  `MCPRequestHandler` takes an `onWrite` closure, and after every successful
  call of a tool whose `readOnlyHint` is false (errors and reads never
  qualify) it hands over an `MCPWriteRecord` — timestamp, tool, the
  arguments re-encoded compactly, the first 300 characters of the receipt,
  the citations scanned out of it, and the destructive flag.
  `MCPServerService` wires the `MCPWriteJournal` actor, which appends one
  JSON line to `<Application Support>/MCP/writes.jsonl` and keeps the newest
  half when the file passes 2 MB; a write failure is logged, never thrown
  into the tool call. `recent_mcp_writes` reads it back. Nothing in the
  journal leaves the Mac and nothing in it is needed by the app.
- **Catalogue cost.** The whole catalogue is sent on every connection —
  about 68 KB, roughly 17k tokens, for 82 tools — and schemas are two thirds
  of it. Batch tools therefore describe their fields once at the top level
  and strip descriptions from the array-item copy
  (`JSONValue.withoutDescriptions`); descriptions carry what the model needs
  to call the tool correctly (dedup, refusals, confirm rules) and not the
  "as the in-app control would" reassurance, which lives in this document.
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
| `student_observations` | `CDNote` fetch + `NoteScope` filter — `days_back` (default 30) or an explicit `since` / `until` window (`DayWindow`, YYYY-MM-DD, inclusive days), `limit` 1–200 (default 40), newest first with a "showing N of M" trailer |
| `student_presentation_history` | presented `CDLessonAssignment`s, newest first — `limit` 1–200 (default 10), `since` (YYYY-MM-DD), and `lesson` (id or name) narrow it; with `lesson` the child's `CDLessonPresentation` record is read as well, so a checklist mark with no dated presentation is reported rather than read as "never had it". A lesson this child has had more than once carries its ordinal, and the reason if the record's notes open with one: `(2nd time; second pass)`, `(2nd time; review)`, or `(2nd time)`. The first giving of a lesson, and a lesson given once, say nothing |
| `presentations_missing_observations` | `PresentationObservationCoverageService`, judged child by child: a group presentation is listed while any child on it has no observation about her, and the line names those children; takes the same `since` / `until` window |
| `create_observation` (write) | `CDNote` + `syncStudentLinks` + `safeSave`, mirroring `LogObservationIntent`; an optional `date` back-dates the note the way `create_meeting_entry` does. A `notes` array files several in one call — every name and date resolves before anything is written, one save covers them all. An identical note (same trimmed body, same student scope, same day) is reported and cited rather than filed again, unless `force` is true; the guard also catches a duplicate inside one batch |
| `update_observation` (write) | `NoteRepository.updateNote` + `safeSave` — body, tags, follow-up and report flags, and the children the note is about, by note id. `student_names` replaces the note's scope rather than adding to it (`.all` on an empty list, as `UnifiedNoteEditor.determineScope` reads an empty selection) and re-syncs the link rows; the presentation relationship is left alone, matching the in-app editor, which attaches a note to its context only at creation |
| `record_presentation` (write) | `LifecycleService.recordPresentation` + `PresentationOutcomePersistenceService.persistObservations` + `CaptureFollowUpPersistence.persist` + `safeSave`, mirroring the command bar's `saveCaptureProposal` — completes a planned presentation when one matches, and re-recording the same lesson/students/day edits that presentation instead of duplicating it. Each `student_observations` item may carry the guide's decision as `follow_up` (`practice`, `follow_up_work`, `re_present`, `ready_for_next_lesson`, `continue_observing`) plus `follow_up_detail`; a `presentations` array files a whole day — every item resolves first, then one save. Every filing's origin is settled before anything is written, and a filing that would put a lesson on a child's record a second time is refused unless it carries `purpose` (`second_pass` / `review`) — one refusal names every such filing in the call, and nothing is written. Re-filing the same lesson/children/day (an edit) and completing a plan (which passed the guard when it was made) are exempt |
| `mark_mastered` (write) | the Mastered pill's `updateProficiencyState` and the checklist's `upsertLessonPresentation` shape — the child's latest `CDLessonPresentation` for the lesson flipped to `mastered` in place with `masteredAt` set (today, or an explicit `date`), then `SequenceTrackService.checkAndCompleteTrackIfNeeded`; this is the only write that advances a track step. Refuses the whole call, writing nothing, if any named child has no presentation of the lesson on record — it never manufactures a row. An already-mastered row keeps its original date. A `marks` array confirms several lessons at once: every item's lesson and every child resolve before the first row is touched, so one unrecorded name refuses the batch (`marks[i]: …`), and one save covers them all; the single form and `marks` together are refused |
| `mastery_candidates` | the read that feeds that batch, and the only thing standing between "presented" and "mastered" that does not require a second trip through the record. `PresentationRecordIndex` gives every enrolled child's given-but-unmarked lessons; a pair is a candidate only with evidence beside the presentation — confirmed ready at capture (3, cited with the day), a `.practiceLesson` `CDWorkModel` in a completed state (3 when its `completionOutcome` is proficient, else 2), a `CDLessonRecallCheck` with the retained outcome (1) — ranked by summed weight, ties to the lesson given longest ago. `student`, `area`, `group_by` (`student` / `lesson`), `limit` 1–200 (default 40) narrow it. It never writes: it closes with the exact `{"marks":[…]}` JSON for `mark_mastered`, to be sent only once the guide says they assessed those children |
| `update_student` (write) | `StudentRepository.updateStudent` + `safeSave` — nickname, names, birthday, level; accepts a name or a student id |
| **Schedule** | |
| `schedule_for_range` | `TodayDataFetcher.fetchLessons` / `fetchCalendarEvents` + `CDWorkCheckIn` (resolved through `resolvedWork`, the relationship or the `workID` string) + `CDCalendarNote` + `SchoolCalendarService.isNonSchoolDaySync`; capped at 60 days. A check-in whose work is gone is labelled an orphan, never printed as an unassigned plan |
| `schedule_presentation` (write) | `PresentationFactory.makeDraft` + `schedule(onDay:)` — or `schedule(for:)` when an `HH:MM` `time` is given, the same write the calendar's drag makes — reusing an existing unpresented plan for the same lesson and exact student set rather than duplicating it. Without `time` the plan lands at `UIConstants.morningHour`, the in-app default. Refuses days `SchoolCalendarService` says school is out, in `schedule_meeting`'s words. Refuses, too, when `PresentationRecordIndex` says a named child already has the lesson on record (any day before the one asked for, or an undated mark) — naming each child and her days — unless `purpose` says which repeat this is: `second_pass` also sets `needsAnotherPresentation` on her most recent presented assignment, and either purpose opens the plan's `notes` with `Second pass — planned YYYY-MM-DD` / `Review — planned YYYY-MM-DD` |
| `reschedule_presentation` (write) | the assignment's own `schedule(onDay:)` / `schedule(for:)` / `unschedule()`; takes the same optional `time`, and `time` alone re-times the day the plan already has; refuses presentations already given |
| `discard_presentation` (write) | the planning list's context-menu delete — `context.delete` + save, notes cascading — confirm-gated like `remove_student_from_work`: no `confirm` = report only (lesson, day, roster, note count), `confirm: true` = deleted in that call, whether or not a report was asked for first; a year-plan entry promoted into the plan goes back to `planned`; refuses presentations already given |
| `update_presentation_roster` (write) | the detail view's Save shape — `studentIDs` rewritten in place, `modifiedAt` stamped, confirmed ids pruned; refuses an empty group and presentations already given |
| **Work** | |
| `student_work` | `CDWorkModel` owned by or participated in by the student |
| `work_detail` | one work item: steps, check-ins, participants, linked notes |
| `assign_work` (write) | `WorkRepository.createWork` + participant cross-links + optional `CDWorkCheckIn` (through `CDWorkCheckIn.make`), mirroring the Quick New Work sheet; refuses a withdrawn or transferred student by name and status, as the repository itself does |
| `update_work` (write) | `WorkRepository.markWorkCompleted` / `WorkCompletionService.markCompleted`; status, due date, per-student completion, check-in completion |
| `remove_student_from_work` (write) | `WorkDeletionService.removalPlan` / `apply`; refuses until called with `confirm: true`, and reports owner promotion, passenger drops and linked-copy deletion before doing any of it |
| **Attendance** | |
| `attendance_for_day` | `attendanceStatuses(for:on:)` — deduplicated per student/day |
| `student_attendance` | `CDAttendanceRecord` + `deduplicatedPerStudentDay()`, with a tally |
| `mark_attendance` (write) | `CDAttendanceStore` — the permission + attribution + store-assignment chokepoint. One `student_name` + `status`, or a `students` array, or `mark_all_present` (everyone not named in `students` is marked present); every name resolves before any write, and `absence_reason` / `note` are refused alongside the batch forms because they are per-student |
| **Todos & follow-ups** | |
| `list_open_follow_ups` | open `CDTodoItem`s + active `CDStudentFocusItem`s + `needsFollowUp` notes, optionally filtered to one student |
| `list_todos` | `CDTodoItem` filtered by status, student, due window, someday, tag |
| `add_follow_up` (write) | `CDTodoItem` + `TodoTagHelper.syncStudentTags` + `safeSave`, mirroring `NewTodoForm.createTodo`; takes priority, scheduled date and the someday flag at creation, so a follow-up no longer needs a second `update_todo`. An identical open todo from today (same trimmed title, same students) is reported and cited rather than added, unless `force` is true |
| `update_todo` (write) | title, notes, dates, priority, someday, students (+ retagging via `TodoTagHelper`) |
| `resolve_follow_up` (write) | completes a `CDTodoItem` (refusing recurring todos, whose next occurrence only the app schedules) or resolves a `CDStudentFocusItem` by id |
| **Meetings** | |
| `create_meeting_entry` (write) | `CDStudentMeeting` + `FocusItemService` + `safeSave`, mirroring `MeetingFormPane.saveAndContinue` — reflection, lesson requests, guide notes, goals-as-focus-items; then `MeetingScheduler.completeBooking` deletes the student's booking for that day (or an earlier one still pending), as the Today agenda does when a started meeting is completed |
| `student_meetings` | `CDStudentMeeting` history with its work reviews and linked notes — the read side of `create_meeting_entry`; `limit` 1–100 (default 5) and a `since` / `until` window |
| `scheduled_meetings` | `CDScheduledMeeting`; uses `allStudentIDs`, so a group sitting lists its whole party; shows each booking's `purpose` and the work it is about |
| `schedule_meeting` (write) | `CDScheduledMeeting` via `MeetingScheduler.bookMeeting`, the meetings tab's date-picker path: one individual booking per student (another day moves it, the same day keeps it), group sittings untouched; refuses a day `SchoolCalendarService.isNonSchoolDaySync` says school is out |
| **Observation depth** | |
| `practice_sessions` | `CDPracticeSession` — duration, quality, independence, and the flagged behaviours (`activeBehaviours`), filterable by signal and by a `since` / `until` window |
| `recall_checks` | `CDLessonRecallCheck` — retained / shaky / forgotten, weeks after mastery, filterable by a `since` / `until` window |
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
| `students_pending` | one lesson across the class, from the plan: every enrolled child with a planned (unsatisfied) or promoted `CDYearPlanEntry` for it, or an unpresented `CDLessonAssignment` naming her, with target date, `isBehindPace`, and the presentation's day, time and group; closes with who has had it (`CDLessonPresentation` or a presented assignment) and who has no plan. Every fetch is keyed on the lesson id — a handful of small queries, not a per-child scan |
| `students_ready` | the record-side counterpart: every enrolled child the record holds as `confirmedStudentIDs` on a presented `CDLessonAssignment`, or marked mastered, on a lesson whose successor in the same sub-area (`BlockingAlgorithmEngine.buildNextLessonCache`) is neither on her record nor on an open plan for her. `group_by` student or lesson, narrowed by `student`, `area`, `basis` (`either` / `confirmed` / `mastered`) and `include_almost_ready`; a sub-area whose `LessonProgressionRules` require practice holds a child at almost-ready while her own work on the lesson she just had is open. The by-lesson form closes each group with the literal `schedule_presentation` call for its ready children on the next school day. One `PresentationRecordIndex`, one work fetch, dictionary lookups from there |
| `update_year_plan_entry` (write) | one `CDYearPlanEntry`'s status and target date. Refuses promoted entries — the presentation carries the date once an entry reaches the calendar, so `reschedule_presentation` moves those — and refuses `promoted` as a status to set by hand, since promotion is `schedule_presentation` linking a real assignment |
| `skip_year_plan_entries` (write) | `StudentDeparturePlans.plannedEntries` + `skip` for one student, the same call the roster makes when a child is withdrawn; skips only `planned` entries and deletes nothing |
| `clear_year_plan` (write) | the same `StudentDeparturePlans.plannedEntries` + `skip`, scoped to one track (`sequenceGroupKey`, matched as `Area::Sequence`, `Area › Sequence`, or the sequence alone) and/or entries targeted before a day, two-step: without `confirm` it reports the count and lists the entries by track and writes nothing |
| `list_templates` | meeting / note / todo templates and sample work with steps, in one tool keyed by `kind` |
| **Operations** | |
| `sync_status` | `CloudKitSyncStatusService.shared` — health, last sync, pending uploads, and the terminal mirroring-delegate failure |
| `recent_mcp_writes` | `MCPWriteJournal` — every successful non-read-only call on this Mac, newest first: tool, the arguments it was made with (strings clipped, long arrays summarised), the receipt's first line, and the `[kind id=…]` citations parsed from it; `days` (default 7) or `since` / `until`, `tool`, `limit` 1–500. The review-or-undo call after a filing session |
| `create_backup` (write) | `AutoBackupManager.performManualBackup` — the `.manual` trigger, never change-gated and independent of the auto-backup switch, so a call always writes a `ManualBackup-<timestamp>` archive into the auto-backup folder and reports its path and size. The call to make before a bulk write |
| `draft_parent_report` (write) | `MonthlyReportDraftService.generateDraft` + `upsertReport`, the Parent Reports screen's Generate button: drafts one child's month from the recorded evidence (AI when available, the deterministic assembly otherwise — the receipt says which) and files it as a `draft` `CDParentCommunication`. Refuses to touch a `reviewed` or `sent` report, and keeps an existing draft's text unless `overwrite` is true; says so and writes nothing when the month has no evidence. Never sends |
| **Reference & progression** | |
| `list_procedures` | `CDProcedure`; a single match returns its full text |
| `list_stories` | `CDStory` metadata (the PDFs themselves are not returned) |
| `student_tracks` | `TrackProgressResolver` over the student's `CDStudentTrackEnrollmentEntity`s |
| `student_curriculum_map` | `CurriculumMapLoader.snapshot` + `CurriculumMapEngine.cells(for:)` — the Three-Year View's cells for one child: Great Lessons, then every area with each key lesson's state (not presented / presented / chosen / repeated / mastered), dates, latest recall outcome, and the untouched-area list from `CurriculumMapSettings` |
| `class_curriculum_map` | the same engine over every enrolled child, for one lesson (or the best state across one area), grouped by state and ordered by enrollment year — the names to hand to `schedule_presentation` |

Deletes are deliberately not exposed, with one exception:
`remove_student_from_work` takes a child off a work item, which on a linked
copy she owns means deleting that row. It is one of two tools that destroy
rows, so it is confirm-gated — a call without `confirm` only reports the
plan — and it never touches another child's completion.
`discard_presentation` is the other: `reschedule_presentation(unschedule:
true)` only returns a plan to the planning list, so a regrouped presentation
used to leave its original behind; discarding is the planning list's own
delete (notes cascade with it), gated the same way, refused for anything
already given, and it returns any year-plan entry promoted into the plan to
`planned` rather than leaving it pointing at nothing. The gate is the
`confirm` flag, not a call count: a first call *with* `confirm: true`
deletes at once, and the preview call is offered rather than required, so a
caller who already holds the presentation id is not made to ask twice. Regrouping itself is
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

**App-level services.** `AutoBackupManager` and `MonthlyReportDraftService`
are reached through `AppDependencies`, which is injected into the SwiftUI
environment rather than resolvable from a static tool handler. `MCPAppServices`
is the one-slot locator that bridges the gap: `performStartupBootstrap`
registers the app's container just before `MCPServerService` starts, and
`makeTools(context:dependencies:)` hands the two tools that need it
(`create_backup`, `draft_parent_report`) a provider closure — nil before
startup and under tests, where they answer that the app is still starting,
or a container built on the in-memory stack when a test supplies one.
`sync_status` needs none of this because `CloudKitSyncStatusService` is a
singleton.

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
decisions the capture review offers ride on each `student_observations`
item as `follow_up`: `practice` and `follow_up_work` create one work item
per (presentation, child, kind), titled from `follow_up_detail` when given;
`re_present` puts the lesson back on the child's planning list unless a plan
naming her is already waiting; `ready_for_next_lesson` confirms her on the
presentation; `continue_observing` (or the older `needs_follow_up` flag)
sends the observation to the follow-up inbox. They are written by
`CaptureFollowUpPersistence`, the command bar's own follow-up code lifted out
of `CommandBarViewModel` so both paths share one implementation. The
`presentations` array is the evening-catch-up form: every item is resolved
before anything is written, each item is written without saving, and one
save covers the batch — a bad name in the fourth item leaves nothing behind
from the first three, and the error names the item (`presentations[3]: …`).

`mastery_candidates` + `mark_mastered`'s `marks` array are the pair that
closes the gap the sequence tracks show as "0 mastered": recording a
presentation never marks mastery, and going back to assess is a separate
trip. Nothing about that is fixed by inferring a mark — a mark means the
guide assessed the child — so the read proposes and the write confirms.
The read gathers what the notebook already holds beside the presentation
(the guide's confirmation at capture, practice work that came back complete
or proficient, a recall check that found the lesson retained), ranks the
pairs by how much of it there is, cites each one, and hands back the exact
call to make. The guide's yes then covers the whole list in a single write.

The two curriculum-map tools are the Three-Year View over MCP. They read
nothing the screens do not: `CurriculumMapLoader` reduces the notebook to
value types, `CurriculumMapEngine` derives one cell per (child, lesson) —
a presentation makes it *presented*, work or practice following it makes it
*chosen*, three practice sessions or work past active make it *repeated*,
the mastery record (or the guide's confirmation on the presentation) makes
it *mastered*, and the latest recall check rings it — and both tools print
those cells. `student_curriculum_map` is the call for "what has Ora not had
yet" and for planning a child's next month: Great Lessons first (built from
the `greatLessonRaw` tag, story-format lessons preferred, never by name),
then every area at the chosen granularity (`keyLesson` by default: hand-
marked `isKeyLesson`, the first lesson of every sub-area, and the Great
Lesson stories), closing with the areas that have had no presentation inside
the guide's threshold. `class_curriculum_map` answers "who has not had the
distributive law" as names grouped by state, oldest cohort first, ready for
`schedule_presentation`. Neither judges: they report presence and absence
of records, and say so.

`students_pending` is the planning-side counterpart: where the class map
reads the record (who has *had* a lesson), this reads the plan (who is *due*
for it). It is the call a guide makes when forming a group — one lesson in,
every enrolled child who still has it ahead of her out, each with her target
date, whether she is behind pace, and the scheduled presentation she is
already on, if any, with its day, time and the rest of the group. It used to
take one `year_plan` call per child. The three sources that make a child
pending are a planned entry the record has not answered, a promoted entry,
and an unpresented assignment with no entry behind it; the trailer names who
has had it and who has no plan, so the guide can see who could join.

`students_ready` asks the same question from the record's end, and it is the
one the notebook could not answer at all before: at capture the guide tags a
child ready for the next lesson, and a mastery mark says it more strongly,
but neither mark went anywhere — the only way to say "soon" was to put a date
on it. The tool turns both into a queue. A child is in it when she is
confirmed or mastered on a lesson and the next lesson in the *same* sub-area
is neither on her record nor on an open plan for her; the practice gate the
Small Sequence Planner applies holds her at almost-ready, with the reason, so
the two surfaces never disagree about the same child on the same day. Grouped
by lesson it closes each group with the exact `schedule_presentation` call —
it proposes, and writes nothing.

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

## Example calls

Arguments as a client sends them in `tools/call`. Names resolve the way
every tool resolves them — a student by first name, full name, nickname, or
id; a lesson by id or by exact then unique-partial name — and a miss or an
ambiguity comes back as a tool error naming the candidates.

```jsonc
// Put a lesson on the calendar at a time. Without "time" it lands at the
// app's default morning slot (9:00); the receipt names the time either way.
{"name": "schedule_presentation", "arguments": {
  "lesson": "The Distributive Law of Multiplication",
  "student_names": ["Ora", "Etty Klein"],
  "date": "2026-09-14", "time": "10:30"}}
// → Scheduled [presentation id=…] The Distributive Law of Multiplication — Ora Levi, Etty Klein on 2026-09-14 at 10:30.

// Re-time a plan on the day it already has; add "date" to move the day too.
{"name": "reschedule_presentation", "arguments": {
  "presentation_id": "6121E630-…", "time": "13:15"}}
// → [presentation id=…] The Distributive Law of Multiplication stays on 2026-09-14, now at 13:15.

// "Has Ora ever had the checkerboard?" — dated presentations plus her
// presentation record for the lesson, so a checklist mark still counts.
{"name": "student_presentation_history", "arguments": {
  "student_name": "Ora", "lesson": "Checkerboard"}}
// → Presentations of Checkerboard for Ora Levi (1): … / Presentation record of Checkerboard: mastered; …

// Everything since a date, past the default ten.
{"name": "student_presentation_history", "arguments": {
  "student_name": "Ora", "since": "2026-06-01", "limit": 200}}

// Who is due for a lesson — the group-forming query.
{"name": "students_pending", "arguments": {"lesson": "Checkerboard"}}
// → [lesson id=…] Checkerboard — Math › Multiplication — pending for 4 of 22 enrolled child(ren):
//   - [student id=…] Ora Levi — target 2026-09-05 (behind pace) — not on the calendar
//   - [student id=…] Etty Klein — target 2026-09-19 — scheduled 2026-09-14 at 10:30 with Dalia Roth [presentation id=…]
//   …

// Who is ready for what — the same question from the record's end.
{"name": "students_ready", "arguments": {"group_by": "lesson", "area": "Math"}}
// → [lesson id=…] Distributive Law — Math › Laws — ready (2): Avital Beyderman, Etty Krinsky; almost ready (1): Ora Levi (practice on Commutative Law not yet complete)
//   To schedule: {"arguments":{"date":"2026-09-14","lesson":"…","student_names":["Avital Beyderman","Etty Krinsky"]},"name":"schedule_presentation"}
//   Already given (12): … / No plan for it (6): …

// Discard a plan. Without "confirm" this only reports; with it, the
// presentation is deleted in this call — no second call needed.
{"name": "discard_presentation", "arguments": {
  "presentation_id": "6121E630-…", "confirm": true}}
// → Discarded. [presentation id=…] Checkerboard — scheduled 2026-09-14 — Ora Levi …
```

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
- `Maria's Notebook Tests/Services/MCPServer/MCPMasteryToolsTests.swift`
  — `mark_mastered`: an MCP mark and a checklist mark read identically to
  `TrackProgressResolver`, the row is mutated rather than duplicated, the
  refusal for a child with no presentation on record writes nothing, and
  today-default versus back-dated assessment.
- `Maria's Notebook Tests/Services/MCPServer/MCPMasteryBatchToolTests.swift`
  — the `marks` batch: two lessons for two children in one call, an
  unrecorded child in the second item leaving every row untouched, the
  single form and `marks` together refused, and an empty array refused.
- `Maria's Notebook Tests/Services/MCPServer/MCPMasteryCandidatesToolTests.swift`
  — `mastery_candidates`: a confirmed unmarked child listed with her day, an
  already-marked pair, a never-presented lesson and a withdrawn child all
  kept out, completed practice work standing as evidence on its own,
  `group_by: lesson` gathering the names, `area` and `limit`, and the
  closing JSON parsing and feeding straight back into `mark_mastered`.
- `Maria's Notebook Tests/Services/MCPServer/MCPCurriculumToolsTests.swift`
  — the curriculum tools: uncapped listing, create (append, after-anchor,
  idempotency, area refusal, track refresh), rename and move, partial
  reorder carrying unlisted lessons, and store routing on a split stack.
- `Maria's Notebook Tests/Services/MCPServer/MCPPlanningEditToolsTests.swift`
  — discard (preview, confirmed delete with note cascade and year-plan
  entry restored, refusal when given), roster edits and their refusals,
  and `clear_year_plan` scoped by track and date, previewed then applied.
- `Maria's Notebook Tests/Services/MCPServer/MCPScheduleToolsTests.swift`
  — the calendar tools, including the `time` argument on
  `schedule_presentation` and `reschedule_presentation` (default morning
  slot, `HH:MM` placement, time-only re-timing, malformed times refused).
- `Maria's Notebook Tests/Services/MCPServer/MCPRepeatGuardToolsTests.swift`
  — the regive guard on both write tools: per-child dates in the refusal and
  nothing written, `second_pass` flagging the earlier record, `review`
  leaving it alone, a purpose with nothing to explain, an unknown purpose, a
  non-school day, a batch refused whole for one repeat, and the same-day and
  planned-lesson exemptions.
- `Maria's Notebook Tests/Services/MCPServer/MCPPresentationHistoryToolsTests.swift`
  — `student_presentation_history`: the default cap and what it says when it
  holds rows back, `limit`, `since`, and the `lesson` filter reading the
  presentation record beside the dated rows, and the ordinal-and-purpose
  suffix on a lesson given more than once.
- `Maria's Notebook Tests/Services/MCPServer/MCPPendingStudentsToolTests.swift`
  — `students_pending`: planned, promoted and calendar-only children, behind
  pace, the group on a scheduled presentation, the given / no-plan trailer,
  and a withdrawn child kept out.
- `Maria's Notebook Tests/Services/MCPServer/MCPReadyForNextToolTests.swift`
  — `students_ready`: both groupings, the closing `schedule_presentation`
  call decoded rather than pattern-matched (right lesson, right names, a day
  school is in), the `basis` / `include_almost_ready` / `student` / `area`
  filters, the empty-queue sentence, and a withdrawn child kept out. The
  queue's own rules are pinned separately in
  `Maria's Notebook Tests/Planning/ReadyForNextEngineTests.swift`.
- `Maria's Notebook Tests/Services/MCPServer/MCPPresentationOutcomeToolsTests.swift`
  — the `follow_up` decisions on `record_presentation` (work items, the
  re-present plan, confirmation, the inbox flag, an unknown value refused)
  and the `presentations` batch (one receipt per lesson, all-or-nothing,
  the failing item named).
- `Maria's Notebook Tests/Services/MCPServer/MCPAppServiceToolsTests.swift`
  — `create_backup` and `draft_parent_report` through a container built on
  the in-memory stack: the still-starting refusal when none is registered,
  an archive written and cited, a month with no evidence, and the reviewed /
  sent / existing-draft protections.
- `Maria's Notebook Tests/Services/MCPServer/MCPObservationBatchToolsTests.swift`,
  `MCPFollowUpGuardToolsTests.swift`, `MCPAttendanceBatchToolsTests.swift`
  — the duplicate guards and `force` on `create_observation` and
  `add_follow_up`, the `notes` batch, and `students` / `mark_all_present`
  on `mark_attendance`, each all-or-nothing on name resolution.
- `Maria's Notebook Tests/Services/MCPServer/MCPDateRangeReadToolsTests.swift`
  — `since` / `until` on the observation, meeting, practice and recall
  reads: a note beyond `days_back`'s reach, `until` excluding newer rows,
  `since > until` refused, and old arguments unchanged.
- `Maria's Notebook Tests/Services/MCPServer/MCPWriteJournalToolsTests.swift`
  — the journal round-trip in a temporary directory (newest first, window
  and tool filters, a malformed line skipped, the cap rewrite keeping the
  newest half) and `recent_mcp_writes` over a seeded journal; the handler
  suite covers what is journaled (a write's success with parsed citations
  and clipped arguments) and what is not (reads, errors).
- `MCPToolRegistryTests` also pins the tool count, the exact non-read-only
  and destructive sets, and `openWorldHint == false` everywhere.
- End-to-end smoke test from a shell (app running, toggle on):

  ```bash
  printf '%s\n%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"smoke","version":"0"}}}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
    | MARIAS_NOTEBOOK_NO_AUTOLAUNCH=1 "/Users/dannydeberry/Developer/Maria's Notebook/Scripts/mcp/marias-notebook-mcp"
  ```
