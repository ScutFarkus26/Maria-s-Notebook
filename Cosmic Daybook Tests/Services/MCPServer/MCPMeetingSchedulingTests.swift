import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

@Suite("MCP schedule_meeting")
@MainActor
struct MCPMeetingSchedulingTests {
    // 2026-09-10 is a Thursday, 2026-09-12 a Saturday, 2026-09-15 a Tuesday.
    private static let thursday = "2026-09-10"
    private static let saturday = "2026-09-12"
    private static let tuesday = "2026-09-15"

    private func makeTools() throws -> (tools: [MCPToolDefinition], context: NSManagedObjectContext) {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let tools = MCPNotebookTools.makeTools(context: { context })
        return (tools, context)
    }

    private func tool(named name: String, in tools: [MCPToolDefinition]) throws -> MCPToolDefinition {
        try #require(tools.first { $0.name == name })
    }

    private func day(_ iso: String) throws -> Date {
        AppCalendar.startOfDay(try #require(MCPNotebookTools.isoDay.date(from: iso)))
    }

    private func bookings(in context: NSManagedObjectContext) -> [CDScheduledMeeting] {
        context.safeFetch(CDFetchRequest(CDScheduledMeeting.self))
    }

    @discardableResult
    private func seedGroupSitting(
        for student: CDStudent, with other: CDStudent, on iso: String, in context: NSManagedObjectContext
    ) throws -> CDScheduledMeeting {
        let sitting = CDScheduledMeeting(context: context)
        sitting.isGroupMeeting = true
        sitting.studentIDUUID = student.id
        sitting.participantStudentIDs = [student.id, other.id].compactMap { $0?.uuidString }
        sitting.date = try day(iso)
        return sitting
    }

    // MARK: - Booking

    @Test("schedule_meeting books a CDScheduledMeeting that scheduled_meetings then lists")
    func bookingAppearsInScheduledMeetings() async throws {
        let (tools, context) = try makeTools()
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        let studentID = try #require(student.id)
        let work = CoreDataTestHelpers.seedWorkModel(in: context, title: "Racks and Tubes", studentID: studentID)
        let workID = try #require(work.id)
        CoreDataTestHelpers.save(context)

        let output = try await tool(named: "schedule_meeting", in: tools).handler([
            "student": .string("Ora"),
            "date": .string(Self.thursday),
            "purpose": .string("Plan the civilization project"),
            "work_id": .string(workID.uuidString)
        ])

        let booked = bookings(in: context)
        #expect(booked.count == 1)
        let booking = try #require(booked.first)
        let id = try #require(booking.id).uuidString
        #expect(output == "Booked [scheduledMeeting id=\(id)] with Ora Levi on \(Self.thursday) "
            + "(Plan the civilization project; about Racks and Tubes).")
        #expect(booking.studentIDUUID == studentID)
        #expect(booking.date == (try day(Self.thursday)))
        #expect(booking.purpose == "Plan the civilization project")
        #expect(booking.workIDUUID == workID)
        #expect(!booking.isGroupMeeting)

        let listed = try await tool(named: "scheduled_meetings", in: tools).handler([
            "start_date": .string("2026-09-01")
        ])
        #expect(listed.contains("[scheduledMeeting id=\(id)] \(Self.thursday)"))
        #expect(listed.contains("Ora Levi"))
        #expect(listed.contains("Plan the civilization project"))
        #expect(listed.contains("about Racks and Tubes"))
    }

    @Test("schedule_meeting resolves the student by id as create_meeting_entry does")
    func bookingByStudentID() async throws {
        let (tools, context) = try makeTools()
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        let studentID = try #require(student.id)
        CoreDataTestHelpers.save(context)

        let output = try await tool(named: "schedule_meeting", in: tools).handler([
            "student": .string(studentID.uuidString),
            "date": .string(Self.thursday)
        ])
        #expect(output.hasPrefix("Booked [scheduledMeeting id="))
        #expect(bookings(in: context).first?.studentIDUUID == studentID)
    }

    // MARK: - One booking per student

    @Test("Booking the same day again keeps the one booking")
    func sameDayBookingIsKept() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        CoreDataTestHelpers.save(context)
        let schedule = try tool(named: "schedule_meeting", in: tools)

        let first = try await schedule.handler([
            "student": .string("Ora"), "date": .string(Self.thursday), "purpose": .string("Goals")
        ])
        let firstID = try #require(bookings(in: context).first?.id)

        let second = try await schedule.handler([
            "student": .string("Ora"), "date": .string(Self.thursday)
        ])
        #expect(first != second)
        #expect(second == "Ora Levi was already booked for \(Self.thursday); "
            + "[scheduledMeeting id=\(firstID.uuidString)] stands (Goals).")
        let booked = bookings(in: context)
        #expect(booked.count == 1)
        #expect(booked.first?.id == firstID)
        #expect(booked.first?.purpose == "Goals", "A re-booking without a purpose keeps the one it had")
    }

    @Test("Booking another day moves the student's booking instead of adding a second")
    func differentDayBookingMoves() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        CoreDataTestHelpers.save(context)
        let schedule = try tool(named: "schedule_meeting", in: tools)

        _ = try await schedule.handler(["student": .string("Ora"), "date": .string(Self.thursday)])
        let firstID = try #require(bookings(in: context).first?.id)

        let output = try await schedule.handler([
            "student": .string("Ora"), "date": .string(Self.tuesday), "purpose": .string("Reading plan")
        ])
        #expect(output == "Ora Levi holds one booking at a time, so "
            + "[scheduledMeeting id=\(firstID.uuidString)] was moved from \(Self.thursday) to "
            + "\(Self.tuesday) rather than a second one made (Reading plan).")
        let booked = bookings(in: context)
        #expect(booked.count == 1)
        #expect(booked.first?.id == firstID)
        #expect(booked.first?.date == (try day(Self.tuesday)))
        #expect(booked.first?.purpose == "Reading plan")
    }

    @Test("A group sitting the student is in is not mistaken for their own booking")
    func groupSittingIsLeftAlone() async throws {
        let (tools, context) = try makeTools()
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        let noam = CoreDataTestHelpers.seedStudent(in: context, firstName: "Noam", lastName: "Bar")
        let sitting = try seedGroupSitting(for: ora, with: noam, on: Self.tuesday, in: context)
        CoreDataTestHelpers.save(context)

        let output = try await tool(named: "schedule_meeting", in: tools).handler([
            "student": .string("Ora"), "date": .string(Self.thursday)
        ])
        #expect(output.hasPrefix("Booked [scheduledMeeting id="))
        let booked = bookings(in: context)
        #expect(booked.count == 2)
        #expect(sitting.date == (try day(Self.tuesday)))
        #expect(sitting.isGroupMeeting)
    }

    // MARK: - Non-school days

    @Test("schedule_meeting refuses a day school is not in session and books nothing")
    func refusesNonSchoolDay() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        CoreDataTestHelpers.save(context)

        do {
            _ = try await tool(named: "schedule_meeting", in: tools).handler([
                "student": .string("Ora"), "date": .string(Self.saturday)
            ])
            Issue.record("A Saturday booking should be refused")
        } catch let error as MCPToolError {
            #expect(error.message == "School is not in session on \(Self.saturday) (Saturday); "
                + "nothing was booked. Choose a school day.")
        }
        #expect(bookings(in: context).isEmpty)
    }

    // MARK: - Scheduled → held

    @Test("create_meeting_entry completes the booking instead of stranding it")
    func filingTheMeetingCompletesTheBooking() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        CoreDataTestHelpers.save(context)
        let scheduled = try tool(named: "scheduled_meetings", in: tools)
        let window: [String: JSONValue] = ["start_date": .string("2026-09-01")]

        _ = try await tool(named: "schedule_meeting", in: tools).handler([
            "student": .string("Ora"), "date": .string(Self.thursday), "purpose": .string("Goals")
        ])
        let bookingID = try #require(bookings(in: context).first?.id).uuidString
        #expect(try await scheduled.handler(window).contains("[scheduledMeeting id=\(bookingID)]"))

        let output = try await tool(named: "create_meeting_entry", in: tools).handler([
            "student": .string("Ora"),
            "date": .string(Self.thursday),
            "reflection": .string("Chose Mesopotamia; wants the timeline next."),
            "goals": .array([.string("Draft the timeline")])
        ])
        #expect(output.hasSuffix("on \(Self.thursday) with 1 new goal(s), "
            + "completing the booking made for \(Self.thursday)."))

        #expect(bookings(in: context).isEmpty, "The booking is gone, not left beside the entry")
        #expect(try await scheduled.handler(window) == "No meetings are scheduled from 2026-09-01 onward.")

        let held = context.safeFetch(CDFetchRequest(CDStudentMeeting.self))
        #expect(held.count == 1)
        #expect(held.first?.completed == true)
        let history = try await tool(named: "student_meetings", in: tools).handler([
            "student_name": .string("Ora")
        ])
        #expect(history.contains("] \(Self.thursday)\n"))
        #expect(!history.contains("not finished"))
    }

    @Test("Filing a meeting after its booked day still completes the booking")
    func lateFilingCompletesAnEarlierBooking() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        CoreDataTestHelpers.save(context)

        _ = try await tool(named: "schedule_meeting", in: tools).handler([
            "student": .string("Ora"), "date": .string(Self.thursday)
        ])
        let output = try await tool(named: "create_meeting_entry", in: tools).handler([
            "student": .string("Ora"),
            "date": .string(Self.tuesday),
            "reflection": .string("Held a few days late.")
        ])
        #expect(output.hasSuffix("completing the booking made for \(Self.thursday)."))
        #expect(bookings(in: context).isEmpty)
    }

    @Test("A booking for a later day is the next meeting and survives filing this one")
    func futureBookingSurvivesFiling() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        CoreDataTestHelpers.save(context)

        _ = try await tool(named: "schedule_meeting", in: tools).handler([
            "student": .string("Ora"), "date": .string(Self.tuesday)
        ])
        let output = try await tool(named: "create_meeting_entry", in: tools).handler([
            "student": .string("Ora"),
            "date": .string(Self.thursday),
            "reflection": .string("An extra sitting before the booked one.")
        ])
        #expect(!output.contains("completing the booking"))
        let booked = bookings(in: context)
        #expect(booked.count == 1)
        #expect(booked.first?.date == (try day(Self.tuesday)))
    }

    @Test("Filing one child's meeting does not end a group sitting they are part of")
    func filingDoesNotEndGroupSitting() async throws {
        let (tools, context) = try makeTools()
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        let noam = CoreDataTestHelpers.seedStudent(in: context, firstName: "Noam", lastName: "Bar")
        let sitting = try seedGroupSitting(for: ora, with: noam, on: Self.thursday, in: context)
        CoreDataTestHelpers.save(context)

        let output = try await tool(named: "create_meeting_entry", in: tools).handler([
            "student": .string("Ora"),
            "date": .string(Self.thursday),
            "reflection": .string("Met on her own.")
        ])
        #expect(!output.contains("completing the booking"))
        #expect(bookings(in: context) == [sitting])
    }
}
