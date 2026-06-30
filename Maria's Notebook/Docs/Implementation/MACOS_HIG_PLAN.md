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

## Phase 1 — Accessibility baseline + radial-menu compliance
- [x] Radial menu kept and made compliant: 5 actions added to File ▸ New with ⌃⌘P/R/T/K shortcuts (via new `AppRouter.triggerNewTodo`/`triggerNewNote` + RootView handlers); macOS `.contextMenu` (right-click) on the button; per-action `.accessibilityAction(named:)` + "Open Command Bar"; de-touched the accessibility hint on macOS. (`QuickNoteGlassButton.swift`, `MariasNotebookApp.swift`, `AppRouter.swift`, `RootView.swift`)
- [x] Honor Reduce Motion on macOS in `adaptiveWithAnimation` (`AdaptiveAnimationModifier.swift` now checks `NSWorkspace…ShouldReduceMotion`).
- [~] Accessibility labels/state: "Sync Now → Syncing/Idle" (`accessibilityValue`) and launch spinners (`accessibilityElement(.combine)`) done. **Today date chevrons deferred** — `TodayViewHeader.swift` has unrelated uncommitted WIP; add the two labels once that's committed/stashed.
- [~] `.help()` tooltips: QuickNote button + global Search button done. Broader icon-only tooltip + hover/pointer-style sweep → folded into Phase 5 polish.

**Phase 1 verified:** macOS + iOS both BUILD SUCCEEDED, zero warnings (2026-06-29).

## Phase 2 — Settings as a real Settings window
- [x] **Relocated troubleshooting controls out of the Help menu** (completes the Phase 0 deferral): "Enable CloudKit Sync" was a duplicate of the existing Data & Sync "Enable iCloud Sync" toggle → removed; "Allow Local Store Fallback" (macOS) + "Use In-Memory Store" → moved into a new **Advanced** disclosure in Settings → Database → Maintenance (`DatabaseMaintenanceCard`), the in-memory option now confirmation-gated. Help menu reduced to a `#if DEBUG` reset.
- [ ] Add the `Settings { SettingsView() }` scene under `#if os(macOS)`; drop the manual `.appSettings` ⌘, override. **BLOCKED/needs care:** (1) heavily touches `SettingsView+Sections.swift`, which has uncommitted WIP; (2) needs runtime verification (open app, ⌘,, confirm standalone window + in-window route superseded) — build-only verification is insufficient. Do after the Settings WIP is committed/stashed.
- [ ] Rebuild panes with `Form`/`.formStyle(.grouped)`/`LabeledContent`; drop the rounded-card chrome and the `.scaleEffect(0.8)` toggle hack. Same WIP-collision caveat.

**Phase 2 slice verified:** macOS + iOS both BUILD SUCCEEDED, zero warnings (2026-06-29).

## Phase 3 — The native shell (keystone)
- [ ] Drop `.windowStyle(.hiddenTitleBar)`; adopt a real title bar + unified toolbar app-wide.
- [ ] Move Search / sync / school-year controls from the corner overlay into `.toolbar`; set per-screen `.navigationTitle`; reserve `ViewHeader` for iOS.
- [ ] Add toolbar customization + `.windowToolbarStyle(.unified)`.
- [ ] Route record open/edit to their windows (`openWindow`) instead of fitted modal sheets; reserve sheets for confirmations.

## Phase 4 — Native data browsers
- [ ] Convert tappable cards to real `Button`s (keyboard focus, focus ring, VoiceOver trait, pointer cursor).
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
