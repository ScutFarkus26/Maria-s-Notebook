// PresentationPlannerCard+ShowFirst.swift
// A strip card's "to check first" pieces: the chip that opens a child's
// earlier open work, and the card's count line (`WorkToShowFirst`).
//
// Split from the card for SwiftLint's type-length limit; the state these read
// is declared in PresentationPlannerCard.swift.

import CoreData
import SwiftUI

extension PresentationPlannerCard {

    /// The children whose chips the card draws: those on it that the roster
    /// has (`studentChipsRow`). The "to check first" count and action read
    /// only these.
    var chippedStudentIDs: [UUID] {
        let known = Set(cachedStudents.compactMap(\.id))
        return snapshot.studentIDs.filter(known.contains)
    }

    /// Open earlier work across the children whose chips are drawn, for the
    /// card's line, its spoken label and its VoiceOver action.
    var showFirstCount: Int {
        Self.showFirstCount(of: chippedStudentIDs, in: workToShowFirst)
    }

    static func showFirstCount(of studentIDs: [UUID], in marks: WorkToShowFirst.ByChild) -> Int {
        studentIDs.reduce(0) { $0 + (marks[$1]?.count ?? 0) }
    }

    /// A chip with earlier work open is a button that lists it; the others
    /// are plain, so a tap on them still opens the presentation.
    @ViewBuilder
    func studentChip(for student: CDStudent, sid: UUID) -> some View {
        if let items = workToShowFirst[sid], !items.isEmpty, let actions = showFirstActions {
            Button {
                showFirstChild = sid
            } label: {
                chipLabel(for: student, sid: sid)
            }
            .buttonStyle(.plain)
            #if os(macOS)
            .help(WorkToShowFirst.helpText(for: items))
            #endif
            .popover(isPresented: showFirstBinding(for: sid), arrowEdge: .bottom) {
                WorkToShowFirstPopover(
                    childName: student.shortName,
                    items: items,
                    onOpenWork: { workID in
                        showFirstChild = nil
                        actions.openWork(workID)
                    },
                    onCheckToday: { item in
                        showFirstChild = nil
                        actions.checkToday(item)
                    }
                )
            }
        } else {
            chipLabel(for: student, sid: sid)
        }
    }

    /// The card's VoiceOver action, only when a drawn chip has a list to open.
    @ViewBuilder
    var showFirstAccessibilityAction: some View {
        if showFirstCount > 0 {
            Button("Show work to check first") {
                showFirstChild = chippedStudentIDs.first { workToShowFirst[$0] != nil }
            }
        }
    }

    private func showFirstBinding(for sid: UUID) -> Binding<Bool> {
        Binding(
            get: { showFirstChild == sid },
            set: { if !$0, showFirstChild == sid { showFirstChild = nil } }
        )
    }

    // MARK: - Work to check first

    /// The chip's mark: a glyph as well as the amber ring.
    var showFirstMark: some View {
        Image(systemName: WorkToShowFirst.glyph)
            .font(.caption2.weight(.bold))
            .imageScale(.small)
            .foregroundStyle(AppColors.color(for: .brewing))
            .accessibilityLabel("Has work to check first")
    }

    @ViewBuilder
    var showFirstLine: some View {
        let count = showFirstCount
        if count > 0 {
            // Tighter than a Label's icon gap, to sit under the chips.
            HStack(spacing: 4) {
                Image(systemName: WorkToShowFirst.glyph)
                    .accessibilityHidden(true)
                Text(WorkToShowFirst.countLine(count))
                    .lineLimit(1)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(AppColors.color(for: .brewing))
        }
    }
}

extension PresentationPlannerCard {
    /// What the "to check first" list can do from a strip card.
    struct ShowFirstActions {
        let openWork: (UUID) -> Void
        /// Puts the work on today's checks (`WorkToShowFirst.checkToday`).
        let checkToday: (WorkToShowFirst.Item) -> Void
    }
}
