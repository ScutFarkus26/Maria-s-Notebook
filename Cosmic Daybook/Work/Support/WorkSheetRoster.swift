// WorkSheetRoster.swift
// The children Quick New Work and the practice sheets offer, and which of the
// children a sheet was opened with it keeps, apart from the views so the
// rules can be tested.

import Foundation

enum WorkSheetRoster {

    /// The children a practice sheet offers: the enrolled roster less the
    /// hidden test students. The sheets used to read the enrolled roster
    /// alone, so a hidden test student was offered (bug hunt 2026-11-03 #38).
    static func students(
        enrolled: [CDStudent], testStudents: TestStudentVisibility.Value
    ) -> [CDStudent] {
        testStudents.visible(enrolled)
    }

    /// The children a sheet was opened with that it keeps selected: only
    /// those on the roster it shows. The Checklist or the command bar can name
    /// a child the chips never show, a hidden test student or one who has
    /// left, who then couldn't be taken off: work or practice was saved for
    /// her unseen, or Create failed naming a child who wasn't on the list
    /// (bug hunt 2026-11-03 #41).
    static func keptPrefill(_ ids: Set<UUID>, roster: [CDStudent]) -> Set<UUID> {
        ids.intersection(roster.compactMap(\.id))
    }
}
