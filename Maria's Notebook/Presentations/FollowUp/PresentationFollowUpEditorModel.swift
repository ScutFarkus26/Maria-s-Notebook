import CoreData
import Foundation
import Observation

@Observable
@MainActor
final class PresentationFollowUpEditorModel {
    enum Scope: Hashable {
        case allChildren
        case child(NSManagedObjectID)
    }

    private(set) var scope: Scope = .allChildren
    private(set) var selectedAction: PresentationFollowUpAction?
    private(set) var hasMixedActions = false
    private(set) var selectedSupport: PresentationFollowUpSupport?
    private(set) var reviewAt: Date?

    func setScope(_ scope: Scope, rows: [CDLessonPresentation]) {
        self.scope = scope
        synchronize(from: rows)
    }

    func rowsInScope(from rows: [CDLessonPresentation]) -> [CDLessonPresentation] {
        let openRows = rows.filter(\.hasOpenFollowUp)

        switch scope {
        case .allChildren:
            return openRows
        case .child(let objectID):
            return openRows.filter { $0.objectID == objectID }
        }
    }

    func synchronize(from rows: [CDLessonPresentation]) {
        if case .child(let objectID) = scope,
           !rows.contains(where: { $0.objectID == objectID }) {
            scope = .allChildren
        }

        let scopedRows = rowsInScope(from: rows)
        guard let firstRow = scopedRows.first else {
            clearSelection()
            return
        }

        let actions = Set(scopedRows.compactMap(\.followUpAction))
        hasMixedActions = actions.count > 1
        selectedAction = actions.count == 1 ? actions.first : nil

        guard let selectedAction else {
            selectedSupport = nil
            reviewAt = nil
            return
        }

        if selectedAction == .planSupport {
            let supports = Set(scopedRows.map { $0.followUpSupport ?? .represent })
            selectedSupport = supports.count == 1 ? supports.first : nil
        } else {
            selectedSupport = nil
        }

        if selectedAction == .checkWork,
           scopedRows.dropFirst().allSatisfy({ $0.followUpReviewAt == firstRow.followUpReviewAt }) {
            reviewAt = firstRow.followUpReviewAt
        } else {
            reviewAt = nil
        }
    }

    @discardableResult
    func selectAction(
        _ action: PresentationFollowUpAction,
        rows: [CDLessonPresentation],
        reviewAt: Date? = nil,
        support: PresentationFollowUpSupport? = nil,
        calendar: Calendar = AppCalendar.shared,
        persist: () -> Bool
    ) -> Bool {
        let affectedRows = rowsInScope(from: rows)
        guard !affectedRows.isEmpty else {
            synchronize(from: rows)
            return true
        }

        let snapshots = affectedRows.map(FollowUpBundleSnapshot.init)
        selectedAction = action
        hasMixedActions = false
        selectedSupport = action == .planSupport ? (support ?? .represent) : nil
        self.reviewAt = action == .checkWork
            ? reviewAt.map(calendar.startOfDay(for:))
            : nil

        PresentationFollowUpService.setAction(
            action,
            for: affectedRows,
            reviewAt: reviewAt,
            support: support,
            calendar: calendar
        )

        guard persist() else {
            snapshots.forEach { $0.restore() }
            synchronize(from: rows)
            return false
        }

        synchronize(from: rows)
        return true
    }
}

private extension PresentationFollowUpEditorModel {
    func clearSelection() {
        selectedAction = nil
        hasMixedActions = false
        selectedSupport = nil
        reviewAt = nil
    }

    struct FollowUpBundleSnapshot {
        let row: CDLessonPresentation
        let actionRaw: String?
        let reviewAt: Date?
        let resolvedAt: Date?
        let resolutionRaw: String?
        let updatedAt: Date?
        let evidenceRaw: String?
        let note: String?
        let supportRaw: String?

        init(row: CDLessonPresentation) {
            self.row = row
            actionRaw = row.followUpActionRaw
            reviewAt = row.followUpReviewAt
            resolvedAt = row.followUpResolvedAt
            resolutionRaw = row.followUpResolutionRaw
            updatedAt = row.followUpUpdatedAt
            evidenceRaw = row.followUpEvidenceRaw
            note = row.followUpNote
            supportRaw = row.followUpSupportRaw
        }

        func restore() {
            row.followUpActionRaw = actionRaw
            row.followUpReviewAt = reviewAt
            row.followUpResolvedAt = resolvedAt
            row.followUpResolutionRaw = resolutionRaw
            row.followUpUpdatedAt = updatedAt
            row.followUpEvidenceRaw = evidenceRaw
            row.followUpNote = note
            row.followUpSupportRaw = supportRaw
        }
    }
}
