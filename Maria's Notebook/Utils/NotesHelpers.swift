import CoreData
import Foundation

#if DEBUG
/// Temporary fallback to satisfy compilation in helpers. Do NOT rely on this.
/// Option A: Pass `[Student]` explicitly into NotesHelpers functions instead of using `studentsAll`.
/// If you see this assertion, update the caller to pass `students` explicitly.
#endif
private var studentsAll: [Student] {
    #if DEBUG
    assertionFailure(
        "NotesHelpers: 'studentsAll' is unavailable. Pass [Student] explicitly into the helper (Option A)."
    )
    #endif
    return []
}

// MARK: - Note helpers
extension Note {
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
private func notesSortedNewestFirst(_ notes: [Note]) -> [Note] {
    notes.sorted { lhs, rhs in
        let lhsUpdated = lhs.updatedAt ?? .distantPast
        let rhsUpdated = rhs.updatedAt ?? .distantPast
        if lhsUpdated != rhsUpdated { return lhsUpdated > rhsUpdated }
        return (lhs.createdAt ?? .distantPast) > (rhs.createdAt ?? .distantPast)
    }
}

// MARK: - Lesson filtering
extension Lesson {
    @MainActor
    /// Notes visible to a specific student: includes `.all` and any note scoped to that student.
    /// Sorted newest first (updatedAt, then createdAt).
    func notesVisible(to studentID: UUID) -> [Note] {
        let allNotes = (notes?.allObjects as? [CDNote]) ?? []
        let filtered = allNotes.filter { note in
            switch note.scope {
            case .all:
                return true
            case .student(let id):
                return id == studentID
            case .students(let ids):
                return ids.contains(studentID)
            }
        }
        return notesSortedNewestFirst(filtered)
    }
}
