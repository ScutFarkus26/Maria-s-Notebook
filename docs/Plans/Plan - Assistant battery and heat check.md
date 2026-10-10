# Assistant battery and heat check

> **Working on it.** Written 2026-10-07. An assistant's iPhone battery died during the school day; Danny wants to be sure the Daybook Assistant isn't the cause.
> In short: Audit and measure the Daybook Assistant for battery, memory and heat, report what it costs while open and while closed, then fix the items Danny picks.

## Goal

Danny gets a plain answer to "could the Assistant have drained her battery?", backed by measurements and a read of the code. The answer covers what the app does on screen all day and what it does while closed (cloud wake-ups, reminders, Siri). He also gets a ranked list of fixes, each marked as a safe change (same behavior, cheaper) or a behavior change that needs his call. Nothing in the app changes until he picks from that list. The picked fixes land in a later session, with before and after numbers.

## Progress
- [ ] Phase 1: Audit and measure (session: here) · est. ~3–4% weekly · started at 14%
- [ ] Phase 2: Fix what Danny picks (session: fresh, once Danny has picked) · est. ~3–6% weekly (sized once he picks)
- [ ] Phase 3: Combine, full check, re-measure (session: same as Phase 2) · est. ~1–2% weekly

## Cost

About 7–12% of the weekly limit in total (Max plan). Rechecked 2026-10-10: 14% used, resets Fri 16 Oct at 1 pm. Everything fits this week. (When the plan was written on 2026-10-07, 93% was used, so Phases 2–3 were held for the 9 Oct reset. That reset has passed.)

## Decisions

- **Audit first, fixes after Danny picks** (Danny, 2026-10-07). The plan first waited for the 9 Oct weekly reset; that reset has passed.
- **Report only; Danny picks** (Danny). Phase 1 changes no app code. Even safe changes wait for his choice.
- **Simulator only** (Danny). The numbers come from Sample Class on a leased simulator: CPU while idle, idle wake-ups, memory footprint, body redraws and SQL fetches. A simulator can't show real heat or radio cost. The report says so and doesn't present simulator numbers as battery numbers.
- **The cheapest real-world evidence is her phone's own battery screen.** It's free and decisive: Settings › Battery › Last 24 Hours (or 10 Days), sorted by app, shows the Assistant's share and splits it into on-screen and background time. Danny asks her for a screenshot. It isn't a phase, it's a row in Tide. If the screenshot shows the Assistant using a small share, the report says the drain was probably something else, and the fixes become routine upkeep rather than urgent.
- **The focus is what runs while the app is closed.** The Assistant has `UIBackgroundModes` = `remote-notification` and mirrors two stores through `NSPersistentCloudKitContainer`: the classroom share, plus its own private database (the 2026-09-29 pass left that second one alone; see the efficiency-pass codebase map). Every change Danny makes in the notebook can push a silent wake to her phone, and each wake can rebuild state, reload views or schedule reminders. Hunter A owns this area and runs on Opus.
- **Measure a Release build opened through "Try a Sample Class", not `-AssistantSampleClass`.** That launch flag is Debug-only, and it returns from `AssistantBootstrapper.start()` (`AssistantBootstrapper.swift:102-110`) before the remote-change, account, mirroring and history-upkeep observers start. It also leaves out the reminder upkeep (`EarlyPickupReminderUpkeep.swift:53`). Measuring with it would skip the paths this check is about. The join screen's button sets `AssistantSampleClass.isChosen` and takes the full start path, in Release too. Caveat for the report: the simulator has no iCloud account, so no real pushes arrive there.
- **Ask for her battery screenshot first.** The Tide row is added as soon as the plan is approved, not at the end of Phase 1.
- **The report is a numbered markdown file.** Danny picks fixes by number from it. It isn't the private artifact that `audit-and-waves.md` describes, to save tokens this week; one can be published later if he wants to read it on his phone.
- **Three hunters by area, not by file count.** A: background and sync. B: on screen all day. C: launch, memory and shared code. They're read-only, so they need no worktrees. The main session re-reads the top findings before anything goes in the report. Sonnet runs B and C because view and memory patterns are well covered by `audit_hotspots.py` and its rules, and the lead re-checks their findings anyway.
- **Ruled out:** an on-device Power Profiler run (Danny chose simulator only), a full `verify.sh` in Phase 1 (no code changes), and Xcode Organizer energy reports (too few TestFlight users to have data; the verifier confirms below).
- **Last pass to start from:** the 2026-09-29 Assistant pass (`docs/Technical notes/Performance baselines/2026-09-29-assistant-grid-redraws.md`, codebase map › Daybook Assistant). Since then, 39 commits touched `Daybook Assistant/`: onboarding, early-pickup and arrival reminders, wallpaper, restock, Siri, front desk, history trim, the name-list off-main lookups and the sync fixes.
- **Rechecked 2026-10-10 against main 05826331** (11 commits after this plan was written). Three touch the Assistant: plain-English wording, the sample class opening fresh on a new day, and the 10-09 bug-hunt fixes. The shared sync-status code also changed: store health and account readiness. Every file and line this plan cites still says the same thing: the `-AssistantSampleClass` early return, the observers, the reminder upkeep under `SiriSyncKeepAlive`, and `UnsentChangesKeepAlive`. The new sync-status code falls in Hunter A's `Services/Sync` area. Before Phase 1, bring this worktree up to main.

## Apple guidance

Checked 2026-10-07 against Xcode 27.0 (27A266a, iOS 27.0 SDK) by an sdk-verifier pass. Xcode 27.1 RC and 27.2 beta 2 exist; nothing in their notes changes this plan, so there's no need to update Xcode first.

- **CloudKit pushes** ([Syncing a Core Data store with CloudKit](https://developer.apple.com/documentation/coredata/syncing-a-core-data-store-with-cloudkit), 14 Aug 2026; [Pushing background updates](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app); [WWDC25-227](https://developer.apple.com/videos/play/wwdc2025/227/)):
  - CloudKit wakes the app in the background through `remote-notification`, and Core Data imports. Pushes are low priority and coalesced. Each wake gets 30 s. A force-quit app gets none.
  - "Apps that use significant amounts of power when processing remote notifications may not always be woken up early."
  - Apple publishes no per-hour rate for CloudKit's own pushes.
  - Two mirrored stores mean two database subscriptions, and so possibly two imports per notebook change. That's an inference Hunter A checks; Apple doesn't say.
- **Cheap remote-change handling** ([Consuming relevant store changes](https://developer.apple.com/documentation/coredata/consuming-relevant-store-changes); `NSPersistentStoreCoordinator.h`):
  - The remote-change notification fires "for every write to the store", including other processes.
  - Keep the handler to a history-token check and an entity filter, on a background context.
  - It's "unnecessary to update your UI in response to every notification."
  - Purge history only once every client has consumed it.
  - Hunters A and C judge the Assistant's observers against this.
- **Real-phone evidence** ([iOS 27 battery guide](https://support.apple.com/guide/iphone/understand-iphone-battery-usage-health-iphd453d043a/27.0/ios/27.0)): Settings › Battery › View All Battery Usage › a day lists each app's On screen and Background use, and how often notifications woke the device. iOS 18 shows only screen on/off graphs and usage by app, with no Background line. Danny should ask which iOS her phone runs.
- **Organizer and MetricKit:** Xcode Organizer battery reports cover App Store apps and show "Insufficient usage data" for small audiences, so expect nothing for the Assistant. `MetricManager` is iOS 27+ only, since the old MetricKit API is "to be deprecated". Neither is used here.
- **Power Profiler** ([Measuring your app's power use](https://developer.apple.com/documentation/xcode/measuring-your-app-s-power-use-with-power-profiler), 14 Aug 2026; [WWDC25-226](https://developer.apple.com/videos/play/wwdc2025/226/)):
  - Works untethered on iOS 26+ through Settings › Developer › Performance Trace, and can trace TestFlight installs for up to 10 hours.
  - It needs Developer Mode, which only appears on a phone that has been paired with a Mac once.
  - The iOS 27 notes list a Control Center trace widget that may fail.
  - Not used now (Danny chose simulator only), but it's the follow-up if the screenshot points at the Assistant. It would run on Danny's own phone, not hers.
- **Simulator numbers:** `top -stats pid,cpu,idlew,power` works for the simulator app's process. Those numbers are Mac-side: good for comparing the app's own timers and wake-ups, silent on radio, display and pushes. Xcode 27.2 b2 notes that Simulate Memory Warning doesn't work.
- **TimelineView:** Apple gives no energy guidance for `.everyMinute` or `.periodic` (iOS 15+). The rule is to keep the closure small and avoid needless body updates ([WWDC25-306](https://developer.apple.com/videos/play/wwdc2025/306/)).
- **Wallpaper:** `AssistantWallpaperPhoto.prepare` already downsamples with `CGImageSourceCreateThumbnailAtIndex` and a max pixel size, as Apple advises. `loadTransferable(type: Data.self)` still loads the full original once while importing, and Apple documents no smaller PhotosPicker representation.
- **App Intents** ([Creating your first app intent](https://developer.apple.com/documentation/appintents/creating-your-first-app-intent), 11 Sep 2026): with no extension target, every Siri intent runs in the Assistant's process. Apple says intents should be "lightweight wrappers". Whether the Core Data stack gets built depends on the app's own start-up, which Hunter A checks. Running intents in an extension needs iOS 27+, so it can't be the only path at the iOS 18 target.
- **`apple-guidance.md` is partly stale.** Phase 3 adds the Developer Mode pairing need, TestFlight tracing, Organizer being App Store only, the shared-store push cost, and the MetricKit wording.

## Phase 1: Audit and measure

- Who: main session (Opus 5.5, high), plus three read-only `general-purpose` hunters launched together in the background:
  - **A, background and sync** (Opus; a subtle mistake here is the likeliest battery cause). It owns `Daybook Assistant/Sync/*` except `AssistantSyncStatusView.swift`, plus `AssistantApp.swift`, `Reminders/*` and `Siri/*`. From the shared code it owns the persistence, sync, sharing and Siri files: `Cosmic Daybook/AppCore/Persistence`, `Services/Sync`, the sharing files, `Siri/*` including `SiriSyncKeepAlive.swift`, `UnsentChangesKeepAlive.swift` and `ShareAcceptanceAppDelegate`. It answers:
    - What runs on each silent push and each `NSPersistentStoreRemoteChange` from either store while the app is in the background. That includes the reminder upkeep under a background task (`AssistantBootstrapper+Observers.swift:25`, `EarlyPickupReminderUpkeep.swift:31-36`) and `followLeaveElsewhere`.
    - Background-task seconds per wake.
    - Whether the Assistant's own saves or exports post that same notification (a loop), and whether anything it writes in the background can bounce back and forth with the notebook.
    - How long the keep-alives (`SiriSyncKeepAlive`, `UnsentChangesKeepAlive.limit` = 25 s) hold the app awake after it leaves the screen.
    - What the second private-database mirror does.
    - What each Siri intent costs (does it build the whole stack?).
    - When the history trim runs.
    - A static count of how often the notebook writes to the shared zone in a normal school day. That code lives in the notebook only, so A reads it there and multiplies to wakes per day × cost per wake.
  - **B, on screen all day** (Sonnet): `Attendance/*`, `FrontDesk/*`, `Restock/*`, `Wallpaper/*`, `AssistantTabs.swift`, `AssistantRootView.swift`, `AssistantToastService.swift`, `AssistantSyncStatusView.swift`. It covers `TimelineView` cadence (everyMinute ×2, periodic 300 s and 60 s), `onReceive` reloads, full-size wallpaper decode (`UIImage(data:)` / `contentsOfFile`), animations, and redraw fan-out per change.
  - **C, launch, memory and the rest of the shared code** (Sonnet): `AssistantStack.swift`, the `AssistantBootstrapper*.swift` files (for launch and memory only; A owns what they do on wakes), `Onboarding/*`, `AssistantSampleClass.swift`, and the shared `Cosmic Daybook/` files in the Assistant target that A doesn't own (about 105 shared files in all; list them from `Cosmic Daybook.xcodeproj/project.pbxproj`). It covers whole-table fetches, unbounded caches, singletons that keep large graphs alive, and work done at launch that could wait.
  - Each hunter first reads `.claude/skills/efficiency-pass/references/codebase-map.md` (what's already fixed and verified) and `apple-guidance.md`. It runs `python3 .claude/skills/efficiency-pass/scripts/audit_hotspots.py --root "Daybook Assistant"` (the script defaults to `Cosmic Daybook`), plus a second run on `Cosmic Daybook` filtered to its shared files. It replies in at most 25 lines: findings ranked by likely battery or memory cost, each with file:line, what triggers it, how often, the estimated cost, and **safe** (same behavior) or **behavior** (Danny's call).
- Steps (main session, while the hunters run):
  1. Build the `Daybook Assistant` scheme in **Release** for the leased simulator through `Scripts/locked_xcodebuild.sh` (in the background; let the queue wait). Lease with `~/.claude/bin/sim-lease`; it boots 1 simulator.
  2. Launch with no flags and tap "Try a Sample Class" on the join screen, which takes the full start path. Then measure on the attendance screen, idle in the foreground:
     - CPU % and idle wake-ups over 60 s: `top -l 2 -s 60 -pid <sim app pid> -stats pid,cpu,idlew,power`.
     - Memory footprint: `footprint <pid>` or `vmmap --summary`.
     - Footprint again after setting a wallpaper photo, and again after three tab trips.
  3. **While closed:** send the app to the background (`simctl launch <udid> com.apple.Preferences`) and run the same 60 s `top`. The check is that CPU and wake-ups fall to about 0 once the keep-alive and background-task windows end. Record how many seconds that takes.
  4. Count the work per change. Launch with `-com.apple.CoreData.SQLDebug 1` and count SELECTs for one mark, one return to the app (the 2026-09-29 recipe), and one simulated remote change if Sample Class can produce one. If it can't, the report counts statically and says so.
  5. Lead verification: re-read the top findings from all three hunters and drop or downgrade anything that doesn't hold.
  6. Write `docs/Reviews/Assistant battery and heat check 2026-10-07.md`. It opens with a plain-English verdict on whether the Assistant could have drained her battery, and what would show it. Then comes a **While closed** section: the cost per wake, the estimated wakes per school day, and how long the app stays awake after leaving the screen. After it come the on-screen measurements, then the numbered findings with **safe** or **behavior** on each and a rough size, then what was checked and found fine.
  7. Record the numbers in `docs/Technical notes/Performance baselines/2026-10-07-assistant-idle-baseline.md`.
  8. Shut the simulator down: `~/.claude/bin/sim-lease --done`.
- Cost: ~3–4% (one Opus hunter ~0.7%, two Sonnet hunters ~0.3% each, the sdk-verifier ~0.3%, one Assistant build, simulator measurements ~1–1.5%, report and lead re-reads ~0.5%; sized from the Kalends speed-pass Phase 1 at ~2% and the Tide bug hunt at ~7% for nine Opus hunters over 30k lines).
- Done when: the report and the baseline file exist and are committed. Every finding has file:line, the safe or behavior label and a size. Every number says how it was taken, and nothing from the simulator is presented as a battery figure. The report has a While closed section with a cost per wake and an estimate of wakes per day; without it a missed background cause would still pass. The simulator is shut down. (The battery-screenshot row went into Tide at approval.)
- Hand off: yes. Phase 2 needs Danny's picks.

## Phase 2: Fix what Danny picks

- Who: decided once Danny has picked, using these defaults. Picks in background, sync or Core Data go to `feature-phase-deep` (Opus, xhigh). On-screen and view fixes go to `feature-phase` (Opus, high), or to `feature-phase-light` (Sonnet, medium) when an item is a one-liner in an existing pattern. Each agent works in its own worktree and owns separate files; agents that touch different files run at the same time (‖).
- Steps: the session first writes the picked items into this section, grouped by files with one agent per group. It adds a "Before" number for each from the Phase 1 baseline. Then it follows the efficiency-pass skill's "What a good change looks like" and its Avoid list: no Core Data model edits, no CKShare zone moves, and no removed safety nets. Each fix is its own commit, with the before and after number in the message.
- Cost: ~3–6% (at most three agents; past small agent phases landed under 1% each, while deep sync work runs 2–4%).
- Done when: each agent builds only the `Daybook Assistant` scheme (plus `Cosmic Daybook` if it touched shared files) for the leased simulator, and runs `-only-testing:` for the suites covering its files (the Assistant's test target, and `CosmicDaybookTests/<Suite>` for shared code). Each change that adds a gate or reshapes a cache gets a test pinning old path = new path and one pinning the gate skipping. Each agent re-takes the Phase 1 measurement that its fix should move, and reports both numbers.
- Hand off: no. Phase 3 follows in the same session.

## Phase 3: Combine, full check, re-measure

- Who: main session (Opus 5.5, high).
- Steps: merge the agents' branches onto this session's branch. Run `.claude/skills/efficiency-pass/scripts/verify.sh`, which builds iOS, macOS and the Assistant through the lock and runs the whole suite once. Re-take every Phase 1 measurement into a dated "after" section of the baseline file. Update `.claude/skills/efficiency-pass/references/codebase-map.md` › Daybook Assistant with what was fixed and what was left, and add the Apple guidance gaps above to `apple-guidance.md`. Mark the report's findings fixed or left. Ship to TestFlight only if Danny asks (`roll-out`).
- Cost: ~1–2%.
- Done when: `verify.sh` passes (all three builds, whole suite green or failures explained as pre-existing on main). The after-numbers are recorded beside the before-numbers. The codebase map is updated. The branch is on main through close-out.
- Hand off: no.

## Starting a phase
Read the plan usage (`get_usage`) and note the weekly % used next to the phase under Progress ("started at N%").

## Ending a phase
1. Check every "Done when" item for the phase.
2. Tick the phase under Progress and note anything that differed from the plan. Read the plan usage again and note the actual cost (end % minus start %).
3. Add a row to the log in `~/.claude/skills/plan-efficiently/references/cost-estimates.md`.
4. Update the build board, if the plan lists one.
5. Make every "not verified", "for your review" or "check on a device" item from this phase a row in the app's list in Tide (`Areas/App Development/Cosmic Daybook/To do.md`, `add_action`), skipping ones already there. Tide holds the row; the repo line keeps one plain sentence plus the row's `tide://` link (from the `add_action` reply, or `get_area` for an existing row).
6. Run /close-out. It sets the plan's status line (`> **Working on it.**` after a phase, `> **Done <date>** (<commit>).` after the last, checked against main) and runs `docs-index` so the map follows.
7. If the next phase is a fresh session, print its starter prompt: "Model: <from its Who line>" on the first line, then "In <project folder>, read <this file> and do Phase <N>. Follow its Starting a phase and Ending a phase steps."

## Open questions
None. What Phase 2 fixes depends on Danny's picks from the Phase 1 report.
