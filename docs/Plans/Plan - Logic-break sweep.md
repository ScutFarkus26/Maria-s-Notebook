> Moved from `~/.claude/plans/analyze-my-code-and-happy-frog.md` on 2026-10-04; archived the same day: built and on main.

# Logic-break sweep: findings and fix plan

> **Done 2026-09-30** (81e8f4cb).
> In short: Whole-app logic-break sweep and its fix order.
> The sweep landed on main squashed as 81e8f4cb; its loose ends landed as fa1c434f (2026-09-30).

## Context
Danny asked for a whole-app check for breaks in logic ("does the workflow work?"). Three read-only sweeps traced sync/sharing/backup, the classroom workflows, and the MCP server + parent reports + chat. I re-read the code for the top findings (marked ✔). The rest are agent-verified with file:line evidence but not yet re-checked by me. Nothing has been changed.

**Short answer:** most day-to-day flows hold together. Scheduling, recording and reading back presentations works; work check-ins work; attendance works; backup upsert works. The real breaks cluster in four places: (1) launch cleanup during a first download (data loss), (2) group records leaking one child's state onto classmates, (3) "given" rows that outlive the presentation, (4) MCP writes that half-commit or report success on failure.

## Fix order (one commit per group, tests first where a test fits)

### Group A — data loss during first download (sync)
1. ✔ `Services/MigrationRunner.swift:35-37,101`: launch cleanups (`repairWorkCheckInLinks`, `cleanOrphanedWorkStudentIDs`, `cleanOrphanedStudentIDs`) aren't behind `FirstDownloadGate.isPending()`, which the zone repair, orphan guard and seeder already use. After Reset Local Cache or on a new device, they delete check-ins and clear student links for rows that haven't downloaded yet, then export those changes. Fix: skip the orphan-based passes while the gate is armed. Reset Local Cache should also clear `UserDefaultsKeys.checkInLinkRepairHasRun`.
2. `AppCore/CoreDataStack+Stores.swift:186-190`: the non-CloudKit fallback calls `FirstDownloadGate.open()`, which disarms the gate permanently. Fix: only a genuine "no import will come" path opens it.
3. `Services/CloudKitSyncStatusService.swift:214-228`: the event stream starts about 2 s late, so the first import's completion can be missed and the gate stays armed. Fix: subscribe at store load, or check the existing import state when observing starts.
4. ✔ `Services/DeduplicationCoordinator.swift:136-144`: `pendingScope` is reset before `guard !isRunning`, so a request that arrives mid-pass is dropped. Fix: return before the reset, or merge the scope back and re-arm.

### Group B — one child's state leaking onto classmates (classroom)
5. ✔ `Students/Presentations/PresentationDetailViewModel+MasteryTracking.swift:14-89`: the group's highest mastery state is written to every child on any save. Fix: per-child state, written only when the guide changes it.
6. `Presentations/Planning/BlockingAlgorithmEngine.swift:185-192` + `BlockingCacheBuilder.swift:121-130`: a classmate's open copy blocks a child. Fix: filter by `WorkGrouping.owner` as `buildBlockingForPresented` does.
7. `Work/Completion/WorkLogService.swift:138-157`: `close` stamps every participant; `reopen` clears only the owner. Make the two symmetric.

### Group C — stale "given" / "promoted" rows
8. `PresentationDetailViewModel.swift:266-296`, `PresentationDetailActions.swift:37-40`: deleting, un-marking or removing a child leaves `CDLessonPresentation` rows, so the year plan shows satisfied and the regive guard refuses. Reuse the cleanup Just Presented's Undo already does.
9. The same delete path, plus `StudentDeparturePlans.swift:125-143` and `YearPlanReleaseService.swift:125-132`: promoted entries are never returned to planned or skipped.
10. `ImmediatePresentationRecordingService.swift:69-100`: Undo doesn't restore plans trimmed by `releaseRedundantPlans`.
11. `LifecycleService.swift:61-64`: a corrected given date doesn't update `presentedAt`.

### Group D — MCP writes that half-commit or misreport
12. ✔ `MCPNotebookTools+WorkWrites.swift:340`: `markCompleted` saves immediately (default `saveImmediately: true`), so a later argument error can't roll it back. Pass `saveImmediately: false`.
13. `mark_attendance`, `update_todo`, `update_issue`, `record_parent_communication`, `update_going_out`, `update_community_topic`, `update_project`, `update_guardian` throw without `rollback()` after a partial edit. Wrap them in the same do/catch-rollback shape `update_work` uses.
14. ✔ `MCPNotebookTools+Mastery.swift:180`: the `safeSave()` result is ignored. Check it, roll back and throw. The same fix applies to `RolloverService.apply` (`:224-227`).
15. ✔ `MCPNotebookTools+Reads.swift:160-166`: with `until` alone, the lower bound comes from today's rolling window, so the result is empty. The same bug is in `presentations_missing_observations`, `practice_sessions`, `recall_checks` and `recent_mcp_writes`. Fix: anchor the window to `until`, as `student_meetings` does.
16. `MCPSocketServer.swift:130-139,203-226`: after the toggle is turned off, one more tool still runs. Check `Task.isCancelled` or a stopped flag before dispatching, and cancel the connections.
17. `reschedule_presentation` doesn't call `requireSchoolDay`. `schedule_presentation` doesn't promote year-plan entries through `YearPlanPromotionService`.
18. Previews and no-op calls get journaled as writes (`MCPRequestHandler.swift:146-151`). A failed `create_backup` returns `isError:false`.

### Group E — medium/low, batch after the above
- Settings backup/restore acts on the Sample Class store (`Settings/DataManagementGrid.swift`). It should use the primary dependencies, matching the disabled menu commands.
- Ask AI in Sample Class reads the real store (`Services/AI/NotebookTools.swift:129`), and the chat session key is shared. "New Chat" mid-stream brings the old chat back (`ChatViewModel.swift:155-163`).
- Auto-created share never sweeps in the orphans. `hasActiveShare` is only set by a repair pass. The "Repair Sync Errors" message is inverted (`ClassroomSharingView.swift:503-509`).
- Membership sort order disagrees (`ClassroomMembershipEntity.swift` asc vs `ClassroomRepository.swift` desc).
- Rollover carry-over uses `currentYearStart()` instead of `incomingYear(store:).start`.
- Today drops open work older than 90 days (`TodayDataFetcher.swift:144-153`) and counts attendance without `deduplicatedPerStudentDay()` (`:368-382`).
- `SchoolDayChecker` matches holidays by exact date, unlike the day-rounded `SchoolCalendarService`.
- Parent reports count cancelled outings (`MonthlyReportContextBuilder.swift:253-264`). `draft_parent_report` defaults to the current month rather than `ReportMonth.currentCycle` and can revert a report marked sent.
- Smaller items: order stage skips, `create_observation` doesn't accept ids, and `WorkAging` "most recent touch".

## Update 2026-09-29: rechecked against main 285c6deb, then f4a5eb56 (APPROVED by Danny 2026-09-29)
Work on a fresh branch from current `main`; this worktree (64b69d19) is stale.
- **No longer apply (dropped):** sync #5 (share auto-create), #6 (`hasActiveShare`), #7 (Repair Sync message), #11 (zone-repair detection), all deleted by the two-zone move; #10 (membership sort) fixed by `CDClassroomMembership.current(in:)`. Photo cleanup is now gated.
- **Still open:** everything else above. The item-1 launch cleanups remain ungated, and the MCP `mark_attendance` partial edit still happens after the new `refuseLockedDay`.

### Group F: Daybook Assistant (new code; ✔ = re-read by me on main)
Lifecycle and sync:
1. ✔ `Daybook Assistant/AssistantShareAttacher.swift:57-95`: a pass keeps the container it started with, and a `flush` for a rebuilt stack only sets `runAgain`. The old pass resolves nothing on the dead context and `forget`s those marks, so they're lost. Fix: tie the pass to its stack (cancel or await it before a rebuild, restart with the new container), and never forget URIs just because resolving them failed.
2. ~~Waiting marks only retried on a save 10+ min later~~ — FIXED in f4a5eb56 (backoff 1→10 min with its own retry, foreground retry, early retry on success; AssistantShareAttacherTests). Note for F1: `UnsentChangesKeepAlive` now waits on `waitUntilIdle()`, so a pass stuck on the old stack also holds the phone awake 25 s after locking.
3. ✔ `Cosmic Daybook/Sharing/ClassroomSharingService.swift:274-291`: Leave skips the purge when no pinned share is readable, yet still deletes the membership (and ignores a failed save). Fix: fall back to the only share or throw, and check the save.
4. ✔ `AssistantBootstrapper.swift:199`: a `.couldNotDetermine` or `.temporarilyUnavailable` first check arms a full stack rebuild. Only `.noAccount` (and `.restricted`) should.
5. ✔ `AssistantAttendanceView.swift:122-126`: the "everyone marked" haptic, ripple and bell fire on every launch, because the value goes from nil to 0. Trigger only on a real increase.
6. The mirroring-stopped signal is dropped (`CDAttendanceStore+ClassroomShare.swift:69`), and `fetchShares` runs on the main actor when offline (`ClassroomShareAttach.swift:175-185`).
7. Smaller: the Rebuild button can do nothing when Siri has opened the stack. Leave on another iPhone doesn't send this one back to joining. The sync-status keys survive a rebuild. Sample mode and Leave don't clear the Late-phase and Siri-undo defaults.

Attendance and Siri:
8. ✔ `Cosmic Daybook/Siri/SiriAttendance.swift:50-58`: Siri checks `isEnrolled`, not `AttendanceRoster` for today. It can mark a child who hasn't started yet, and it refuses a child who is leaving but is still on today's grid. Use the roll rule, in both apps' Siri hosts.
9. ✔ `Cosmic Daybook/Logs/AttendanceLogView+Rows.swift:102-105`: the log's Change Status sets `record.status` directly. That skips the lock, `modifiedAt`, the marker name and `markedAt`. Route it through `CDAttendanceStore.updateStatus`, and delete through the store too.
10. Close Arrival's automatic absent can win the duplicate cleanup over a real mark made on another device (`CDAttendanceStore.swift:229-241`, `AttendanceDeduplication.swift:14-22`). An automatic absence should lose to any real mark.
11. The Assistant roll may show test students (`AssistantDayRoll.swift`); check whether `AttendanceRoster.predicate` excludes them. The Assistant also doesn't remove duplicate student rows.
12. Siri Undo: fails after a reason-only change, ignores the lock and forgets the change, and can undo an older voice mark after a grid Close Arrival. Close Arrival by Siri doesn't re-check the lock after confirmation. A failed Close Arrival leaves the day in Late.
13. The two apps disagree: in the notebook, "here" after the Assistant closes arrival records present rather than tardy, and the locked-phone fallback searches former and test students.

Pending outside the code: deploy the Production CloudKit schema for `leftAt` before the next install (tracked in Progress.md).

## Suggested order
A (launch cleanup data loss) → F1–F3 (lost marks, Leave) → B (group leaks) → F8–F10 (roll rule, log bypass, auto-absent) → C → D → F rest → E.

## Verification
- A Swift Testing test per fix where the logic is unit-shaped: dedup re-arm, the `until`-only window, update_work rollback, per-child mastery on save, the owner-only blocker, and delete removing `CDLessonPresentation` rows. Run with `-only-testing:` for each suite, then the full suite once at the end (`Scripts/locked_xcodebuild.sh`).
- Group A needs a simulator run: Reset Local Cache with a seeded store, then confirm the check-in and work-student counts are unchanged after the first download (sqlite count before and after).
- MCP fixes: live check against the relaunched app with the cosmic-daybook tools (bad-argument `update_work`, `student_observations(until:)`, toggle off mid-session).
- Don't run the macOS test host against the live store (see memory: test host opens the live store).
