import Foundation
import Testing
@testable import CosmicDaybook

/// The review of the 2026-11-05 fixes (W12): only an object whose keys are
/// all whole numbers reads as one of PHP's keyed lists. A single child sent
/// as an object where the roster's list should be is a page that changed, not
/// an empty class whose children all read as "not matched".
@Suite("ParentLocker fixes 2026-11-05 D: the wire")
@MainActor
struct ParentLockerFix1105DWire {

    private static let course = ParentLockerCourse(
        courseID: 6301, name: "Upper Elementary", period: 1, attendanceReportID: "990301"
    )

    private static func student(_ id: Int, _ first: String) -> ParentLockerJSON {
        .object([
            "student_id": .int(id), "first_name": .string(first), "last_name": .string("Lee"),
            "attendance": .object(["comment": .string(""), "confirmed": .bool(false)])
        ])
    }

    @Test("W12: only an object keyed by whole numbers is a list")
    func onlyNumberKeyedObjectsAreLists() {
        let keyed = ParentLockerJSON.object(["10": .string("c"), "2": .string("b"), "0": .string("a")])
        #expect(keyed.listValue == [.string("a"), .string("b"), .string("c")])
        #expect(ParentLockerJSON.array([.int(1)]).listValue == [.int(1)])
        #expect(ParentLockerJSON.object([:]).listValue == [], "PHP's empty keyed list")
        #expect(Self.student(1, "Al").listValue == nil, "one child's fields aren't a list of children")
        #expect(ParentLockerJSON.object(["0": .string("a"), "name": .string("b")]).listValue == nil)
        #expect(ParentLockerJSON.object(["1.5": .string("a")]).listValue == nil)
        #expect(ParentLockerJSON.string("a").listValue == nil)
    }

    @Test("W12: a single child sent as an object where the class list should be reads as the page changed")
    func singleObjectStudentsIsPageChanged() throws {
        #expect(throws: ParentLockerError.pageChanged) {
            try ParentLockerRoster(reply: .object([
                "students": Self.student(1, "Al"),
                "attendance_settings": .array([])
            ]), course: Self.course)
        }
        // A keyed list of children still reads, in key order.
        let roster = try ParentLockerRoster(reply: .object([
            "students": .object(["1": Self.student(2, "Bo"), "0": Self.student(1, "Al")])
        ]), course: Self.course)
        #expect(roster.students.map(\.firstName) == ["Al", "Bo"])
    }

    @Test("W12: marks in a shape that isn't a list read as the page changed, not as no marks")
    func unreadableMarksArePageChanged() {
        #expect(throws: ParentLockerError.pageChanged) {
            try ParentLockerRoster(reply: .object([
                "students": .array([Self.student(1, "Al")]),
                "attendance_settings": .object(["present": .string("P")])
            ]), course: Self.course)
        }
    }
}
