// CurriculumMapEngine+OwnWork.swift
// Which work rows count for a child on the Three-Year View. Kept with the
// engine's other pure rules; the cell sheet reads it too, so a cell and the
// list behind it never disagree.

import Foundation

nonisolated extension CurriculumMapEngine {

    /// The work rows that count for a child, out of every row that names her:
    /// the rows she owns, every shared row she is on (project work: one row,
    /// several children, so no copy of hers sits beside it), and, on a lesson
    /// where she owns nothing, every other row that names her. Linked copies
    /// each list the whole group, so a classmate's copy names her without
    /// being hers. `WorkVisibility`'s rule, not `gatingWork`'s, which would
    /// drop the shared row beside her own. Order is kept.
    static func ownWork(for studentID: UUID, among works: [CurriculumWorkRef]) -> [CurriculumWorkRef] {
        let naming = works.filter { $0.ownerID == studentID || $0.studentIDs.contains(studentID) }
        let ownedLessons = Set(naming.filter { $0.ownerID == studentID }.map(\.lessonID))
        return naming.filter {
            $0.ownerID == studentID || $0.isSharedRow || !ownedLessons.contains($0.lessonID)
        }
    }
}
