# Siri & Apple Intelligence Improvements

**Date:** 2026-06-24
**Status:** 9 of 10 items shipped in-app (iOS + macOS builds green, lint-clean). 1 item (widgets/Control Center) is a documented Xcode handoff.
**Scope:** Make the app a first-class citizen of Siri, Spotlight, and Apple Intelligence using the modern **App Intents** framework (the successor to SiriKit custom intents).

---

## 1. Plain-English overview

Before this work, Siri could only *open screens* in the app. It didn't know who your students were, what your lessons were, or how to do anything for you.

After this work:

- You can **talk to Siri to get things done** — log an observation about a student, mark a lesson presented, mark a student absent — and it happens **without opening the app**.
- Your **students and lessons show up in phone search** (Spotlight), and tapping one jumps into the app.
- A **"Today's Observations" card** can be shown by Siri/Spotlight with the real notes you logged today and a button to open the Today view.
- When something can't be done, Siri **says a real sentence** ("I couldn't find Maria in your students") instead of a generic error.
- A new **"Siri & Shortcuts"** section in Settings → AI Features shows the available phrases.

Two of the ten goals turned out to be **already satisfied** in the codebase (Writing Tools and on-device structured AI), so those were verified rather than changed. The last goal (home-screen widget + Control Center button) **requires a one-time Xcode step** that can't be done from code — there's a complete recipe in `SIRI_WIDGETS_HANDOFF.md`.

### Phrases you can now use with Siri

- "Log an observation about *[student]*"
- "Mark *[lesson]* as presented to *[student]*"
- "Mark *[student]* absent"
- "Open *[student]*" / "Open *[lesson]*"
- Plus the existing navigation phrases ("Open Today", "Take attendance", etc.)

---

## 2. The top-10, item by item

| # | Item | Status | Notes |
|---|------|--------|-------|
| 1 | Model domain objects as `AppEntity` | ✅ Shipped | Student + Lesson |
| 2 | CloudKit-safe stable entity IDs | ✅ Shipped | App-controlled `UUID`, never `NSManagedObjectID` |
| 3 | Parameterized action intents | ✅ Shipped | Log Observation, Mark Presented, Mark Absent |
| 4 | Spotlight semantic indexing | ✅ Shipped | Students + Lessons via `IndexedEntity` |
| 5 | Interactive snippet | ✅ Shipped | Real "Today's Observations" card |
| 6 | Richer shortcut phrases + `ParameterSummary` + Siri tips | ✅ Shipped | 10 App Shortcuts (the platform max); in-app tips |
| 7 | Control Center control + widget | ⚠️ Handoff | Needs a Widget Extension target (Xcode) — recipe written |
| 8 | Hardened intents (localized errors, auth policy) | ✅ Shipped | Spoken errors; auth on the data-revealing snippet |
| 9 | Writing Tools in editors | ✅ Already done | Verified — no change needed |
| 10 | `@Generable` guided generation | ✅ Already done | Verified — report stays cloud-routed by design |

---

## 3. Technical summary

### 3.1 Files added (`Maria's Notebook/Siri/`)

| File | Type | Purpose |
|------|------|---------|
| `StudentAppEntity.swift` | `StudentEntity: AppEntity, IndexedEntity` + `StudentEntityQuery: EntityStringQuery` | Siri/Spotlight-facing student value type; resolves students by id, name, and as suggestions |
| `LessonAppEntity.swift` | `LessonEntity: AppEntity, IndexedEntity` + `LessonEntityQuery: EntityStringQuery` | Same for lessons |
| `LogObservationIntent.swift` | `AppIntent` (+ `LogObservationError`) | Creates a `CDNote` scoped to a student |
| `MarkLessonPresentedIntent.swift` | `AppIntent` (+ error) | Find-or-create a `CDLessonAssignment`, then `markPresented()` |
| `MarkAbsentIntent.swift` | `AppIntent` (+ error) | Marks today's attendance via `AttendanceRepository` |
| `OpenStudentIntent.swift` | `OpenIntent` | Deep-links to a student's detail screen |
| `OpenLessonIntent.swift` | `OpenIntent` | Opens the Lessons library |
| `SpotlightIndexer.swift` | `enum` | Indexes students + lessons into Core Spotlight |

### 3.2 Files modified

| File | Change |
|------|--------|
| `AppCore/AppIntents.swift` | Registered the new intents in `MariasNotebookAppShortcuts` (now exactly 10 shortcuts) with natural + parameterized phrases |
| `AppCore/MariasNotebookApp.swift` | Added `Task { await SpotlightIndexer.reindexAll() }` at the end of `performStartupBootstrap()` |
| `Students/SummarizeTodaysObservationsIntent.swift` | Replaced mock data with a live, async-loading snippet view + interactive button; added `authenticationPolicy` |
| `Settings/SettingsView+Sections.swift` | Added a "Siri & Shortcuts" group (`SiriTipView` on iOS, text fallback on macOS) |

### 3.3 Key design decisions

- **Stable identity:** every `AppEntity.id` is the entity's app-controlled `UUID` (`CDStudent.id`, `CDLesson.id`), **not** `NSManagedObjectID`. Object IDs can change after CloudKit re-mirroring, which would silently break Siri/Spotlight references. This is consistent with the project's "additive-only CloudKit schema" rule.
- **Reuse the app's real write paths.** Intents don't hand-roll persistence:
  - Observation → mirrors `QuickNoteViewModel.saveNote`: `CDNote(context:)`, set `scope = .student(id)`, call `syncStudentLinks(in:)`, then `safeSave()`.
  - Presentation → `CDLessonAssignment.markPresented()` (the canonical mutation that also snapshots lesson title/section). Reuses an existing not-yet-presented assignment for that lesson+student when one exists.
  - Attendance → `AttendanceRepository.loadOrCreateRecords(forDate:students:)` + `updateStatus(.absent)` (so day-boundary normalization matches the Attendance grid).
- **Background-first.** Action intents set `openAppWhenRun = false` so they complete without launching the UI. They reach Core Data through `AppBootstrapping.getSharedCoreDataStack().viewContext` on the main actor.
- **Main-actor query witnesses.** `EntityStringQuery` methods are `@MainActor` (the established pattern in this codebase, mirroring the existing intents' `@MainActor func perform()`), since Core Data access here is main-actor bound.
- **Spotlight via `IndexedEntity`** (not raw `CSSearchableItem`): `CSSearchableIndex.default().indexAppEntities(...)`. This links each search result back to its `OpenIntent`, so tapping a student opens that student.
- **10-shortcut ceiling.** App Shortcuts are hard-capped at 10 per app. The "Summarize Today's Observations" snippet intent is intentionally **not** an App Shortcut — it's still usable as a Shortcuts action and snippet result, it just doesn't consume one of the 10 voice-phrase slots.
- **`@Generable` (#10) left as-is on reports — deliberate.** The app already uses `@Generable` guided generation wherever on-device structured output is appropriate (meeting summaries, note tag/student suggestions, todo parsing, story analysis). `AIReportService` deliberately routes report writing through the **cloud** model (`AnthropicAPIClient`) for quality; converting it to on-device `@Generable` would *cap* report quality. So no change was made.
- **Writing Tools (#9) needed no change.** Every text surface already uses native `TextEditor`/`TextField` (auto Writing Tools) or `SmartTextEditor` (custom `UIViewRepresentable`/`NSViewRepresentable` with `.writingToolsBehavior = .complete`).

---

## 4. The build failure that was caught and fixed

**Symptom:** the macOS build failed after the Settings change.

**Cause:** `SiriTipView` is `@available(macOS, unavailable)`. It was added to a shared (non-platform-gated) part of `SettingsView+Sections.swift`, so it compiled on iOS but broke the macOS build. The initial CLI verification only targeted the iOS simulator, which hid it.

**Fix:** the "Siri & Shortcuts" tips are now `#if os(macOS)` (a text list of the phrases) / `#else` (`SiriTipView`s on iOS/visionOS).

**Process change:** this is a single multiplatform target — **build both iOS and macOS** after any SwiftUI + App Intents change. Both are green now.

---

## 5. Verification

- ✅ `xcodebuild ... -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' build` — **BUILD SUCCEEDED** (clean build)
- ✅ `xcodebuild ... -destination 'platform=iOS Simulator,...' build-for-testing` — **TEST BUILD SUCCEEDED**
- ✅ `xcodebuild ... -destination 'platform=macOS' build` — **BUILD SUCCEEDED**
- ✅ SwiftLint clean on all new/changed files (one pre-existing, unrelated `file_length` note on `MariasNotebookApp.swift`, which was already over the limit before this work).
- ⚠️ **On-device Siri behavior is not yet verified** — only compilation. Needs a real device run.

### How to test on device (≈5 min)

1. Run on an iPhone/iPad from Xcode.
2. Open **Shortcuts** — the new actions appear automatically.
3. Say *"Hey Siri, log an observation about [a real student]"* → it should ask what you observed, then confirm.
4. Swipe down on the home screen and search a **student or lesson name** → it should appear; tap to open.
5. In the Shortcuts app, run **"Summarize Today's Observations"** to see the live card.

---

## 6. Known limitations / future work

- **#7 widgets + Control Center** require a Widget Extension target + App Group — see `SIRI_WIDGETS_HANDOFF.md`. The Todo widget UI already exists in `Services/TodoWidgetProvider.swift`.
- **Background intent caveat:** action intents build the CloudKit stack via `AppBootstrapping.getSharedCoreDataStack()` without the app's `performInitialSetup()` having run. If background actions misbehave on-device, the one-line fallback is `openAppWhenRun = true` (still useful — it just opens the app).
- **Per-lesson deep link:** `AppRouter` has no `openLessonDetail`, so `OpenLessonIntent` (and tapping a lesson in Spotlight) lands on the Lessons list rather than the specific lesson. Adding a `NavigationDestination.openLessonDetail(UUID)` + a `RootView` handler would complete this.
- **More entities/verbs (optional):** `Note`/`WorkModel`/`RecallCheck` as `AppEntity`; a `LogPractice` intent; a Control Center "start observation" intent that triggers Quick Note capture.
