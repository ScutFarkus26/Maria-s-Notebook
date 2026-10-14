// ReportGeneratorFix1010GTests.swift
// What families receive (bug hunt 2026-10-10, P2 #31–#33, #36): a report made
// in Dark Mode is still dark ink on white, a long note flows onto the next page
// instead of off the bottom, the date ranges cover whole days and "This School
// Year" starts on the class's first day, and work closed as Keep Practicing or
// Incomplete is never called "Completed".

import CoreData
import Foundation
import PDFKit
import Testing
@testable import CosmicDaybook
#if canImport(UIKit)
import UIKit
#endif

@Suite("Report generator fixes 2026-10-10")
@MainActor
struct ReportGeneratorFix1010GTests {

    private func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 10, minute: Int = 0) throws -> Date {
        try #require(AppCalendar.shared.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        ))
    }

    /// One student with one note flagged for reports, written at `createdAt`.
    @discardableResult
    private func seedReportNote(
        body: String, createdAt: Date, for student: CDStudent, in context: NSManagedObjectContext
    ) throws -> CDNote {
        let note = CoreDataTestHelpers.seedNote(in: context, body: body)
        note.scope = .student(try #require(student.id))
        note.includeInReport = true
        note.createdAt = createdAt
        return note
    }

    // MARK: - PDF

    #if canImport(UIKit)
    /// Renders `page` onto white and counts the pixels dark enough to be text.
    private func darkPixelCount(_ page: PDFPage) throws -> Int {
        let box = page.bounds(for: .mediaBox)
        let width = Int(box.width), height = Int(box.height)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        page.draw(with: .mediaBox, to: context)
        let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        var dark = 0
        for index in stride(from: 0, to: width * height * 4, by: 4)
        where pixels[index] < 90 && pixels[index + 1] < 90 && pixels[index + 2] < 90 {
            dark += 1
        }
        return dark
    }

    @Test("A report made under a dark trait collection prints dark text on the white page")
    func darkModeReportHasVisibleText() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stone")
        let note = try seedReportNote(
            body: "Built the long bead chain of five and counted it by fives to the end.",
            createdAt: Date(), for: student, in: context
        )
        let service = ReportGeneratorService()

        var data = Data()
        UITraitCollection(userInterfaceStyle: .dark).performAsCurrent {
            data = service.generatePDF(
                student: student, notes: [note], style: .progressReport,
                dateRange: Date().addingTimeInterval(-86_400)...Date(),
                aiNarrative: "Maya has settled into the work cycle."
            )
        }

        let document = try #require(PDFDocument(data: data))
        let page = try #require(document.page(at: 0))
        // The label colors resolved white here, which left the page blank to the eye.
        #expect(try darkPixelCount(page) > 500)
        #expect(document.string?.contains("long bead chain") == true)
    }
    #endif

    @Test("A note too long for one page carries on to the next, nothing lost or off the page")
    func longNoteFlowsOntoASecondPage() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ezra", lastName: "Bloom")
        let words = (1...1500).map { String(format: "w%04d", $0) }
        let note = try seedReportNote(
            body: words.joined(separator: " "), createdAt: Date(), for: student, in: context
        )

        let data = ReportGeneratorService().generatePDF(
            student: student, notes: [note], style: .parentConference,
            dateRange: Date().addingTimeInterval(-86_400)...Date()
        )

        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount >= 2)
        let text = try #require(document.string)
        let missing = words.filter { !text.contains($0) }
        #expect(missing.isEmpty, "missing \(missing.count) words, first \(missing.first ?? "")")
        let lastPage = try #require(document.page(at: document.pageCount - 1))
        #expect(lastPage.string?.contains("w1500") == true)
        for index in 0..<document.pageCount {
            let page = try #require(document.page(at: index))
            let all = page.selection(for: NSRange(location: 0, length: page.numberOfCharacters))
            let bounds = try #require(all).bounds(for: page)
            #expect(bounds.minY >= 0, "page \(index + 1) has text below the bottom edge")
        }
    }

    // MARK: - Date ranges

    @Test("This School Year starts on the school year's first day, not four months back")
    func thisSchoolYearStartsOnTheFirstDay() throws {
        let firstDay = try day(2026, 8, 25, hour: 0)
        let today = try day(2026, 10, 10, hour: 9)

        let range = ReportGeneratorService.DateRangeOption.thisSchoolYear
            .dateRange(from: today, schoolYearStart: { _ in firstDay })
        #expect(range.lowerBound == AppCalendar.startOfDay(firstDay))
        #expect(AppCalendar.isSameDay(range.upperBound, today))
        #expect(range.upperBound > today)

        // Unless told otherwise it asks the configured school-year start.
        let configured = ReportGeneratorService.DateRangeOption.thisSchoolYear.dateRange(from: today)
        #expect(configured.lowerBound == YearPlanStaleness.currentYearStart(asOf: today))
        #expect(ReportGeneratorService.DateRangeOption.thisSchoolYear.rawValue == "This School Year")
    }

    @Test("Without the school-year start on this device, the year starts at the class's first mark")
    func unconfiguredStartFollowsFirstAttendance() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let today = try day(2026, 10, 10)
        let fallback = YearPlanStaleness.currentYearStart(asOf: today)
        let firstDay = try day(2026, 8, 25)
        CoreDataTestHelpers.seedAttendance(in: context, date: firstDay).statusRaw = AttendanceStatus.present.rawValue
        // An unmarked placeholder earlier on doesn't count as school meeting.
        CoreDataTestHelpers.seedAttendance(in: context, date: try day(2026, 8, 10)).statusRaw =
            AttendanceStatus.unmarked.rawValue
        CoreDataTestHelpers.seedNote(in: context, body: "Summer planning").createdAt = try day(2026, 8, 5)
        #expect(CoreDataTestHelpers.save(context))

        let start = ReportGeneratorService.schoolYearStart(asOf: today, context: context, hasConfiguredStart: false)
        #expect(start.isKnown)
        #expect(start.date == min(fallback, firstDay))
        let range = ReportGeneratorService.DateRangeOption.thisSchoolYear
            .dateRange(from: today, schoolYearStart: { _ in start.date })
        #expect(range.contains(try day(2026, 8, 26)) || fallback < firstDay)

        // With the class's start set, that start stands.
        let configured = ReportGeneratorService.schoolYearStart(asOf: today, context: context, hasConfiguredStart: true)
        #expect(configured == .init(date: fallback, isKnown: true))
    }

    @Test("Without attendance it starts at the earliest note or lesson; with nothing at all it is unknown")
    func unconfiguredStartWithoutAttendance() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let today = try day(2026, 10, 10)
        let fallback = YearPlanStaleness.currentYearStart(asOf: today)

        let empty = ReportGeneratorService.schoolYearStart(asOf: today, context: context, hasConfiguredStart: false)
        #expect(empty == .init(date: fallback, isKnown: false))

        let lessonDay = try day(2026, 8, 27)
        let given = CDLessonAssignment(context: context)
        given.state = .presented
        given.presentedAt = lessonDay
        CoreDataTestHelpers.seedNote(in: context, body: "Last spring").createdAt = try day(2026, 5, 20)
        #expect(CoreDataTestHelpers.save(context))

        let start = ReportGeneratorService.schoolYearStart(asOf: today, context: context, hasConfiguredStart: false)
        #expect(start == .init(date: min(fallback, lessonDay), isKnown: true))
    }

    @Test("A custom range keeps notes from early on its first day and late on its last")
    func customRangeCoversWholeDays() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Reyes")
        let notes: [(String, Date)] = [
            ("Early", try day(2026, 10, 1, hour: 0, minute: 10)),
            ("Late", try day(2026, 10, 3, hour: 23, minute: 50)),
            ("After", try day(2026, 10, 4, hour: 0, minute: 5))
        ]
        for (body, createdAt) in notes {
            try seedReportNote(body: body, createdAt: createdAt, for: student, in: context)
        }
        #expect(CoreDataTestHelpers.save(context))

        // The pickers hand over whatever time the sheet opened at.
        let range = ReportGeneratorService.DateRangeOption.custom.dateRange(
            customStart: try day(2026, 10, 1, hour: 15), customEnd: try day(2026, 10, 3, hour: 9)
        )
        let bodies = ReportGeneratorService()
            .fetchReportNotes(for: student, dateRange: range, context: context)
            .map(\.body)
        #expect(Set(bodies) == ["Early", "Late"])

        // Picked the wrong way round, it still covers the same days.
        let reversed = ReportGeneratorService.DateRangeOption.custom.dateRange(
            customStart: try day(2026, 10, 3, hour: 9), customEnd: try day(2026, 10, 1, hour: 15)
        )
        #expect(reversed == range)
    }

    // MARK: - Monthly report wording

    @Test("Mastered reads Completed and Finished reads Finished; the other closings are worded as closed")
    func workIsWordedByHowItWasClosed() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Lena", lastName: "Park", level: .upper)
        let studentID = try #require(student.id)
        let closings: [(String, WorkStatus)] = [
            ("Bead frame", .mastered), ("Stamp game", .keepPracticing),
            ("Map of Africa", .incomplete), ("Old checkerboard", .done), ("Reopened", .active)
        ]
        for (index, closing) in closings.enumerated() {
            let work = CoreDataTestHelpers.seedWorkModel(in: context, title: closing.0, studentID: studentID)
            work.status = closing.1
            work.completedAt = try day(2026, 9, 10 + index)
        }
        #expect(CoreDataTestHelpers.save(context))

        let builder = MonthlyReportContextBuilder(context: context, reportService: ReportGeneratorService())
        let month = builder.buildContext(
            for: student, month: ReportMonth(year: 2026, month: 9), includeStudentReflection: false
        )
        #expect(month.workEvidence.map(\.phrase) == [
            "Completed “Bead frame”",
            "Worked on “Stamp game” and will keep practicing it",
            "Worked on “Map of Africa”",
            "Finished “Old checkerboard”"
        ])

        // The fallback draft counts only the two finished pieces, Mastered and Finished.
        let draft = MonthlyReportDraftService(
            modelContext: context, mcpClient: UnusedClient(), reportService: ReportGeneratorService()
        ).makeFallbackDraft(from: month)
        #expect(draft.narrative.contains("completed 2 pieces of follow-up work"))
    }
}

/// The fallback draft never calls the model.
private struct UnusedClient: MCPClientProtocol {
    struct Unused: Error {}
    func generateText(prompt: String, temperature: Double) async throws -> String { throw Unused() }
    func generateStructuredJSON(prompt: String, temperature: Double) async throws -> String { throw Unused() }
    func sendConversation(
        messages: [[String: String]], systemMessage: String?, temperature: Double,
        maxTokens: Int, timeout: TimeInterval?
    ) async throws -> String { throw Unused() }
    // swiftlint:disable:next function_parameter_count
    func streamConversation(
        messages: [[String: String]], systemMessage: String?, temperature: Double,
        maxTokens: Int, timeout: TimeInterval?,
        onText: @escaping @MainActor @Sendable (String) -> Void
    ) async throws -> String { throw Unused() }
}
