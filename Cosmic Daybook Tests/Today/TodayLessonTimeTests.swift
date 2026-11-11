import CoreData
import Foundation
import SwiftUI
import Testing
@testable import CosmicDaybook

/// Lesson times on Today and on the lesson's sheet (docs/Plans/Plan - Lesson
/// times on cards.md, Phase 4, decisions 4, 5 and 9): timed lessons lead
/// Today's list in clock order whatever order was saved by hand, a drag among
/// the other rows can't put one above them, and the sheet's date edits set,
/// keep and remove a time through the planner's rules.
@Suite("Today and sheet lesson times")
@MainActor
struct TodayLessonTimeTests {

    private let calendar = AppCalendar.shared

    /// Wednesday, November 11, 2026.
    private var wednesday: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 11)) ?? Date()
    }

    private func at(_ hour: Int, _ minute: Int = 0, second: Int = 0, on day: Date? = nil) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: second, of: day ?? wednesday) ?? wednesday
    }

    private func lesson(_ scheduledFor: Date, in context: NSManagedObjectContext) -> CDLessonAssignment {
        let assignment = CDLessonAssignment(context: context)
        assignment.id = UUID()
        assignment.schedule(for: scheduledFor, using: calendar)
        return assignment
    }

    private func timed(_ hour: Int, _ minute: Int, in context: NSManagedObjectContext) -> CDLessonAssignment {
        lesson(DayHalfPlanner.settingTime(hour: hour, minute: minute, on: wednesday, using: calendar), in: context)
    }

    private func saveHandOrder(_ lessons: [CDLessonAssignment], in context: NSManagedObjectContext) {
        for (position, assignment) in lessons.enumerated() {
            let row = CDTodayAgendaOrder(context: context)
            row.day = AppCalendar.startOfDay(wednesday)
            row.itemType = .lesson
            row.itemID = assignment.id
            row.position = Int64(position)
        }
    }

    // MARK: - Today's order

    @Test("With no saved order, timed lessons lead in clock order and the rest keep the order given")
    func noSavedOrder() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let firstSlot = lesson(at(9, second: 0), in: context)
        let tenThirty = timed(10, 30, in: context)
        let secondSlot = lesson(at(9, second: 1), in: context)
        let nine = timed(9, 0, in: context)
        let afternoonSlot = lesson(at(14), in: context)

        let agenda = TodayAgendaBuilder.buildAgenda(
            lessons: [firstSlot, tenThirty, secondSlot, nine, afternoonSlot], day: wednesday, context: context
        )
        #expect(agenda.map(\.id) == [nine, tenThirty, firstSlot, secondSlot, afternoonSlot].compactMap(\.id))
    }

    @Test("A saved hand order never puts an untimed row above a timed one; it orders the rest")
    func savedOrderKeepsTimedOnTop() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let slotA = lesson(at(9, second: 0), in: context)
        let slotB = lesson(at(9, second: 1), in: context)
        let onePM = timed(13, 0, in: context)
        let quarterToNine = timed(8, 45, in: context)
        // Saved before the times were set: B, the 1:00, A, the 8:45.
        saveHandOrder([slotB, onePM, slotA, quarterToNine], in: context)

        let agenda = TodayAgendaBuilder.buildAgenda(
            lessons: [slotA, slotB, onePM, quarterToNine], day: wednesday, context: context
        )
        #expect(agenda.map(\.id) == [quarterToNine, onePM, slotB, slotA].compactMap(\.id))
    }

    @Test("A lesson set for exactly 9:00 counts as timed; a 9:00 ordering slot doesn't")
    func exactNineIsTimed() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let slot = lesson(at(9), in: context)
        let nine = timed(9, 0, in: context)
        #expect(TodayAgendaBuilder.setTime(of: .lesson(slot)) == nil)
        #expect(TodayAgendaBuilder.setTime(of: .lesson(nine)) == LessonClockTime(hour: 9, minute: 0))

        let agenda = TodayAgendaBuilder.buildAgenda(lessons: [slot, nine], day: wednesday, context: context)
        #expect(agenda.map(\.id) == [nine, slot].compactMap(\.id))
    }

    @Test("Dragging an untimed row to the very top leaves the timed rows on top")
    func moveAboveTimedRows() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let nine = timed(9, 15, in: context)
        let eleven = timed(11, 0, in: context)
        let slotA = lesson(at(9, second: 0), in: context)
        let slotB = lesson(at(9, second: 1), in: context)
        let items: [AgendaItem] = [nine, eleven, slotA, slotB].map { .lesson($0) }

        let moved = TodayAgendaBuilder.moving(items, fromOffsets: [3], toOffset: 0)
        #expect(moved.map(\.id) == [nine, eleven, slotB, slotA].compactMap(\.id))
    }

    @Test("A move among the untimed rows is kept, and saved order rebuilds the same list")
    func moveAmongUntimedRowsIsSaved() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let ten = timed(10, 0, in: context)
        let slotA = lesson(at(9, second: 0), in: context)
        let slotB = lesson(at(9, second: 1), in: context)
        let slotC = lesson(at(14), in: context)
        let items: [AgendaItem] = [ten, slotA, slotB, slotC].map { .lesson($0) }

        let moved = TodayAgendaBuilder.moving(items, fromOffsets: [3], toOffset: 1)
        #expect(moved.map(\.id) == [ten, slotC, slotA, slotB].compactMap(\.id))

        TodayAgendaBuilder.saveOrder(items: moved, day: wednesday, context: context)
        let rebuilt = TodayAgendaBuilder.buildAgenda(
            lessons: [ten, slotA, slotB, slotC], day: wednesday, context: context
        )
        #expect(rebuilt.map(\.id) == moved.map(\.id))
    }

    @Test("A given lesson isn't treated as timed")
    func presentedIsNotTimed() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let given = timed(10, 0, in: context)
        given.markPresented(at: wednesday, snapshotLesson: false)
        #expect(TodayAgendaBuilder.setTime(of: .lesson(given)) == nil)
    }

    // MARK: - The sheet's date edits

    @Test("Setting a time through the sheet's date, including exactly 9:00 and 2:00, reads back as that time")
    func sheetSetsTime() {
        let slot = at(9, second: 3)
        for (hour, minute) in [(10, 30), (9, 0), (14, 0), (8, 45)] {
            let edited = ScheduledDateEdits.settingTime(hour: hour, minute: minute, on: slot, using: calendar)
            let readBack = ScheduledDateEdits.clockTime(of: edited, using: calendar)
            #expect(readBack == LessonClockTime(hour: hour, minute: minute))
            #expect(edited.map { calendar.isDate($0, inSameDayAs: wednesday) } == true)
        }
        #expect(ScheduledDateEdits.settingTime(hour: 10, minute: 0, on: nil, using: calendar) == nil)
    }

    @Test("Removing the time keeps the day and the half, as an ordering slot")
    func sheetRemovesTime() {
        let morning = ScheduledDateEdits.settingTime(hour: 9, minute: 0, on: wednesday, using: calendar)
        let removed = ScheduledDateEdits.removingTime(from: morning, using: calendar)
        #expect(ScheduledDateEdits.clockTime(of: removed, using: calendar) == nil)
        #expect(removed.map { DayHalfPlanner.moment(of: $0, using: calendar) } == .half(.morning))
        #expect(removed.map { calendar.isDate($0, inSameDayAs: wednesday) } == true)

        let afternoon = ScheduledDateEdits.settingTime(hour: 13, minute: 30, on: wednesday, using: calendar)
        let removedAfternoon = ScheduledDateEdits.removingTime(from: afternoon, using: calendar)
        #expect(removedAfternoon.map { DayHalfPlanner.moment(of: $0, using: calendar) } == .half(.afternoon))

        let slot = at(14, second: 4)
        #expect(ScheduledDateEdits.removingTime(from: slot, using: calendar) == slot)
    }

    @Test("Picking another day on the sheet keeps a set time, 9:00 included, and keeps a slot's rank")
    func sheetDayChangeKeepsTime() throws {
        let friday = try #require(calendar.date(byAdding: .day, value: 2, to: wednesday))
        // The date picker hands back the new day at whatever time it likes.
        let picked = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: friday)

        for (hour, minute) in [(10, 30), (9, 0), (14, 0)] {
            let set = ScheduledDateEdits.settingTime(hour: hour, minute: minute, on: wednesday, using: calendar)
            let moved = ScheduledDateEdits.changingDay(of: set, to: picked, using: calendar)
            let readBack = ScheduledDateEdits.clockTime(of: moved, using: calendar)
            #expect(readBack == LessonClockTime(hour: hour, minute: minute))
            #expect(moved.map { calendar.isDate($0, inSameDayAs: friday) } == true)
        }

        let slot = at(14, second: 3)
        let movedSlot = ScheduledDateEdits.changingDay(of: slot, to: picked, using: calendar)
        #expect(movedSlot.map { DayHalfPlanner.moment(of: $0, using: calendar) } == .half(.afternoon))
        #expect(movedSlot.map { calendar.component(.second, from: $0) } == 3)

        #expect(ScheduledDateEdits.changingDay(of: slot, to: nil, using: calendar) == nil)
        #expect(ScheduledDateEdits.changingDay(of: nil, to: picked, using: calendar) == picked)
    }

    @Test("Picking a time across the daylight-saving change on Sunday, March 14, 2027 keeps the clock time")
    func sheetDayChangeAcrossDaylightSaving() throws {
        let friday = try #require(calendar.date(from: DateComponents(year: 2027, month: 3, day: 12)))
        let monday = try #require(calendar.date(from: DateComponents(year: 2027, month: 3, day: 15)))
        let set = ScheduledDateEdits.settingTime(hour: 10, minute: 15, on: friday, using: calendar)
        let moved = ScheduledDateEdits.changingDay(of: set, to: monday, using: calendar)
        #expect(ScheduledDateEdits.clockTime(of: moved, using: calendar) == LessonClockTime(hour: 10, minute: 15))
    }

    @Test("The picker's taken times are the day's other set times, not this lesson's, a slot's or a given lesson's")
    func takenMinutes() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let editing = timed(10, 0, in: context)
        _ = timed(10, 30, in: context)
        _ = timed(9, 0, in: context)
        _ = lesson(at(9, second: 2), in: context)
        let given = timed(11, 0, in: context)
        given.markPresented(at: wednesday, snapshotLesson: false)
        let thursday = try #require(calendar.date(byAdding: .day, value: 1, to: wednesday))
        _ = lesson(DayHalfPlanner.settingTime(hour: 13, minute: 0, on: thursday, using: calendar), in: context)
        try context.save()

        let taken = ScheduledDateEdits.takenMinutes(on: wednesday, excluding: editing.id, in: context, using: calendar)
        #expect(taken == [9 * 60, 10 * 60 + 30])
    }

    // MARK: - Words

    @Test("The sheet's status line names the time when one is set")
    func statusLine() throws {
        let set = DayHalfPlanner.settingTime(hour: 10, minute: 0, on: wednesday, using: calendar)
        let time = try #require(ScheduledDateEdits.clockTime(of: set, using: calendar))
        let line = LessonTimeText.statusLine(
            plannedOn: set, at: time, now: at(8, on: wednesday), calendar: calendar,
            locale: Locale(identifier: "en_US")
        )
        #expect(line == "Planned for this morning at 10:00")
    }

    // MARK: - Pictures

    @Test("Pictures: three Today rows, two with a time and one without")
    func todayRowsPicture() throws {
        let rows = VStack(alignment: .leading, spacing: 16) {
            LessonListRow(
                lessonName: "Long Division with Racks and Tubes",
                startTime: LessonClockTime(hour: 9, minute: 15),
                children: [.init(id: UUID(), name: "Maya S"), .init(id: UUID(), name: "Theo R")],
                hereText: "2 of 2 here",
                isPresented: false
            )
            Divider()
            LessonListRow(
                lessonName: "Timeline of Life",
                startTime: LessonClockTime(hour: 13, minute: 30),
                children: [.init(id: UUID(), name: "Ava L"), .init(id: UUID(), name: "Noah K", isAbsent: true)],
                hereText: "1 of 2 here",
                isPresented: false
            )
            Divider()
            LessonListRow(
                lessonName: "Parts of Speech: the Adverb",
                children: [.init(id: UUID(), name: "Lily P")],
                hereText: "1 of 1 here",
                isPresented: false
            )
        }
        .padding(20)
        let data = try LessonTimePictures.save(rows, named: "today-rows", scheme: .dark, width: 420)
        #expect((data?.count ?? 0) > 0)
    }

    @Test("Pictures: the sheet's status line and Time row with a time set")
    func sheetSectionPicture() throws {
        // The section's date and half controls are system controls, which
        // `ImageRenderer` can't draw; the status line and the Time row are
        // this phase's part of the sheet.
        let set = DayHalfPlanner.settingTime(hour: 10, minute: 0, on: wednesday, using: calendar)
        let time = try #require(ScheduledDateEdits.clockTime(of: set, using: calendar))
        let status = LessonTimeText.statusLine(
            plannedOn: set, at: time, now: at(8, on: calendar.date(byAdding: .day, value: -2, to: wednesday)),
            calendar: calendar
        )
        let section = VStack(alignment: .leading, spacing: 14) {
            Text("Timeline of Life").font(.title3.bold())
            Text(status).font(.subheadline).foregroundStyle(.secondary)
            Divider()
            ScheduledTimeRow(scheduledFor: .constant(set), lessonTitle: "Timeline of Life", presentationID: nil)
        }
        .padding(20)
        let data = try LessonTimePictures.save(section, named: "sheet-time-row", scheme: .dark, width: 420)
        #expect((data?.count ?? 0) > 0)
    }
}
