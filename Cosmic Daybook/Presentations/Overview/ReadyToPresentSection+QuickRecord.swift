// ReadyToPresentSection+QuickRecord.swift
// Presented, from the row: the everyday case — the whole group, the lesson's
// usual next step — without opening the sheet. The toast carries Undo and
// Details…, which opens How It Went on the same record.

import CoreData
import SwiftUI

extension ReadyToPresentSection {

    /// Rows a child could be given today: not ones still waiting on work, and
    /// not ones already given.
    func canQuickRecord(_ la: CDLessonAssignment, context: BacklogRenderContext) -> Bool {
        context.state != .waitingForWork && context.state != .followUp
            && !la.isPresented && la.lesson != nil && !la.resolvedStudentIDs.isEmpty
    }

    func quickRecord(_ la: CDLessonAssignment) {
        let lessonName = viewModel.lessonTitle(for: la)
        do {
            let receipt = try PresentationQuickRecord.record(
                la,
                lessons: dependencies.lessonCatalog.all,
                context: viewContext,
                saveCoordinator: saveCoordinator
            )
            let names = Dictionary(
                dependencies.roster.all.compactMap { student in student.id.map { ($0, student.shortName) } },
                uniquingKeysWith: { first, _ in first }
            )
            PresentationDetailUtilities.notifyInboxRefresh()
            dependencies.toastService.show(
                PresentationQuickRecord.message(for: receipt, lessonName: lessonName, names: names),
                type: .success,
                duration: 8,
                undoAction: { undoQuickRecord(receipt) },
                action: ToastAction(label: "Details…") {
                    coordinator.showLessonAssignmentDetail(la)
                }
            )
        } catch {
            // The one click took everything back, so a failed follow-up save
            // reads as the recording not happening, not as notes kept.
            let fallback = "Couldn't record the presentation. Nothing was changed. Try again."
            let message = PresentationFailureMessage.message(for: error, fallback: fallback)
            dependencies.toastService.showError(error is PresentationSessionCommit.CommitError ? fallback : message)
        }
    }

    private func undoQuickRecord(_ receipt: PresentationQuickRecord.Receipt) {
        do {
            try PresentationQuickRecord.undo(receipt, context: viewContext, saveCoordinator: saveCoordinator)
            PresentationDetailUtilities.notifyInboxRefresh()
        } catch {
            // The work deletion's own wording ("Couldn't save the change")
            // says less than this.
            let fallback = "Couldn't undo. Try again."
            let message = PresentationFailureMessage.message(for: error, fallback: fallback)
            let isRecordingError = error is ImmediatePresentationRecordingService.RecordingError
            dependencies.toastService.showError(isRecordingError ? message : fallback)
        }
    }
}

/// On the Mac, a Presented button appears at the trailing edge of a row
/// under the pointer. Everywhere, the row's context menu has the same item.
struct QuickPresentedHover: ViewModifier {
    let isEnabled: Bool
    let action: () -> Void

    @State private var isHovering = false

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .overlay(alignment: .trailing) {
                if isEnabled && isHovering {
                    Button(action: action) {
                        Label("Presented", systemImage: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .padding(.trailing, 8)
                    .help("Record it as given today for the children who are here")
                }
            }
            .onHover { isHovering = $0 }
        #else
        content
        #endif
    }
}
