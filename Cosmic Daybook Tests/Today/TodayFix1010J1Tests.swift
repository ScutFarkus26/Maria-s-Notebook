import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-10, Part 2 #86 and #87: Today kept a child who left in its
/// student cache until the screen was rebuilt, its Meetings ignored the level
/// filter and never said "Student removed", and reordering the agenda under a
/// level filter erased the other levels' order.
@Suite("Today cache, meetings and agenda order (fix 10-10 J1)")
@MainActor
struct TodayFix1010J1Tests {

    // MARK: - Student cache

    @Test("A child who leaves drops out of Today's student cache on the next reload")
    func departedChildLeavesCache() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stern")
        #expect(CoreDataTestHelpers.save(context))
        let mayaID = try #require(maya.id)

        let cache = TodayCacheManager()
        cache.loadStudentsIfNeeded(ids: [mayaID], context: context)
        #expect(cache.studentsByID[mayaID] === maya)

        maya.enrollmentStatus = .withdrawn
        #expect(CoreDataTestHelpers.save(context))
        cache.loadStudentsIfNeeded(ids: [mayaID], context: context)

        #expect(cache.studentsByID[mayaID] == nil)
        #expect(cache.departedStudents(context: context)[mayaID] === maya)
    }

    // MARK: - Meetings

    @Test("Meetings follow the level filter, and every meeting shows under All")
    func meetingsFollowLevelFilter() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let lower = CoreDataTestHelpers.seedStudent(in: context, firstName: "Noa", lastName: "Cohen", level: .lower)
        let upper = CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Dechter", level: .upper)
        let lowerMeeting = CDScheduledMeeting(context: context)
        lowerMeeting.studentID = try #require(lower.id).uuidString
        let upperMeeting = CDScheduledMeeting(context: context)
        upperMeeting.studentID = try #require(upper.id).uuidString
        let goneMeeting = CDScheduledMeeting(context: context)
        goneMeeting.studentID = UUID().uuidString
        #expect(CoreDataTestHelpers.save(context))

        let cached = [try #require(lower.id): lower, try #require(upper.id): upper]
        let all = [lowerMeeting, upperMeeting, goneMeeting]
        #expect(TodayMeetingRows.filter(all, studentsByID: cached, levelFilter: .upper) == [upperMeeting])
        #expect(TodayMeetingRows.filter(all, studentsByID: cached, levelFilter: .lower) == [lowerMeeting])
        #expect(TodayMeetingRows.filter(all, studentsByID: cached, levelFilter: .all) == all)
    }

    @Test("A meeting row names a child who left, and says Student removed when no one is left")
    func meetingNames() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let etty = CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Dechter")
        let left = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Sarah", lastName: "Klein", enrollmentStatus: .withdrawn
        )
        #expect(CoreDataTestHelpers.save(context))
        let known = [try #require(etty.id): etty, try #require(left.id): left]

        #expect(TodayMeetingRows.names(for: [try #require(left.id)], knownStudents: known) == "Sarah K")
        #expect(TodayMeetingRows.names(for: [UUID()], knownStudents: known) == "Student removed")
        #expect(TodayMeetingRows.names(for: [], knownStudents: known) == "Student removed")
        #expect(
            TodayMeetingRows.names(for: [try #require(etty.id), UUID()], knownStudents: known) == "Etty D"
        )
    }

    // MARK: - Agenda order

    @Test("Rearranging what one level shows keeps the other rows where they were")
    func mergedOrderKeepsHiddenSlots() {
        let ids = (0..<5).map { _ in UUID() }
        let saved = ids.map { (AgendaItemType.lesson, $0) }
        // Under a filter only items 1 and 3 show; she drags 3 above 1.
        let shown = [(AgendaItemType.lesson, ids[3]), (AgendaItemType.lesson, ids[1])]
        let merged = TodayAgendaBuilder.mergedOrder(saved: saved, shown: shown).map(\.1)
        #expect(merged == [ids[0], ids[3], ids[2], ids[1], ids[4]])

        // A shown item with no saved place yet goes last.
        let newcomer = UUID()
        let withNew = TodayAgendaBuilder.mergedOrder(
            saved: saved, shown: shown + [(.lesson, newcomer)]
        ).map(\.1)
        #expect(withNew == [ids[0], ids[3], ids[2], ids[1], ids[4], newcomer])
    }

    @Test("Saving the Meetings order under a filter keeps the hidden meetings' places")
    func savedMeetingOrderUnderFilter() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let day = AppCalendar.startOfDay(Date())
        let meetings = (0..<4).map { _ in CDScheduledMeeting(context: context) }
        #expect(CoreDataTestHelpers.save(context))
        let ids = try meetings.map { try #require($0.id) }

        TodayAgendaBuilder.saveMeetingOrder(meetingIDs: ids, day: day, context: context)
        // Under a filter only meetings 0 and 2 show; she moves 2 to the top.
        TodayAgendaBuilder.saveMeetingOrder(meetingIDs: [ids[2], ids[0]], day: day, context: context)

        let ordered = TodayAgendaBuilder.orderMeetings(meetings, day: day, context: context)
        #expect(ordered.compactMap(\.id) == [ids[2], ids[1], ids[0], ids[3]])
    }
}
