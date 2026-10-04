# Whole-app audits and implementation waves

Use this when Danny asks for a whole-app pass ("find 50 ways to…", "audit battery and memory"),
or to implement numbered items from one ("do 12, 13, 25"). It is how the 2026-09-25 "Energy
Fifty" audit was found and how its five waves landed (the private artifact "Daybook Energy
Fifty"; per-wave numbers in `docs/Technical notes/Performance baselines/2026-09-2*-energy-fifty-wave*.md`).

## 1. Know which copy you are measuring

- Find the running copy first: `ps -axo pid,etime,command | grep "Cosmic Daybook.app/Contents/MacOS"`.
  A DerivedData `Debug` path, especially under `debugserver`, is not what the day costs: `-Onone`,
  debug-only fetches, and coverage counters if the scheme instrumented the run build. The daily
  driver is `/Applications/Cosmic Daybook.app`, a Release build of main
  (`Scripts/install_release.sh`). Say which copy a baseline came from.
- Mac tools that work on a debuggable build without sudo: `footprint <pid>`, `heap -s <pid>`,
  `top -l 0 -s 60 -stats pid,command,cpu,idlew,power,mem`, and `/usr/bin/log show` (not zsh's
  `log` builtin). A 24-hour idle snapshot (footprint, compressed memory, CPU seconds, log
  repeats) made a good "before" row.
- Two things the Mac never tells you: memory pressure almost never fires (caches need idle
  trims), and a minimized, covered or other-Space window gets no `onDisappear` (gate on
  occlusion). See SKILL.md, "On the Mac".

## 2. Fan out, then check every claim yourself

- Read-only agents by area, in parallel: Mac lifecycle and windows; Core Data, CloudKit and
  persistent history; SwiftUI bodies, menus and layout; long-lived memory (albums, images,
  PDFs, caches); scheduling and background (BGTask, `NSBackgroundActivityScheduler`, QoS,
  EventKit); iPad lifecycle and memory warnings; the Assistant and the MCP bridge; Apple's
  current documentation. Give each the codebase map and the audit script's output for its area.
- Check each high-ranked claim in the code before it goes on the list. Agents over-report
  (things already fixed, or measured on the wrong build) and under-report cross-file effects.
- One entry per item: title, platform, impact, what it saves (battery / memory), effort,
  whether it needs Danny's decision, the current state with `file:line`, the change, the Apple
  rule with a link, and how to verify it.

## 3. Publish, then decide before building

- A numbered private artifact (filters by status, platform and impact; "copy picked numbers")
  lets Danny answer with item numbers. Mark anything he could notice, or that touches the Core
  Data model, as needing a decision, and ask all of them before the first wave (a few per
  question, with a recommended option).
- After each wave, update the artifact: status (done / partly, with the reason for "partly"), a
  one-line result with the numbers, and a footer section for the wave. If the builder script in
  the scratchpad is gone (it does not survive a session), read the artifact back and edit the
  `REPORT` JSON embedded in the page.

## 4. Run the work in waves

- **Group** items so no two agents touch the same files. List the files that two or more items
  touch and sequence those items rather than parallelising them.
- **Worktrees by hand**, from local main: `git worktree add -b <branch> .claude/worktrees/<name> main`.
  (`isolation: worktree` starts at the last *pushed* main, which can be many commits behind.)
  Build the first worktree once before launching agents so the others replay the compile cache.
- **One agent per group, one simulator per agent.** Parallel test runs on one simulator fight.
  Only the "iPhone 17" simulator loads the NaturalLanguage sentence model, so give it to whoever
  owns album work.
- **The brief** carries: the worktree, branch and base commit; the build and test commands (the
  lock script, the worktree prefix-mapping flags, `test-without-building`,
  `-collect-test-diagnostics never`, totals from the `.xcresult`); the rules (never the macOS
  test action — it opens the live store; the SwiftLint hook reports violations that predate the
  edit; zero warnings; `@concurrent` to leave the main actor); the item with `file:line`; "measure
  before and after, keep the old code verbatim in the test target and compare, mutation-check the
  new tests"; and the report format. Agents must not edit shared docs (the app's CLAUDE.md, the
  codebase map): they report doc facts and the orchestrator writes the docs after merging.
- **Review each report.** A trade-off an agent flags is yours to decide or to bring to Danny.
  The rule used in 2026-09: an efficiency pass must not add main-thread time (the album fold was
  sent back to run off the main thread; a streamed restore that nearly doubled the main-thread
  import was replaced by a version that did not). Send work back with `SendMessage` to the agent's
  id; it resumes with its context. Record agent ids in memory while a wave runs, so an app restart
  does not lose them.
- **Integrate**: one branch (`efficiency/waveN`), `git merge --no-ff` each agent branch, then
  `verify.sh` on the iPhone 17 simulator. The usual failure is a test that races under the full
  parallel suite (a process-wide notification, a second read of UserDefaults, a heavy synchronous
  `@MainActor` test starving a timing test); see the codebase map's traps. Then fast-forward main,
  write the dated baseline file, update the codebase map and CLAUDE.md, remove the worktrees and
  branches, move their DerivedData to the Trash (CLAUDE.md has the recipe), and update the artifact
  and memory. Push only when Danny asks.

## 5. Afterwards

- Reinstall the Release copy (`Scripts/install_release.sh`, after Danny quits the app) and re-take
  the baseline on it. For the iPhone and iPad: archive Release for `generic/platform=iOS` and
  install the archived app with `xcrun devicectl device install app --device <UDID> <app>` (the
  device must be unlocked). A device new to the team's provisioning profile has to be registered
  first, and an archive never registers it: run a `build` with `-destination "id=<UDID>"
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration`, then archive. Registering
  changes Danny's developer account, so ask first.
