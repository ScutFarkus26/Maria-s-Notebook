# Tide list check 2026-11-22

Phase 1 of `docs/Plans/Plan - Tide list clean-up 2026-11.md`. Every open row in Cosmic Daybook's list in Tide (`Areas/App Development/Cosmic Daybook/To do.md`) was read and put in exactly one of four piles. Nothing was reworded. Each closed row got one dated line in its note saying why. Main was 0bd5c3225 (plus the plan commits) when the checks ran.

## Counts

| | Before | Completed | Dropped | Left open | After |
|---|---|---|---|---|---|
| Release | 11 | 7 | 1 | 3 | 3 |
| Check on a device | 205 | 0 | 6 | 199 | 199 |
| Review choices | 77 | 0 | 1 | 76 | 76 (+1 new, below) |
| Build & fix | 15 | 1 | 0 | 14 | 14 |
| Someday ideas | 1 | 0 | 0 | 1 | 1 |
| **All rows** | **309** | **8** | **8** | **293** | **293** (+1 new row = 294) |

The four piles add up to 309: 8 completed + 8 dropped + 52 doubtful (left open) + 241 still apply (left open). Of the 293 rows left open, 52 are doubtful and 241 still apply (one of those is the Someday row). The new "Go through the doubtful rows from the 2026-11-22 list check" row makes 294.

How each pile was decided: git (`git merge-base --is-ancestor`, `git grep` on main, commit logs), the plan's D2 (every device is on Cosmic Daybook 047 and Assistant 036) and D10, then an Opus agent re-checked every completed and dropped row cold against the code. It found two that didn't hold (a ParentLocker "before switching" row and a To-dos row whose Tide check still exists); both moved to doubtful.

## Completed (8)

| Row | Why |
|---|---|
| Install TestFlight build 300000000034 of Cosmic Daybook on the Mac, iPad and iPhone, so the track tables can be dropped | Replaced: build 300000000047 is on every device (D2), and the track retirement it waited on landed on main as schema 23 (afcf5daaa; the four tables are kept as dormant tombstones, their columns dropped). |
| Install TestFlight build 300000000038 of Cosmic Daybook on the Mac, iPad and iPhone | Replaced: build 047 is on every device (D2); roll-out B was 038, from main afcf5daaa, an ancestor of 047's main. |
| Roll out main (ba5c5e15 or later) to the Mac, iPhone and iPad together | Done: ba5c5e15 is an ancestor of main aa27f869c, which became build 047 on every device (D2). |
| Roll out the Lessons & Work changes (all six, on main) to the Mac, iPhone and iPad | Done: the Lessons & Work changes rolled out in the 2026-11-03 1.1 roll-out, and build 047 is on every device (D2). |
| Update Cosmic Daybook on the Mac to TestFlight build 300000000022, then the iPad and iPhone | Done: build 022 is far older than 047, which is on the Mac, iPad and iPhone (D2); 13df091f is an ancestor of 047's main. |
| Drag the old "Cosmic Daybook (old 300000000029, root-owned).app.old" folder in Applications to the Trash and enter your… | Done: no .app.old folder is in /Applications (checked 2026-11-22); the Mac runs the TestFlight copy. |
| Roll out lesson times to every device together (Mac, iPhone, iPad and the Assistant) | Done: lesson times shipped in 044 (e3549bb6f) and co-teacher times (4b0d8d555) are in 047's main; 047 and Assistant 036 are on every device (D2). |
| Ask Claude to clear the stale staged change to AssistantAttendanceIntents.swift in the main Maria's Notebook folder | Done: the primary checkout is clean (git status, 2026-11-22), as planning D10 found. |

## Dropped (8)

| Row | Why |
|---|---|
| Upload Cosmic Daybook build 300000000026 from Xcode's Organizer, iOS then Mac | Never uploaded, and no longer needed: build 047 replaced 026 on every device (D2). |
| After the next roll-out, from the iPad in Dark Mode send myself a test parent report with a long note, and check it rea… | Parent Reports and the per-child report were cut (9032574d3, 2026-11-21); no report PDF is left to send. |
| After the next roll-out, open Resources and Clubs & Projects on the Mac and check the toolbar filter and that a selecte… | Resources, Stories, Procedures and Clubs & Projects screens are gone (8e0011ee0, c0de77edf); git grep finds no ResourcesView or ClubsProjects view type on main. |
| After the next roll-out, in Cosmic Daybook's Resources click from one file to another and check the preview and Share f… | The Resources screen and Procedures editor are gone (8e0011ee0); no ResourcesView or ProceduresView on main. |
| After round-two Simplify lands, check the iPad sidebar's Classroom group hides Going Out while there are no outings, an… | Going Out was cut (4e5c5f28f); no GoingOut view or sidebar row on main. |
| After round-two Simplify lands, on the iPhone leave More on Going Out with no outings, relaunch, and check it opens on … | Going Out was cut (4e5c5f28f); More no longer has a Going Out row. |
| After the next roll-out, on my iPhone: try Todos › Clear Completed and check it asks with a count and clears only the l… | The To-dos screen was cut (11794e745); Todos › Clear Completed no longer exists. |
| Cosmic Daybook: the classroom time zone is filled in on its own only by the Mac, at its first settings save, never by a… | Replaced by row 'the classroom time zone is now set only when you pick it' (Review choices): the Mac no longer fills it in on a save. |

## Doubtful (52, all left open)

Grouped so one answer settles a group. Row numbers below are positions in the row list the check read (the order the 309 rows came back from Tide on 2026-11-22), shown beside the row's own words.

### A. Half cut, half still alive (left open, D8) (14)

Suggested answer: Half of each row is about a screen that was cut on 2026-11-21/22 (Book Clubs, Resources, Todos, templates, parent-report sending, Recall) and half still applies. Suggested answer: drop the rows that are mostly about the cut part (67, 74, 103, 153, 154, 273, 298, 16, 73), and keep the rest (12, 113, 117, 119, 283) as they stand, since their still-alive half is worth a look.

- (12) [Check on a device] Check the Mac sidebar's new groups and Settings row, and try ⌘1 to ⌘7
- (16) [Check on a device] Launch Cosmic Daybook on the Mac and check there's one copy of each note and meeting template
- (67) [Check on a device] After the next roll-out, edit a Book Club session that has held meetings and check the marks and chosen leaders stay, then write in the same day's Day Pad on the Mac and…
- (73) [Check on a device] After the next roll-out, edit a template and an album note on the Mac and check Cancel and Save ask only when something changed, never twice
- (74) [Check on a device] After the next roll-out, send a report with Send to Family and an office order email on the Mac, and check each asks "Did the email send?" before marking it sent
- (103) [Check on a device] After the next roll-out, on my iPhone and iPad tap Open PDF on a Book Club packet and a story, open a Student File, and use Open in Pages on a lesson, and check each one…
- (113) [Check on a device] After the next roll-out, look over Cosmic Daybook's new six-group sidebar on the Mac, the iPad and the iPhone More tab, and check an old Three-Year View or Stories windo…
- (117) [Check on a device] After the schema 19 roll-out, turn on Tide sharing in Cosmic Daybook's Settings on the Mac with Tide open, check the first-run matches and how it looks, then tick a to-d…
- (119) [Check on a device] After the next roll-out, open the Class Grid on the Mac and try all four views with the real class
- (153) [Check on a device] After round-two Simplify lands, open Todos on the Mac, run the Tide sharing, and check every open to-do ends up under From Tide
- (154) [Check on a device] After round-two Simplify lands, add a to-do in Tide and tick it in Cosmic Daybook on the Mac, and check Tide ticks it too
- (273) [Review choices] Domain logic fixes Phase 8: review how classmates' names are left out of reports
- (283) [Review choices] Domain logic fixes Phase 10: review how a departure finishes after her last day
- (298) [Review choices] Someday and work-linked to-dos no longer have their own screen: check you can still find them

### B. Superseded or unprovable from git, left open (5)

Suggested answer: Row 3 (Assistant 1.1 019 before ParentLocker) can't be shown from git that every assistant had 019 first; Assistant 036 is on every phone now, so it is moot. Rows 235-238 are Review choices that later plans changed (the readiness rule and practice holding a child back were reshaped by Domain logic fixes and the Cut plan's Phase 4; the Tide sharing and Simplify choices predate the To-dos screen cut). Suggested answer: close row 3 as done; answer 235-238 by reading the current behavior in the Cut Phase 4 rows (214, 303) and drop them once you have.

- (3) [Release] Make sure every assistant has Daybook Assistant 1.1 (019) before switching attendance to ParentLocker
- (235) [Review choices] Review the readiness choices Claude made in Cosmic Daybook's one readiness rule
- (236) [Review choices] Decide whether open practice work should hold a child back in the Checklist and Today the way it does in Presentations
- (237) [Review choices] Review the choices Claude made in Cosmic Daybook's Tide sharing where it differs from the Simplify plan
- (238) [Review choices] Review the choices Claude made overnight finishing Cosmic Daybook's Simplify plan (Phase 12 notes in the plan)

### C. Old-build checks tied to builds now replaced by 047 (3)

Suggested answer: The builds these rows name (029, 034, 038) have been replaced by 047 on every device. Suggested answer: tick them if Settings shows sync healthy and the sequence cards look right, which you would have noticed; otherwise leave open.

- (137) [Check on a device] After installing build 300000000034, open a child's Current Learning and History and check her sequence cards, counts and next lesson match what the old cards showed
- (138) [Check on a device] A day after build 300000000038 is on every device, check Settings shows sync healthy on the Mac, iPad and iPhone, and that a child's notes and sequence cards still look …
- (140) [Check on a device] After updating the Mac to TestFlight build 300000000029, pick Upper Elementary, then Adolescent, in Meetings and in its History, and check only those children show

### D. Attendance and front-desk email, shipped before Oct 22, used every school day (17)

Suggested answer: You and your assistant have taken attendance on these builds for a month or more. Suggested answer: tick all of them except any you have never tried (Siri's Undo, Leaving Early, Left Early / Back in Class, future-day tiles); leave those.

- (11) [Check on a device] Mark a child on my assistant's phone, lock it right away, and check the mark reaches the Mac
- (13) [Check on a device] Mark a child on my iPhone and check my assistant's grid shows it within 2 minutes
- (14) [Check on a device] Try the Siri attendance commands on my assistant's phone and mine
- (17) [Check on a device] Have my assistant send the front-desk email from the Assistant and check my notebook shows it sent
- (18) [Check on a device] Take a morning's attendance in the notebook on my iPhone and look over the Mac's attendance screen
- (21) [Check on a device] Check the Assistant's Classroom ID and that Siri's Undo stops at Close Arrival
- (22) [Check on a device] Set a pickup time with Leaving Early… and check the reminder and the "17 here" count on my assistant's SE
- (25) [Check on a device] Check the Attendance buttons fit on my iPad with Insights open, sidebar shown and hidden
- (28) [Check on a device] Mark a child Left Early, then Back in Class, and check the trip shows on the phone tile and Mac card
- (30) [Check on a device] Try the redesigned Attendance screen on the Mac, then on the iPad
- (42) [Check on a device] With the notebook closed on my iPhone, mark a child here with Siri and check my assistant's phone shows it
- (46) [Check on a device] After the roll-out, have my assistant mark a child with Siri while her app is closed, then open it and check the line says sending until the mark reaches my Mac
- (57) [Check on a device] On a school day, leave the Mac's Attendance open from before 8:30 to after 9:00 and check the front-desk line changes at 8:30 and turns orange at 9:00
- (65) [Check on a device] After the next roll-out, open a future day's attendance in the Daybook Assistant on an iPhone and in the notebook on my iPhone, and check the tiles read "Absences only" …
- (80) [Check on a device] After the next roll-out, mark a child absent on the Assistant, then have Claude mark everyone else present, and check her absence stays
- (95) [Check on a device] After the next Assistant roll-out, check marks go on their own when the phone gets its connection back
- (101) [Check on a device] After the next roll-out, mark a test child Left Early, then tell Siri on my iPhone to mark her here, and check she's back in class with her arrival time and trip kept

### E. ParentLocker attendance since Oct 13, used every school day (5)

Suggested answer: Attendance has gone to ParentLocker since 2026-10-13. Suggested answer: tick all five if Close Arrival & Send has reached ParentLocker each morning.

- (89) [Check on a device] Switch Attendance to the School to ParentLocker in Settings, sign in once, and check Match Names finds all 23 children
- (90) [Check on a device] Take one morning's attendance with Close Arrival & Send, then check the class in ParentLocker
- (91) [Check on a device] Have each assistant sign in to ParentLocker once in the Assistant's Classroom sheet and try Siri's "Close arrival"
- (92) [Check on a device] Check the iPhone's front-desk row shows Send to ParentLocker, and the Mac's ⋯ Send Now asks about unmarked children first
- (93) [Check on a device] On the Assistant (build 019 or later), tap Who's Absent on a day with someone marked absent and check their first names show on screen

### F. Today, Lessons, Students, Meetings, Groups, Checklist screens redesigned in early October, used every school day (8)

Suggested answer: These screens were redesigned 2026-10-01 to 10-03 and you use them every school day. Suggested answer: tick all eight; anything that looked wrong would have come back as a bug.

- (23) [Check on a device] Look over the redesigned Lessons & Work on the Mac and drag a lesson onto the week
- (24) [Check on a device] Look over the redesigned Students screen on the Mac, then my iPhone and iPad
- (26) [Check on a device] Hold one real meeting in the redesigned Meetings on the Mac
- (27) [Check on a device] Present one real lesson with the new presentation sheet on the Mac, and try Presented Today on a Ready row
- (31) [Check on a device] Scroll Today on the Mac and check no grey band covers the first rows of either column
- (33) [Check on a device] Open Groups on the Mac with the real class and check the grid, level picker, area chips and the ladder's ‹ ›
- (38) [Check on a device] Look over the redesigned Checklist grid on the Mac with the real class
- (39) [Check on a device] Look over the redesigned Today screen on the Mac


## Rows that still apply (241)

Everything else, left open and untouched, including every row from the 2026-11-22 Cut phases and the removal checks that a grep for the gone views would have matched (check the sidebars no longer show Parent Reports, check the pad card is gone, and the others). Planning's D9 rows (Photos to Drive, the battery screenshot, setting up Schedules, the report switches), the Someday row, "Install the new Cosmic Daybook build on the Mac" and the 14 Build & fix rows that Phases 2 to 6 finish are among them.

By heading, what is left open after this check: Release 3, Check on a device 199, Review choices 76 (77 with the new row), Build & fix 14, Someday 1.

## Method notes

- The area read was one 330k-character reply, queried with `jq`. Positions and revisions from planning were not reused.
- Evidence checked against main: `git grep` for ResourcesView, ClubsProjects, GoingOut, TodosView, ProceduresView, StoriesView (none), ParentReport (one file), `git merge-base --is-ancestor` for ba5c5e15, 4b0d8d555, e3549bb6f, 13df091f against aa27f869c (all ancestors), and `ls /Applications` for the old app folder (none).
- The To-dos screen was cut but Tide sharing was not (11794e745 kept it), so Tide-sharing rows (117, 154) stay open.
