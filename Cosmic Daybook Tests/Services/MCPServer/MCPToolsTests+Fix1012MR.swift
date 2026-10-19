import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-10-12, agent MR: MCP attendance overwriting marks the
// assistants made (#5) and ignoring a named child beside mark_all_present
// (#6), linked copies on the schedule (#8) and record batches (#9). The
// rest is in MCPReadToolsTests+Fix1012MR.swift.

@Suite("MCP reads and attendance (Fix1012MR)")
@MainActor
struct MCPToolsFix1012MRTests {
    private func makeTools() throws -> (tools: [MCPToolDefinition], context: NSManagedObjectContext) {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        return (MCPNotebookTools.makeTools(context: { context }), context)
    }

    private func call(
        _ name: String, _ arguments: [String: JSONValue], in tools: [MCPToolDefinition]
    ) async throws -> String {
        let tool = try #require(tools.first { $0.name == name })
        return try await tool.handler(arguments)
    }

    private func refusal(
        _ name: String, _ arguments: [String: JSONValue], in tools: [MCPToolDefinition]
    ) async -> String? {
        do {
            _ = try await call(name, arguments, in: tools)
            return nil
        } catch let error as MCPToolError {
            return error.message
        } catch {
            return "unexpected: \(error)"
        }
    }

    private func mark(_ name: String, _ status: String) -> JSONValue {
        .object(["student_name": .string(name), "status": .string(status)])
    }

    private func status(
        of student: CDStudent, on day: String, in context: NSManagedObjectContext
    ) throws -> AttendanceStatus {
        let id = try #require(student.id)
        let date = try CoreDataTestHelpers.day(day)
        return context.attendanceStatuses(for: [id], on: date)[id] ?? .unmarked
    }

    // MARK: - #5 / #6: mark_attendance in a batch

    private struct Room {
        let ora: CDStudent
        let etty: CDStudent
        let dalia: CDStudent
        let maya: CDStudent
    }

    private func seedRoom(in context: NSManagedObjectContext) -> Room {
        CoreDataTestHelpers.seedClassroomMembership(in: context, role: .leadGuide)
        let room = Room(
            ora: CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi"),
            etty: CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Klein"),
            dalia: CoreDataTestHelpers.seedStudent(in: context, firstName: "Dalia", lastName: "Roth"),
            maya: CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stern")
        )
        CoreDataTestHelpers.save(context)
        return room
    }

    @Test("mark_all_present keeps the marks already made and names who kept one")
    func markAllPresentKeepsEarlierMarks() async throws {
        let (tools, context) = try makeTools()
        let room = seedRoom(in: context)
        // The assistant's marks from earlier in the morning.
        _ = try await call("mark_attendance", [
            "students": .array([mark("Ora", "absent"), mark("Etty", "leftEarly")]),
            "date": .string("2026-09-14")
        ], in: tools)

        let receipt = try await call("mark_attendance", [
            "students": .array([mark("Dalia", "tardy")]),
            "mark_all_present": .bool(true),
            "date": .string("2026-09-14")
        ], in: tools)

        #expect(try status(of: room.ora, on: "2026-09-14", in: context) == .absent)
        #expect(try status(of: room.etty, on: "2026-09-14", in: context) == .leftEarly)
        #expect(try status(of: room.dalia, on: "2026-09-14", in: context) == .tardy)
        #expect(try status(of: room.maya, on: "2026-09-14", in: context) == .present)
        #expect(receipt.contains("- Dalia Roth — late"))
        #expect(receipt.contains("- Maya Stern — present"))
        #expect(receipt.contains("Already marked, left as they were: Etty Klein (left early), Ora Levi (absent)."))
        #expect(receipt.contains("2 student(s) marked."))
    }

    @Test("student_name and status beside mark_all_present mark that child, not present")
    func topLevelStudentFoldsIntoTheBatch() async throws {
        let (tools, context) = try makeTools()
        let room = seedRoom(in: context)

        let receipt = try await call("mark_attendance", [
            "student_name": .string("Maya"),
            "status": .string("absent"),
            "mark_all_present": .bool(true),
            "date": .string("2026-09-14")
        ], in: tools)

        #expect(try status(of: room.maya, on: "2026-09-14", in: context) == .absent)
        #expect(try status(of: room.ora, on: "2026-09-14", in: context) == .present)
        #expect(receipt.contains("- Maya Stern — absent"))
        #expect(receipt.contains("4 student(s) marked."))
    }

    @Test("a top-level student_name without a status in a batch is refused, nothing written")
    func topLevelStudentWithoutStatusIsRefused() async throws {
        let (tools, context) = try makeTools()
        _ = seedRoom(in: context)

        let message = await refusal("mark_attendance", [
            "student_name": .string("Maya"),
            "mark_all_present": .bool(true),
            "date": .string("2026-09-14")
        ], in: tools)

        #expect(message?.contains("status") == true)
        #expect(context.safeFetch(CDFetchRequest(CDAttendanceRecord.self)).isEmpty)
    }

    // Only the locked day is tested: no classroom role lacks permission to
    // mark attendance today (`ClassroomPermissions` lets an assistant write
    // attendance records), so the batch's role refusal can't be reached. It
    // stays in `applyAttendanceBatch` as a commented defense against
    // `markUnmarkedPresent`'s silent no-op, should such a role ever be added.
    @Test("mark_all_present on its own is still refused when the day can't be marked")
    func markAllPresentStillRefusesALockedDay() async throws {
        #expect(ClassroomPermissions.canWrite(entityName: "AttendanceRecord", role: .assistant))
        let (tools, context) = try makeTools()
        _ = seedRoom(in: context)
        let day = try CoreDataTestHelpers.day("2026-09-14")
        #expect(AttendanceDayLocks.setLocked(true, for: day, role: .leadGuide, in: context))
        CoreDataTestHelpers.save(context)

        let message = await refusal("mark_attendance", [
            "mark_all_present": .bool(true),
            "date": .string("2026-09-14")
        ], in: tools)

        #expect(message?.contains("locked") == true)
        #expect(context.safeFetch(CDFetchRequest(CDAttendanceRecord.self)).isEmpty)
    }

    // MARK: - #8 / #14: schedule_for_range and linked copies

    private func assignLinkedCopies(
        tools: [MCPToolDefinition], context: NSManagedObjectContext
    ) async throws -> [String: CDWorkModel] {
        CoreDataTestHelpers.seedLesson(in: context, name: "Checkerboard", area: "Math", sequence: "Multiplication")
        for name in ["Maya", "Eli", "Ana"] {
            CoreDataTestHelpers.seedStudent(in: context, firstName: name, lastName: "Test")
        }
        CoreDataTestHelpers.save(context)
        _ = try await call("assign_work", [
            "lesson": .string("Checkerboard"),
            "student_names": .array([.string("Maya"), .string("Eli"), .string("Ana")]),
            "title": .string("Checkerboard practice"),
            "check_in_date": .string("2026-09-18")
        ], in: tools)
        let students = context.safeFetch(CDFetchRequest(CDStudent.self))
        var rows: [String: CDWorkModel] = [:]
        for work in context.safeFetch(CDFetchRequest(CDWorkModel.self)) {
            guard let owner = WorkGrouping.owner(of: work),
                  let student = students.first(where: { $0.id == owner }) else { continue }
            rows[student.firstName] = work
        }
        #expect(rows.count == 3)
        return rows
    }

    @Test("a student filter shows her own copy only, not her classmates'")
    func scheduleFilterShowsOnlyHerCopy() async throws {
        let (tools, context) = try makeTools()
        let rows = try await assignLinkedCopies(tools: tools, context: context)
        let mayaID = try #require(rows["Maya"]?.id).uuidString

        let schedule = try await call("schedule_for_range", [
            "start_date": .string("2026-09-18"), "student_name": .string("Maya")
        ], in: tools)

        #expect(schedule.components(separatedBy: "Checkerboard practice").count - 1 == 1)
        #expect(schedule.contains("[work id=\(mayaID)]"))
        #expect(schedule.contains("Maya Test's copy (with Ana Test, Eli Test)"))
    }

    @Test("an unfiltered schedule names each linked copy by its owner")
    func scheduleLabelsCopiesByOwner() async throws {
        let (tools, context) = try makeTools()
        _ = try await assignLinkedCopies(tools: tools, context: context)

        let schedule = try await call("schedule_for_range", ["start_date": .string("2026-09-18")], in: tools)

        #expect(schedule.contains("Maya Test's copy (with Ana Test, Eli Test)"))
        #expect(schedule.contains("Eli Test's copy (with Ana Test, Maya Test)"))
        #expect(schedule.contains("Ana Test's copy (with Eli Test, Maya Test)"))
    }

    // MARK: - #9: record_presentation batches

    @Test("two givings of one lesson in a batch don't both claim the waiting plan")
    func batchDoesNotReuseAClaimedPlan() async throws {
        let (tools, context) = try makeTools()
        let lesson = CoreDataTestHelpers.seedLesson(
            in: context, name: "Checkerboard", area: "Math", sequence: "Multiplication"
        )
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        _ = PresentationFactory.makeDraft(lesson: lesson, students: [ora], context: context)
        CoreDataTestHelpers.save(context)

        let output = try await call("record_presentation", [
            "presentations": .array([
                .object([
                    "lesson": .string("Checkerboard"), "student_names": .array([.string("Ora")]),
                    "date": .string("2026-09-14")
                ]),
                .object([
                    "lesson": .string("Checkerboard"), "student_names": .array([.string("Ora")]),
                    "date": .string("2026-09-16"), "purpose": .string("review")
                ])
            ])
        ], in: tools)

        let given = context.safeFetch(CDFetchRequest(CDLessonAssignment.self)).filter(\.isPresented)
        let days = Set(given.compactMap(\.presentedAt).map { MCPNotebookTools.dayString($0) })
        #expect(given.count == 2)
        #expect(days == ["2026-09-14", "2026-09-16"])
        #expect(output.contains("Recorded the lesson planned for them"))
    }

    @Test("a second giving in the same batch is held to the repeat guard")
    func batchSecondGivingNeedsAPurpose() async throws {
        let (tools, context) = try makeTools()
        let lesson = CoreDataTestHelpers.seedLesson(
            in: context, name: "Checkerboard", area: "Math", sequence: "Multiplication"
        )
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        let plan = PresentationFactory.makeDraft(lesson: lesson, students: [ora], context: context)
        CoreDataTestHelpers.save(context)

        let message = await refusal("record_presentation", [
            "presentations": .array([
                .object([
                    "lesson": .string("Checkerboard"), "student_names": .array([.string("Ora")]),
                    "date": .string("2026-09-14")
                ]),
                .object([
                    "lesson": .string("Checkerboard"), "student_names": .array([.string("Ora")]),
                    "date": .string("2026-09-16")
                ])
            ])
        ], in: tools)

        #expect(message?.hasPrefix("record_presentation refused — nothing has been changed.") == true)
        let all = context.safeFetch(CDFetchRequest(CDLessonAssignment.self))
        #expect(all == [plan])
        #expect(!plan.isPresented)
    }

    @Test("the same lesson, child and day twice in one batch updates one record")
    func batchSameDayDuplicateUpdatesTheFirst() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedLesson(in: context, name: "Checkerboard", area: "Math", sequence: "Multiplication")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        CoreDataTestHelpers.save(context)

        let output = try await call("record_presentation", [
            "presentations": .array([
                .object([
                    "lesson": .string("Checkerboard"), "student_names": .array([.string("Ora")]),
                    "date": .string("2026-09-14")
                ]),
                .object([
                    "lesson": .string("Checkerboard"), "student_names": .array([.string("Ora")]),
                    "date": .string("2026-09-14")
                ])
            ])
        ], in: tools)

        let given = context.safeFetch(CDFetchRequest(CDLessonAssignment.self)).filter(\.isPresented)
        #expect(given.count == 1)
        #expect(output.contains("Updated the presentation already recorded"))
    }
}

// Outside the struct body only for SwiftLint's type length limit.
extension MCPToolsFix1012MRTests {
    @Test("a truncated range resumes on the next calendar day")
    func truncatedRangeResumesOnTheNextDay() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        CoreDataTestHelpers.save(context)
        // Sixty days from 2026-09-03 end on 2026-11-01, the day the clocks go back
        // in the US: 86,400 seconds after its midnight is still 2026-11-01.
        let pad = CDDayPad(context: context, day: AppCalendar.startOfDay(try CoreDataTestHelpers.day("2026-09-03")))
        pad.body = "First day back"
        CoreDataTestHelpers.save(context)

        let schedule = try await call("schedule_for_range", [
            "start_date": .string("2026-09-03"), "end_date": .string("2026-12-01")
        ], in: tools)

        #expect(schedule.contains("ask again from 2026-11-02 for the rest"))

        // The reply above runs in the device's zone, which may have no clock
        // change at all. Pinned to New York, where 2026-11-01 is 25 hours
        // long, the step has to be a calendar day: 86,400 seconds is still
        // the 1st. (Not by moving the process's default zone: other suites
        // run alongside, and the day formatter keeps the zone it was made in.)
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let lastDay = try #require(newYork.date(from: DateComponents(year: 2026, month: 11, day: 1)))
        let resume = try #require(MCPNotebookTools.resumeDay(after: lastDay, calendar: newYork))
        #expect(newYork.component(.month, from: resume) == 11)
        #expect(newYork.component(.day, from: resume) == 2)
        #expect(newYork.component(.day, from: lastDay.addingTimeInterval(86_400)) == 1)
    }
}
