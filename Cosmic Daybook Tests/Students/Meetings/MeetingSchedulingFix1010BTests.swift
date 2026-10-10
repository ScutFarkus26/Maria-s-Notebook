import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-10-10, Part 2 #69 and #71: clearing a child's meeting date
// leaves the group meetings she's first in, and a lesson given later on the
// day of her last meeting counts as given since it.
@Suite("Meeting scheduling and lessons since (bug hunt 2026-10-10)")
@MainActor
struct MeetingSchedulingFix1010BTests {

    // MARK: - Clearing a date (#69)

    @Test("Clearing a child's meeting date leaves the group meetings she's first in")
    func clearLeavesGroupMeetings() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let maya = UUID()
        let eli = UUID()
        let today = AppCalendar.startOfDay(Date())
        MeetingScheduler.scheduleMeeting(studentID: maya, date: AppCalendar.addingDays(1, to: today), context: context)
        MeetingScheduler.scheduleMeeting(studentID: eli, date: AppCalendar.addingDays(1, to: today), context: context)
        MeetingScheduler.scheduleGroupMeeting(
            participantIDs: [maya, eli], date: AppCalendar.addingDays(7, to: today), context: context
        )

        MeetingScheduler.clearMeetings(studentID: maya, context: context)

        let left = context.safeFetch(CDFetchRequest(CDScheduledMeeting.self))
        #expect(left.count == 2)
        let group = try #require(left.first { $0.isGroupMeeting })
        #expect(group.participantStudentIDs == [maya.uuidString, eli.uuidString])
        #expect(left.contains { !$0.isGroupMeeting && $0.studentID == eli.uuidString })
        #expect(!left.contains { !$0.isGroupMeeting && $0.studentID == maya.uuidString })
        #expect(!context.hasChanges)
    }

    // MARK: - Lessons since the last meeting (#71)

    /// A child, a meeting this morning at ten, a lesson recorded for today (a
    /// given day is stored at its start), one from yesterday, and an undated
    /// one marked today.
    private struct LessonsRoom {
        let context: NSManagedObjectContext
        let child: UUID
        let meetingTime: Date
        let today: CDLessonAssignment
        let yesterday: CDLessonAssignment
        let undatedToday: CDLessonAssignment
    }

    private func makeLessonsRoom() throws -> LessonsRoom {
        let context = try CoreDataTestHelpers.makeContext()
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        let child = try #require(student.id)
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Stamp Game")
        let dayStart = AppCalendar.startOfDay(Date())
        let meetingTime = try #require(AppCalendar.shared.date(byAdding: .hour, value: 10, to: dayStart))
        let today = PresentationFactory.makePresented(
            lesson: lesson, students: [student], presentedAt: dayStart, context: context
        )
        let yesterday = PresentationFactory.makePresented(
            lesson: lesson, students: [student], presentedAt: AppCalendar.addingDays(-1, to: dayStart),
            createdAt: AppCalendar.addingDays(-1, to: dayStart), context: context
        )
        let undatedToday = PresentationFactory.makeDraft(
            lesson: lesson, students: [student], createdAt: dayStart, context: context
        )
        undatedToday.markPreviouslyPresented()
        #expect(CoreDataTestHelpers.save(context))
        return LessonsRoom(
            context: context, child: child, meetingTime: meetingTime,
            today: today, yesterday: yesterday, undatedToday: undatedToday
        )
    }

    @Test("A lesson given later on the meeting day counts as since the meeting; one from the day before doesn't")
    func lessonsLaterOnTheMeetingDay() throws {
        let room = try makeLessonsRoom()
        let since = MeetingWorkSnapshotHelper.lessonsSinceLastMeeting(
            for: room.child, lastMeetingDate: room.meetingTime,
            allLessonAssignments: [room.today, room.yesterday, room.undatedToday]
        )
        #expect(Set(since.compactMap(\.id)) == Set([room.today, room.undatedToday].compactMap(\.id)))
    }

    @Test("The meeting's own fetch reads lessons since by day too")
    func lessonsSincePredicateByDay() throws {
        let room = try makeLessonsRoom()
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = MeetingWorkSnapshotHelper.lessonsSincePredicate(
            cutoff: SchoolYearCounters.countFrom(room.meetingTime)
        )
        let fetched = room.context.safeFetch(request)
        #expect(Set(fetched.compactMap(\.id)) == Set([room.today, room.undatedToday].compactMap(\.id)))
    }
}
