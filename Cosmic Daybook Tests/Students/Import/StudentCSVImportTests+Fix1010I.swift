import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-10, P2 #59, #60 and #72's CSV items: short-year
/// birthdays, re-imports that duplicated children, the header row that turned
/// into a student, and "Smith, Maya".
@Suite("Student CSV import (bug hunt 2026-10-10)")
@MainActor
struct StudentCSVImportFix1010ITests {

    private func localDay(_ date: Date) -> DateComponents {
        AppCalendar.shared.dateComponents([.year, .month, .day], from: date)
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try #require(AppCalendar.shared.date(from: DateComponents(year: year, month: month, day: day)))
    }

    // MARK: - Dates

    @Test("Two-digit years are two-digit years, never the years 3 to 13 AD")
    func twoDigitYears() throws {
        let march = try #require(DateParser.parse("3/5/15"))
        #expect(localDay(march) == DateComponents(year: 2015, month: 3, day: 5))
        let newYearsEve = try #require(DateParser.parse("12/31/09"))
        #expect(localDay(newYearsEve) == DateComponents(year: 2009, month: 12, day: 31))
        let older = try #require(DateParser.parse("6/1/98"))
        #expect(localDay(older) == DateComponents(year: 1998, month: 6, day: 1))
    }

    @Test("Years before 1900 and days that don't exist are refused")
    func refusals() {
        #expect(DateParser.outcome("3/5/1815") == .tooEarly(year: 1815))
        #expect(DateParser.outcome("0015-03-05") == .tooEarly(year: 15))
        #expect(DateParser.outcome("2/30/2015") == .unreadable)
        #expect(DateParser.outcome("next spring") == .unreadable)
        #expect(DateParser.outcome("3/5/015") == .unreadable)
        #expect(DateParser.outcome("  ") == .empty)
    }

    @Test("Month first, then day first when the first number can't be a month; names and ISO still read")
    func otherShapes() throws {
        let expected: [String: DateComponents] = [
            "13/05/2018": DateComponents(year: 2018, month: 5, day: 13),
            "2018/05/04": DateComponents(year: 2018, month: 5, day: 4),
            "Mar 5, 2015": DateComponents(year: 2015, month: 3, day: 5),
            "March 5, 2015": DateComponents(year: 2015, month: 3, day: 5)
        ]
        for (text, components) in expected {
            #expect(localDay(try #require(DateParser.parse(text))) == components, "\(text)")
        }
        let parsed = try #require(DateParser.parse("3/5/15"))
        #expect(parsed == AppCalendar.startOfDay(parsed))
    }

    // MARK: - Parsing a file

    private func parse(
        _ csv: String, existing: [CDStudent] = []
    ) throws -> StudentCSVImporter.Parsed {
        try StudentCSVImporter.parse(
            data: Data(csv.utf8),
            mapping: nil,
            existingFullKeys: Set(existing.map { StudentCSVImporter.duplicateKey(for: $0) }),
            existingNameKeys: Set(existing.map { $0.fullName.normalizedNameKey() })
        )
    }

    @Test("A header row with a blank cell is still the header, not a student")
    func blankHeaderCell() throws {
        let parsed = try parse("First Name,Last Name,,Birthday\nMaya,Smith,x,3/5/15\n")
        #expect(parsed.rows.count == 1)
        let row = try #require(parsed.rows.first)
        #expect(row.firstName == "Maya" && row.lastName == "Smith")
        #expect(localDay(try #require(row.birthday)) == DateComponents(year: 2015, month: 3, day: 5))
    }

    @Test("A repeated header cell keeps the header and numbers the copy")
    func repeatedHeaderCell() throws {
        let csv = "First Name,Last Name,Notes,Notes\nLeo,Brown,a,b\n"
        let table = try #require(StudentCSVImporter.readTable(Data(csv.utf8)))
        #expect(table.headers == ["First Name", "Last Name", "Notes", "Notes 2"])
        #expect(table.rows == [["Leo", "Brown", "a", "b"]])
        #expect(try parse(csv).rows.map(\.firstName) == ["Leo"])
    }

    @Test("A file with no header row keeps every row")
    func noHeaderRow() throws {
        let table = try #require(StudentCSVImporter.readTable(Data("Maya,Smith,\nLeo,Brown,\n".utf8)))
        #expect(table.rows.count == 2)
    }

    @Test("\"Smith, Maya\" in a full-name column is Maya Smith")
    func lastCommaFirst() throws {
        let parsed = try parse("Name,Birthday\n\"Smith, Maya\",3/5/15\nLeo Brown,\n")
        #expect(parsed.rows.map { "\($0.firstName)|\($0.lastName)" } == ["Maya|Smith", "Leo|Brown"])
    }

    @Test("A refused birthday is left out with a warning naming the line")
    func earlyBirthdayWarning() throws {
        let parsed = try parse("First Name,Last Name,Birthday\nMaya,Smith,3/5/1815\nLeo,Brown,soon\n")
        #expect(parsed.rows.allSatisfy { $0.birthday == nil })
        #expect(parsed.warnings.contains { $0.hasPrefix("Line 2:") && $0.contains("before 1900") })
        #expect(parsed.warnings.contains { $0.hasPrefix("Line 3:") && $0.contains("couldn\u{2019}t read") })
    }

    @Test("A row with a birthday that matches a child by name is flagged in the preview")
    func previewFlagsNameMatch() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Smith")
        maya.birthday = try day(2016, 1, 2)
        let parsed = try parse("First Name,Last Name,Birthday\nMaya,Smith,3/5/15\n", existing: [maya])
        #expect(parsed.potentialDuplicates == ["Maya Smith"])
    }

    // MARK: - Committing

    private func commit(
        _ rows: [StudentCSVImporter.Row], existing: [CDStudent], in context: NSManagedObjectContext
    ) throws -> StudentCSVImporter.Summary {
        let parsed = StudentCSVImporter.Parsed(rows: rows, totalRows: rows.count, potentialDuplicates: [], warnings: [])
        return try StudentCSVImporter.commit(parsed: parsed, into: context, existingStudents: existing)
    }

    private func students(_ context: NSManagedObjectContext) -> [CDStudent] {
        context.safeFetch(CDFetchRequest(CDStudent.self))
    }

    @Test("Re-importing with a birthday fills in a child who has none, rather than adding her again")
    func fillsMissingBirthday() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Smith")
        #expect(CoreDataTestHelpers.save(context))
        let born = try day(2015, 3, 5)

        let summary = try commit(
            [.init(firstName: "Maya", lastName: "Smith", birthday: born)], existing: [maya], in: context
        )
        #expect(summary.insertedCount == 0)
        #expect(summary.updatedCount == 1)
        #expect(students(context).count == 1)
        #expect(maya.birthday == born)
    }

    @Test("A different birthday on file writes nothing and lists the row")
    func differentBirthdayIsLeftOut() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Smith")
        let onFile = try day(2016, 1, 2)
        maya.birthday = onFile
        #expect(CoreDataTestHelpers.save(context))

        let summary = try commit(
            [.init(firstName: "Maya", lastName: "Smith", birthday: try day(2015, 3, 5))], existing: [maya], in: context
        )
        #expect(summary.insertedCount == 0 && summary.updatedCount == 0)
        #expect(summary.skippedDuplicates == ["Maya Smith"])
        #expect(students(context).count == 1)
        #expect(maya.birthday == onFile)
        #expect(ImportCommitService.message(for: summary).contains("\u{2022} Maya Smith"))
    }

    @Test("Two children already in the class with one name are never treated as one")
    func twoSameNamedChildrenNeverMerge() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let first = CoreDataTestHelpers.seedStudent(in: context, firstName: "Sarah", lastName: "Cohen", level: .lower)
        let second = CoreDataTestHelpers.seedStudent(in: context, firstName: "Sarah", lastName: "Cohen", level: .lower)
        #expect(CoreDataTestHelpers.save(context))

        let summary = try commit(
            [.init(firstName: "Sarah", lastName: "Cohen", birthday: nil, level: .upper)],
            existing: [first, second], in: context
        )
        #expect(summary.skippedDuplicates == ["Sarah Cohen"])
        #expect(summary.updatedCount == 0 && summary.insertedCount == 0)
        #expect(first.level == .lower && second.level == .lower)
    }

    @Test("Two rows in one file with one name and different birthdays are two children")
    func twoSarahsInOneFile() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let summary = try commit(
            [
                .init(firstName: "Sarah", lastName: "Cohen", birthday: try day(2015, 3, 5)),
                .init(firstName: "Sarah", lastName: "Cohen", birthday: try day(2016, 7, 9))
            ],
            existing: [], in: context
        )
        #expect(summary.insertedCount == 2)
        #expect(summary.skippedDuplicates.isEmpty)
    }

    @Test("A birthday typed in late in the evening still matches its day")
    func keyUsesTheLocalDay() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Smith")
        // A time whose GMT day differs from its local day wherever this runs:
        // late evening west of Greenwich, just after midnight east of it.
        let west = AppCalendar.shared.timeZone.secondsFromGMT() < 0
        let typed = try #require(AppCalendar.shared.date(
            from: DateComponents(year: 2015, month: 3, day: 5, hour: west ? 23 : 0, minute: 30)
        ))
        maya.birthday = typed
        #expect(CoreDataTestHelpers.save(context))

        #expect(
            StudentCSVImporter.duplicateKey(for: maya)
                == StudentCSVImporter.duplicateKey(first: "Maya", last: "Smith", birthday: try day(2015, 3, 5))
        )
        let summary = try commit(
            [.init(firstName: "Maya", lastName: "Smith", birthday: try day(2015, 3, 5))], existing: [maya], in: context
        )
        #expect(summary.insertedCount == 0)
        #expect(students(context).count == 1)
        #expect(maya.birthday == typed)
    }
}
