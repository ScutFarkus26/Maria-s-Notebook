import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-17, #39 and #44: deleting a child and the records she
/// shares. A group meeting booking keeps its first participant in
/// `studentID`, so the old sweep by `studentID` deleted the whole group's
/// booking when she was first and left her on it otherwise; issue actions
/// and practice sessions kept her id and her deleted work's ids.
@Suite("Student deletion and shared records (fix 10-17 St)")
@MainActor
struct StudentDeletionFix1017StTests {

    private struct Class {
        let context: NSManagedObjectContext
        let danny: UUID
        let maya: UUID
        let eli: UUID
        /// Withdrawn: she has left the class.
        let wendy: UUID
    }

    private func makeClass() throws -> Class {
        let context = try CoreDataTestHelpers.makeContext()
        func child(_ first: String, _ status: CDStudent.EnrollmentStatus = .enrolled) throws -> UUID {
            try #require(CoreDataTestHelpers.seedStudent(
                in: context, firstName: first, lastName: "Fix", enrollmentStatus: status
            ).id)
        }
        return Class(
            context: context,
            danny: try child("Danny"), maya: try child("Maya"), eli: try child("Eli"),
            wendy: try child("Wendy", .withdrawn)
        )
    }

    private func groupBooking(_ ids: [UUID], in context: NSManagedObjectContext) -> CDScheduledMeeting {
        let booking = CDScheduledMeeting(context: context)
        booking.isGroupMeeting = true
        booking.participantStudentIDs = ids.map(\.uuidString)
        booking.studentID = ids[0].uuidString
        booking.date = AppCalendar.startOfDay(Date())
        return booking
    }

    private func delete(_ studentID: UUID, in context: NSManagedObjectContext) throws -> StudentDeletionReport {
        #expect(CoreDataTestHelpers.save(context))
        return try StudentRepository(context: context).deleteStudent(id: studentID)
    }

    private func isGone(_ object: NSManagedObject) -> Bool {
        object.isDeleted || object.managedObjectContext == nil
    }

    // MARK: - #39 Group bookings

    @Test("Her group booking stays for the others when she was its first participant")
    func firstParticipantLeavesTheBooking() throws {
        let room = try makeClass()
        let booking = groupBooking([room.danny, room.maya, room.eli], in: room.context)

        let report = try delete(room.danny, in: room.context)

        #expect(!isGone(booking))
        #expect(booking.participantStudentIDs == [room.maya.uuidString, room.eli.uuidString])
        #expect(booking.studentID == room.maya.uuidString)
        #expect(report.detached["ScheduledMeeting"] == 1)
        #expect(report.deleted["ScheduledMeeting"] == nil)
    }

    @Test("She leaves a group booking she was in the middle of, rather than staying on it")
    func middleParticipantLeavesTheBooking() throws {
        let room = try makeClass()
        let booking = groupBooking([room.maya, room.danny, room.eli], in: room.context)

        _ = try delete(room.danny, in: room.context)

        #expect(!isGone(booking))
        #expect(booking.participantStudentIDs == [room.maya.uuidString, room.eli.uuidString])
        #expect(booking.studentID == room.maya.uuidString)
    }

    @Test("A group booking she was alone in goes")
    func soleParticipantBookingGoes() throws {
        let room = try makeClass()
        let booking = groupBooking([room.danny], in: room.context)

        let report = try delete(room.danny, in: room.context)

        #expect(isGone(booking))
        #expect(report.deleted["ScheduledMeeting"] == 1)
    }

    @Test("A group booking goes when everyone left in it has left the class")
    func bookingOfDepartedChildrenGoes() throws {
        let room = try makeClass()
        let booking = groupBooking([room.wendy, room.danny], in: room.context)

        _ = try delete(room.danny, in: room.context)

        #expect(isGone(booking))
    }

    @Test("Her own booking goes; a classmate's own booking stays")
    func individualBookingsFollowTheirChild() throws {
        let room = try makeClass()
        let hers = CDScheduledMeeting(context: room.context)
        hers.studentIDUUID = room.danny
        let mayas = CDScheduledMeeting(context: room.context)
        mayas.studentIDUUID = room.maya

        let report = try delete(room.danny, in: room.context)

        #expect(isGone(hers))
        #expect(!isGone(mayas))
        #expect(report.deleted["ScheduledMeeting"] == 1)
    }

    // MARK: - #44 Issue actions and practice sessions

    @Test("An issue that stays loses her from its actions too")
    func issueActionsLoseHer() throws {
        let room = try makeClass()
        let issue = CDIssue(context: room.context)
        issue.title = "Sharing the bead frame"
        issue.studentIDs = [room.danny.uuidString, room.maya.uuidString]
        let action = CDIssueAction(context: room.context)
        action.issueID = issue.id?.uuidString ?? ""
        action.issue = issue
        action.participantStudentIDs = [room.danny.uuidString, room.maya.uuidString]
        // An action about her alone stays on the issue, with nobody named.
        let hersAlone = CDIssueAction(context: room.context)
        hersAlone.issueID = issue.id?.uuidString ?? ""
        hersAlone.issue = issue
        hersAlone.participantStudentIDs = [room.danny.uuidString]

        _ = try delete(room.danny, in: room.context)

        #expect(!isGone(issue))
        #expect(issue.studentIDs == [room.maya.uuidString])
        #expect(action.participantStudentIDs == [room.maya.uuidString])
        #expect(!isGone(hersAlone))
        #expect(hersAlone.participantStudentIDs.isEmpty)
    }

    @Test("A practice session that stays loses her deleted work's id")
    func practiceSessionsLoseHerDeletedWork() throws {
        let room = try makeClass()
        let hers = CoreDataTestHelpers.seedWorkModel(in: room.context, title: "Bead frame", studentID: room.danny)
        let mayas = CoreDataTestHelpers.seedWorkModel(in: room.context, title: "Bead frame", studentID: room.maya)
        let herID = try #require(hers.id).uuidString
        let mayaID = try #require(mayas.id).uuidString
        let session = CDPracticeSession(context: room.context)
        session.studentIDsArray = [room.danny.uuidString, room.maya.uuidString]
        session.workItemIDsArray = [herID, mayaID]

        _ = try delete(room.danny, in: room.context)

        #expect(isGone(hers))
        #expect(!isGone(session))
        #expect(session.studentIDsArray == [room.maya.uuidString])
        #expect(session.workItemIDsArray == [mayaID])
    }
}
