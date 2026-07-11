# macOS HIG Conformance — Phased Plan

Derived from the macOS Human Interface Guidelines audit (2026-06-28). The audit produced 56 adversarially-verified findings + 5 completeness additions; this is the build plan that turns the top items into work.

**Decision on file:** The floating radial PieMenu quick-command button is **kept** (Danny's call). It is made HIG-compliant by adding parallel standard paths, not removed. See Phase 1.

**Ground rules (every phase):** build both iOS and macOS, keep the test suite green, zero warnings, pass SwiftLint.

---

## Phase 0 — Honesty pass (quick correctness wins)
- [x] Remove the dead "<App> Help" menu item + its ⌘? binding (`MariasNotebookApp.swift`). *(wire to real hosted help later)*
- [x] Wire ⌘F → the app-wide search sheet (`RootView` observes `.focusSearch` → `isShowingSearch`).
- [x] Add `SidebarCommands()` so View ▸ Show/Hide Sidebar (⌃⌘S) exists (`MariasNotebookApp.swift`).
- [x] Remove the hand-rolled ⌘W Close; rely on SwiftUI's automatic Close (`MariasNotebookApp.swift`).
- [x] Title the detail windows with their object (`StudentDetailWindowHost`/`WorkDetailWindowHost`/`LessonDetailWindowHost` → `.navigationTitle`).
- [ ] Move the sync/database troubleshooting toggles out of the Help menu → **deferred to Phase 2** (folded into the Settings rebuild, with confirmation gating).
- [x] Made default window size (1000×720) ≥ the enforced minimum so a new window isn't snapped wider. Full removal of the `EnsureResizableWindow` AppKit hack → **deferred to Phase 3** (window-chrome rework; keep `SheetWindowResizer`).
- [x] Replaced "Tap" → platform-aware "Click" + `cursorarrow.click` glyph on macOS via new `Utils/PlatformVerb.swift`. Files: `SchoolCalendarSettingsView`, `GoingOutRootView`, `ClassroomSharingView` (×2), `ProcedureDetailView`, `PresentationNotesSectionUnified`.
- [x] Set `NSHumanReadableCopyright` (About-window copyright) in both app build configs.

**Phase 0 verified:** macOS + iOS both BUILD SUCCEEDED, zero warnings (2026-06-28).

## Post-phase adversarial review (2026-06-30) — corrections
A 25-agent review of the five commits confirmed 13 findings; fixes applied:
- **⌘F / quick-capture commands rearchitected to `@FocusedValue`** (new `AppCore/AppCommands.swift`: `FileNewCommands` + `FindCommands`). Fixes three confirmed defects of the notification/router-flag approach: double-handling with `DebouncedSearchField`'s old `.focusSearch` observer (removed), the sheet opening in every main window at once, and stranded one-shot trigger flags when no main window exists (menu items now disable instead). `triggerNewTodo`/`triggerNewNote` removed from AppRouter; presentation-draft creation factored into one `RootView.createPresentationDraft()`.
- **"New Window" now calls `openWindow(id:)` directly** (works with zero windows open; got ⌃⌘N); `.openNewWindow` + `.focusSearch` notification names deleted.
- **File ▸ New items normalized with ellipses** (all open sheets needing input).
- Radial-button macOS hint trimmed to result-only ("Opens the command bar."); Sync Now announces a value only while syncing; Auto-Backup toggle got a real VoiceOver title; Search tooltip made informative; Advanced disclosure font no longer cascades into child controls.
- **Tap sweep completed** (8 more strings: BookClub, Community, TodoEditSheet, APIKey, Meeting/NoteTemplate, StoryDetail, CloudKitStatus recovery text, WorkLifecycleTip) — `PlatformVerb.tapLowercased` now in use.
- **Gesture-phrased VoiceOver hints fixed (2026-06-30):** all 18 "Double tap …"/"swipe/drag …" hints reworded to result-only phrasing per Apple's hint guideline (VoiceOver supplies its own per-platform activation instructions) — correct on macOS *and* better on iOS, no platform helper needed. Files: AttendanceCard, AgendaItemRows, GroupedWorkListRows, TodayViewListRows, TemplatePickerView, NoteEditorStudentSelection, ClassChecklistSmartCell, QuickNoteGlassButton (hint branches unified).
- **Still pre-existing / untouched:** ⌘N quadruple-binding (menu New Lesson vs screen-local New Student/New Todo buttons) pre-dates the branch.

## Phase 1 — Accessibility baseline + radial-menu compliance
- [x] Radial menu kept and made compliant: 5 actions added to File ▸ New with ⌃⌘P/R/T/K shortcuts (via new `AppRouter.triggerNewTodo`/`triggerNewNote` + RootView handlers); macOS `.contextMenu` (right-click) on the button; per-action `.accessibilityAction(named:)` + "Open Command Bar"; de-touched the accessibility hint on macOS. (`QuickNoteGlassButton.swift`, `MariasNotebookApp.swift`, `AppRouter.swift`, `RootView.swift`)
- [x] Honor Reduce Motion on macOS in `adaptiveWithAnimation` (`AdaptiveAnimationModifier.swift` now checks `NSWorkspace…ShouldReduceMotion`).
- [x] Accessibility labels/state: "Sync Now → Syncing/Idle" (`accessibilityValue`) and launch spinners (`accessibilityElement(.combine)`) done. Today's date chevrons now identify "Previous School Day" and "Next School Day" and provide matching macOS help text.
- [~] `.help()` tooltips: QuickNote button + global Search button done. Broader icon-only tooltip + hover/pointer-style sweep → folded into Phase 5 polish.

**Phase 1 verified:** macOS + iOS both BUILD SUCCEEDED, zero warnings (2026-06-29).

## Phase 2 — Settings as a real Settings window
- [x] **Relocated troubleshooting controls out of the Help menu** (completes the Phase 0 deferral): "Enable CloudKit Sync" was a duplicate of the existing Data & Sync "Enable iCloud Sync" toggle → removed; "Allow Local Store Fallback" (macOS) + "Use In-Memory Store" → moved into a new **Advanced** disclosure in Settings → Database → Maintenance (`DatabaseMaintenanceCard`), the in-memory option now confirmation-gated. Help menu reduced to a `#if DEBUG` reset.
- [x] Add the `Settings { SettingsView() }` scene under `#if os(macOS)` and restore the standard App → Settings / ⌘, behavior. The existing in-window route remains available for iOS.
- [x] Rebuild the macOS Settings presentation with native controls. Settings groups use `GroupBox`; age, lesson-planning, AI model, CloudKit, attendance-email, template, and database-summary controls use aligned `LabeledContent`, native disclosure groups, checkboxes, pickers, and compact actions. iPhone/iPad retain their existing layouts; custom warning, progress, sharing, and backup workflow surfaces remain intentionally styled because they communicate state rather than simple preferences.

**Phase 2 slice verified:** macOS + iOS both BUILD SUCCEEDED, zero warnings (2026-06-29).

## Phase 3 — The native shell (keystone)
- [x] Drop `.windowStyle(.hiddenTitleBar)`; adopt a real title bar + unified toolbar app-wide.
- [x] Move Search / sync / school-year controls from the corner overlay into `.toolbar`; set per-screen `.navigationTitle`; reserve `ViewHeader` for iOS. Main and feature-level controls now use native macOS toolbars, while iPhone/iPad retain their existing page headers.
- [x] Add toolbar customization + `.windowToolbarStyle(.unified)`.
- [~] Route record open/edit to their windows (`openWindow`) instead of fitted modal sheets; reserve sheets for confirmations. **Done:** Work, Student, Lesson, and Presentation detail have native macOS window scenes; Today, Student detail, Presentations, and app-wide student deep links route those detail opens to windows on macOS. **Remaining:** sweep secondary record sheets (notes, meetings, files, reports) and decide which deserve independent windows.

**Phase 3 implementation note (2026-07-07):** macOS build validation is currently blocked before completion by SDK/API drift unrelated to this phase: the local Xcode reports macOS SDK 26.5 while the project targets macOS 27.0, and compilation fails in AI/Speech sources on missing `PrivateCloudComputeLanguageModel`, `ContextOptions`, `LanguageModelError`, and `@diagnose`.

**Focused toolbar passes (2026-07-10):** Schedules, Procedures, Checklist, Projects, Supplies, Logs, Resources, Community, Lessons, and Open Work now use native macOS titles/toolbars while retaining their existing iOS page headers. Resource selection actions collapse into a toolbar menu; Community, Lessons, and Open Work use native toolbar search.

## Phase 4 — Native data browsers
- [~] Convert tappable cards to real `Button`s (keyboard focus, focus ring, VoiceOver trait, pointer cursor). **Done:** the shared student roster/needs-lesson grid plus Topics, Resources, student Documents, Stories, Book Club packets, recent observations, resource list rows, and student project/report cards use plain-styled native buttons while preserving their visual design and context menus. **Remaining:** continue feature-by-feature, excluding drag surfaces and cards with nested controls until they can be safely redesigned.
- [ ] Sortable `Table` for Students / Lessons / Logs (keep card grid as an option).
- [ ] Native drag-and-drop reorder for the student grid (replace the long-press DragGesture).

## Phase 5 — Depth & ongoing polish
- [ ] Typography sweep → semantic / `ScaledFont` tokens; raise sub-10pt labels (Dynamic Type).
- [ ] Undo for destructive deletes (UndoManager + the unused `ToastService.undoAction`).
- [~] Dark Mode / contrast color fixes: **amber status colors now adaptive** via new `Components/Color+Adaptive.swift` `Color(light:dark:)` helper — `AppColors.attention` + `.brewing` get a brighter Dark Mode variant (verified macOS + iOS, 0 warnings, 2026-06-29). **Deliberately skipped:** card shadows (naive `Color.primary` swap → white glow in Dark Mode; needs a material/separator approach), and the floating-button gradient (it's the button's visual identity — would change the look the user chose to keep).
- [x] Misc polish landed: native `.controlSize(.small)` on the Auto-Backup toggle (was a blurry `.scaleEffect(0.8)`); real `ProgressView` for AppSearchView's "Building index…" (was a static empty-state); Return now submits the New Todo form (`.keyboardShortcut(.defaultAction)`). Verified macOS + iOS, 0 warnings (2026-06-30).
- [ ] Optional: MenuBarExtra + Dock menu quick capture; window state restoration; background-work notifications/Dock badge; localization scaffolding.

---

Full evidence (file:line per finding) lives in the audit report. Ranking weighs breadth × severity for the Mac experience, not raw effort.
