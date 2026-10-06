import Foundation
import Testing
@testable import CosmicDaybook

/// Set Up Classroom Sharing takes every classroom-share type, and the summary
/// counts them all: the list is built from `CoreDataStack.sharedEntityNames`, so
/// a type added to the share can't be left out of either (2026-10-05 hunt, #57).
@Suite("Classroom share setup list")
struct ClassroomShareSetupListTests {

    @Test("Setup's list is every classroom-share type, once each, students first")
    func listMatchesTheShare() {
        let names = ClassroomShareSetupReport.orderedEntityNames
        #expect(Set(names) == CoreDataStack.sharedEntityNames)
        #expect(names.count == CoreDataStack.sharedEntityNames.count)
        #expect(names.first == "Student")
        #expect(names.prefix(2) == ["Student", "AttendanceRecord"])
    }
}
