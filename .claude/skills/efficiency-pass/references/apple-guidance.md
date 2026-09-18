# Apple guidance on energy, memory, and heat (through WWDC26 / OS 27 SDKs)

Compiled 2026-09-17 against Xcode 27.0 (27A266a). Items were checked against a fetched
Apple page unless marked **[older]** (pre-2025 but still Apple's current published
guidance), **[secondary]** (not from an Apple page), or **[unverified]**.

Reading tip: `developer.apple.com/documentation/...` pages render client-side and return
only a title to a fetcher. The text mirror
`https://developer.apple.com/tutorials/data/documentation/<same path>.md` returns the
full article with availability metadata.

## Contents

1. [Top 15 rules by leverage](#1-top-15-rules-by-leverage)
2. [What changed recently (habits that are now wrong)](#2-what-changed-recently)
3. [SwiftUI](#3-swiftui)
4. [Core Data and CloudKit](#4-core-data-and-cloudkit)
5. [Background, scheduling, thermal, power](#5-background-scheduling-thermal-power)
6. [Memory](#6-memory)
7. [Heat specifically](#7-heat-specifically)
8. [Tooling: Instruments, MetricKit, Organizer](#8-tooling)
9. [Session index](#9-session-index)

---

## 1. Top 15 rules by leverage

Ranked for a data-heavy, long-lived, sync-driven SwiftUI + Core Data + CloudKit app.

1. **Stop over-invalidation.** A view should depend only on the `@Observable` properties
   its body reads. Split views by dependency. Never put geometry, scroll offset, or timers
   in the environment. The WWDC26 Power lab calls unnecessary redraws "the biggest silent
   battery killer in SwiftUI". Verify with the SwiftUI instrument (Update Groups, Show
   Causes). (Lab 8003; session 306; [SwiftUI performance doc](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance))
2. **No work in `body`, `init`, `onAppear`, `onChange`.** Precompute derived collections,
   formatted strings, formatters, thumbnails. Target zero red (>1 ms) body updates.
3. **Filter persistent history instead of relying on `automaticallyMergesChangesFromParent`
   wake-ups.** Consume history on a background context, merge only relevant entities, keep
   the token on disk, prune conservatively (≥7 days) and only after the CloudKit exporter
   has caught up. ([Consuming relevant store changes](https://developer.apple.com/documentation/coredata/consuming-relevant-store-changes))
4. **Batch saves and writes.** Each save triggers a CloudKit export task and SSD writes.
   Coalesce edits, use `NSBatchInsert/Delete/Update`, short-lived background contexts,
   `fetchBatchSize`/`fetchLimit`, `count(for:)` instead of materialising.
5. **Event-driven, not polling.** `NSPersistentStoreRemoteChange`, `NWPathMonitor`,
   `EKEventStoreChanged`, Observation streams. Any timer that survives gets a tolerance.
   ([Scheduling CPU work efficiently](https://developer.apple.com/documentation/xcode/scheduling-cpu-work-efficiently); [Timer.tolerance](https://developer.apple.com/documentation/foundation/timer/tolerance))
6. **Hand discretionary work to the OS scheduler.** macOS: `NSBackgroundActivityScheduler`
   (default `.background` QoS, check `shouldDefer`). iOS: `BGAppRefreshTask` /
   `BGProcessingTask` with `requiresExternalPower`, chunked so it can pause and resume,
   exponential `earliestBeginDate` backoff. On iOS 27 background tasks may be deferred
   during Apple Intelligence workloads, so chunking matters more. (Lab 8003; [NSBackgroundActivityScheduler](https://developer.apple.com/documentation/foundation/nsbackgroundactivityscheduler))
7. **One policy object for `thermalState` and Low Power Mode.** Fair: defer prefetch,
   index and matcher jobs. Serious: pause sync-adjacent background work, drop animation
   rates. Critical: UI only. (This is `EnergyPolicy` in the repo.)
8. **Lowest QoS that works; main actor for UI only.** `@concurrent` / `nonisolated` for
   parsing, matching, PDF and thumbnail work. Batch results to avoid thousands of actor
   hops per second. Watch the Swift Executors instrument for Main Actor saturation.
9. **Right-size and cache images.** Downsample with ImageIO or `QLThumbnailGenerator` to
   display size, cache in `NSCache` with cost limits, drop view content when backgrounded.
10. **Lazy containers, stable identity.** `List` / `LazyVStack`; do not reconfigure state in
    `onAppear` (SwiftUI prefetches rows and throws that work away); inert-variance
    modifiers instead of `if`-swapped views; `scrollPosition(id:)` not offsets.
11. **Liquid Glass only on the navigation layer**, grouped in one `GlassEffectContainer` per
    region. The system recomputes glass when nearby regions update. Check with Debug ▸
    View Debugging ▸ Rendering ▸ Flash Updated Regions.
12. **Networking hygiene for anything not user-initiated.** One `URLSession`,
    `waitsForConnectivity`, `allowsExpensiveNetworkAccess = false`,
    `allowsConstrainedNetworkAccess = false`, background sessions with `isDiscretionary`.
13. **Lower frame rates and pixel luminance.** No `repeatForever` / `TimelineView`
    animation while idle; explicit low `CAFrameRateRange` for ambient motion; full Dark
    Mode support (measured by `PixelLuminanceMetric`).
14. **Launch only the first frame.** Defer warm-ups, matchers, sync setup, MCP servers until
    after first draw. Measure with MetricKit `TimeToFirstDrawMetric` / Organizer, not in-app.
15. **Instrument before and after, in the field too.** `MetricManager` + StateReporting
    (OS 27) with a few stable states, `OSSignposter` around hot paths, Power Profiler passive
    traces on the iPad, Run Comparisons in Instruments 27 to prove each fix.

---

## 2. What changed recently

Habits from 2023-2024 that no longer match Apple's current guidance:

| Old habit | Current guidance | Since |
|---|---|---|
| `MXMetricManager` / `MXMetricPayload` | Swift-first `MetricManager`, `MetricReport`, `DiagnosticReport` as `AsyncSequence`s; old API deprecated. StateReporting slices metrics per app state. | OS 27 (session 222) |
| Time Profiler for CPU | **CPU Profiler** (no timer aliasing); **Top Functions** mode; **Run Comparisons** for before/after | Xcode 26/27 (sessions 308, 268-26) |
| Guessing at main-actor contention | **Swift Executors** instrument shows Main Actor saturation and actor congestion | Xcode 27 |
| `Task.detached` for CPU work | `Task { @concurrent in ... }` / `@concurrent` functions; `nonisolated` library code stays on the caller's executor with no hop | Swift 6.2+ (sessions 268-25, 268-26) |
| `ObservableObject` | `@Observable`: a view updates only when a property body *reads* changes | iOS 17+, now the first fix Apple names for over-updating |
| `@State` allocating a model per parent update | `@State` is a macro with lazy init: the object is built once. Remove default values if you also assign in `init`. | OS 27 (session 269); back-deploy **[unverified]** |
| `@ViewBuilder` computed sub-views | Extract separate view structs (own identity and dependency tracking) | Lab 8006 |
| `VStack` for long lists | `LazyVStack` / `List` (macOS `List` 6× faster load, 16× faster update at 100k rows) | WWDC25 session 256 |
| Custom image caching for `AsyncImage` | `AsyncImage` uses HTTP caching by default; `.asyncImageURLSession(_:)` for custom | OS 27 |
| Long-running foreground work | `BGContinuedProcessingTask` (iOS/iPadOS 26 only, user-initiated, must report `Progress`) | iOS 26 (session 227) |
| Explicit modules as an opt-in | On by default for Swift | Xcode 26 |
| `Timer` for animation | `CADisplayLink` / framework animations with `preferredFrameRateRange` | ProMotion doc |

---

## 3. SwiftUI

- **What re-evaluates `body`:** changes to state, environment, or `@Observable` properties
  the body reads; parent passing different inputs. An environment update notifies every
  view with any environment dependency. ([doc](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance); session 306)
- **Structure rules:** limited dependencies; logic in model types; isolate `GeometryReader`
  / `ScrollViewReader` (they re-run on parent layout changes); **do not store closures in
  views** (captured state widens dependencies; call child-building closures in `init`,
  keep the result, never `@escaping`); threshold `onGeometryChange` before reacting.
- **Environment churn:** pass an `@Observable` object through the environment (stable
  reference, only property reads track), never raw fast-changing values.
- **`onChange(of:initial:)`** runs on the main actor: "avoid long-running tasks in the
  closure". `.task(id:)` cancels and restarts when the id changes **[doc not fetched]**.
- **`drawingGroup`** rasterises the subtree via Metal offscreen; only SwiftUI primitives
  render; costs memory, measure first. Same limit for `ImageRenderer`.
- **Images:** size to display, cache decoded results; `QLThumbnailGenerator` with
  `.lowQualityThumbnail` then `.thumbnail`; `saveBestRepresentation` keeps PNG/JPEG encoding
  out of constrained processes. `Image(decorative:)` is accessibility, not performance.
- **Liquid Glass:** "the system performs additional calculations to update the Liquid Glass
  appearance when your app updates screen regions around the effect"; group with
  `GlassEffectContainer`; do not group spatially distant glass; glass cannot sample glass;
  navigation layer only. ([rendering efficiency](https://developer.apple.com/documentation/xcode/improving-your-app-s-rendering-efficiency); session 323)
- **SwiftUI instrument thresholds:** orange > 500 µs, red > 1 ms per body update. Lanes:
  Update Groups / Long View Body Updates / Long Platform View Updates / Other Long Updates.
- **`Self._printChanges()`** for a quick check; the instrument for real work.
- **`@FetchRequest`:** Apple gives no current numbers. Apply the SwiftData-lab rules: precise
  predicates, fetch limits, narrower views, selective refetch from persistent history.

## 4. Core Data and CloudKit

- **Sync mechanics:** `NSPersistentCloudKitContainer` exports on every context save via a
  background task (record conversion + upload) and imports on push; ~1 minute latency.
  Fewer saves = fewer export operations. Pin `viewContext.setQueryGenerationFrom(.current)`.
  ([Syncing a Core Data store with CloudKit](https://developer.apple.com/documentation/coredata/syncing-a-core-data-store-with-cloudkit))
- **Persistent history:** fetch on a background context ("Important: Execute the fetch
  request on a background context"); filter by entity / `transactionAuthor` /
  `contextName`; merge with `mergeChanges(fromContextDidSave: transaction.objectIDNotification())`;
  store the token on disk; purge with `deleteHistory(before:)` (Apple's example: 7 days)
  only after every client has consumed it. Pruning history the mirroring delegate has not
  exported yet is a known data-loss cause **[secondary]**: keep the window conservative and
  never prune from a second process.
- **`automaticallyMergesChangesFromParent`:** every background save wakes the view context.
  History-filtered merging is Apple's documented alternative.
- **Batching:** `NSBatchDeleteRequest` at SQL level (return `.resultTypeObjectIDs`, then
  `mergeChanges(fromRemoteContextSave:into:)`); `fetchBatchSize` is an in-memory cursor;
  `returnsObjectsAsFaults = false` only when every property will be touched;
  `stalenessInterval` affects fault fulfilment only.
- **Save cadence:** "the longer your app goes between saves, the bigger Core Data's working
  set can grow… the more frequently your app saves, the more writes… strike a balance."
  ([reduce memory](https://developer.apple.com/documentation/xcode/making-changes-to-reduce-memory-use); [reduce disk writes](https://developer.apple.com/documentation/xcode/reducing-disk-writes))
- **Blobs:** `allowsExternalBinaryDataStorage` for large per-record data.
- **SwiftData lab rules that carry over (8017):** precise predicates + `fetchLimit`;
  `count(for:)` not materialise; batch inserts in short-lived contexts; I/O is the
  bottleneck, so few contexts; pass `NSManagedObjectID`s across actors; sync latency is
  platform policy (the phone throttles when hot); verify indexes with the **Data
  Persistence** template. Nothing new in Core Data at WWDC26.
- **Debugging sync cost:** `-com.apple.CoreData.CloudKitDebug 1`; `-com.apple.CoreData.SQLDebug 1`;
  test by backgrounding/foregrounding, not force-quit.
- **SQLite hygiene Apple attributes to Core Data:** WAL, transactions, indexes
  (`EXPLAIN QUERY PLAN` showing "USE TEMP B-TREE" means a missing index), no explicit
  `VACUUM`, do not close connections.

## 5. Background, scheduling, thermal, power

- **`ProcessInfo.thermalState`** actions per state. `.fair`: "reduce or defer background
  work, like prefetching content over the network or updating database indexes".
  `.serious`: reduce I/O, lower location accuracy, stop or defer CPU/GPU work, 60→30 fps.
  `.critical`: minimum for user interaction, stop camera/mic/speaker.
  ([ThermalState](https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.enum); [Responding to power notifications](https://developer.apple.com/documentation/xcode/responding-to-power-notifications))
- **`isLowPowerModeEnabled`** (iOS 9+, macOS 12+) + `NSProcessInfoPowerStateDidChange`: pause
  optional activity, fewer display updates and animations, fewer connections.
- **`NSBackgroundActivityScheduler`** (macOS only): "gives the system flexibility to
  determine the most efficient time to execute based on energy usage, thermal conditions,
  and CPU use". For autosave, backups, data maintenance, ≥10-minute intervals. `tolerance`
  defaults to half the interval; QoS default `.background` is "the recommended value";
  check `shouldDefer` mid-run and return `.deferred`.
- **`BGTaskScheduler`** (iOS, iPadOS, tvOS, visionOS, Catalyst; **not macOS**):
  `BGAppRefreshTask` follows usage history; `BGProcessingTask` with
  `requiresNetworkConnectivity` / `requiresExternalPower`; `earliestBeginDate` backoff
  5→10→20 min; call `setTaskCompleted` promptly. Session 227's adjectives: efficient,
  minimal, resilient, courteous, adaptive.
- **`BGContinuedProcessingTask`** (iOS/iPadOS 26+): foreground-started, user-initiated, Live
  Activity progress, must conform to `ProgressReporting`; the system kills the task showing
  least progress first; `.gpu` resource needs an entitlement.
  ([Performing long-running tasks](https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados))
- **Timers:** `tolerance` default 0; "allowing the system flexibility in when a timer fires
  increases the ability of the system to optimize for increased power savings". The
  10%-of-interval rule is from the 2016 Energy Efficiency Guide **[older]**.
- **QoS:** "use the lowest QoS value that makes sense… the system uses more energy-efficient
  scheduling for tasks with lower QoS"; 10–100 ms per concurrent unit. Thread Performance
  Checker flags high-QoS waiting on low-QoS and main-thread I/O.
- **Memory pressure source:** `DispatchSource.makeMemoryPressureSource` (`.warning /
  .critical / .normal`), inactive until `activate()`; the only signal on macOS.
- **`os_proc_available_memory()`**: iOS-family only, advisory, do not cache.
- **Networking:** one `URLSession`; batch and compress; `waitsForConnectivity`;
  `allowsExpensiveNetworkAccess` / `allowsConstrainedNetworkAccess` off for discretionary
  work; background sessions with `isDiscretionary` are coalesced across apps.
  ([Reducing networking power](https://developer.apple.com/documentation/xcode/reducing-networking-and-bluetooth-power-usage))
- **`NWPathMonitor`**: event-driven, one instance; let `waitsForConnectivity` handle request
  timing rather than gating on reachability.
- **Location / EventKit:** `CLLocationUpdate.liveUpdates` stops when stationary; observe
  `EKEventStoreChanged` and refetch rather than poll **[page not fetched]**.

## 6. Memory

- **Metrics:** peak memory and memory-at-suspension (Organizer, MetricKit
  `SuspendedMemoryMetric`, new `MemoryExceptionDiagnostic` on iOS); footprint = dirty pages
  × 16 KB. ([Reducing memory use](https://developer.apple.com/documentation/xcode/reducing-your-app-s-memory-use))
- **Warnings:** iOS has `didReceiveMemoryWarningNotification`; macOS only the dispatch
  source. "Don't traverse your app's whole object graph looking for memory to release."
  Avoid `NSCache` + `NSPurgeableData` together. Allocate large buffers gradually.
  ([Responding to low-memory warnings](https://developer.apple.com/documentation/xcode/responding-to-low-memory-warnings))
- **`NSCache` vs dictionary:** auto-eviction, thread-safe, `countLimit` / `totalCostLimit`.
  Apple's anti-pattern example is an unbounded dictionary of messages.
- **Images:** downsample with ImageIO to display size and colour depth; release view
  content when backgrounded.
- **Swift (6.2 / 6.4):** `InlineArray`, `Span` / `RawSpan` / `OutputSpan`, struct-held state
  to drop `swift_beginAccess`, `UniqueArray` / `UniqueBox`, `borrow` / `mutate` accessors,
  `withTaskCancellationShield` for must-finish flushes. `ContiguousArray` only beats `Array`
  for class or `@objc` element types. (sessions 312, 262) `autoreleasepool` in loops and
  String bridging costs: WWDC18 416 and WWDC16 "Understanding Swift Performance" **[older]**.
- **Tools:** Xcode memory gauge (simulator never warns), Debug Memory Graph, Allocations
  Generations (Mark Generation), Leaks, VM Tracker, export memory graph for `vmmap` / `leaks`.

## 7. Heat specifically

- Battery doc: subsystem use "potentially increases the device's temperature, which can
  cause the device to limit its function to avoid overheating".
- The thermal ladder in §5 is the canonical mitigation. The 2016 Mac guide adds: even at
  nominal, route discretionary work through `NSBackgroundActivityScheduler` **[older]**.
- ProMotion doc: the system already drops max refresh in Low Power Mode and when hot; do not
  let a `CADisplayLink` callback cycle the device in and out of thermal mode; use separate
  code paths per frame rate rather than adapting quality dynamically (oscillation).
- Sustained workloads: split long tasks across frames, cache render products, adapt to Low
  Power Mode. `com.apple.developer.sustained-execution` entitlement for benchmarking.
- On-device ML (Core AI, session 324): compile ahead of time, never specialise a model in an
  interactive flow, let the framework place work.
- Tooling: **Thermal State** instrument, Power Profiler thermal lane, Device Conditions
  (Xcode ▸ Devices and Simulators ▸ Device Conditions) to induce Fair / Serious / Critical,
  Performance Trace on-device for hours-long captures, MetricKit `Environment.lowPowerModeEnabled`.

## 8. Tooling

- **Templates on Xcode 27:** Activity Monitor, Allocations, Animation Hitches, App Launch,
  CPU Counters, CPU Profiler, Core AI, Data Persistence, File Activity, Foundation Models,
  Game Memory, Game Performance, Leaks, Logging, Metal System Trace, Network, Power
  Profiler, Processor Trace, Swift Concurrency, SwiftUI, System Trace, Time Profiler.
  Instruments of note: Thermal State, Hangs, Hitches, Swift Executors, Data Faults /
  Fetches / Saves, VM Tracker, os_signpost, Points of Interest, Thread Activity (effective
  vs requested QoS).
- **Command line:**
  `xcrun xctrace record --template 'SwiftUI' --attach 'Cosmic Daybook' --time-limit 30s --output x.trace`;
  `--launch -- <app>`; `--window 60s`; `--instrument 'Thermal State'` to add one.
  Xcode 27 adds `--show-recording-options` / `--recording-options <json>` and
  `xctrace export --time-start/--time-end`. The simulator-attach bug is fixed in 27.
- **Power Profiler:** iOS/iPadOS 26+ physical devices only. Passive mode: Settings ▸
  Developer ▸ Performance Trace ▸ Power Profiler ▸ toggle the app, then the Control Center
  control; up to 10 h; share the `.aar`. Values not comparable across device models;
  system power reads 0 while charging.
  ([doc](https://developer.apple.com/documentation/xcode/measuring-your-app-s-power-use-with-power-profiler))
  Mac: Energy Impact gauge, Activity Monitor, `powermetrics` (sudo).
- **Instruments 27:** Top Functions, Run Comparisons, Swift Executors, unified System Trace
  with syscall Inspector, os_log overlay, StateReporting states under Points of Interest.
  Diagnostic model: CPU saturation → CPU Profiler + Top Functions; contention → Swift
  Executors; system blocking → System Trace. (session 268-26)
- **MetricKit (OS 27):** `MetricManager.metricReports` / `diagnosticReports`; groups `.cpu
  .memory .energy .display .disk .network .gpu .launch .hang .metal`; StateReporting
  `StateReporter.reporter(for:)` + `reportTransition(to:)`; `trackLaunchTask(id:)`;
  `logHandle(category:)` for custom signpost metrics; `DiagnosticReport.Environment.signpostData`
  lists open signpost intervals at hang or crash time. Set up once at launch; few, stable
  states; never report per frame. ([Analyzing app performance with MetricKit](https://developer.apple.com/documentation/metrickit/analyzing-app-performance-with-metrickit))
- **Organizer (Xcode 27):** Hitches metric (≤10 ms/s good, ≤25 warning, ≤50 critical),
  Storage metric, Metric Goals (battery, disk writes, hang rate, hitches, memory, storage),
  Battery Usage split on-screen vs background and by subsystem, energy exception reports.
  ([Analyzing battery use](https://developer.apple.com/documentation/xcode/analyzing-your-app-s-battery-use))
- **Thread Performance Checker:** on by default for Run; can fail tests via test-plan
  Runtime API Checking.
- **Build diagnostics:** `-Xfrontend -warn-long-expression-type-checking=<ms>` and
  `-warn-long-function-bodies=<ms>` (unsupported frontend flags, still work in 27
  **[secondary]**); Apple's official advice is explicit types and split expressions.
  `@ContentBuilder` (OS 27) and Swift 6.4 attack the same problem.
- **Disk:** File Activity template; `XCTStorageMetric`; `XCTCPUMetric` for CPU regression tests.

## 9. Session index

WWDC26: 268 Profile, fix, and verify (Instruments) · 258 What's new in Xcode 27 · 222 Meet
the new MetricKit · 269 What's new in SwiftUI · 102 Platforms State of the Union · 262
What's new in Swift · 274 What's new in SwiftData · 8003 Power and Performance Group Lab ·
8006 SwiftUI Group Lab · 8017 SwiftData Group Lab · 388 Metal games performance · 303
Responsive camera app launch · 324 Meet Core AI. No WWDC26 session is dedicated to
background tasks, CloudKit, Core Data, memory, or thermal; the labs cover them.

WWDC25: 226 Profile and optimize power usage · 227 Finish tasks in the background · 306
Optimize SwiftUI performance with Instruments · 308 Optimize CPU performance with
Instruments · 312 Improve memory usage and performance with Swift · 247 What's new in
Xcode 26 · 256 What's new in SwiftUI · 266 Explore concurrency in SwiftUI · 268 Embracing
Swift concurrency · 323 Build a SwiftUI app with the new design.

URL pattern: `https://developer.apple.com/videos/play/wwdc2026/<number>/` and `wwdc2025/`.

### Not confirmed

`@State` lazy-init back-deployment; Liquid Glass opacity slider and "cheaper glass on older
hardware" in iOS 27; a Power Profiler for macOS targets; `task(id:)`, `EKEventStoreChanged`,
and `performExpiringActivity` doc pages (404 on the text mirror). Apple publishes no numbers
for `@FetchRequest`, `automaticallyMergesChangesFromParent`, `NWPathMonitor`, or idle
`MTLDevice` cost.
