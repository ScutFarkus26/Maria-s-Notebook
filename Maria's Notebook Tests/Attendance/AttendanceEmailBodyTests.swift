import Foundation
import Testing
@testable import Maria_s_Notebook

// The attendance email body is the only place the name-order and grouping settings
// show up, so the rules are pinned here rather than exercised through the UI.
@Suite("Attendance email body")
struct AttendanceEmailBodyTests {

    private func student(
        _ first: String,
        _ last: String,
        _ level: AttendanceEmailLevel? = .upper
    ) -> AttendanceEmailStudent {
        AttendanceEmailStudent(firstName: first, lastName: last, level: level)
    }

    /// The body minus its two header lines, which carry only the date.
    private func sections(
        present: [AttendanceEmailStudent] = [],
        tardy: [AttendanceEmailStudent] = [],
        absent: [AttendanceEmailStudent] = [],
        nameOrder: AttendanceEmailNameOrder = .firstLast,
        groupByLevel: Bool = false
    ) -> [String] {
        let body = AttendanceEmailReport.makeBody(
            present: present,
            tardy: tardy,
            absent: absent,
            date: Date(),
            nameOrder: nameOrder,
            groupByLevel: groupByLevel
        )
        return Array(body.components(separatedBy: "\n").dropFirst(2))
    }

    @Test("First-name order writes and sorts by first name")
    func firstNameOrder() {
        let lines = sections(present: [student("Ada", "Zeller"), student("Bo", "Adams")])
        #expect(lines.prefix(4) == ["", "On Time (2):", "  • Ada Zeller", "  • Bo Adams"])
    }

    @Test("Last-name order writes 'Last, First' and sorts by last name")
    func lastNameOrder() {
        let lines = sections(
            present: [student("Ada", "Zeller"), student("Bo", "Adams")],
            nameOrder: .lastFirst
        )
        #expect(lines.prefix(4) == ["", "On Time (2):", "  • Adams, Bo", "  • Zeller, Ada"])
    }

    @Test("A missing name half doesn't leave a stray comma or space")
    func partialNames() {
        let lastOnly = student("", "Zeller")
        let firstOnly = student("Ada", "")
        #expect(lastOnly.name(order: .lastFirst) == "Zeller")
        #expect(lastOnly.name(order: .firstLast) == "Zeller")
        #expect(firstOnly.name(order: .lastFirst) == "Ada")
        #expect(firstOnly.name(order: .firstLast) == "Ada")
    }

    @Test("Grouping puts Upper Elementary ahead of Adolescent")
    func groupOrder() {
        let lines = sections(
            present: [
                student("Bo", "Adams", .adolescent),
                student("Ada", "Zeller", .upper),
                student("Cy", "Nolan", .adolescent)
            ],
            groupByLevel: true
        )
        #expect(lines.prefix(7) == [
            "",
            "On Time (3):",
            "  Upper Elementary (1):",
            "    • Ada Zeller",
            "  Adolescent (2):",
            "    • Bo Adams",
            "    • Cy Nolan"
        ])
    }

    @Test("Grouping honors the chosen name order inside each level")
    func groupedNamesUseChosenOrder() {
        let lines = sections(
            present: [student("Ada", "Zeller"), student("Bo", "Adams")],
            nameOrder: .lastFirst,
            groupByLevel: true
        )
        #expect(lines.prefix(4) == ["", "On Time (2):", "  Upper Elementary (2):", "    • Adams, Bo"])
    }

    @Test("Empty levels are left out, and an unrecognized level trails as Other")
    func sparseGroups() {
        let lines = sections(
            present: [student("Cy", "Nolan", nil), student("Ada", "Zeller", .upper)],
            groupByLevel: true
        )
        #expect(lines.prefix(6) == [
            "",
            "On Time (2):",
            "  Upper Elementary (1):",
            "    • Ada Zeller",
            "  Other (1):",
            "    • Cy Nolan"
        ])
    }

    @Test("Grouping still reports an empty section as none")
    func emptySectionWhenGrouped() {
        let lines = sections(present: [student("Ada", "Zeller")], groupByLevel: true)
        #expect(lines.contains("Tardy (0):"))
        #expect(lines.contains("Absent (0):"))
        #expect(lines.filter { $0 == "  — none —" }.count == 2)
    }
}
