import CoreData
import Foundation

#if DEBUG
#endif
private var studentsAll: [CDStudent] {
    #if DEBUG
    assertionFailure(
        "NotesHelpers: 'studentsAll' is unavailable. Pass [CDStudent] explicitly into the helper (Option A)."
    )
    #endif
    return []
}

// MARK: - CDNote helpers
extension CDNote {
    @MainActor
    /// Returns true if this note applies to the given student based on its scope.
    /// `.all` applies to any student attached to the parent (enforced by caller).
    /// `.student(id)` applies when id matches.
    /// `.students(ids)` applies when ids contains `studentID`.
    func applies(to studentID: UUID) -> Bool {
        switch scope {
        case .all:
            return true
        case .student(let id):
            return id == studentID
        case .students(let ids):
            return ids.contains(studentID)
        }
    }
}

// MARK: - Sorting rule
@MainActor
private func notesSortedNewestFirst(_ notes: [CDNote]) -> [CDNote] {
    notes.sorted { lhs, rhs in
        let lhsUpdated = lhs.updatedAt ?? .distantPast
        let rhsUpdated = rhs.updatedAt ?? .distantPast
        if lhsUpdated != rhsUpdated { return lhsUpdated > rhsUpdated }
        return (lhs.createdAt ?? .distantPast) > (rhs.createdAt ?? .distantPast)
    }
}
