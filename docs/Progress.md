# Progress: Production move, then the Daybook Assistant improvements

> **In progress** Milestones 1–12 and 14–32 are done or landed on main; Milestone 13 (ship to the devices) is active with its device checks open, and Milestone 32's on-screen check waits for Danny. Status checked against git 2026-10-04.

Repo copy of the build board (https://claude.ai/artifact/VZpfwHWT7cGz1vkn3xNzNm).
Milestones 1–7: Part 2 of the two-zone Production move. Milestones 8–13: the 20
Daybook Assistant improvements picked from the 2026-09-29 top-25 review (plan:
`Plans/Plan - Daybook Assistant 20 fixes.md`). Milestones 14–21: the logic-break
sweep (plan: `Plans/Plan - Logic-break sweep.md`), squashed onto main
as 81e8f4cb. Milestone 22: the sweep's loose ends and live MCP checks, squashed onto
main as fa1c434f. Milestone 13 ships it all to the devices.

## Milestones
- [x] 1. Two-zone app changes
- [x] 2. Production schema
- [x] 3. Mac on Production
- [x] 4. Assistant test
- [x] 5. iPhone + iPad
- [x] 6. Tidy up
- [x] 7. Attendance parity (63101f40 on main 2026-09-29; rolled out with 4c83cb89 on 2026-09-30, see 13)
- [x] 8. Tests & correctness
- [x] 9. Joining & identity
- [x] 10. Tile menu
- [x] 11. Reminder, Siri, sync
- [x] 12. Close Arrival & layout
- [ ] 13. Ship to devices (active)
- [x] 14. Launch cleanup gate
- [x] 15. Assistant attach, Leave
- [x] 16. Group leaks
- [x] 17. Siri roll, log, absent
- [x] 18. Stale given rows
- [x] 19. MCP write safety
- [x] 20. Assistant leftovers
- [x] 21. Medium and low
- [x] 22. Sweep loose ends

## 5. iPhone + iPad (done 2026-09-28)

### Build
- [x] Release build of main for Production (ab5b2200)

### Install
- [x] Mac on the same build
- [x] iPhone 18 Pro installed
- [x] iPad mini installed

### First download
- [x] iPhone shows the whole notebook (38 students, 3,107 attendance)
- [x] iPad shows the whole notebook (same counts)

### Sync checks
- [x] A change on one device reaches the other
- [ ] Attendance roll redraws when another device marks (fix landed on main as 63101f40 and rolled out 2026-09-30; the device check is under 13)
- [x] Production holds exactly two zones
- [x] Push main to GitHub

## 6. Tidy up

### Tidy up
- [x] Move store copies with children's data to the Trash
- [x] Update memory and docs for the Production move

### After step 6
- [x] Ship attendance parity + roll redraw fix together (63101f40, rolled out with 4c83cb89 on 2026-09-30)
- [ ] Make former students easier to find on iPhone/iPad (optional)

## 8. Tests & correctness (done 2026-09-29)

### Foundations
- [x] #24 Assistant test target (a1657a95; 8 tests pass on the iPhone SE simulator)
- [x] #23 Privacy manifest (fc7ae7f8; UserDefaults CA92.1)
- [x] #23 Icon: dark and tinted variants (.icon bundle + flat PNGs from the same SVGs)

### Correctness
- [x] #3 Time rules + departure time (schema 11, backup v33; Production schema deploy owed before any install)
- [x] #4 Future days: absences only
- [x] #6 Haptics only for her own taps
- [x] #7 Errors that clear and tell the truth
- [x] #8 Roster by day (Assistant, notebook grid, MCP)
- [x] #22 Less work per tap

## 9. Joining & identity (done 2026-09-29)
- [x] #5 Join errors visible (toast overlay, onboarding shows the error; a good join no longer reads as failed)
- [x] #15 "Joining your classroom…" state + iCloud account check (onboarding and sync line)
- [x] #14 Name required on first run, mirrored to iCloud key-value storage
- [x] #16 Classroom screen (guide, joined, classroom ID, name, Leave); real Leave untested pending Danny's go-ahead

## 10. Tile menu (done 2026-09-29)
- [x] #9 Absent + reason in one step; Appointment, Family, Other (Other opens the note)
- [x] #11 "Marked by you / Rivka / your guide at 8:02" heading the menu

## 11. Reminder, Siri, sync (done 2026-09-29)
- [x] One stack per process (AssistantBootstrapper.shared) + AssistantSave (save + share attach) for grid and intents
- [x] #17 Arrival reminder: school days at 8:15 (adjustable in Classroom), withdrawn once everyone's marked; tap opens today
- [x] #19 Siri & Shortcuts: Mark Present / Late / Absent (reason, day ahead), Who's Not Here Yet
- [x] #25 Sync line: "All marks sent · class updated 2 min ago"

## 12. Close Arrival & layout (done 2026-09-29)
- [x] #1/#10 Close Arrival… button with a confirm naming who'll be marked absent; "Late" capsule reopens arrival
- [x] #2 Tiles stay as they are and scroll; slimmer bar and a fade above it
- [x] #12 Accessibility text sizes: two columns, two-line detail, stacked bar (AM/PM dropped earlier)
- [x] #13 Sideways swipe on the grid steps school days, with a slide

## 14. Launch cleanup gate (done 2026-09-29, 6909e2f8)
- [x] Orphan cleanups wait for the first download; Reset Local Cache clears the check-in flag
- [x] A CloudKit fallback no longer opens the gate
- [x] First import caught inside the 2 s observer delay (no unit test)
- [x] Dedup keeps a request that arrives mid-pass
- [x] Device check (2026-09-30, iPhone 17 sim, spare Apple Account): 30 students / 300 work / 600 check-ins unchanged after Reset Local Cache; mid-download 99 check-ins sat unlinked with a relaunch, none lost

## 15. Assistant attach, Leave (done 2026-09-29, ef5c7369)
- [x] F1: attach pass follows a rebuilt stack and keeps marks it can't read
- [x] F2: waiting marks retried on a backoff (already in f4a5eb56)
- [x] F3: Leave purges the only share and checks its save

## 16. Group leaks (done 2026-09-29, 9e6bdb63)
- [x] B5: group mastery written only when the guide changes it
- [x] B6: a classmate's open copy no longer blocks a child
- [x] B7: close and reopen stamp the same children

## 17. Siri roll, log, absent (done 2026-09-29, ef1351c9)
- [x] F8: Siri uses today's roll, not enrollment, in both apps
- [x] F9: the log's Change Status and delete go through the attendance store
- [x] F10: an automatic absence loses to any real mark in dedup (no schema change)

## 18. Stale given rows (done 2026-09-29, e016c8cf)
- [x] C8: deleting, un-marking or removing a child clears their given rows
- [x] C9: promoted entries go back to planned (or skipped at departure, or follow the presentation that answered them)
- [x] C10: Undo restores plans trimmed or discarded by releaseRedundantPlans
- [x] C11: a corrected given date updates presentedAt

## 19. MCP write safety (done 2026-09-29, 7814b9e0)
- [x] D12: update_work's completion rolls back with a later argument error
- [x] D13: eight write tools roll back a partial edit when they throw
- [x] D14: mark_mastered and rollover check their save
- [x] D15: until-only windows anchor to until
- [x] D16: no tool runs after the toggle is turned off (no unit test; macOS build checked)
- [x] D17: reschedule checks school days; schedule promotes year-plan entries
- [x] D18: previews and no-ops aren't journaled; a failed create_backup is an error

## 20. Assistant leftovers (done 2026-09-29, b5ab0d55)
- [x] F4: only no-account (or restricted) arms a stack rebuild
- [x] F5: everyone-marked haptic and bell fire only on a real increase
- [x] F6: mirroring-stopped signal kept; offline fetchShares off the main actor (off-main part has no unit test)
- [x] F7: Rebuild, Leave elsewhere, sync keys, sample-mode defaults (rebuild and Leave-elsewhere wiring have no unit test)
- [x] F11: Assistant roll excludes test students and duplicate rows
- [x] F12: Siri Undo and Close Arrival edge cases
- [x] F13: the two apps agree on late after close and the locked-phone search (macOS build checked)

## 21. Medium and low (done 2026-09-29, 311aead4)
- [x] E1: Settings backup and restore act on the real notebook, not Sample Class (no unit test; iOS and macOS builds checked)
- [x] E2: Ask AI reads the active store; New Chat mid-stream stays new
- [x] E3: Rollover carry-over uses the incoming year's start
- [x] E4: Today keeps old open work and counts deduplicated attendance
- [x] E5: SchoolDayChecker matches holidays by day
- [x] E6: Reports skip cancelled outings; draft_parent_report month and sent guard (the sent-during-draft re-check has no unit test)
- [x] E7: Order stage skips, create_observation ids, WorkAging most recent touch

### Full suites (2026-09-29, iOS 27 iPhone 17 simulator)
- [x] Daybook Assistant: 89 of 89
- [x] Cosmic Daybook: 1963 of 1965; the two failures pass alone (ChatViewModelTests raced on the process-wide chat context, now serialized; RemoteImportReloaderTests' pause test is timing-bound under load and untouched by this branch)
- [x] Group A device check (milestone 14): passed
- [x] Found during it and fixed: F4 temporarily-unavailable iCloud rebuilds again, Leave refuses with no readable share (ea271509); Manage Sharing saves off the main actor (ba4bf394)
- [x] Merge: squashed onto main as 81e8f4cb and pushed 2026-09-30 (Assistant 116/116, notebook 2080/2080, Mac build clean)

## 22. Sweep loose ends (done 2026-09-30, fa1c434f; was branch fix/logic-break-loose-ends-2026-09-30)

### Code (612956a4; each new test failed on the old code first)
- [x] The notebook's Close Arrival retires Siri's Undo for that day, as the Assistant's grid does
- [x] The Assistant's Classroom ID reads the share UUID ("DB5879EF"), not "com.appl"
- [x] Leave-elsewhere ignores this iPhone's own Leave in progress (rule unit-tested; the flag wiring has no unit test); own Leave also cancels the front-desk email reminder
- [x] Ask AI streams: already on main as 80437937 (ChatService passes `timeout: nil`)

### Live MCP checks (2026-09-30, Release origin/main 81e8f4cb installed in /Applications)
- [x] update_work: a real completion plus a bad due_date is refused and leaves no completion, nothing journaled
- [x] student_observations with only `until` (2026-02-15) returns the 30 days through it (3 notes, not the Jan 5 ones)
- [x] Turning the Claude Desktop toggle off mid-session: the next call gets "Connection closed", the port is closed, and the log shows only the disconnect

### Full suites (2026-09-30, iOS 27 iPhone 17 simulator) and Mac build
- [x] Daybook Assistant: 118 of 118
- [x] Cosmic Daybook: 2081 of 2081
- [x] macOS build of the branch: clean
- [x] Merge: squashed onto main as fa1c434f (2026-09-30), pushed

## 13. Ship to devices (active, 2026-09-30)

### Ship
- [x] Merge the branch to main and push (944eb2c5)
- [x] Schemas 11 and 12 deployed to Production (12 on 2026-09-30: Production had refused CD_AttendanceEmailSettings, which stopped classroom sync on 92f7f54f and 81e8f4cb)
- [x] Assistant App ID: extended share access capability
- [x] Roll main 4c83cb89 out to Mac, iPhone and iPad (16:35–16:41)
- [x] Daybook Assistant on Danny's iPhone (4c83cb89, 16:43)
- [x] Assistant TestFlight build for the assistants: 0.1 (202609302045) from 6674a930, uploaded and processed

### Checks
- [ ] Classroom sync resumes after the roll-out (Mac: first upload 16:35 clean; iPhone and iPad not yet read)
- [ ] Real-share checks: join state, Leave, guide's name, reminder firing, Siri
- [ ] Tide device checks: fa1c434f, gmail re-invite, then the rest

## Plain English (milestones 27–32, plan `docs/Plans/Plan - Plain English messages.md`)
- [x] 27. Plain English: shared
- [x] 28. Plain English: sync
- [x] 29. Plain English: backup
- [x] 30. Plain English: sharing & Siri
- [x] 31. Plain English: screens
- [ ] 32. Plain English: merge & verify (on main as 9503d7f2 on 2026-10-03, merged and tested; the on-screen check waits for Danny)
