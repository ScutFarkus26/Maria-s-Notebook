import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The same work given to the same children twice, weeks apart, through
/// assign_work. Neither call sets a presentation, so before linked copies had
/// to be made together the second assignment joined the first, and every
/// write to the new rows reached the old ones too.
@Suite("MCP Repeat Assignment")
@MainActor
struct MCPRepeatAssignmentTests {
    private typealias Fixture = CheckInFixture

    /// Gives "Checkerboard practice" to the same children again, three weeks
    /// after `first`, and returns the new rows keyed by first name.
    private func assignAgainWeeksLater(
        _ first: [String: CDWorkModel], tools: [MCPToolDefinition], context: NSManagedObjectContext
    ) async throws -> [String: CDWorkModel] {
        for row in first.values {
            row.createdAt = AppCalendar.addingDays(-21, to: row.createdAt ?? Date())
        }
        CoreDataTestHelpers.save(context)
        let before = Set(first.values.map(\.objectID))
        _ = try await Fixture.tool(named: "assign_work", in: tools).handler([
            "lesson": .string("Checkerboard"),
            "student_names": .array(first.keys.sorted().map { .string($0) }),
            "title": .string("Checkerboard practice"),
            "check_in_date": .string("2026-10-02")
        ])
        let new = context.safeFetch(CDFetchRequest(CDWorkModel.self)).filter { !before.contains($0.objectID) }
        let rows = Fixture.rowsByFirstName(new, in: context)
        #expect(rows.count == first.count)
        return rows
    }

    @Test("a check-in, a status and a delete on the newer assignment reach only its rows")
    func repeatAssignmentStaysSeparate() async throws {
        let (tools, context) = try Fixture.makeTools()
        let old = try await Fixture.assignWithCheckIn(to: ["Maya", "Eli"], tools: tools, context: context)
        let new = try await assignAgainWeeksLater(old, tools: tools, context: context)
        try await expectWritesStaySeparate(old: old, new: new, tools: tools, context: context)
    }

    /// The common case: the lesson was given to the children together, so
    /// `createWork` links both assignments' rows to that one presentation.
    @Test("with the lesson given to the group, the newer assignment's writes still reach only its rows")
    func repeatAssignmentOfAGivenLessonStaysSeparate() async throws {
        let (tools, context) = try Fixture.makeTools()
        let old = try await Fixture.assignWithCheckIn(
            to: ["Maya", "Eli"], tools: tools, context: context
        ) { lesson, students in
            _ = PresentationFactory.makePresented(
                lessonID: lesson.id!, studentIDs: students.compactMap(\.id), context: context
            )
        }
        let new = try await assignAgainWeeksLater(old, tools: tools, context: context)
        let presentations = Set((Array(old.values) + Array(new.values)).map(\.presentationID))
        #expect(presentations.count == 1)
        let shared = try #require(presentations.first ?? nil)
        #expect(!shared.isEmpty)
        try await expectWritesStaySeparate(old: old, new: new, tools: tools, context: context)
    }

    private func expectWritesStaySeparate(
        old: [String: CDWorkModel], new: [String: CDWorkModel],
        tools: [MCPToolDefinition], context: NSManagedObjectContext
    ) async throws {
        let oldMaya = try #require(old["Maya"])
        let oldEli = try #require(old["Eli"])
        let newMaya = try #require(new["Maya"])
        let newEli = try #require(new["Eli"])
        let update = try Fixture.tool(named: "update_work", in: tools)

        // A check-in on the new Maya row reaches the new Eli row only.
        let added = try await update.handler([
            "work_id": .string(try Fixture.id(of: newMaya)),
            "add_check_in_on": .string("2026-10-07")
        ])
        #expect(added.contains("also added to Eli Test's linked copy [work id=\(try Fixture.id(of: newEli))]"))
        #expect(!added.contains(try Fixture.id(of: oldEli)))
        #expect(Fixture.checkIns(of: newEli, on: "2026-10-07", in: context).count == 1)
        #expect(Fixture.checkIns(of: oldEli, on: "2026-10-07", in: context).isEmpty)
        #expect(Fixture.checkIns(of: oldMaya, on: "2026-10-07", in: context).isEmpty)

        // A status for everyone closes the two new rows and leaves the old open.
        let logged = try await update.handler([
            "work_id": .string(try Fixture.id(of: newMaya)),
            "status": .string("mastered")
        ])
        #expect(logged.contains("for everyone (2 linked copies)"))
        #expect(newMaya.isClosed)
        #expect(newEli.isClosed)
        #expect(!oldMaya.isClosed)
        #expect(!oldEli.isClosed)

        // Taking Maya off the new work deletes her new row only, and only the
        // new Eli row stops naming her.
        let mayaID = try #require(WorkGrouping.owner(of: oldMaya))
        _ = try await Fixture.tool(named: "remove_student_from_work", in: tools).handler([
            "work_id": .string(try Fixture.id(of: newMaya)),
            "student_name": .string("Maya Test"),
            "confirm": .bool(true)
        ])
        #expect(newMaya.isDeleted || newMaya.managedObjectContext == nil)
        #expect(!oldMaya.isDeleted && oldMaya.managedObjectContext != nil)
        #expect(!WorkGrouping.involves(mayaID, in: newEli))
        #expect(WorkGrouping.involves(mayaID, in: oldEli))
        #expect(WorkGrouping.group(containing: oldMaya, in: context).shape == .linkedCopies(total: 2))
    }

    @Test("student_work lists each assignment once for her")
    func studentWorkListsBothAssignments() async throws {
        let (tools, context) = try Fixture.makeTools()
        let old = try await Fixture.assignWithCheckIn(to: ["Maya", "Eli"], tools: tools, context: context)
        let new = try await assignAgainWeeksLater(old, tools: tools, context: context)
        let oldMaya = try #require(old["Maya"])
        let mayaID = try #require(WorkGrouping.owner(of: oldMaya))

        let listed = MCPNotebookTools.allWork(for: mayaID, in: context)
        let mayas = [old["Maya"], new["Maya"]].compactMap { $0?.objectID }
        #expect(Set(listed.map(\.objectID)) == Set(mayas))
    }
}
