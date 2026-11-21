// ReportClassmateNamesTests.swift
// Domain logic review 2026-11-20, R1 (plan "Domain logic fixes", Decision 3):
// a note about two children goes into both reports, so before a report is
// drafted or printed, every other child's name in it becomes "a classmate".

import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

@Suite("Report classmate names (domain logic R1)")
@MainActor
struct ReportClassmateNamesTests {

    private let month = ReportMonth(year: 2026, month: 9)

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return calendar
    }

    private func september(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: 10)) ?? Date()
    }

    private struct Room {
        let context: NSManagedObjectContext
        let maya: CDStudent
        let leo: CDStudent
    }

    private func makeRoom() throws -> Room {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Sela")
        let leo = CoreDataTestHelpers.seedStudent(in: context, firstName: "Leo", lastName: "Katz")
        return Room(context: context, maya: maya, leo: leo)
    }

    @discardableResult
    private func flaggedNote(
        _ body: String, about students: [CDStudent], in context: NSManagedObjectContext
    ) throws -> CDNote {
        let note = CoreDataTestHelpers.seedNote(in: context, body: body)
        let ids = try students.map { try #require($0.id) }
        note.scope = ids.count == 1 ? .student(ids[0]) : .students(ids)
        note.includeInReport = true
        note.createdAt = september(10)
        note.updatedAt = september(10)
        note.syncStudentLinks(in: context)
        return note
    }

    private func observations(for student: CDStudent, in context: NSManagedObjectContext) -> String {
        MonthlyReportContextBuilder(context: context, reportService: ReportGeneratorService(), calendar: calendar)
            .buildContext(for: student, month: month, includeStudentReflection: false)
            .observations.map(\.phrase).joined(separator: "\n")
    }

    @Test("Leo's name never reaches Maya's draft, and hers never reaches his")
    func leoNeverInMayasDraft() throws {
        let room = try makeRoom()
        try flaggedNote(
            "Maya and Leo argued over the bead frame. Later Leo Katz apologized to Maya.",
            about: [room.maya, room.leo], in: room.context
        )
        #expect(CoreDataTestHelpers.save(room.context))

        let mayas = observations(for: room.maya, in: room.context)
        #expect(mayas.contains("bead frame"), "the note is in her report")
        #expect(!mayas.contains("Leo"))
        #expect(!mayas.contains("Katz"))
        #expect(mayas.contains("Maya and a classmate argued"))
        #expect(mayas.contains("Later a classmate apologized to Maya."))

        let leos = observations(for: room.leo, in: room.context)
        #expect(!leos.contains("Maya"))
        #expect(leos.contains("A classmate and Leo argued"), "a sentence still starts with a capital")
    }

    @Test("The report's PDF text leaves classmates' names out too")
    func pdfTextScrubbed() throws {
        let room = try makeRoom()
        let note = try flaggedNote(
            "Leo's tower fell, and Maya helped rebuild it.", about: [room.maya, room.leo], in: room.context
        )
        #expect(CoreDataTestHelpers.save(room.context))

        let text = ReportGeneratorService().buildReportText(
            student: room.maya, notes: [note], style: .progressReport,
            dateRange: month.closedRange(calendar: calendar), aiNarrative: nil
        ).string
        #expect(text.contains("a classmate's tower fell, and Maya helped rebuild it.")
            || text.contains("A classmate's tower fell, and Maya helped rebuild it."))
        #expect(!text.contains("Leo"))
        #expect(note.body.contains("Leo"), "the note itself is never changed")
    }

    @Test("A classmate who shares her first name is left out by her full or short name only")
    func sharedFirstName() throws {
        let room = try makeRoom()
        let otherMaya = CoreDataTestHelpers.seedStudent(in: room.context, firstName: "Maya", lastName: "Tal")
        try flaggedNote(
            "Maya Tal read to Maya. Maya T laughed, and Maya kept reading.",
            about: [room.maya, otherMaya], in: room.context
        )
        #expect(CoreDataTestHelpers.save(room.context))

        let mayas = observations(for: room.maya, in: room.context)
        #expect(!mayas.contains("Tal"))
        #expect(!mayas.contains("Maya T "))
        #expect(mayas.contains("A classmate read to Maya. A classmate laughed, and Maya kept reading."))
    }

    @Test("Lowercase words aren't names: a classmate called Will doesn't change \"will\"")
    func lowercaseWordsKept() throws {
        let room = try makeRoom()
        let will = CoreDataTestHelpers.seedStudent(in: room.context, firstName: "Will", lastName: "Adler")
        try flaggedNote("Maya says she will teach Will the chain.", about: [room.maya, will], in: room.context)
        #expect(CoreDataTestHelpers.save(room.context))

        #expect(observations(for: room.maya, in: room.context)
            .contains("Maya says she will teach a classmate the chain."))
    }

    // MARK: - Phase 10 review, finding 6

    @Test("A classmate's last name alone is a word: Brown Stair and Long Division stay")
    func lastNameAloneIsAWord() throws {
        let room = try makeRoom()
        let leo = CoreDataTestHelpers.seedStudent(in: room.context, firstName: "Leo", lastName: "Brown")
        let ari = CoreDataTestHelpers.seedStudent(in: room.context, firstName: "Ari", lastName: "Long")
        ari.nickname = "Lee"
        try flaggedNote(
            "Maya built the Brown Stair with Leo Brown, then did Long Division beside Lee Long.",
            about: [room.maya, leo, ari], in: room.context
        )
        #expect(CoreDataTestHelpers.save(room.context))

        let mayas = observations(for: room.maya, in: room.context)
        #expect(mayas == "Maya built the Brown Stair with a classmate, then did Long Division beside a classmate.")
    }

    @Test("A classmate's name in a work title doesn't reach her draft")
    func workTitlesSwapped() throws {
        let room = try makeRoom()
        let mayaID = try #require(room.maya.id)
        let work = CoreDataTestHelpers.seedWorkModel(
            in: room.context, title: "Research with Leo", studentID: mayaID
        )
        work.status = .done
        work.completedAt = september(12)
        #expect(CoreDataTestHelpers.save(room.context))

        let phrases = MonthlyReportContextBuilder(
            context: room.context, reportService: ReportGeneratorService(), calendar: calendar
        )
        .buildContext(for: room.maya, month: month, includeStudentReflection: false)
        .workEvidence.map(\.phrase)
        #expect(phrases == ["Finished “Research with a classmate”"])
    }
}
