// Cosmic Daybook/Lessons/LessonsScopeMapView.swift
//
// Scope-and-sequence "Map" view: every sequence is one labeled row, every lesson
// is a small pill on that row, organized into a spine (Area or Great Lesson).
// Tapping a thread row drills into LessonsScopeThreadFocusView.
// Press and hold a row to pick it up, then drag it to reorder within its area.

import SwiftUI
import CoreData

// MARK: - LessonsScopeMapView

struct LessonsScopeMapView: View {
    let lessons: [CDLesson]
    /// Optional area filter (nil = show all areas).
    /// Ignored when `spine == .greatLesson` — the Great Lesson spine is intentionally cross-area.
    let selectedArea: String?
    @Binding var spine: MapSpine
    var isEditing: Bool = false
    let onSelectThread: (ThreadKey) -> Void
    /// Called with the dragged row's area and the new order of that area's *visible*
    /// sequence names. Sequences hidden by the current filter aren't listed and keep
    /// their saved positions.
    var onMoveSequences: ((String, [String]) -> Void)?
    var onConfigureTrack: ((ThreadKey) -> Void)?
    var onReorderSections: ((ThreadKey) -> Void)?
    var onFocusArea: ((String) -> Void)?
    var onClearAreaFocus: (() -> Void)?

    /// How long a row has to be held before it can be dragged. Deliberately long:
    /// this map is the curriculum's spine, and a reorder nudged in by accident is
    /// easy to miss and tedious to undo. Edit mode uses `editHoldDuration` instead,
    /// since the user has already declared intent by turning it on.
    static let holdToMoveDuration: TimeInterval = 5
    static let editHoldDuration: TimeInterval = 0.15

    private static let mapSpace = "lessonsScopeMap"

    /// Row currently lifted out of the stack, as `rowID(section:row:)`.
    @State private var pickedUpRowID: String?
    @State private var pickedUpName: String = ""
    /// Row the lifted one would land on if released now.
    @State private var hoverRowID: String?
    @State private var rowFrames: [String: CGRect] = [:]
    /// True from the moment a hold succeeds until shortly after the press ends, so the
    /// mouse-up that finishes a move doesn't also register as a tap and drill into the row.
    @State private var moveGestureDidEngage = false

    /// Set while a press is being held on a row and reset the moment it ends — drives
    /// the hold progress bar so a five-second wait doesn't look like a dead click.
    @GestureState(resetTransaction: Transaction(animation: .easeOut(duration: 0.2)))
    private var holdingRowID: String?

    private var hasAreaFocus: Bool {
        guard let selectedArea else { return false }
        return !selectedArea.trimmed().isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                spinePicker

                ForEach(MapSectionBuilder(lessons: lessons, selectedArea: selectedArea)
                    .sections(for: spine)) { section in
                    sectionView(section)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .coordinateSpace(name: Self.mapSpace)
        .onPreferenceChange(MapRowFramePreference.self) { frames in
            // Preference updates land during layout; defer to avoid layout recursion.
            Task { @MainActor in rowFrames = frames }
        }
        .overlay(alignment: .bottom) {
            if pickedUpRowID != nil {
                MapMoveHintBanner(sequenceName: pickedUpName)
            }
        }
    }

    @ViewBuilder
    private func sectionView(_ section: MapSection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(section)
                .padding(.bottom, 2)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(section.rows) { row in
                    threadRow(row, in: section)
                }
            }
        }
    }

    @ViewBuilder
    private func threadRow(_ row: ThreadRowData, in section: MapSection) -> some View {
        let rowID = section.rowID(for: row)
        let isPickedUp = pickedUpRowID == rowID
        let movable = canMove(row, in: section)

        ThreadRow(
            threadKey: row.key,
            lessons: row.lessons,
            color: AppColors.color(forArea: row.key.area),
            isEditing: isEditing,
            hasSections: hasMultipleSections(row: row),
            isPickedUpForMove: isPickedUp,
            isMoveTarget: hoverRowID == rowID && !isPickedUp,
            isHoldingToMove: holdingRowID == rowID,
            canHoldToMove: movable,
            onTap: {
                // A completed hold ends with a mouse-up on the row; that must not
                // count as the click that drills into the thread.
                guard !moveGestureDidEngage else { return }
                onSelectThread(row.key)
            },
            onConfigureTrack: { onConfigureTrack?(row.key) },
            onReorderSections: { onReorderSections?(row.key) }
        )
        .modifier(MapRowFrameReporter(rowID: rowID, space: Self.mapSpace))
        .when(movable) { view in
            view.simultaneousGesture(holdThenDragGesture(row: row, in: section, rowID: rowID))
        }
    }

    // MARK: - Hold-then-drag reordering

    /// Hold to lift a row, then keep dragging in the same press to place it. Sequenced
    /// so the whole move is one gesture — release drops the row where it hovers.
    private func holdThenDragGesture(
        row: ThreadRowData,
        in section: MapSection,
        rowID: String
    ) -> some Gesture {
        let duration = isEditing ? Self.editHoldDuration : Self.holdToMoveDuration
        let hold = LongPressGesture(minimumDuration: duration, maximumDistance: 14)
            .updating($holdingRowID) { pressing, state, transaction in
                state = pressing ? rowID : nil
                transaction.animation = .linear(duration: duration)
            }
        let drag = DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.mapSpace))

        return hold.sequenced(before: drag)
            .onChanged { value in
                switch value {
                case .first(true):
                    beginMove(rowID: rowID, name: row.key.displayName)
                case .second(true, let dragValue?):
                    if pickedUpRowID != rowID {
                        beginMove(rowID: rowID, name: row.key.displayName)
                    }
                    let target = nearestRowID(to: dragValue.location, from: rowID, row: row, in: section)
                    if target != hoverRowID {
                        withAnimation(.easeOut(duration: 0.12)) { hoverRowID = target }
                    }
                default:
                    break
                }
            }
            .onEnded { _ in
                finishMove(row: row, in: section)
            }
    }

    private func beginMove(rowID: String, name: String) {
        guard pickedUpRowID != rowID else { return }
        moveGestureDidEngage = true
        pickedUpName = name
        HapticService.shared.impact(.medium)
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            pickedUpRowID = rowID
        }
    }

    private func finishMove(row: ThreadRowData, in section: MapSection) {
        let landedOn = hoverRowID
        let wasPickedUp = pickedUpRowID != nil
        resetMoveState()
        guard wasPickedUp, let landedOn else { return }
        guard let target = section.rows.first(where: { section.rowID(for: $0) == landedOn }),
              target.key != row.key
        else { return }

        let names = section.movableSequences(in: row.key.area)
        guard let srcIdx = names.firstIndex(of: row.key.sequence),
              let dstIdx = names.firstIndex(of: target.key.sequence)
        else { return }

        var reordered = names
        reordered.move(
            fromOffsets: IndexSet(integer: srcIdx),
            toOffset: dstIdx > srcIdx ? dstIdx + 1 : dstIdx
        )
        onMoveSequences?(row.key.area, reordered)
    }

    private func resetMoveState() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
            pickedUpRowID = nil
            hoverRowID = nil
        }
        // Outlive the mouse-up that ends the gesture, then let clicks drill in again.
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            moveGestureDidEngage = false
        }
    }

    /// The row under the pointer, restricted to rows this one can actually swap with:
    /// same area, real sequence, and close enough vertically to be a deliberate target.
    private func nearestRowID(
        to location: CGPoint,
        from rowID: String,
        row: ThreadRowData,
        in section: MapSection
    ) -> String? {
        var best: (id: String, frame: CGRect)?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for candidate in section.rows where candidate.key.area == row.key.area {
            let candidateID = section.rowID(for: candidate)
            guard candidateID != rowID,
                  canMove(candidate, in: section),
                  let frame = rowFrames[candidateID]
            else { continue }
            let distance = abs(frame.midY - location.y)
            guard distance < bestDistance else { continue }
            bestDistance = distance
            best = (candidateID, frame)
        }
        // Too far from any row to be a deliberate target.
        guard let best, bestDistance <= best.frame.height else { return nil }
        return best.id
    }

    private func canMove(_ row: ThreadRowData, in section: MapSection) -> Bool {
        onMoveSequences != nil && section.canMove(row)
    }

    @ViewBuilder
    private func sectionHeader(_ section: MapSection) -> some View {
        // Area-spine headers double as area filters; Great Lesson headers stay static.
        let isAreaSpine = (spine == .area)
        let canTap = isAreaSpine && (hasAreaFocus ? onClearAreaFocus != nil : onFocusArea != nil)

        Button {
            if !isAreaSpine { return }
            if hasAreaFocus {
                onClearAreaFocus?()
            } else {
                onFocusArea?(section.title)
            }
        } label: {
            HStack(spacing: 6) {
                if isAreaSpine && hasAreaFocus {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .bold))
                } else if let icon = section.icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(isAreaSpine && hasAreaFocus
                     ? "All Areas".uppercased()
                     : section.title.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(0.8)
                if isAreaSpine && hasAreaFocus {
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(section.title.uppercased())
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(section.color)
                }
            }
            .foregroundStyle(isAreaSpine && hasAreaFocus ? Color.secondary : section.color)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canTap)
        .help({
            if !isAreaSpine { return "" }
            return hasAreaFocus ? "Show all areas" : "Focus on \(section.title)"
        }())
    }

    private var spinePicker: some View {
        HStack(spacing: 8) {
            Text("Spine")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(.secondary)

            Picker("Spine", selection: $spine) {
                ForEach(MapSpine.allCases) { option in
                    Label(option.rawValue, systemImage: option.icon).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 260)

            Spacer()
        }
        .padding(.bottom, 4)
    }

    // MARK: - Helpers

    private func hasMultipleSections(row: ThreadRowData) -> Bool {
        let sections = Set(row.lessons.map { $0.section.trimmed() }.filter { !$0.isEmpty })
        return sections.count > 1
    }
}

// MARK: - Move chrome

/// Floats over the map while a row is lifted, so the hold reads as "picked up"
/// rather than "nothing happened".
private struct MapMoveHintBanner: View {
    let sequenceName: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.up.and.down")
                .font(.system(size: 11, weight: .semibold))
            Text("Drag \(sequenceName) into place, then release")
                .font(.system(size: 12, weight: .medium, design: .rounded))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule(style: .continuous).fill(Color.accentColor.opacity(0.92)))
        .padding(.bottom, 16)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .allowsHitTesting(false)
    }
}

// MARK: - Preferences

/// Publishes each row's frame in the map's coordinate space so a drag can tell which
/// row it is over without hit-testing.
private struct MapRowFrameReporter: ViewModifier {
    let rowID: String
    let space: String

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: MapRowFramePreference.self,
                    value: [rowID: proxy.frame(in: .named(space))]
                )
            }
        )
    }
}

private struct MapRowFramePreference: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
