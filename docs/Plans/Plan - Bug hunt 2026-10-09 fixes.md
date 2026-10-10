# Bug hunt 2026-10-09 fixes

> **Done 2026-10-10** (edcfb352). Written 2026-10-09 from the read-only hunt in <../Reviews/Bug hunt 2026-10-09.md> (26 findings over main ce8303c3). Reviewed by an Opus plan reviewer the same day; its eight points are folded in.
> In short: fix all 26 findings in six parallel fix agents over two waves, review the combined change, and land it on main without rolling out.

## Goal

Every finding in the report is fixed, from the two sync-status holes that could share records twice down to the order email's CC parsing. When it's done:
- Share setup and the filing step can't put records into the share a second time.
- The "sync stopped" state holds until the store that stopped recovers.
- Meetings keep Re-present and Ready for Next decisions, and undo them properly.
- MCP check-ins never land twice on one day or reach unrelated work.
- Restock needs keep what the office was asked for, and the request email goes to real addresses.

Everything ends on main, built and tested for iOS, Mac and the Assistant. It is not rolled out (Danny's call). Device checks become Tide rows.

## Progress
Build board: https://claude.ai/artifact/EqECVJ38VbFq3sWJ7gE7VR (Daybook Bug Fixes; milestones m1 Wave 1, m2 Wave 2, m3 Combine and land; task slugs p1/p3a/p5/p2/p3b/p4 for the agents, f1–f26 per finding, c-* for Phase 6).

- [x] Wave 1: Phase 1 ‖ Phase 3a ‖ Phase 5 (session: here, agents in worktrees) · started at 2% weekly, 2026-10-10 00:20 UTC · ended at 5% (actual ~3%)
  - [x] Phase 1: Share setup and sync status (#1–#3) · est. ~3–6% weekly · **done 2026-10-10** `b39eb940`, merged `42cea553`: iOS + Mac clean, 14 suites 108/108. Differed: the pause also covers an account still signing in; `mirroringDelegateFailed` is now derived from `stoppedStores`; Remove Last Year refuses under the pause too.
  - [x] Phase 3a: Meetings decisions (#8–#13) · est. ~4–6% weekly · **done 2026-10-10** `d06ce38c`, merged `55a93503`: iOS + Mac clean, 6 suites 65/65. Differed: any new outcome on a card takes back its earlier close first (one close per card); a group presentation without per-child rows gets her own row for the Re-present; only the Ready for Next button hides at a sequence's end.
  - [x] Phase 5: Restock and the order email (#20–#26) · est. ~3–5% weekly · **done 2026-10-10** `8b4aafe4`, merged `c3f4b610`: both schemes iOS + notebook Mac clean; notebook 12 suites 117/117, Assistant 6 suites 44/44. Differed: the address parser moved to a new Assistant-shared file `Attendance/Email/EmailRecipients.swift` (added to the Assistant target); "We need…" now shows How many for a staple; `webURL` no longer reads `mailto:` text as a website. Link titles not tried against real pages: a device check is in [Tide](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=After%20the%20next%20roll-out%2C%20have%20my%20assistant%20paste%20a%20link%20in%20We%20need%E2%80%A6%2C%20then%20open%20Draft%20Request%20on%20the%20Mac%20and%20check%20the%20item%20shows%20a%20real%20title%20beside%20its%20link).
- [x] Wave 2: Phase 2 ‖ Phase 3b ‖ Phase 4 (session: here; start each as soon as a wave-1 agent finishes)
  - [x] Phase 2: Name list (#4–#7) · est. ~3–5% weekly · started 2026-10-10 00:45 UTC · **done** `f3d20db9`, merged `ed8f90af`: both schemes build; notebook 12 suites 92/92, Assistant 4 suites 35/35 (SE, iOS 26.5); each new notebook test fails with its fix reverted. Differed: on a lookup timeout, writes wait for the next import rather than writing with "no answer" (that would add a second row once a class is pinned); the unknown-account undo applies to both apps.
  - [x] Phase 3b: The Scheduled strip (#14) · est. ~1–2% weekly · started 2026-10-10 00:57 UTC · **done** `259889eb`: iOS + Mac clean, 3 suites 20/20. Growth only at rest, scroll back to the previous leading day without animation, position reports ignored until it lands; the saved start day is written at rest. Not watched scrolling yet: a device check is in [Tide](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=After%20the%20next%20roll-out%2C%20scroll%20the%20Lessons%20%26%20Work%20Scheduled%20strip%20to%20its%20left%20end%20on%20the%20Mac%20and%20my%20iPhone%2C%20and%20check%20it%20holds%20its%20place).
  - [x] Phase 4: MCP check-ins and linked copies (#15–#19) · est. ~2–4% weekly · started 2026-10-10 01:02 UTC · **done** `7e3207b0`: iOS clean, 12 suites 107/107 incl. two `assign_work` calls three weeks apart. #16 callers: status reach, removal plan, delete cleanup and the grid menu now stay within one assignment; `visibleWork` unchanged for normal data; one edge case in `WorkLogService:138` (an old row whose own copies were deleted now logs as one shared row).
- [x] Phase 6: Combine, review, full builds and suites, main (session: here) · est. ~4–6% weekly · started at 7% weekly. The sync + names review ran early (7 real issues, sent back to the Phase 1 and 2 agents). Danny's late-iCloud answer narrowed after that review: the pause-until-reopen stays for no account at all; an account that is signed in but not ready yet pauses only until its store's setup succeeds again (Core Data reruns setup, TN3164). **Done 2026-10-10**, squashed to main as `edcfb352` and pushed (unsquashed history on local branch `bug-hunt-2026-10-09-fixes-unsquashed`). Two Opus reviews found 13 more real issues (sync/names 7 + one follow-up on the waiting name's account; MCP linked copies still joined by a shared presentation; link titles racing the draft; the strip's hold released too early; an undated group Re-present; a meeting open in a second window writing a cleared draft back), all fixed by the agents that wrote the code and re-tested. Main moved twice during the checks (29cdbb8d Assistant wording, 82309223 sample-class fix); both merged cleanly, and two MCP attendance tests were updated for main's "Late" wording. Final, on top of main: notebook iOS + Mac and the Assistant build with no warnings; whole suites notebook 2,853/2,853 and Assistant 273/273. Device checks are five Tide rows, linked from the report. Ended at 13% weekly: the whole plan cost ~11% against an estimate of 20–34% (wave 2 + reviews + Phase 6 ~8%; noisy, a sample-class fix session ran alongside).

## Cost

About 20–34% of the weekly all-models limit on Max, plus ~1–2% spent planning and hunting. 98% is left (2% used at writing) until Fri Oct 16, 1 PM EDT. **Fits.**

The 5-hour window was 6% used at writing (resets 12:40 AM EDT). Three agents at once, two at xhigh, can take most of a window, so the work runs as two waves of three rather than all six together.

Sizes come from the cost log: Core Data and sync fix agents at xhigh came to ~3–4% each on the 10-05/10-06 plans (six of them ~26%), and Opus-high feature agents to 1–3%. Phase 3a is sized up for its token stack and six readers (the reviewer's estimate). Phase 6 includes two Opus reviewers and a fix round.

## Decisions

**Danny's answers (2026-10-09):**
- **Ready for Next at the end of a sequence (#13):** hide the button when the work's lesson has no next lesson. Only Re-present and Keep Working show for that work. Whether there's a next lesson is worked out once per draft (one lesson fetch), not in each card's view body (`MeetingDraftModel.swift:358` fetches every lesson).
- **iCloud not ready at launch (#2, second trigger):** pause filing into the share and say so plainly in the sync status: "iCloud wasn't ready when the notebook opened. Quit and reopen it to finish sharing." No automatic stack rebuild in the notebook.
- **Roll-out:** none in this plan. It stays on main; Danny rolls out when he can update every device together.

**Sharing (Phase 1):**
- **#1 resumed setup.** After `setupPreflight` returns a pinned share (`Setup.swift:55-57`): if this device has never seen that zone (`pinSeenKey` differs), go through `forgetWhatSetupElsewhereTook` first, which stamps `pinSeenAt`. Then refuse while `waitingForImportAfterPin` is true, with "This device is still downloading the class from iCloud. Try again in a few minutes." `resumePin` stops calling `notePinMadeHere`; only `createPinnedShare` (a pin truly made here) does. (A1, A2)
- **#2 the store behind a failed attach.** The attach reports which store it ran against (the guide's attaches use the private store, `.notebook`). The outside setter of `mirroringDelegateFailed` takes that store instead of assuming `.classroomShare` (A4). Update the "deliberately one flag" comment at `CloudKitSyncStatusService.swift:75`.
- **#2 an account-less setup.** Danny's pause is its own flag, set by a setup event that failed for want of an account and kept for the life of the process. `resetForNewAccount` doesn't clear it (`+StoreHealth.swift:88` clears `mirroringDelegateFailed`, which is why it can't be that flag). Every attach path checks it: `ClassroomSharingService+Setup.swift:135`, `ClassroomAttendanceCatchUp.swift:102`, `ClassroomShareRelease+Live.swift:70` and the guard (`SharedStoreOrphanGuard.swift:179`).
- **#3 older builds' pins.** Nothing on the device records that the pin was made here (`CDClassroomMembership` has no device field, and the Mac and iPad share one owner). So when `pinSeenKey` is missing, record the zone and stamp `pinSeenAt`, meaning wait for an import, and forget nothing. The worst case is a short wait on the pin's own device.

**Name list (Phase 2):**
- **#4.** Start `Arrival` at `AppCore/AppBootstrapping+ErrorHandling.swift:22`, beside `beginEarlyEventCapture`, so it's listening before the launch import. `configure` empties the early-event buffer and nothing else reads it, so seeding from it isn't an option.
- **#7 the stuck lookup.** `recordIDs(for:)` is synchronous and runs on a pool thread (`ClassroomNames+Zones.swift:232-239`). Put a time limit (30 s) on waiting for it (A3, A5). On timeout every row reads "no answer", which the fold already keeps, and the gate is released. While a timed-out call is still out, new lookups get "no answer" at once rather than blocking a second pool thread. Its late result is ignored.

**Meetings (Phase 3a):**
- **#9 / #10 undo.** Save each close's `WorkLogService` receipt token with the draft (`MeetingPersistenceService`'s data, as a new optional field so older drafts load). Object IDs go as URIs; the snapshots are plain values. Each work keeps a stack of tokens, undone newest first, because switching Re-present straight to Ready runs `decide` again (`MeetingDraftModel.swift:202`).
  - Before undoing, check the work is still as the meeting left it (same closed status, not modified since the token). `WorkLogService.undo` itself only checks that the rows exist (`WorkLogService+Undo.swift:88`) and would overwrite a later change.
  - When it isn't, leave it alone and say "<Lesson> was changed after the meeting, so it was left as it is." When the token is unreadable, reopen through `WorkLogService` as today.
  - The undo removes the completion record the close wrote (its `createdObjectIDs`), which the plain reopen (`WorkLogService.swift:168`) doesn't.
- **#8 the student's Meetings tab.** The tab has no `MeetingDraftModel`, so the undo and filing logic moves into a helper both use, working from the stored draft (its tokens included).
  - Clear undoes the closes, like the workflow's Clear.
  - Save to History files the two lists the way Complete does: re-present her lessons and plan the next ones. It does not do the rest of `complete()`: it doesn't clear the meeting booking or save reviews, so the tab behaves as before apart from the two lists.
- **#12 Re-present for one child.** `PresentationFollowUpService.resolve` does nothing when her row has no follow-up (`PresentationFollowUpService.swift:52`), so the meeting sets her own `CDLessonPresentation` follow-up to re-present explicitly, not only resolve one.
  - Add one accessor, "needs another presentation for this child": her own row says re-present, or the shared flag is set.
  - The shared flag is set only when the presentation has her alone. The presentation review keeps setting it for the group (`CaptureFollowUpPersistence.swift:54`): there the guide decides for everyone at once.
  - Per-child readers use the accessor: `StudentReadinessAssessor.swift:185`, `CurriculumDataAssembler.swift:191`, `ChatContextAssembler.swift:167` and `WorkDetailView+CompletionSection.swift:187`.
  - Group views (`LessonAssignmentDetailSheet.swift:299`, `SequenceRecapBlocks.swift:258`) show the shared flag as now, and also any child flagged on her own row.
  - No schema change.

**MCP (Phase 4):**
- **#16 linked copies.** Linked copies have different owners, each naming the other (`WorkGrouping.swift:193-196`). Add one condition: the two rows share a presentation, or neither has one and they were created within 60 seconds of each other.
  - If either `createdAt` is missing, today's rule applies, so older group work keeps working.
  - Callers whose behavior changes, and which need tests or a check: `WorkLogService.swift:138,286`, `WorkDeletionService.swift:157,287`, `visibleWork` (`StudentDetailViewModel.swift:150`, `MCPNotebookTools+Work.swift:155`) and `WorkCard+GridMenu.swift:203`.

**Restock (Phase 5):**
- **#20 merging needs:** when either copy has been asked for, keep its quantity, notes, title and link along with the request fields. The rule stays one every device applies the same way.
- **#22 link titles:** fill missing titles on the notebook, with the title fetch `RestockNeedSheet.swift:217` already uses (A8), when Restock appears and when the request draft opens. The Assistant doesn't fetch.
- **#23 link field:** pull the first http(s) link out of pasted text; if there isn't one, refuse with the inline note `StapleEditSheet` uses. Only http and https links open.
- **#24 addresses:** split on commas, semicolons and whitespace; keep only address-shaped entries; Settings says in a plain line which entries were dropped. The parser is shared with the attendance email, which gets the same behavior.
- **#25 mail:** iOS checks the open's result (A7), not `canOpenURL` (deprecated in 27).

**The Scheduled strip (Phase 3b):**
- **#14:** don't rely on SwiftUI keeping the position when days are added in front. Apple promises nothing for inserts (A6). After adding days, scroll to the previous leading day's id explicitly, without animation, and add days only when scrolling settles. The device check stays in Tide.

**Shared files between agents:** no source file is edited by two phases (checked by the reviewer). The soft spots are the wording catalogs (`SettingsCopy.swift`, `AppErrorMessages.swift`), which Phases 1, 2 and 5 may all touch, and `project.pbxproj`, where Assistant-shared files are listed by path. Agents add new strings at the end of the relevant section, add code to existing files where they reasonably can, and name any new file in an Assistant-shared group in their reply. Phase 6 resolves the merges.

**Ruled out:**
- A schema field for per-child re-present (#12): the per-child follow-up row already exists.
- Rebuilding the notebook's stack after a late iCloud account (#2): Danny chose pause and reopen.
- Guessing which todos and check-ins a close touched (#9): saving the token is exact; guessing could reopen a todo the guide finished by hand.
- Fixing #14 only after a device check: the explicit scroll is safe either way.

## Apple guidance

Checked 2026-10-09 against Xcode 27.0 (27A266a, Swift 6.4, iOS/macOS 27.0 SDKs). Xcode 27.1 RC and 27.2 beta 2 exist; their release notes change none of these topics, so there's no need to update first. Most doc pages were last modified Aug 14, 2026.

- **A1. What `fetchShares` knows.** `fetchShares(in:)` and `fetchShares(matching:)` read only the shares already mirrored on the device. The header says it "does not do any network work", and the matching form leaves out objects not yet exported. So a half-downloaded device can't tell already-shared records from unshared ones, which is #1's premise. ([doc](https://developer.apple.com/documentation/coredata/nspersistentcloudkitcontainer/fetchsharesinpersistentstore:error:))
- **A2. `share(_:to:)` on an already-shared object.** The call fails if any object, or anything reached by its relationships, is already shared, and also with no iCloud account or a failed container setup. No error codes are documented. Its completion means the share exists, not that the objects were exported. ([doc](https://developer.apple.com/documentation/coredata/nspersistentcloudkitcontainer/sharemanagedobjects:toshare:completion:))
- **A3. `recordIDs(for:)` has no documented threading or time limit.** Nothing is said about blocking, timeouts or cancellation, so #7 treats it as able to hang.
- **A4. Events.** `Event.storeIdentifier` is always present, which is how #2 names the store. 27.0 adds `EventChangedMessage`, posted on CloudKit's private queue, but the Assistant (iOS 18) keeps the Notification. Apple documents no recovery after a failed setup (no account at launch), which supports Danny's pause-and-reopen.
- **A5. Timeouts (#7).** The standard library has no timeout API (a `withTimeout` pitch isn't shipped). A task group waits for every child, cancelled or not, so it can't walk away from a call that won't return. Use a checked continuation inside `withTaskCancellationHandler`, with a resume-once guard and a sleeping task that resumes it with a timeout. The late result is ignored. ([TaskGroup](https://developer.apple.com/documentation/swift/withthrowingtaskgroup(of:returning:isolation:body:)), [CheckedContinuation](https://developer.apple.com/documentation/swift/checkedcontinuation))
- **A6. Scroll position (#14).** `ScrollPosition`, `scrollPosition(_:anchor:)` and `defaultScrollAnchor(_:for:)` (roles `initialOffset`, `sizeChanges`, `alignment`) are iOS 18 / macOS 15, so they're usable everywhere here. Apple promises to keep the identified view visible on reorder, resize and first layout, but says nothing about inserting items in front. WWDC26 session 321 calls absolute offsets "estimated and unstable" and recommends `scrollTo(id:)`. So after prepending, scroll to the previous leading day's id explicitly, without animation. Device check stays. ([ScrollPosition](https://developer.apple.com/documentation/swiftui/scrollposition), [WWDC26 321](https://developer.apple.com/videos/play/wwdc2026/321/))
- **A7. Opening a `mailto:` link (#25).** `canOpenURL` is deprecated in iOS 27: "attempt to open URLs and handle any failures". On iOS use `UIApplication.open(_:options:) async -> Bool` or SwiftUI `OpenURLAction` with its accepted-Bool completion; `false` means nothing handled it. On macOS use `NSWorkspace.open(_:configuration:)`, which reports an error. Show the composer only when `MFMailComposeViewController.canSendMail()` is true (iOS only). ([open](https://developer.apple.com/documentation/uikit/uiapplication/open(_:options:completionhandler:)), [canOpenURL](https://developer.apple.com/documentation/uikit/uiapplication/canopenurl(_:)))
- **A8. Link titles (#22).** `LPMetadataProvider` has only completion handlers: one fetch per instance, the completion on a background queue, a 30-second default timeout, and the Mac needs the network-client entitlement. Reuse whatever `RestockNeedSheet` already does rather than adding a second fetcher.

## Phase 1: Share setup and sync status (#1, #2, #3)
- Who: `feature-phase-deep` (Opus, xhigh). The sharing code behind the 2026-09-28 incident; a subtle mistake stops sync.
- Steps (per Decisions › Sharing):
  - `Cosmic Daybook/Sharing/ClassroomSharingService+Setup.swift`: the resumed-setup path (#1, A1, A2) and the pause check at `:135`.
  - `Cosmic Daybook/Sharing/SharedStoreOrphanGuard+WaitingList.swift`: `notePinMadeHere` only for a pin made here; a missing `pinSeenKey` waits for an import and forgets nothing (#3).
  - `Cosmic Daybook/Services/Sync/CloudKitSyncStatusService.swift`, `+StoreHealth.swift`: the outside setter takes a store (A4); the account-less pause flag, which `resetForNewAccount` leaves alone; the reopen message in the sync status.
  - The attach callers pass the store they used, and check the pause: `SharedStoreOrphanGuard.swift:179,281`, `ClassroomAttendanceCatchUp.swift:102`, `ClassroomShareRelease+Live.swift:70`.
  - Tests:
    - a resumed setup on an unseen zone stamps `pinSeenAt` and is refused;
    - `resumePin` doesn't clear `pinSeenAt`;
    - the stopped flag survives the other store's success and clears on its own store's;
    - the pause survives `resetForNewAccount`, and every attach path stops under it;
    - a missing `pinSeenKey` forgets nothing.
- Don't touch: `ClassroomNames*`, `AppBootstrapping+ErrorHandling.swift` (Phase 2), the Assistant's Leave.
- Cost: ~3–6% (sync at xhigh; notebook target only).
- Done when: `Cosmic Daybook` builds for iOS Simulator and macOS; `-only-testing:` the share-setup, orphan-guard, attendance catch-up, share-release and sync-status suites pass (named in the reply). Nothing for Danny to see.
- Hand off: no (agent in a worktree; the main session merges).

## Phase 2: Name list (#4, #5, #6, #7)
- Who: `feature-phase-deep` (Opus, xhigh). Concurrency in the off-main zone lookup, where the freeze fix needed a second round for six races.
- Steps (per Decisions › Name list):
  - `Cosmic Daybook/AppCore/AppBootstrapping+ErrorHandling.swift:22` and `Sharing/ClassroomNames+Arrival.swift`: start `Arrival` beside `beginEarlyEventCapture` (#4). Don't edit `CloudKitSyncStatusService*` (Phase 1).
  - `ClassroomNames+Arrival.swift:109-121`: at most one queued warm-up, and only when the import brought `ClassroomPerson` rows (#6).
  - `ClassroomNames.swift:115-124`, `ClassroomNames+Zones.swift:319-323`: undo the waiting mark whenever the record name isn't `me`, including when it's unknown; drop a waiting name on an account change, as the Assistant's `forgetForNewAccount` does; Settings' `setName` reports "not saved" on `.nothing` (#5).
  - `ClassroomNames+Zones.swift:232-297`: the time limit and the one-call cap (#7, A3, A5).
  - Tests for each, including: a lookup that never returns (the gate is released, a second lookup gets "no answer" without blocking), and an account change during a save.
- Cost: ~3–5%.
- Done when: both schemes build for iOS Simulator (`ClassroomNames*` is in the Assistant too); `-only-testing:` the ClassroomNames suites in the notebook and the Assistant pass. Nothing for Danny to see.
- Hand off: no.

## Phase 3a: Meetings decisions (#8–#13)
- Who: `feature-phase-deep` (Opus, xhigh). Undo tokens saved with a draft, a shared filing helper, and six readers; mistakes here close or reopen the wrong work.
- Steps (per Decisions › Meetings):
  - `Cosmic Daybook/Students/Meetings/Workflow/MeetingDraftModel.swift`: token stack and checked undo (#9, #10); skip planning a next lesson she already has, given or mastered (#11); her own follow-up for Re-present (#12); has-next-lesson worked out once per draft, Ready for Next hidden when there isn't one (#13, in the view that draws the work card's buttons).
  - The stored draft type behind `MeetingPersistenceService` gains the token field (optional).
  - A helper both the workflow and `Students/Meetings/Tab/StudentMeetingsTab.swift:303,426` use for Clear and Save to History (#8).
  - The "needs another presentation for this child" accessor and its six readers (#12).
  - Tests:
    - each of #8–#13;
    - undo after reopening the app (the token read back from the stored draft);
    - Re-present → Ready → Clear;
    - work changed after the meeting is left alone;
    - a group presentation where one child is re-presented.
- Don't touch: `WorkGrouping.swift` (Phase 4), the Scheduled strip (Phase 3b).
- Cost: ~4–6%.
- Done when: `Cosmic Daybook` builds for iOS Simulator and macOS; `-only-testing:` the meeting draft, meeting persistence, WorkLogService, readiness and presentation follow-up suites pass. Device checks for Danny, as a Tide row: run one meeting with Re-present, then Clear; one with Ready for Next, then Complete.
- Hand off: no.

## Phase 3b: The Scheduled strip (#14)
- Who: `feature-phase` (Opus, high). One SwiftUI scroll fix on both platforms.
- Steps: `Cosmic Daybook/Presentations/Planning/WeekPlanSection+Data.swift:60-87` and the strip view: after adding days in front, scroll to the previous leading day's id without animation; add days only when scrolling settles (A6). A test that growth keeps the leading day and never adds twice for one scroll.
- Cost: ~1–2%.
- Done when: `Cosmic Daybook` builds for iOS Simulator and macOS; `-only-testing:` the week-plan suites pass. Device check for Danny, as a Tide row: scroll the strip to its left end on the Mac and the iPhone.
- Hand off: no.

## Phase 4: MCP check-ins and linked copies (#15–#19)
- Who: `feature-phase` (Opus, high). Small, but #16 changes which work counts as one group everywhere.
- Steps:
  - `Cosmic Daybook/Services/MCPServer/MCPNotebookTools+WorkCheckIns.swift`:
    - refuse a move onto a day that already has a check-in; leave a linked copy where it is and say so (#15);
    - run the closed-work check after the call's own status (#17, with `+WorkWrites.swift:328-330`);
    - `markNothingWritten()` when nothing changed (#18);
    - skip copies whose owner isn't enrolled and name them in the reply (#19).
  - `Cosmic Daybook/Work/Support/WorkGrouping.swift:157-205`: the rule per Decisions › MCP (#16). The reply lists each caller and whether its behavior changed.
  - Tests for each, including two `assign_work` calls weeks apart: a check-in, a status change and a delete each reach only the right rows.
- Cost: ~2–4% (the reviewer widened its test reach).
- Done when: `Cosmic Daybook` builds for iOS Simulator; `-only-testing:` the MCP work-write, check-in, WorkGrouping, WorkLogService, WorkDeletion and student-detail suites pass.
- Hand off: no.

## Phase 5: Restock and the order email (#20–#26)
- Who: `feature-phase` (Opus, high). Both apps; #20 is a dedup rule in shared records, so careful but small.
- Steps (per Decisions › Restock):
  - `Cosmic Daybook/Supplies/Services/RestockService+Needs.swift:277-283`: the merge keeps the asked-for copy's fields (#20).
  - `Daybook Assistant/Restock/AssistantRestockModel.swift:315-330`: the chosen quantity on a staple's open need while it hasn't been asked for (#21).
  - The notebook fills titles for untitled needs when Restock appears and when the draft opens (#22, A8).
  - `Cosmic Daybook/Orders/Services/OrderService.swift:151-152` and `OrderItemEditSheet`: the first web link, or an inline refusal; only http(s) opens (#23).
  - `Cosmic Daybook/Attendance/Email/AttendanceEmailReport.swift:268-275`: the parser, plus the plain Settings line (#24).
  - `Cosmic Daybook/Orders/Views/OrderRequestDraftSheet.swift:302-315`: check whether the mail link opened (#25, A7).
  - `Daybook Assistant/Restock/AssistantOfficeRunView.swift` and the "We need…" sheet: show save errors there; keep the sheet open when its save fails (#26).
  - Tests:
    - the merge keeps the request's quantity;
    - the Assistant's chosen quantity;
    - link extraction;
    - address parsing, shared with the attendance email's tests.
- Cost: ~3–5%.
- Done when: both schemes build for iOS Simulator and `Cosmic Daybook` for macOS (the email paths differ). `-only-testing:` passes for the notebook's Restock, Orders, order-request and attendance-email suites and the Assistant's Restock suites. Device check for Danny, as a Tide row: on an iPhone with no Mail account, Send shows the copy-instead message.
- Hand off: no.

## Phase 6: Combine, review, builds, main
- Who: main session (Opus 5.5) plus two `Plan` reviewers (Opus): one over Phases 1–2 (sync and names), one over Phases 3a–5.
- Steps:
  1. Merge each agent's branch into `claude/bug-hunt-a68784` (agents' worktrees start at pushed main ce8303c3). Resolve the wording-catalog and project-file conflicts.
  2. Run the two reviewers in parallel on the combined diff. Fix what holds up, via the agent (SendMessage) or here when small.
  3. Full builds: `Cosmic Daybook` for iOS Simulator and macOS, `Daybook Assistant` for iOS Simulator.
  4. Run each whole suite once (notebook, Assistant) on the leased simulator with `-parallel-testing-enabled NO` (one simulator each), then `sim-lease --done`.
  5. Squash onto main and push. If the main checkout is on another branch, land with `update-ref` (memory: merge-when-checkout-shared).
  6. Then docs, as a separate commit on main:
     - the report marks each finding "Fixed in <squash commit>";
     - `docs/Technical notes/` records the changed invariants (sync stopped per store plus the account-less pause; the linked-copy rule; meeting undo tokens);
     - this plan's status line;
     - `docs-index`.
  7. Add Tide rows under Cosmic Daybook's To do.md › Check on a device: the strip, the two meeting flows, the iPhone no-Mail send, and share setup on a second device after the update. Link them from the report.
- Cost: ~4–6%.
- Done when: all three builds are clean; both whole suites pass (counts in the Progress line); main contains the squash and is pushed; the Tide rows exist and the report links them.
- Hand off: no.

## Starting a phase
Read the plan usage (`get_usage`) and note the weekly % used next to the phase under Progress ("started at N%").

## Ending a phase
1. Check every "Done when" item for the phase.
2. Tick the phase under Progress and note anything that differed from the plan. Read the plan usage again and note the actual cost (end % minus start %).
3. Add a row to the log in `~/.claude/skills/plan-efficiently/references/cost-estimates.md`.
4. Update the build board, if the plan lists one.
5. Make every "not verified", "for your review" or "check on a device" item from this phase a row in the app's list in Tide (`Areas/App Development/Cosmic Daybook/To do.md`, `add_action`), skipping ones already there. Tide holds the row; the repo line keeps one plain sentence plus the row's `tide://` link.
6. Run /close-out. It sets the plan's status line (`> **Working on it.**` after a phase, `> **Done <date>** (<commit>).` after the last, checked against main) and runs `docs-index` so the map follows.
7. Every phase here runs from this session, so there's no starter prompt to print. If the session ends early, the next one starts with: "Model: Opus 5.5, effort: high. In Maria's Notebook, read docs/Plans/Plan - Bug hunt 2026-10-09 fixes.md and carry on from the first unticked phase. Follow its Starting a phase and Ending a phase steps."

## Agent prompts (what each fix agent gets)
- The plan's path, its phase section and the Decisions it cites, plus the report <../Reviews/Bug hunt 2026-10-09.md> for the finding details. Nothing is pasted in.
- `isolation: worktree`, branching from pushed main.
  - Build once before editing (the agent-worktree recipe in Cosmic Daybook/CLAUDE.md).
  - Builds go through `Scripts/locked_xcodebuild.sh`.
  - Tests run on `$(~/.claude/bin/sim-lease)` with `-parallel-testing-enabled NO`; `sim-lease --done` before replying.
  - Never the whole suite.
- Commit on its branch with the attribution line; don't merge or push.
- Reply in at most 15 lines: what changed (files), build and test results with counts, anything unresolved or decided differently from the plan. No narrative.

## Open questions
None.
