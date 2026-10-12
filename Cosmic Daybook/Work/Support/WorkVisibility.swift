//
//  WorkVisibility.swift
//  Cosmic Daybook
//
//  Whose each work row is, for a screen that reads many rows at once.
//

import CoreData
import Foundation

/// Whose each row is, for a screen that reads many rows at once: the
/// checklist's cells, the Work column and its child filter, the Works log.
///
/// `WorkGrouping.visibleWork`'s rule, decided per linked group: a set of
/// linked copies counts only for each copy's owner, and a genuinely shared
/// row (one row, several children, as project work is) counts for everyone
/// on it. Reading every row as shared made a classmate's copy count as the
/// child's own wherever she was named on it (bug hunt 2026-10-11, #18 and
/// #19). `visibleWork` fetches each row's lesson per call; this takes the
/// rows once, so a screen's worth costs one fetch, and remembers each row's
/// group.
///
/// Not `gatingWork`'s rule, which keeps only the rows a child owns whenever
/// she owns any, and so drops a real shared row beside her own work.
final class WorkVisibility {
    private let rowsByLesson: [String: [CDWorkModel]]
    private var membersByRow: [ObjectIdentifier: [CDWorkModel]] = [:]

    /// - Parameter rows: every row of the lessons the screen reads, open and
    ///   closed: a child's closed copy is what tells her classmate's open copy
    ///   apart from a row she shares.
    init(rows: some Sequence<CDWorkModel>) {
        var byLesson: [String: [CDWorkModel]] = [:]
        for row in rows where !row.isDeleted {
            byLesson[row.lessonID, default: []].append(row)
        }
        rowsByLesson = byLesson
    }

    /// `works`, plus every row on the lessons where one of them names more
    /// than one child, in one fetch. A row naming one child is that child's
    /// whatever else is on its lesson, so its lesson needn't be read.
    convenience init(covering works: [CDWorkModel], in context: NSManagedObjectContext) {
        let lessonIDs = Set(works.filter { WorkGrouping.studentIDs(of: $0).count > 1 }.map(\.lessonID))
        guard !lessonIDs.isEmpty else {
            self.init(rows: works)
            return
        }
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(format: "lessonID IN %@", Array(lessonIDs))
        request.relationshipKeyPathsForPrefetching = ["participants"]
        var seen = Set<ObjectIdentifier>()
        let rows = (works + context.safeFetch(request)).filter { seen.insert(ObjectIdentifier($0)).inserted }
        self.init(rows: rows)
    }

    /// Whether `work` counts as `studentID`'s: she owns it, or she is on it
    /// and owns no row of its group.
    func isVisible(_ work: CDWorkModel, to studentID: UUID) -> Bool {
        guard WorkGrouping.involves(studentID, in: work) else { return false }
        if WorkGrouping.owner(of: work) == studentID { return true }
        return !members(of: work).contains { WorkGrouping.owner(of: $0) == studentID }
    }

    /// The rows made together with `work`, itself included.
    private func members(of work: CDWorkModel) -> [CDWorkModel] {
        let key = ObjectIdentifier(work)
        if let cached = membersByRow[key] { return cached }
        let candidates = (rowsByLesson[work.lessonID] ?? []).filter { $0 !== work }
        let members = WorkGrouping.closure(from: work, among: candidates)
        membersByRow[key] = members
        return members
    }
}
