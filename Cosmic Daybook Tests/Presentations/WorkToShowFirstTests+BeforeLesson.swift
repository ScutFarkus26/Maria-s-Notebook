import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The Work tab's "Before a Lesson" list (`BeforeLessonWork`), built on
/// `WorkToShowFirst`. Split from WorkToShowFirstTests.swift for SwiftLint's
/// length limits; the helpers are that file's.
extension WorkToShowFirstTests {

    // MARK: - The Work tab's list

    @Test("Before a Lesson groups under each upcoming lesson, soonest first, each work once")
    func beforeLessonSections() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let first = lesson("Bead Addition", step: 1, in: context)
        let second = lesson("Stamp Game Addition", step: 2, in: context)
        let third = lesson("Dot Game", step: 3, in: context)
        let adaWork = try work(for: ada, on: first, in: context)
        let benWork = try work(for: ben, on: second, in: context)
        let today = AppCalendar.startOfDay(Date())
        let tomorrow = AppCalendar.addingDays(1, to: today)
        let later = AppCalendar.addingDays(1, to: tomorrow)
        let nextWeek = AppCalendar.addingDays(7, to: today)
        let presentations = [
            // Out of order on purpose: the list sorts by day.
            PresentationFactory.makeScheduled(
                lessonID: try #require(third.id), studentIDs: [ada, ben], scheduledFor: tomorrow, context: context
            ),
            PresentationFactory.makeScheduled(
                lessonID: try #require(second.id), studentIDs: [ada], scheduledFor: today, context: context
            ),
            PresentationFactory.makeScheduled(
                lessonID: try #require(third.id), studentIDs: [ben], scheduledFor: nextWeek, context: context
            )
        ]

        let list = BeforeLessonWork.build(
            presentations: presentations,
            days: [today, tomorrow, later],
            lessons: [first, second, third],
            in: context,
            now: today
        )

        #expect(list.sections.map(\.title) == [
            "Today · Stamp Game Addition",
            "\(tomorrow.formatted(.dateTime.weekday(.wide))) · Dot Game"
        ])
        #expect(list.sections.first?.works == [adaWork])
        // Ada's work is listed under the sooner lesson only.
        #expect(list.sections.last?.works == [benWork])
        let benOnly = Set([try #require(benWork.id)])
        #expect(list.works(visibleTo: benOnly) == [benWork])
        #expect(list.sections(visibleTo: benOnly).count == 1)
    }

    @Test("Two lessons with one name on one day are two sections; one lesson's two groups are one")
    func beforeLessonSectionsByLessonNotName() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let first = lesson("Bead Addition", step: 1, in: context)
        let second = lesson("Stamp Game", step: 2, in: context)
        // A second sequence with a lesson of the same name.
        let snakeFirst = lesson("Snake Game", step: 1, sequence: "Snake", in: context)
        let snakeSecond = lesson("Stamp Game", step: 2, sequence: "Snake", in: context)
        let adaWork = try work(for: ada, on: first, in: context)
        let benWork = try work(for: ben, on: snakeFirst, in: context)
        let benAddition = try work(for: ben, on: first, in: context)
        let today = AppCalendar.startOfDay(Date())
        let presentations = [
            PresentationFactory.makeScheduled(
                lessonID: try #require(second.id), studentIDs: [ada], scheduledFor: today, context: context
            ),
            PresentationFactory.makeScheduled(
                lessonID: try #require(snakeSecond.id), studentIDs: [ben], scheduledFor: today, context: context
            ),
            PresentationFactory.makeScheduled(
                lessonID: try #require(second.id), studentIDs: [ben], scheduledFor: today, context: context
            )
        ]

        let list = BeforeLessonWork.build(
            presentations: presentations,
            days: [today],
            lessons: [first, second, snakeFirst, snakeSecond],
            in: context,
            now: today
        )

        #expect(list.sections.count == 2)
        #expect(Set(list.sections.map(\.id)).count == 2)
        #expect(list.sections.allSatisfy { $0.title == "Today · Stamp Game" })
        let addition = try #require(list.sections.first { $0.works.contains(adaWork) })
        #expect(Set(addition.works) == [adaWork, benAddition], "both groups of the one lesson")
        #expect(list.sections.contains { $0.works == [benWork] })
    }

    @Test("A day more than six days out is named with its date")
    func farDayNamedWithDate() throws {
        let today = AppCalendar.startOfDay(Date())
        let thursday = AppCalendar.addingDays(3, to: today)
        let farOff = AppCalendar.addingDays(10, to: today)

        #expect(WorkToShowFirst.dayName(today, now: today) == "Today")
        #expect(WorkToShowFirst.dayName(thursday, now: today) == thursday.formatted(.dateTime.weekday(.wide)))
        #expect(
            WorkToShowFirst.dayName(farOff, now: today)
                == farOff.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        )
        #expect(WorkToShowFirst.dayName(farOff, now: today) != farOff.formatted(.dateTime.weekday(.wide)))
    }
}
