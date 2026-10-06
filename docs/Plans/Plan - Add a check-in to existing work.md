# Add a check-in to existing work

> **Done 2026-10-06** (205bfdd2). Written and built the same day.
> In short: `update_work` gets `add_check_in_on` / `add_check_in_purpose` / `add_check_in_for_this_child_only`, so a check-in can be scheduled on work that already exists.

## Goal

From a Claude chat, Danny can say "check in with Maya on her sentence diagrams Thursday" about work that already exists, and the check-in lands on the schedule exactly as one made by `assign_work` would: same record, same fields, scheduled status, on every linked copy unless he says this child only. A closed day moves forward to the next school day, a day that already has one is left alone, and the reply says what happened to each copy.

## Progress
- [x] Phase 1: Build it, test it, document it (session: here) · est. ~1% weekly · started at 93%, ended at 93% (<1%). As planned; the only extra was a duplicate reply that says the existing check-in's status ("already has a scheduled check-in on …").

## Cost

About 1% of the weekly limit (Max). 93% is used, so 7% is left until Sun 11 Oct, 1 pm. Fits, but little else will fit this week.

## Decisions

- **One way to make a check-in.** Today `assign_work` (`Services/MCPServer/MCPNotebookTools+WorkWrites.swift`, `createWork`) calls `CDWorkCheckIn.make(for:on: AppCalendar.startOfDay(day), purpose:, in:)`. That call moves into one small helper, `scheduleCheckIn(for:on:purpose:in:)`, in `MCPNotebookTools+WorkCheckIns.swift`, and both `assign_work` and the new argument use it. `CDWorkCheckIn.make` (`Work/CheckIns/WorkCheckInEntity.swift`) stays the only constructor: it sets the relationship and the `workID` string together, status `.scheduled`, purpose trimmed, not student-initiated.
- **Time of day:** start of day, as `assign_work` does.
- **Closed day:** `YearPlanPacing.schoolDay(onOrAfter:in:)`, the same rule `move_check_in_to` uses, with the same reply wording ("… is not a school day, so it moved forward to …").
- **Linked copies:** found with `WorkGrouping.group(containing:in:).siblings`, as moving does. Every copy gets one by default; `add_check_in_for_this_child_only` adds it to this row only and the reply says how many copies got none.
- **Duplicates (Danny, 2026-10-06):** a *scheduled or completed* check-in on the landing day blocks a new one, for this row and for each copy separately. A *skipped* one does not block. A blocked row is not an error: the reply says "already has a check-in on <day> (scheduled)" and the rest of the call goes on. The existing check-in's purpose is not changed.
- **Closed work (Danny, 2026-10-06):** if this row is closed (mastered, done, keep practicing, incomplete) the call is refused with a plain message, before anything is written. A closed linked copy is skipped and named in the reply.
- **Order inside `update_work`:** adding runs after moving and before the status change, so a move to the same day in the same call counts as the existing check-in, and a status that closes the work in the same call settles the new check-in the way closing settles any later one.
- **`add_check_in_purpose` without `add_check_in_on`** is refused ("add_check_in_purpose needs add_check_in_on — the day of the check-in."). `add_check_in_for_this_child_only` alone does nothing, like its move counterpart.
- **Sync:** nothing new. `update_work` saves through `modelContext.safeSave()` on the app's own context, the same save every other MCP edit uses, so iCloud picks it up like any change. Tests can't see iCloud; that part is by construction.
- **Small tidy-up:** the "Eli Test's linked copy [work id=…]" label in `moveSiblingCheckIn` becomes a shared `linkedCopyLabel(_:in:)` so add and move word copies the same way.
- **Ruled out:** a separate `add_check_in` tool (Danny asked for `update_work` fields); a second constructor for check-ins (the reason `CDWorkCheckIn.make` exists); a check-in time of day (no caller asks for one).

## Apple guidance

Not applicable. No new Apple API: the change uses the project's existing Core Data helpers and save path.

## Phase 1: Build it, test it, document it
- Who: main session (Opus 5.5, high; three files and one test file, all already read here)
- Steps:
  - `Cosmic Daybook/Services/MCPServer/MCPNotebookTools+WorkCheckIns.swift`: `scheduleCheckIn`, `linkedCopyLabel`, `applyCheckInAdd` (validate, closed-row refusal, landing day, this row, then each copy or the this-child-only line).
  - `Cosmic Daybook/Services/MCPServer/MCPNotebookTools+WorkWrites.swift`: `createWork` calls `scheduleCheckIn`; `updateWork` calls `applyCheckInAdd` after `applyCheckInMove`; three new schema fields; tool description mentions adding a check-in.
  - `Cosmic Daybook Tests/Services/MCPServer/MCPWorkCheckInToolsTests.swift`: an "Adding" section — adds one (read back from `schedule_for_range` under Work check-ins due and from `work_detail`'s Check-ins, with the purpose and scheduled status), closed day moves forward and says so, linked copies all get one, this child only, duplicate on this row and on a copy (no second record, reply says so), skipped day doesn't block, closed row refused, purpose without a day refused.
  - `docs/Technical notes/MCP_SERVER.md`: the `update_work` row names the new fields.
- Cost: ~1% of weekly (small, patterned, main session; runs at ~1% in the log)
- Done when: `build-for-testing` of the Cosmic Daybook scheme succeeds; `-only-testing:"Cosmic Daybook Tests/MCPWorkCheckInToolsTests"` passes, plus the other MCP work suites (`MCPWorkToolsTests` or whichever cover `assign_work`) so the shared helper didn't change `assign_work`; then the whole suite once on the leased simulator (1 simulator, `-parallel-testing-enabled NO`).
- Hand off: no

## Starting a phase
Read the plan usage (`get_usage`) and note the weekly % used next to the phase under Progress ("started at N%").

## Ending a phase
1. Check every "Done when" item for the phase.
2. Tick the phase under Progress and note anything that differed from the plan. Read the plan usage again and note the actual cost (end % minus start %).
3. Add a row to the log in `~/.claude/skills/plan-efficiently/references/cost-estimates.md`.
4. No build board for this plan.
5. Make every "not verified", "for your review" or "check on a device" item a row in Tide (`Areas/App Development/Cosmic Daybook/TODO.md`, `add_action`), skipping ones already there. Likely one: try it from a real chat once the app with this change is running, since the MCP server runs inside the installed app.
6. Run /close-out.

## Still to check

- Try it from a real Claude chat once a build with this change is running, and see it on Today and on the other devices after sync. [Tide row](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=From%20a%20Claude%20chat%2C%20add%20a%20check-in%20to%20existing%20work%20with%20updatework%20and%20see%20it%20on%20Today)

## Open questions
None.
