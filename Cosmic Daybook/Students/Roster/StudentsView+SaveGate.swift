// StudentsView+SaveGate.swift
// Which saves can move the roster's change tokens.
//
// Split from the view, which is past SwiftLint's type-length limit, the same
// way `WorksAgendaView+DataHelpers.swift` holds the agenda's gate.

import CoreData

extension StudentsView {
    /// The tables `refreshChangeTokens` reads: attendance (its count and its
    /// latest `modifiedAt`), presentations and lessons, each counted. The
    /// tokens come from these alone, so a save touching none of them cannot
    /// move one.
    nonisolated static let changeTokenEntityNames: Set<String> = ["AttendanceRecord", "LessonAssignment", "Lesson"]

    /// True when a `NSManagedObjectContextDidSave` could move a change token
    /// (fails open on an unrecognised payload — see
    /// `ManagedObjectChangeScope.saveTouches`).
    nonisolated static func saveTouchesChangeTokens(_ userInfo: [AnyHashable: Any]?) -> Bool {
        ManagedObjectChangeScope.saveTouches(changeTokenEntityNames, in: userInfo)
    }
}
