# Design-system migration recipe (2026-09-22)

Consolidation, not redesign: every migrated site renders exactly as before. A value stays the value it was; two sites that differ stay different. `Components/` and `Students/` are the reference; `DesignTokensTests` pins the tokens.

## Tokens — `UIConstants.CornerRadius`

| Literal | Token | | Literal | Token |
|---|---|---|---|---|
| 1 | `hairline` | | 12 | `large` (= `CardStyle.cornerRadius`) |
| 3 | `tiny` | | 14 | `tile` |
| 6 | `small` | | 16 | `extraLarge` |
| 8 | `medium` | | 20 | `hero` |
| 10 | `control` | | 2, 4, 5, 7, 13, 1.5 | no token — leave the literal, list it in the report |

Rule: `cornerRadius: N` → `cornerRadius: UIConstants.CornerRadius.<token>` wherever it appears (`RoundedRectangle`, `.contentShape`, `.background(_, in:)`, `.strokeBorder` overlays, ZStack shapes). A ternary radius (`compact ? 4 : 6`) stays as written.

## Modifiers — `Components/SurfaceModifiers.swift`

`style` defaults to SwiftUI's own default, `.circular`. Copy the shape's `style:` argument verbatim: a shape written without one gets none; `style: .continuous` passes through. Never add or drop it.

| Hand-rolled (before) | After |
|---|---|
| `.background(RoundedRectangle(cornerRadius: R[, style: .continuous]).fill(F))` | `.surface(R, fill: F[, style: .continuous])` |
| the above **immediately followed by** `.overlay(RoundedRectangle(same R, same style).stroke(S[, lineWidth: W]))` | `.surface(R, fill: F, stroke: S[, lineWidth: W][, style: .continuous])` |
| `.clipShape(RoundedRectangle(cornerRadius: R[, style: .continuous]))` | `.clipRounded(R[, style: .continuous])` |
| `.background(Capsule([style: .continuous]).fill(F))` | `.capsuleFill(F[, style: .continuous])` |

`F` and `S` are any `ShapeStyle` (a `Color`, a ternary of colours, `.background.secondary`, a `LinearGradient`). `.stroke(S)` with no `lineWidth` maps to the default (1); keep an explicit `lineWidth: 1` when the site had one.

**Does not map exactly → token only.** Leave the shape hand-rolled and just swap the literal when any of these holds:
- `.background(F, in: RoundedRectangle(…))` / `.background(.ultraThinMaterial, in: …)` (a different modifier, not `_BackgroundModifier`).
- The overlay uses `.strokeBorder`, a `StrokeStyle` (dashed), or a different radius/style from the background.
- The stroke overlay is nested **inside** the background (`.background(shape.fill(…).overlay(shape.stroke(…)))`) or the fill carries `.shadow` — the draw order differs from `background` + `overlay`.
- The shape is a ZStack child, a `.contentShape`, a bare overlay stroke, or `.background { … }` (brace form) — untouched apart from the token.
- `selectableCapsule` was considered and rejected: the selected/unselected capsule appears in five variants, none ten times.

## Families

- `StudentChip(_ label, tint:, isMissing:, leadingSystemImage:, foreground: .tint|.label, onRemove:) { accessory }` — the 16 pt continuous, footnote-semibold, 10 × 6 area chip. Folded: PresentationCard's inline chip (`foreground: .label`), StudentPillsSection (accessory + remove), WorkCard+Compact's `ParticipantChipView` (wrap in `Button … .buttonStyle(.plain)`), the never-called `StudentChip` view in PresentationDetailComponents. Kept apart: `QuickNoteStudentChip` (avatar, subheadline, clip-based capsule) and `DraggableStudentChip` (caption medium, 10 × 5, stroke, drag).
- `StudentCapsuleChip(label:, tint:, isMissing:, isAbsent:, isDoubleBooked:, isHighlighted:, isWaiting:, onTap:)` — the caption2 capsule chip per child; was `ChipView` (Students/Selection) and WorkCard+Pill's `StudentChipView` (the absent-only subset).
- `StatusPill(text:, color:, icon:, metrics:)` with `Metrics.standard | .compact | .emphasized | .mini` — folded `GoingOutStatusBadge` (`.compact`), `WorkflowBadge` (`.emphasized`), `SequenceRecapStateBadge` (`.mini`, label/colour now `SequenceRecapLessonEntry.stateLabel/stateColor`). Kept apart, each renders differently: `StatePill` (stroked, active state), `ProgressionStatusPill` (per-status fill/dash), `LevelBadge` (leading dot), `TagBadge` (rounded rect, tag colours), `ModelBadgeView` (clip-based), `StudentProgressComponents.StatusBadge` (a circle), `ProjectStatusPill` (no fill), `ProjectStandingBadge` (not a view).
- `FilterChip` moved verbatim to `Components/FilterChip.swift` (Lessons and Work bars share it). Kept apart: `TodoFilterChip` (solid fill when on, count slot), `StudentsScopeChips` (10 × 5, secondary tint, counts), `WorkspaceFilterPillRow` (solid fill + count capsule), `FilterMenuChipLabel` (rounded menu label).
- Pill buttons: `AppPillButton` is canonical. `CanonicalPillButton` → `AppPillButton(…, metrics: .snug)` (or an inline `AppPill.Metrics` for custom font/padding); `PillButton` → `AppPillButton(…, metrics: .roomy)`. `SelectablePillButton` kept (solid tint, single 0.3 ring, 14 × 10). `FullWidthStatePillButton` kept (a plain full-width button, not a pill).

## Traps

1. Style defaults: `Capsule()` and `RoundedRectangle(cornerRadius:)` are circular. Do not "normalise" to `.continuous`.
2. `.background(Capsule().fill(…))` in brace form or with a nested `.overlay` is not the capsule shape — leave it.
3. A background whose fill has `.shadow(…)` chained is not a surface; token only.
4. Wrapping: a migrated line over 120 columns is a new SwiftLint `line_length` violation — split the arguments one per line.
5. `SequenceRecapStateBadge`-style badges compute their label from a model: move that logic to a model extension, not into `StatusPill`.
6. Two of the three `StudentChip` structs were private *data* structs (`ChipEntry` now), not views; check `: View` before assuming a member renders.
