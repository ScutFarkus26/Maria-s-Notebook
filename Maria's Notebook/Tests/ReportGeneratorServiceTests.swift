#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - ReportGeneratorService DateRangeOption Tests

@Suite("ReportGeneratorService DateRangeOption Tests", .serialized)
struct ReportGeneratorServiceDateRangeTests {

    @Test("lastWeek returns 7 day range")
    func lastWeekReturns7Days() {
        let today = TestCalendar.date(year: 2025, month: 6, day: 15)
        let range = ReportGeneratorService.DateRangeOption.lastWeek.dateRange(from: today)

        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: range.lowerBound, to: range.upperBound).day ?? 0

        #expect(days == 7)
        #expect(range.upperBound == today)
    }

    @Test("lastMonth returns 30 day range")
    func lastMonthReturns30Days() {
        let today = TestCalendar.date(year: 2025, month: 6, day: 15)
        let range = ReportGeneratorService.DateRangeOption.lastMonth.dateRange(from: today)

        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: range.lowerBound, to: range.upperBound).day ?? 0

        #expect(days == 30)
        #expect(range.upperBound == today)
    }

    @Test("lastQuarter returns 90 day range")
    func lastQuarterReturns90Days() {
        let today = TestCalendar.date(year: 2025, month: 6, day: 15)
        let range = ReportGeneratorService.DateRangeOption.lastQuarter.dateRange(from: today)

        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: range.lowerBound, to: range.upperBound).day ?? 0

        #expect(days == 90)
        #expect(range.upperBound == today)
    }

    @Test("thisSemester returns approximately 4 month range")
    func thisSemesterReturns4Months() {
        let today = TestCalendar.date(year: 2025, month: 6, day: 15)
        let range = ReportGeneratorService.DateRangeOption.thisSemester.dateRange(from: today)

        let calendar = Calendar.current
        let months = calendar.dateComponents([.month], from: range.lowerBound, to: range.upperBound).month ?? 0

        #expect(months == 4)
        #expect(range.upperBound == today)
    }

    @Test("custom defaults to 30 days")
    func customDefaultsTo30Days() {
        let today = TestCalendar.date(year: 2025, month: 6, day: 15)
        let range = ReportGeneratorService.DateRangeOption.custom.dateRange(from: today)

        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: range.lowerBound, to: range.upperBound).day ?? 0

        #expect(days == 30)
    }

    @Test("all cases have unique identifiers")
    func allCasesHaveUniqueIds() {
        let ids = ReportGeneratorService.DateRangeOption.allCases.map { $0.id }
        let uniqueIds = Set(ids)

        #expect(ids.count == uniqueIds.count)
    }

    @Test("all cases have rawValue equal to id")
    func rawValueEqualsId() {
        for option in ReportGeneratorService.DateRangeOption.allCases {
            #expect(option.id == option.rawValue)
        }
    }
}

// MARK: - ReportGeneratorService ReportStyle Tests

@Suite("ReportGeneratorService ReportStyle Tests", .serialized)
struct ReportGeneratorServiceReportStyleTests {

    @Test("progressReport includes images")
    func progressReportIncludesImages() {
        #expect(ReportGeneratorService.ReportStyle.progressReport.includesImages == true)
    }

    @Test("parentConference includes images")
    func parentConferenceIncludesImages() {
        #expect(ReportGeneratorService.ReportStyle.parentConference.includesImages == true)
    }

    @Test("iepDocumentation does not include images")
    func iepDocumentationNoImages() {
        #expect(ReportGeneratorService.ReportStyle.iepDocumentation.includesImages == false)
    }

    @Test("progressReport groups by category")
    func progressReportGroupsByCategory() {
        #expect(ReportGeneratorService.ReportStyle.progressReport.groupsByCategory == true)
    }

    @Test("parentConference does not group by category")
    func parentConferenceNoGrouping() {
        #expect(ReportGeneratorService.ReportStyle.parentConference.groupsByCategory == false)
    }

    @Test("iepDocumentation groups by category")
    func iepDocumentationGroupsByCategory() {
        #expect(ReportGeneratorService.ReportStyle.iepDocumentation.groupsByCategory == true)
    }

    @Test("all styles have unique identifiers")
    func allStylesHaveUniqueIds() {
        let ids = ReportGeneratorService.ReportStyle.allCases.map { $0.id }
        let uniqueIds = Set(ids)

        #expect(ids.count == uniqueIds.count)
    }
}

// MARK: - ReportGeneratorService FetchReportNotes Tests

@Suite("ReportGeneratorService FetchReportNotes Tests", .serialized)
@MainActor
struct ReportGeneratorServiceFetchNotesTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Lesson.self,
            StudentLesson.self,
            Note.self,
            NoteStudentLink.self,
        ])
    }

    @Test("fetchReportNotes returns only flagged notes")
    func fetchReturnsOnlyFlagged() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent(firstName: "Alice", lastName: "Test")
        context.insert(student)

        let flaggedNote = Note(body: "Flagged note", scope: .student(student.id), includeInReport: true)
        let unflaggedNote = Note(body: "Unflagged note", scope: .student(student.id), includeInReport: false)
        context.insert(flaggedNote)
        context.insert(unflaggedNote)
        try context.save()

        let service = ReportGeneratorService()
        let dateRange = TestCalendar.date(year: 2020, month: 1, day: 1)...TestCalendar.date(year: 2030, month: 12, day: 31)

        let notes = service.fetchReportNotes(for: student, dateRange: dateRange, context: context)

        #expect(notes.count == 1)
        #expect(notes.first?.body == "Flagged note")
    }

    @Test("fetchReportNotes filters by date range")
    func fetchFiltersByDateRange() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent(firstName: "Alice", lastName: "Test")
        context.insert(student)

        let inRangeNote = Note(
            createdAt: TestCalendar.date(year: 2025, month: 6, day: 15),
            body: "In range",
            scope: .student(student.id),
            includeInReport: true
        )
        let beforeRangeNote = Note(
            createdAt: TestCalendar.date(year: 2025, month: 1, day: 1),
            body: "Before range",
            scope: .student(student.id),
            includeInReport: true
        )
        let afterRangeNote = Note(
            createdAt: TestCalendar.date(year: 2025, month: 12, day: 31),
            body: "After range",
            scope: .student(student.id),
            includeInReport: true
        )
        context.insert(inRangeNote)
        context.insert(beforeRangeNote)
        context.insert(afterRangeNote)
        try context.save()

        let service = ReportGeneratorService()
        let dateRange = TestCalendar.date(year: 2025, month: 6, day: 1)...TestCalendar.date(year: 2025, month: 6, day: 30)

        let notes = service.fetchReportNotes(for: student, dateRange: dateRange, context: context)

        #expect(notes.count == 1)
        #expect(notes.first?.body == "In range")
    }

    @Test("fetchReportNotes includes notes with scope all")
    func fetchIncludesScopeAll() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent(firstName: "Alice", lastName: "Test")
        context.insert(student)

        let allScopeNote = Note(body: "All students note", scope: .all, includeInReport: true)
        context.insert(allScopeNote)
        try context.save()

        let service = ReportGeneratorService()
        let dateRange = TestCalendar.date(year: 2020, month: 1, day: 1)...TestCalendar.date(year: 2030, month: 12, day: 31)

        let notes = service.fetchReportNotes(for: student, dateRange: dateRange, context: context)

        #expect(notes.count == 1)
        #expect(notes.first?.body == "All students note")
    }

    @Test("fetchReportNotes excludes notes for other students")
    func fetchExcludesOtherStudents() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let alice = makeTestStudent(firstName: "Alice", lastName: "A")
        let bob = makeTestStudent(firstName: "Bob", lastName: "B")
        context.insert(alice)
        context.insert(bob)

        let aliceNote = Note(body: "Alice note", scope: .student(alice.id), includeInReport: true)
        let bobNote = Note(body: "Bob note", scope: .student(bob.id), includeInReport: true)
        context.insert(aliceNote)
        context.insert(bobNote)
        try context.save()

        let service = ReportGeneratorService()
        let dateRange = TestCalendar.date(year: 2020, month: 1, day: 1)...TestCalendar.date(year: 2030, month: 12, day: 31)

        let notes = service.fetchReportNotes(for: alice, dateRange: dateRange, context: context)

        #expect(notes.count == 1)
        #expect(notes.first?.body == "Alice note")
    }

    @Test("fetchReportNotes returns sorted by date descending")
    func fetchReturnsSortedDescending() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent(firstName: "Alice", lastName: "Test")
        context.insert(student)

        let note1 = Note(
            createdAt: TestCalendar.date(year: 2025, month: 6, day: 1),
            body: "First",
            scope: .student(student.id),
            includeInReport: true
        )
        let note2 = Note(
            createdAt: TestCalendar.date(year: 2025, month: 6, day: 15),
            body: "Second",
            scope: .student(student.id),
            includeInReport: true
        )
        let note3 = Note(
            createdAt: TestCalendar.date(year: 2025, month: 6, day: 10),
            body: "Third",
            scope: .student(student.id),
            includeInReport: true
        )
        context.insert(note1)
        context.insert(note2)
        context.insert(note3)
        try context.save()

        let service = ReportGeneratorService()
        let dateRange = TestCalendar.date(year: 2025, month: 6, day: 1)...TestCalendar.date(year: 2025, month: 6, day: 30)

        let notes = service.fetchReportNotes(for: student, dateRange: dateRange, context: context)

        #expect(notes.count == 3)
        // Should be sorted descending by date
        #expect(notes[0].body == "Second") // June 15
        #expect(notes[1].body == "Third")  // June 10
        #expect(notes[2].body == "First")  // June 1
    }
}

// MARK: - ReportGeneratorService PDF Generation Tests

@Suite("ReportGeneratorService PDF Generation Tests", .serialized)
@MainActor
struct ReportGeneratorServicePDFTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Lesson.self,
            Note.self,
        ])
    }

    @Test("generatePDF returns non-empty data")
    func generatePDFReturnsData() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent(firstName: "Alice", lastName: "Test")
        context.insert(student)

        let note = Note(body: "Test observation", scope: .student(student.id), category: .academic, includeInReport: true)
        context.insert(note)
        try context.save()

        let service = ReportGeneratorService()
        let dateRange = TestCalendar.date(year: 2020, month: 1, day: 1)...TestCalendar.date(year: 2030, month: 12, day: 31)

        let pdfData = service.generatePDF(
            student: student,
            notes: [note],
            style: .progressReport,
            dateRange: dateRange
        )

        #expect(!pdfData.isEmpty)
    }

    @Test("generatePDF handles empty notes array")
    func generatePDFHandlesEmptyNotes() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent(firstName: "Alice", lastName: "Test")
        context.insert(student)
        try context.save()

        let service = ReportGeneratorService()
        let dateRange = TestCalendar.date(year: 2025, month: 1, day: 1)...TestCalendar.date(year: 2025, month: 12, day: 31)

        let pdfData = service.generatePDF(
            student: student,
            notes: [],
            style: .progressReport,
            dateRange: dateRange
        )

        // Should still produce valid PDF with header/footer but no notes content
        #expect(!pdfData.isEmpty)
    }

    @Test("generatePDF works with all report styles")
    func generatePDFWorksWithAllStyles() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent(firstName: "Alice", lastName: "Test")
        context.insert(student)

        let note = Note(body: "Test", scope: .student(student.id), includeInReport: true)
        context.insert(note)
        try context.save()

        let service = ReportGeneratorService()
        let dateRange = TestCalendar.date(year: 2020, month: 1, day: 1)...TestCalendar.date(year: 2030, month: 12, day: 31)

        for style in ReportGeneratorService.ReportStyle.allCases {
            let pdfData = service.generatePDF(
                student: student,
                notes: [note],
                style: style,
                dateRange: dateRange
            )

            #expect(!pdfData.isEmpty, "PDF should be generated for style: \(style.rawValue)")
        }
    }

    @Test("generatePDF handles multiple notes with different categories")
    func generatePDFHandlesMultipleCategories() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent(firstName: "Alice", lastName: "Test")
        context.insert(student)

        let academicNote = Note(body: "Academic progress", scope: .student(student.id), category: .academic, includeInReport: true)
        let behavioralNote = Note(body: "Behavioral observation", scope: .student(student.id), category: .behavioral, includeInReport: true)
        let socialNote = Note(body: "Social interaction", scope: .student(student.id), category: .social, includeInReport: true)
        context.insert(academicNote)
        context.insert(behavioralNote)
        context.insert(socialNote)
        try context.save()

        let service = ReportGeneratorService()
        let dateRange = TestCalendar.date(year: 2020, month: 1, day: 1)...TestCalendar.date(year: 2030, month: 12, day: 31)

        let pdfData = service.generatePDF(
            student: student,
            notes: [academicNote, behavioralNote, socialNote],
            style: .progressReport,
            dateRange: dateRange
        )

        #expect(!pdfData.isEmpty)
    }
}

#endif
