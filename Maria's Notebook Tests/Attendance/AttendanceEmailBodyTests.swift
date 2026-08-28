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
        #expect(lines.prefix(4) == ["", "ON TIME (2)", "    • Ada Zeller", "    • Bo Adams"])
    }

    @Test("Last-name order writes 'Last, First' and sorts by last name")
    func lastNameOrder() {
        let lines = sections(
            present: [student("Ada", "Zeller"), student("Bo", "Adams")],
            nameOrder: .lastFirst
        )
        #expect(lines.prefix(4) == ["", "ON TIME (2)", "    • Adams, Bo", "    • Zeller, Ada"])
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

    // Grouping reads as one small report per class, so the whole shape is pinned:
    // Upper Elementary ahead of Adolescent, each carrying its own three lists, and
    // a wider gap between the levels than between the lists inside one.
    @Test("Each level carries its own On Time, Tardy, and Absent lists")
    func levelsCarryEveryStatus() {
        let lines = sections(
            present: [student("Bo", "Adams", .adolescent), student("Ada", "Zeller", .upper)],
            tardy: [student("Cy", "Nolan", .upper)],
            absent: [student("Di", "Ovadia", .adolescent)],
            groupByLevel: true
        )
        #expect(lines == [
            "",
            "UPPER ELEMENTARY",
            "",
            "On Time (1)",
            "    • Ada Zeller",
            "",
            "Tardy (1)",
            "    • Cy Nolan",
            "",
            "Absent (0)",
            "    None",
            "",
            "",
            "ADOLESCENT",
            "",
            "On Time (1)",
            "    • Bo Adams",
            "",
            "Tardy (0)",
            "    None",
            "",
            "Absent (1)",
            "    • Di Ovadia"
        ])
    }

    @Test("Grouping honors the chosen name order inside each level")
    func groupedNamesUseChosenOrder() {
        let lines = sections(
            present: [student("Ada", "Zeller"), student("Bo", "Adams")],
            nameOrder: .lastFirst,
            groupByLevel: true
        )
        #expect(lines.prefix(5) == ["", "UPPER ELEMENTARY", "", "On Time (2)", "    • Adams, Bo"])
    }

    @Test("Empty levels are left out, and an unrecognized level trails as Other")
    func sparseGroups() {
        let lines = sections(
            present: [student("Cy", "Nolan", nil), student("Ada", "Zeller", .upper)],
            groupByLevel: true
        )
        #expect(lines.prefix(5) == ["", "UPPER ELEMENTARY", "", "On Time (1)", "    • Ada Zeller"])
        #expect(lines.contains("OTHER"))
        #expect(lines.suffix(2) == ["Absent (0)", "    None"])
        #expect(!lines.contains("ADOLESCENT"))
        #expect(!lines.contains("LOWER ELEMENTARY"))
    }

    @Test("An empty list reads as None rather than an empty heading")
    func emptyListsReadAsNone() {
        let lines = sections(present: [student("Ada", "Zeller")], groupByLevel: true)
        #expect(lines.contains("Tardy (0)"))
        #expect(lines.contains("Absent (0)"))
        #expect(lines.filter { $0 == "    None" }.count == 2)
    }

    // Grouping has no levels to write when nobody is marked yet, and a report that is
    // nothing but a date reads as a broken email rather than an empty classroom.
    @Test("Grouping an empty roster still writes the three lists")
    func groupingAnEmptyRoster() {
        #expect(sections(groupByLevel: true) == [
            "",
            "ON TIME (0)",
            "    None",
            "",
            "TARDY (0)",
            "    None",
            "",
            "ABSENT (0)",
            "    None"
        ])
    }

    @Test("The report ends on its last list, with no trailing blank line")
    func noTrailingBlankLine() {
        let lines = sections(present: [student("Ada", "Zeller")])
        #expect(lines.last == "    None")
    }
}
