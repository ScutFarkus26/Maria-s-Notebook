import CoreData
import Foundation
import SwiftUI
import Testing
@testable import CosmicDaybook

/// The presentation sheet's "Next lesson" row: the choice it holds, what the
/// sheet reads to offer it, its words, and its place in a Later draft
/// (docs/Plans/Plan - Next lesson row when presenting.md). What Done writes is
/// in `PresentationNextLessonCommitTests`.
@Suite("Presentation Next Lesson")
@MainActor
struct PresentationNextLessonTests {
    private let calendar = AppCalendar.shared
    private let english = Locale(identifier: "en_US")
    private let ada = UUID()
    private let ben = UUID()

    private var today: Date { AppCalendar.startOfDay(Date()) }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: today) ?? today
    }

    /// Thursday, November 12, 2026.
    private var thursday: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 12)) ?? today
    }

    // MARK: - The choice

    @Test("The Inbox has no moment; a day with no time joins the end of the morning")
    func momentWithoutATime() throws {
        #expect(PresentationNextLessonPlace.inbox.scheduledMoment() == nil)

        let place = PresentationNextLessonPlace(day: thursday)
        let moment = try #require(place.scheduledMoment())
        #expect(calendar.isDate(moment, inSameDayAs: thursday))
        #expect(DayHalfPlanner.isSetTime(moment) == false)
        #expect(DayHalfPlanner.moment(of: moment) == .half(.morning))
        #expect(moment == DayHalfPlanner.slot(DayHalfPlanner.lastSlotRank, in: .morning, on: thursday))
    }

    @Test("A set time is stored as the card's picker stores it, the base hours included")
    func momentWithATime() {
        for (hour, minute) in [(10, 15), (9, 0), (14, 0), (13, 30)] {
            let place = PresentationNextLessonPlace(day: thursday).settingTime(hour: hour, minute: minute)
            let moment = place.scheduledMoment()
            #expect(DayHalfPlanner.setMinute(of: moment) == hour * 60 + minute)
            #expect(moment.map { calendar.isDate($0, inSameDayAs: thursday) } == true)
        }
    }

    @Test("A time goes with a change of day, comes off, and needs a day")
    func editingTheChoice() {
        let timed = PresentationNextLessonPlace(day: thursday).settingTime(hour: 10, minute: 15)
        #expect(timed.clockTime == LessonClockTime(hour: 10, minute: 15))

        let moved = timed.moved(to: day(3))
        #expect(moved.day == day(3))
        #expect(moved.clockTime == LessonClockTime(hour: 10, minute: 15))

        #expect(timed.removingTime == PresentationNextLessonPlace(day: thursday))
        #expect(PresentationNextLessonPlace.inbox.settingTime(hour: 10, minute: 0) == .inbox)
        #expect(PresentationNextLessonPlace.inbox.moved(to: thursday) == PresentationNextLessonPlace(day: thursday))
    }

    @Test("The words say where the lesson goes")
    func words() {
        let onDay = PresentationNextLessonPlace(day: thursday)
        #expect(PresentationNextLessonPlace.inbox.phrase(locale: english) == "goes in the Inbox")
        #expect(onDay.phrase(locale: english) == "is scheduled for Thursday, Nov 12")
        #expect(
            onDay.settingTime(hour: 10, minute: 0).phrase(locale: english)
                == "is scheduled for Thursday, Nov 12 at 10:00"
        )

        func caption(_ place: PresentationNextLessonPlace, fromYearPlan: Bool = false) -> String {
            PresentationNextLessonRow.caption(
                names: ["Maya S", "Leo K"], place: place, fromYearPlan: fromYearPlan, locale: english
            )
        }
        #expect(caption(.inbox) == "For Maya S and Leo K. Waits in the Inbox until you give it a day.")
        #expect(caption(.inbox, fromYearPlan: true) == caption(.inbox))
        #expect(caption(onDay) == "For Maya S and Leo K. Goes on the week for Thursday, Nov 12.")
        #expect(
            caption(onDay, fromYearPlan: true) == "For Maya S and Leo K. The year plan has it on Thursday, Nov 12."
        )
    }

    // MARK: - What the sheet reads

    @Test("The sheet learns who is already planned and which day the year plan has")
    func context() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let first = CoreDataTestHelpers.seedLesson(in: context, name: "Nouns", area: "Language", sequence: "Grammar")
        first.orderInSequence = 1
        let second = CoreDataTestHelpers.seedLesson(
            in: context, name: "Collective Nouns", area: "Language", sequence: "Grammar"
        )
        second.orderInSequence = 2
        let secondID = try #require(second.id)
        let cy = UUID()

        // Ben is already on a plan for it; Ada's year plan has it next week,
        // and Cy's had it last week.
        _ = PresentationFactory.makeDraft(lessonID: secondID, studentIDs: [ben], context: context)
        yearPlanEntry(for: ada, lessonID: secondID, on: day(7), in: context)
        yearPlanEntry(for: cy, lessonID: secondID, on: day(-7), in: context)
        try context.save()

        let loaded = try #require(PresentationNextLessonContext.load(
            after: first, lessons: [first, second], studentIDs: [ada, ben, cy], context: context
        ))
        #expect(loaded.lessonName == "Collective Nouns")
        #expect(loaded.alreadyPlanned == [ben])
        #expect(loaded.yearPlanDays == [ada: day(7)])

        #expect(loaded.recipients(newlyReady: [ada, ben, cy]) == [ada, cy])
        #expect(loaded.startingPlace(for: [ada, cy]) == PresentationNextLessonPlace(day: day(7)))
        #expect(loaded.startingPlace(for: [cy]) == .inbox)

        // The last lesson of a sequence has no next lesson.
        #expect(PresentationNextLessonContext.load(
            after: second, lessons: [first, second], studentIDs: [ada], context: context
        ) == nil)
    }

    @discardableResult
    private func yearPlanEntry(
        for studentID: UUID, lessonID: UUID, on date: Date, in context: NSManagedObjectContext
    ) -> CDYearPlanEntry {
        let entry = CDYearPlanEntry(context: context)
        entry.studentID = studentID.uuidString
        entry.lessonID = lessonID.uuidString
        entry.status = .planned
        entry.plannedDate = date
        return entry
    }

    // MARK: - The session and its draft

    @Test("Newly ready children are those ready on their own or alongside work")
    func newlyReady() {
        let session = PresentationSession(presentationID: UUID())
        #expect(session.nextLessonPlace == nil)
        #expect(session.newlyReady(for: [ada, ben]).isEmpty)

        session.setEveryone(.practice)
        session.setDecision(.readyForNextLesson, for: ada)
        session.tap(.readyForNextLesson, for: ben)
        #expect(session.newlyReady(for: [ada, ben]) == [ada, ben])

        session.setDecision(.represent, for: ben)
        #expect(session.newlyReady(for: [ada, ben]) == [ada])
    }

    @Test("A Later draft keeps where the next lesson goes; a day that has passed is dropped")
    func draftKeepsThePlace() throws {
        let defaults = try #require(UserDefaults(suiteName: "PresentationNextLessonTests.\(UUID().uuidString)"))
        let context = try CoreDataTestHelpers.makeContext()

        func reloaded(_ place: PresentationNextLessonPlace?) -> PresentationNextLessonPlace? {
            let id = UUID()
            let first = PresentationSession(presentationID: id)
            first.setEveryone(.readyForNextLesson)
            first.nextLessonPlace = place
            PresentationSessionDraftStore.save(first.draft, presentationID: id, defaults: defaults)

            let second = PresentationSession(presentationID: id)
            second.loadDecisions(
                studentIDs: [ada, ben], defaultDecision: .continueObserving, context: context, defaults: defaults
            )
            return second.nextLessonPlace
        }

        let timed = PresentationNextLessonPlace(day: day(2)).settingTime(hour: 10, minute: 15)
        #expect(reloaded(nil) == nil)
        #expect(reloaded(.inbox) == .inbox)
        #expect(reloaded(PresentationNextLessonPlace(day: today)) == PresentationNextLessonPlace(day: today))
        #expect(reloaded(timed) == timed)
        #expect(reloaded(PresentationNextLessonPlace(day: day(-1))) == nil)
    }

    @Test("A draft saved before the row existed still opens")
    func olderDraftStillReads() throws {
        let defaults = try #require(UserDefaults(suiteName: "PresentationNextLessonTests.\(UUID().uuidString)"))
        let id = UUID()
        let everyone = PresentationChoice(.practice).rawValue
        let json = #"{"everyone":"\#(everyone)","overrides":{},"savedAt":0}"#
        defaults.set(Data(json.utf8), forKey: PresentationSessionDraftStore.key(for: id))

        let draft = try #require(PresentationSessionDraftStore.load(presentationID: id, defaults: defaults))
        #expect(draft.everyone == everyone)
        #expect(draft.nextLessonPlace == nil)
    }

    // MARK: - The summary

    @Test("The summary says where the next lesson goes, and for whom")
    func summary() {
        func line(
            _ place: PresentationNextLessonPlace = .inbox, recipients: Set<UUID>? = nil
        ) -> String? {
            PresentationSessionSummary.lines(.init(
                children: [.init(id: ada, name: "Maya S"), .init(id: ben, name: "Leo K")],
                pending: [ada: .readyForNextLesson, ben: .readyForNextLesson],
                decisions: [ada: .readyForNextLesson, ben: .readyForNextLesson],
                checkIn: .nextWorkCycle,
                checkInChanged: false,
                noteCount: 0,
                lessonName: "Nouns",
                nextLessonName: "Collective Nouns",
                nextLessonPlace: place,
                nextLessonRecipients: recipients
            )).first
        }
        let start = "Maya S and Leo K are ready for the next lesson: Collective Nouns"
        let onDay = PresentationNextLessonPlace(day: thursday)
        #expect(line() == "\(start) goes in the Inbox")
        #expect(line(onDay) == "\(start) \(onDay.phrase())")
        #expect(line(recipients: [ada, ben]) == "\(start) goes in the Inbox")
        #expect(line(recipients: [ada]) == "\(start) goes in the Inbox for Maya S")
        #expect(line(onDay, recipients: []) == "\(start) is already planned")
    }

    // MARK: - Pictures

    private struct PictureState {
        let name: String
        var chosen: PresentationNextLessonPlace?
        var starting: PresentationNextLessonPlace = .inbox
    }

    @Test("Pictures: the row in the Inbox, on a day, and on a day with a time")
    func pictures() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let onDay = PresentationNextLessonPlace(day: thursday)
        let states = [
            PictureState(name: "inbox"),
            PictureState(name: "day", chosen: onDay),
            PictureState(name: "day-and-time", chosen: onDay.settingTime(hour: 10, minute: 0)),
            PictureState(name: "year-plan-day", starting: PresentationNextLessonPlace(day: day(5)))
        ]
        for state in states {
            for scheme in [ColorScheme.light, .dark] {
                let session = PresentationSession(presentationID: UUID())
                session.nextLessonPlace = state.chosen
                let row = HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Next lesson").font(.caption).foregroundStyle(.secondary)
                        .frame(width: 130, alignment: .leading)
                    PresentationNextLessonRow(
                        session: session,
                        lessonName: "Collective Nouns",
                        recipientNames: ["Maya S", "Leo K"],
                        startingPlace: state.starting,
                        nextSchoolDay: thursday
                    )
                    .frame(minWidth: 420, alignment: .leading)
                }
                .padding(14)
                .environment(\.managedObjectContext, context)
                let png = try LessonTimePictures.save(
                    row, named: "next-lesson-row-\(state.name)", scheme: scheme, width: 640
                )
                #expect((png?.count ?? 0) > 1_000)
            }
        }
    }
}
