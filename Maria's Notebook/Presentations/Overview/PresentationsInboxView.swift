// PresentationsInboxView.swift
// Top half of the Presentations planner: composes the chip-row + ready grid
// (ReadyToPresentSection) with the students-needing-lessons sidebar. The
// screen-level header (title, search, Filters, Suggest Next) lives in
// PresentationsHeader.swift and is rendered by PresentationsView+Body above
// this view.

import SwiftUI
import CoreData
import UniformTypeIdentifiers
import OSLog

struct PresentationsInboxView: View {
    private static let logger = Logger.presentations

    let viewModel: PresentationsViewModel
    /// Per-assignment blocking results with per-student readiness.
    let blockingResults: [UUID: BlockingAlgorithmEngine.BlockingCheckResult]
    let getBlockingWork: (CDLessonAssignment) -> [UUID: CDWorkModel]
    let filteredSnapshot: (CDLessonAssignment) -> LessonAssignmentSnapshot
    let missWindow: PresentationsMissWindow
    @Binding var missWindowRaw: String

    let coordinator: PresentationsCoordinator
    let filterState: PresentationsFilterState

    /// Currently highlighted "Suggest Next" lesson, owned by PresentationsView and
    /// passed down so the section can scroll/highlight without owning the action.
    let suggestedLessonID: UUID?

    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(sortDescriptors: []) var lessonAssignments: FetchedResults<CDLessonAssignment>

    var body: some View {
        HStack(spacing: 0) {
            ReadyToPresentSection(
                viewModel: viewModel,
                blockingResults: blockingResults,
                getBlockingWork: getBlockingWork,
                filteredSnapshot: filteredSnapshot,
                coordinator: coordinator,
                filterState: filterState,
                suggestedLessonID: suggestedLessonID
            )
            Divider()
            studentsNeedingLessonsSidebar
        }
        .overlay { dropTargetOverlay }
        .dropDestination(for: String.self, action: handleDrop, isTargeted: { targeted in
            adaptiveWithAnimation { coordinator.setInboxTargeted(targeted) }
        })
    }

    @ViewBuilder
    private var dropTargetOverlay: some View {
        if coordinator.isInboxTargeted {
            Color.accentColor.opacity(UIConstants.OpacityConstants.accent)
                .allowsHitTesting(false)

            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.large)
                .stroke(Color.accentColor, lineWidth: UIConstants.StrokeWidth.extraThick)
                .padding(AppTheme.Spacing.xxsmall)
                .allowsHitTesting(false)

            VStack {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(Color.accentColor)
                Text("Drop to Unschedule")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.accentColor)
            }
            .allowsHitTesting(false)
        }
    }

    private func handleDrop(_ items: [String], _ location: CGPoint) -> Bool {
        guard let str = items.first,
              let payload = UnifiedCalendarDragPayload.parse(str),
              case .presentation(let id) = payload,
              let la = lessonAssignments.first(where: { $0.id == id }),
              la.scheduledFor != nil else { return false }
        la.unschedule()
        viewContext.safeSave()
        return true
    }
}
