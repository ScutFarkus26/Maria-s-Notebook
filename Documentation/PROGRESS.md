# Progress: Production move, then the Daybook Assistant improvements

Repo copy of the build board (https://claude.ai/artifact/VZpfwHWT7cGz1vkn3xNzNm).
Milestones 1–7: Part 2 of the two-zone Production move. Milestones 8–13: the 20
Daybook Assistant improvements picked from the 2026-09-29 top-25 review (plan:
`~/.claude/plans/polymorphic-crafting-kahan.md`).

## Milestones
- [x] 1. Two-zone app changes
- [x] 2. Production schema
- [x] 3. Mac on Production
- [x] 4. Assistant test
- [x] 5. iPhone + iPad
- [x] 6. Tidy up
- [ ] 7. Attendance parity (blocked: roll-out of 63101f40 waits for Danny)
- [x] 8. Tests & correctness
- [x] 9. Joining & identity
- [x] 10. Tile menu
- [x] 11. Reminder, Siri, sync
- [x] 12. Close Arrival & layout
- [ ] 13. Ship to devices

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
- [ ] Attendance roll redraws when another device marks (fix 978fb33d; ships with attendance parity)
- [x] Production holds exactly two zones
- [x] Push main to GitHub

## 6. Tidy up

### Tidy up
- [x] Move store copies with children's data to the Trash
- [x] Update memory and docs for the Production move

### After step 6
- [ ] Ship attendance parity + roll redraw fix together
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
