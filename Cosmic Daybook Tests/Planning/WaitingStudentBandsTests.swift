import CoreData
import Foundation
import SwiftUI
import Testing
@testable import CosmicDaybook

/// The rail folds its last group away, so the bucketing decides who the guide
/// sees without opening anything: a child misfiled into "under a week" is a
/// child who quietly drops out of view.
@Suite("Waiting student bands")
@MainActor
struct WaitingStudentBandsTests {

    private func makeStudent(
        _ context: NSManagedObjectContext,
        first: String,
        last: String
    ) -> CDStudent {
        let student = CDStudent(context: context)
        student.id = UUID()
        student.firstName = first
        student.lastName = last
        return student
    }

    private func ids(_ entries: [WaitingStudent]) -> [NSManagedObjectID] {
        entries.map(\.id)
    }

    private func band(_ days: Int?, threshold: Int) -> WaitingStudentBand {
        WaitingStudentBands.band(forDays: days, longWaitThreshold: threshold)
    }

    // MARK: - Threshold edges

    @Test("The long-wait line is inclusive and the week line sits at five")
    func edgesAtTheDefaultThreshold() {
        // The shipped overdue default is 8 school days.
        #expect(band(8, threshold: 8) == .longWait)
        #expect(band(120, threshold: 8) == .longWait)
        #expect(band(7, threshold: 8) == .aWeekOrMore)
        #expect(band(5, threshold: 8) == .aWeekOrMore)
        #expect(band(4, threshold: 8) == .underAWeek)
        #expect(band(0, threshold: 8) == .underAWeek)
    }

    @Test("A longer threshold widens the middle group, not the top one")
    func edgesAtTen() {
        #expect(band(10, threshold: 10) == .longWait)
        #expect(band(9, threshold: 10) == .aWeekOrMore)
        #expect(band(5, threshold: 10) == .aWeekOrMore)
        #expect(band(4, threshold: 10) == .underAWeek)
    }

    @Test("A threshold of a week or less leaves the middle group empty")
    func shortThresholdEmptiesTheMiddle() {
        #expect(band(5, threshold: 5) == .longWait)
        #expect(band(4, threshold: 5) == .underAWeek)
        // Nobody can be a week late without already being overdue.
        for days in 0...30 {
            #expect(band(days, threshold: 3) != .aWeekOrMore)
        }
        #expect(band(3, threshold: 3) == .longWait)
        #expect(band(2, threshold: 3) == .underAWeek)
    }

    @Test("A zero or negative threshold puts everyone at the top, as the palette does")
    func nonPositiveThresholdIsClamped() {
        #expect(band(0, threshold: 0) == .longWait)
        #expect(band(0, threshold: -4) == .longWait)
        #expect(WaitingStudentBands([], longWaitThreshold: -4).longWaitThreshold == 0)
    }

    // MARK: - Never taught

    @Test("A child who has never been taught is in the top group at any threshold")
    func neverTaughtIsLongWait() {
        #expect(band(nil, threshold: 8) == .longWait)
        #expect(band(nil, threshold: 10) == .longWait)
        #expect(band(nil, threshold: 1000) == .longWait)
    }

    // MARK: - Grouping

    @Test("Each group keeps the waiting order, never-taught first")
    func groupsKeepTheOrder() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let never = makeStudent(context, first: "Nia", last: "Okafor")
        let ada = makeStudent(context, first: "Ada", last: "Byron")
        let bram = makeStudent(context, first: "Bram", last: "Cole")
        let cleo = makeStudent(context, first: "Cleo", last: "Diaz")
        let dev = makeStudent(context, first: "Dev", last: "Ellis")
        let ezra = makeStudent(context, first: "Ezra", last: "Fox")
        let finn = makeStudent(context, first: "Finn", last: "Gray")
        let gus = makeStudent(context, first: "Gus", last: "Hale")

        let waits: [(CDStudent, Int)] = [
            (never, Int.max), (ada, 15), (bram, 15), (cleo, 8),
            (dev, 7), (ezra, 5), (finn, 4), (gus, 0)
        ]
        var daysSince: [UUID: Int] = [:]
        for (student, days) in waits {
            daysSince[try #require(student.id)] = days
        }

        let ordered = WaitingStudentsOrder.ordered(
            students: [gus, finn, ezra, dev, cleo, bram, ada, never],
            daysSince: daysSince,
            studentIDsWithUpcomingLessons: [],
            scope: .everyone
        )
        let bands = WaitingStudentBands(ordered, longWaitThreshold: 8)

        let longWait: [CDStudent] = [never, ada, bram, cleo]
        let aWeekOrMore: [CDStudent] = [dev, ezra]
        let underAWeek: [CDStudent] = [finn, gus]
        #expect(ids(bands.longWait) == longWait.map(\.objectID))
        #expect(ids(bands.aWeekOrMore) == aWeekOrMore.map(\.objectID))
        #expect(ids(bands.underAWeek) == underAWeek.map(\.objectID))
        #expect(bands.hasChildrenAboveTheFold)
        #expect(bands.underAWeekSummary == "2 more, under a week")
        #expect(bands.longWaitTitle == "8+ school days")
    }

    @Test("A class taught this week has nothing above the fold")
    func everyoneRecentHasNothingAboveTheFold() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let ada = makeStudent(context, first: "Ada", last: "Byron")
        let bram = makeStudent(context, first: "Bram", last: "Cole")

        let bands = WaitingStudentBands(
            [WaitingStudent(student: ada, daysWaiting: 1), WaitingStudent(student: bram, daysWaiting: 3)],
            longWaitThreshold: 8
        )

        #expect(bands.longWait.isEmpty)
        #expect(bands.aWeekOrMore.isEmpty)
        #expect(bands.underAWeek.count == 2)
        // The rail shows this group open rather than a list of nothing.
        #expect(!bands.hasChildrenAboveTheFold)
    }

    // MARK: - Color and wording

    @Test("Only the top group is colored, by the same test that files it there")
    func colorFollowsTheTopGroup() {
        let palette = StudentAgePalette(
            warningDays: 6,
            overdueDays: 8,
            fresh: .blue,
            warning: .orange,
            overdue: .red
        )
        #expect(palette.longWaitColor(forDays: nil) == .red)
        #expect(palette.longWaitColor(forDays: 8) == .red)
        // The warning threshold no longer colors anything in this style.
        #expect(palette.longWaitColor(forDays: 7) == nil)
        #expect(palette.longWaitColor(forDays: 0) == nil)
    }

    @Test("The number's full sentence reads as one, singular included")
    func spokenSentences() {
        let lessons = StudentWaitVocabulary.lessons
        #expect(lessons.spokenDetail(forDays: nil) == "Never taught")
        #expect(lessons.spokenDetail(forDays: 0) == "Taught today")
        #expect(lessons.spokenDetail(forDays: 1) == "1 school day since their last lesson")
        #expect(lessons.spokenDetail(forDays: 15) == "15 school days since their last lesson")
        #expect(
            StudentWaitVocabulary.work.spokenDetail(forDays: 12)
                == "12 school days since their work was checked"
        )
    }
}
