import CoreData
import Foundation
import SwiftUI
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-10-11, Students (#26–#34): recall Forgotten on a group
// presentation, finishing one child's meeting from a group booking, a lesson
// mastered twice in the recall queue, pinned notes past the first page, the
// Next Birthday sort, departed children in recall's By Student, and the
// profile's attendance counts.
@Suite("Students and meetings (bug hunt 2026-10-11)")
@MainActor
struct StudentsMeetingsFix1011STests {

    // MARK: - Recall Forgotten (#26)

    private func recall(
        _ outcome: RecallOutcome, for student: CDStudent, lesson: CDLesson, in context: NSManagedObjectContext
    ) throws {
        let coordinator = SaveCoordinator()
        coordinator.suppressAlerts = true
        let service = RecallService(context: context, saveCoordinator: coordinator, schoolYearStore: SchoolYearStore())
        let entry = RecallQueueEntry(
            id: UUID().uuidString,
            studentID: try #require(student.id).uuidString,
            area: lesson.area,
            sequence: lesson.sequence,
            frontierLessonID: try #require(lesson.id),
            frontierLessonName: lesson.name,
            frontierOrderInSequence: 1,
            frontierMasteredAt: nil,
            coveredLessons: [],
            lastCheckedAt: nil,
            dueReason: .spacedDue
        )
        #expect(service.record(entry: entry, outcome: outcome, note: ""))
    }

    private func given(
        _ students: [CDStudent], lesson: CDLesson, in context: NSManagedObjectContext
    ) throws -> CDLessonAssignment {
        let assignment = PresentationFactory.makeDraft(
            lessonID: try #require(lesson.id), studentIDs: try students.map { try #require($0.id) }, context: context
        )
        assignment.markPresented(at: try CoreDataTestHelpers.day("2026-09-14"))
        return assignment
    }

    @Test("Forgotten on a group presentation marks only that child for re-presenting")
    func forgottenInAGroupIsPerChild() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada")
        let ben = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ben")
        let lesson = CoreDataTestHelpers.seedLesson(in: context)
        let group = try given([ada, ben], lesson: lesson, in: context)
        #expect(CoreDataTestHelpers.save(context))

        try recall(.forgotten, for: ada, lesson: lesson, in: context)

        #expect(!group.needsAnotherPresentation)
        let representations = ChildRepresentations(in: context)
        let groupID = try #require(group.id).uuidString
        #expect(representations.contains(presentationID: groupID, studentID: try #require(ada.id).uuidString))
        #expect(!representations.contains(presentationID: groupID, studentID: try #require(ben.id).uuidString))
        #expect(group.needsAnotherPresentation(for: try #require(ada.id).uuidString, given: representations))
        #expect(!group.needsAnotherPresentation(for: try #require(ben.id).uuidString, given: representations))
    }

    // Guard: passes on the old code too.
    @Test("Forgotten on a presentation she had alone still sets its flag")
    func forgottenAloneSetsTheFlag() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada")
        let lesson = CoreDataTestHelpers.seedLesson(in: context)
        let solo = try given([ada], lesson: lesson, in: context)
        #expect(CoreDataTestHelpers.save(context))

        try recall(.forgotten, for: ada, lesson: lesson, in: context)

        #expect(solo.needsAnotherPresentation)
    }

    // MARK: - Group bookings (#27)

    private func bookings(_ context: NSManagedObjectContext) -> [CDScheduledMeeting] {
        context.safeFetch(CDFetchRequest(CDScheduledMeeting.self))
    }

    @Test("Completing one child's meeting takes only her off the group booking")
    func completeBookingLeavesTheRestOfTheGroup() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let maya = UUID(), eli = UUID(), ora = UUID()
        let today = AppCalendar.startOfDay(Date())
        MeetingScheduler.scheduleGroupMeeting(participantIDs: [maya, eli, ora], date: today, context: context)

        let bookedFor = MeetingScheduler.completeBooking(studentID: maya, heldOn: Date(), context: context)
        #expect(CoreDataTestHelpers.save(context))

        #expect(bookedFor == today)
        let group = try #require(bookings(context).first)
        #expect(bookings(context).count == 1)
        #expect(group.participantStudentIDs == [eli.uuidString, ora.uuidString])
        // A group stores its first participant in studentID; it follows.
        #expect(group.studentID == eli.uuidString)
    }

    @Test("The booking goes once the last child in it has met")
    func completeBookingDeletesAnEmptyGroup() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let maya = UUID(), eli = UUID()
        let today = AppCalendar.startOfDay(Date())
        MeetingScheduler.scheduleGroupMeeting(participantIDs: [maya, eli], date: today, context: context)

        _ = MeetingScheduler.completeBooking(studentID: maya, heldOn: Date(), context: context)
        _ = MeetingScheduler.completeBooking(studentID: eli, heldOn: Date(), context: context)
        #expect(CoreDataTestHelpers.save(context))

        #expect(bookings(context).isEmpty)
    }

    // Guard: passes on the old code too.
    @Test("A later group booking stays whole when she meets today")
    func completeBookingLeavesALaterGroup() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let maya = UUID(), eli = UUID()
        let today = AppCalendar.startOfDay(Date())
        MeetingScheduler.scheduleGroupMeeting(
            participantIDs: [maya, eli], date: AppCalendar.addingDays(7, to: today), context: context
        )

        #expect(MeetingScheduler.completeBooking(studentID: maya, heldOn: Date(), context: context) == nil)
        #expect(try #require(bookings(context).first).participantStudentIDs == [maya.uuidString, eli.uuidString])
    }

    @Test("Today's Complete on a group booking keeps it for the children not yet met")
    func todayCompleteKeepsTheRest() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let maya = UUID(), eli = UUID()
        let today = AppCalendar.startOfDay(Date())
        MeetingScheduler.scheduleGroupMeeting(participantIDs: [maya, eli], date: today, context: context)
        let meetingID = try #require(bookings(context).first?.id)

        // The session files the meeting (completeBooking), then Today clears
        // the booking it was opened from.
        _ = MeetingScheduler.completeBooking(studentID: eli, heldOn: Date(), context: context)
        #expect(CoreDataTestHelpers.save(context))
        MeetingScheduler.clearMeeting(id: meetingID, completedFor: eli, context: context)

        let left = bookings(context)
        #expect(left.count == 1)
        #expect(left.first?.participantStudentIDs == [maya.uuidString])
        #expect(!context.hasChanges)
    }

    // Guard: passes on the old code too.
    @Test("Today's Complete on an individual booking deletes it")
    func todayCompleteDeletesAnIndividualBooking() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let maya = UUID()
        MeetingScheduler.scheduleMeeting(studentID: maya, date: Date(), context: context)
        let meetingID = try #require(bookings(context).first?.id)

        MeetingScheduler.clearMeeting(id: meetingID, completedFor: maya, context: context)

        #expect(bookings(context).isEmpty)
    }

    // MARK: - Recall duplicates (#28)

    @Test("A lesson mastered twice is one queue entry, and its strand covers each lower lesson once")
    func duplicateMasteryIsOneEntry() throws {
        let board = UUID(), stamp = UUID(), racks = UUID()
        let lessons = [
            RecallLesson(id: board, name: "Board", area: "Math", sequence: "Division", orderInSequence: 1),
            RecallLesson(id: stamp, name: "Stamp", area: "Math", sequence: "Division", orderInSequence: 2),
            RecallLesson(id: racks, name: "Racks", area: "Math", sequence: "Division", orderInSequence: 3)
        ]
        let early = Date(timeIntervalSince1970: 1_741_000_000)
        let later = Date(timeIntervalSince1970: 1_745_000_000)
        let mastered = [
            RecallMastery(studentID: "S1", lessonID: board.uuidString, masteredAt: early),
            RecallMastery(studentID: "S1", lessonID: stamp.uuidString, masteredAt: later),
            RecallMastery(studentID: "S1", lessonID: stamp.uuidString, masteredAt: early),
            RecallMastery(studentID: "S1", lessonID: racks.uuidString, masteredAt: later),
            RecallMastery(studentID: "S1", lessonID: racks.uuidString.lowercased(), masteredAt: early)
        ]
        let config = RecallConfig(
            schoolYearStart: Date(timeIntervalSince1970: 1_756_684_800), schoolYearKey: "2025-2026",
            spacedInterval: 90 * 86_400, now: Date(timeIntervalSince1970: 1_757_000_000)
        )

        let entries = RecallFrontierEngine.buildQueue(
            lessons: lessons, mastered: mastered, existing: [], config: config
        )

        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry.frontierLessonID == racks)
        #expect(entry.frontierMasteredAt == early)
        #expect(entry.coversCount == 2)
        #expect(entry.coveredLessons.map(\.lessonID) == [board, stamp])
        #expect(entry.coveredLessons.last?.originalMasteredAt == early)
    }

    @Test("Still Has It writes one covered row per lower lesson, even from a doubled entry")
    func coveredIntentsDedupe() {
        let board = UUID(), racks = UUID()
        let ref = RecallCoveredRef(lessonID: board, name: "Board", originalMasteredAt: nil)
        let entry = RecallQueueEntry(
            id: "S1|\(racks.uuidString)", studentID: "S1", area: "Math", sequence: "Division",
            frontierLessonID: racks, frontierLessonName: "Racks", frontierOrderInSequence: 3,
            frontierMasteredAt: nil, coveredLessons: [ref, ref], lastCheckedAt: nil, dueReason: .spacedDue
        )
        let intents = RecallFrontierEngine.coveredIntents(forRetained: entry, existing: [], schoolYearKey: "2025-2026")
        #expect(intents.count == 1)
    }

    // MARK: - Pinned notes (#29)

    private func note(daysAgo: Int, pinned: Bool = false) -> UnifiedNoteItem {
        UnifiedNoteItem(
            id: UUID(), date: Date(timeIntervalSinceNow: -Double(daysAgo) * 86_400), body: "Note \(daysAgo)",
            source: .general, contextText: "", color: .gray, associatedID: nil, tags: [],
            includeInReport: false, needsFollowUp: false, imagePath: nil, reportedBy: nil,
            reporterName: nil, isPinned: pinned
        )
    }

    @Test("A pinned note stays in Pinned however many newer notes there are")
    func pinnedFromTheWholeList() {
        let newer = (0..<40).map { note(daysAgo: $0) }
        let pinnedOld = note(daysAgo: 100, pinned: true)
        let all = newer + [pinnedOld]

        let items = StudentNotesTimelineList.DisplayedItems.make(
            from: all, displayedCount: 30, calendar: AppCalendar.shared
        )

        #expect(items.pinned.map(\.id) == [pinnedOld.id])
        // The page holds 30 unpinned notes; ten more wait behind Show More.
        #expect(items.grouped.flatMap(\.items).count == 30)
        #expect(items.remainingCount == 10)
    }

    // MARK: - Next Birthday sort (#31)

    @Test("A child with no birthday sorts last by Next Birthday")
    func noBirthdaySortsLast() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let none = CoreDataTestHelpers.seedStudent(in: context, firstName: "Nobirthday")
        let soon = CoreDataTestHelpers.seedStudent(in: context, firstName: "Soon")
        let today = try CoreDataTestHelpers.day("2026-10-11")
        soon.birthday = try CoreDataTestHelpers.day("2016-10-20")
        none.birthday = nil
        #expect(CoreDataTestHelpers.save(context))

        let sorted = StudentsViewModel.filteredStudents([none, soon], filter: .all, sortOrder: .birthday, today: today)

        #expect(sorted.map(\.firstName) == ["Soon", "Nobirthday"])
    }

    // MARK: - Recall By Student (#32)

    @Test("Recall's By Student names a child who has left")
    func recallNamesDepartedChildren() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let gone = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Etty", lastName: "Dahan", enrollmentStatus: .withdrawn
        )
        let store = SchoolYearStore()
        let check = CDLessonRecallCheck(context: context)
        check.studentID = try #require(gone.id).uuidString
        check.lessonID = UUID().uuidString
        check.outcome = .retained
        check.source = .observed
        check.checkedAt = Date()
        check.schoolYearKey = store.current.key
        #expect(CoreDataTestHelpers.save(context))

        let model = RecallQueueViewModel()
        model.loadData(context: context, schoolYearStore: store)

        #expect(model.retentionByStudent.map(\.name) == [gone.fullName])
    }

    // MARK: - Profile attendance (#34)

    @Test("The profile counts a duplicated day once and a late arrival who left early as tardy")
    func profileAttendanceCounts() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let ora = UUID()
        let reference = try CoreDataTestHelpers.day("2026-10-15")
        let start = FloridaGradeCalculator.schoolYearStart(for: reference, calendar: AppCalendar.shared)
        func day(_ offset: Int) -> Date { AppCalendar.addingDays(offset, to: start) }
        func mark(_ status: AttendanceStatus, _ offset: Int) -> CDAttendanceRecord {
            let record = CoreDataTestHelpers.seedAttendance(in: context, studentID: ora, date: day(offset))
            record.status = status
            return record
        }
        // Two devices marked day 3 tardy before syncing: one late day.
        _ = mark(.tardy, 3)
        _ = mark(.tardy, 3)
        // Absent twice on day 5 the same way: one absence.
        _ = mark(.absent, 5)
        _ = mark(.absent, 5)
        // Came late on day 8, then left early: still late that day.
        let lateThenLeft = mark(.leftEarly, 8)
        lateThenLeft.statusBeforeLeavingRaw = AttendanceStatus.tardy.rawValue
        // On time on day 9, then left early: not late.
        let onTimeThenLeft = mark(.leftEarly, 9)
        onTimeThenLeft.statusBeforeLeavingRaw = AttendanceStatus.present.rawValue
        #expect(CoreDataTestHelpers.save(context))

        let counts = try AttendanceInfoRow.schoolYearCounts(studentID: ora, on: reference, in: context)

        #expect(counts == AttendanceInfoRow.SchoolYearCounts(tardy: 2, absent: 1))
    }
}
