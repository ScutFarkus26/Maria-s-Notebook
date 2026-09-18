---
name: efficiency-pass
description: Reduce battery drain, memory footprint, and device heat in Cosmic Daybook without changing behavior, following Apple's current (WWDC25/WWDC26, iOS 27 / macOS 27) guidance. Use this whenever Danny mentions the app being hot or warm, the battery, the fan, memory, "over a gigabyte", jetsam, slow sync, the app "doing something" while idle, CPU usage, energy, thermal state, Low Power Mode, or asks for a "perf pass", "battery pass", "efficiency pass", "heat audit", or to make a screen or service "cheaper" or "lighter". Also use it when adding any new background, scheduled, polling, caching, or sync-reactive code, since that is where regressions come from. Not for build-time or launch-time work on its own (see BUILD_AND_LAUNCH_PERFORMANCE_PLAN.md), and not for UI bugs that merely happen to be slow.
---

# Efficiency pass

The app runs all school day on an iPad and a Mac, syncing through CloudKit whether or
not the guide is looking at it. Most of the heat and battery cost comes from work the
app starts on its own initiative, and most of the memory cost comes from materialising
whole Core Data tables. Three passes have already been done (2026-08-24, 2026-09-02,
2026-09-10), so the easy wins in the view layer and the sync pipeline are gone. What
remains is found by measuring, not by browsing.

"Without breaking anything" is the hard constraint. Every change in a pass is a
**pure efficiency change**: same outputs, same records written, same order of events
the user can observe. If a change needs a behavior decision (skip this work entirely,
show fewer rows, sync less often than the user expects) it is a product change, so stop
and describe it to Danny instead of making it.

## Before touching code

1. **Read the map.** `references/codebase-map.md` lists the helpers that already exist
   (EnergyPolicy, memory-pressure hub, shared formatters and calendars, thumbnail cache,
   debounced sync handlers), the known open hot spots, what was verified fine on
   2026-09-10, and the repo's traps. Reusing a helper is always preferred to adding a
   parallel mechanism.
2. **Get a number.** `references/measurement.md` maps each symptom to the cheapest
   measurement that can move. For heat while idle that is CPU over 60 s and what wakes
   it; for memory it is footprint before and after the flow; for sync heat it is body
   evaluations and SQL statements per remote-change burst. Take it before and after.
   If the live store is out of reach, the app's **Sample Class** workspace (seeded by
   `SampleClassroomSeeder`, switchable in the app) gives a populated store on any
   simulator. If no app can run at all (an agent worktree with a flaky simulator), the
   expected fallback is static counting: reads of a computed property per body pass,
   fetches per action, notifications per save. Say that is what you did; do not present a
   guess as a measurement.
3. **Run the audit.** From the repo root:

   ```bash
   python3 .claude/skills/efficiency-pass/scripts/audit_hotspots.py
   ```

   Add `--rule <name>` to focus, `--deep` for the low-signal rules, `--list-rules` for
   the catalogue. Every hit is a place to read, not a defect; each rule prints the
   question to answer first. Scope to the files behind the symptom rather than fixing
   the whole list.
4. **Check the Apple rules.** `references/apple-guidance.md` holds the WWDC25/26-era
   recommendations with links. Read the section that matches the symptom (§3 SwiftUI for
   view-layer cost, §4 for Core Data and sync, §5 for background and thermal, §6 for
   memory) and skim the "what changed" table once per session. The top-15 list is for
   choosing where to start when the symptom is vague ("the iPad is warm"). The points
   that most often surprise:
   - `BGTaskScheduler` does not exist on macOS; the Mac equivalent for maintenance is
     `NSBackgroundActivityScheduler` (default `.background` QoS, honours `shouldDefer`).
     `BGContinuedProcessingTask` is iOS/iPadOS 26+ and must be user-initiated.
   - CPU work belongs in `@concurrent` / `nonisolated` code, not `Task.detached`; under
     main-actor default isolation an unmarked function runs on the main actor.
   - Instruments 27 has **Run Comparisons** (exact before/after deltas), **Top Functions**,
     and a **Swift Executors** instrument that shows Main Actor saturation. The Core Data
     template is now called **Data Persistence**.
   - MetricKit was rewritten for OS 27 (`MetricManager`, async sequences, StateReporting);
     `MXMetricManager` is deprecated. Do not add new code against the old API.
   - Apple's thermal ladder: `.fair` already means "defer prefetch and index updates";
     `.serious` means cut I/O and CPU/GPU work. `EnergyPolicy` gates at `.serious`; a new
     prefetch-style job may reasonably gate at `.fair`.

## What a good change looks like

Prefer, in this order, because each is cheaper to verify than the next:

1. **Do the same work less often.** Gate on a change signal (persistent-history token,
   `.task(id:)`, `onChange` of the actual input) instead of on time or on every
   notification. Debounce bursts. Consult `EnergyPolicy.shared.shouldDeferMaintenance`
   before any self-initiated work, never for user-initiated work.
2. **Do the same work with less data.** `count(for:)` instead of fetching; predicates;
   `fetchLimit`; `fetchBatchSize` for lists; `returnsObjectsAsFaults`; property or
   dictionary result types; object IDs across actor boundaries.
3. **Do the same work somewhere cheaper.** A background context for reads that only feed
   a cache; `.utility` or `.background` priority for maintenance; hoist a computed
   property into a `let` at the top of `body`.
4. **Keep the result instead of recomputing it.** Shared formatters and calendars, the
   thumbnail cache, a `let` cache passed down to rows. Any new long-lived cache must be
   bounded and must clear on `.memoryPressureDetected`.

Avoid, unless Danny asks:

- Changing what a screen shows, what gets synced, or when a record is written.
- Anything that creates, deletes, or moves a CKShare zone.
- Core Data model edits (the model is one in-place version; see the memory note).
- Removing a "safety net" call site (dedup after import, launch repair) because a new
  gate makes it a no-op. Leave the call, let the gate do the work.
- Micro-optimisations with no measurement behind them. A pass of ten unmeasured
  one-liners is harder to review than one measured fix.

Keep each fix small and separately revertible: one commit per hot spot, message says
the before/after number and how it was taken. When committing is not allowed (an eval
run, an agent worktree), the numbers go in the report and in the baseline file instead.

In an agent worktree, first run `git merge-base HEAD main` and
`git diff --stat HEAD...main -- <files you will touch>`. If those files moved on `main`,
stay on your base, do the work, and state in the report that the diff needs a merge; do
not rebase or merge inside the run.

## Verify

Run the gate from the repo root after the last edit:

```bash
.claude/skills/efficiency-pass/scripts/verify.sh
```

It builds the app for iOS and macOS and the Daybook Assistant (they share the
services), then runs the full suite on the iPhone 17 simulator and prints the real
verdict plus any failure messages from the `.xcresult`. Use `--skip-tests` while
iterating, never for the final report. Do not pass `--macos-tests` without a fresh
backup: the macOS test host is the real app and its startup touches the live store.

Then:

- Re-take the measurement from step 2 and put both numbers in the commit message.
- If a cache changed shape or a gate was added, add a test that pins the equivalence
  (old path and new path return the same ids/rows) and one that pins the gate skipping.
  Timing tests must poll with a deadline, not sleep a fixed interval.
- Try the hot path once in the app if a simulator is available (the `run` skill), since
  a gate that never fires looks identical to a gate that always skips.
- Record durable numbers in `Documentation/Implementation/perf-baselines/` as a dated
  file when they are worth comparing against later.

## Report

Lead with what was measured and what changed. Then, per fix: file, symptom, before and
after, why behavior is unchanged. List anything deliberately left alone and why (product
decision needed, no measurement possible, out of scope). Name what still needs Danny:
a run on the live store, a device measurement, a CloudKit schema deploy.
