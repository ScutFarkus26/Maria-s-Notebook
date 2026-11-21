// GuardianPersonTests.swift
// Domain logic review 2026-11-20, A9 (plan "Domain logic fixes", Decisions 12
// and 19): a sibling's copy of the same parent carries the same `personID`,
// so an edit on one child's row changes every copy, and the copies are
// matched once by email, at launch and after a restore.

import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

@Suite("Guardian person (domain logic A9)")
@MainActor
struct GuardianPersonTests {

    private struct Family {
        let context: NSManagedObjectContext
        let maya: CDStudent
        let leo: CDStudent
    }

    private func makeFamily() throws -> Family {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Soto")
        let leo = CoreDataTestHelpers.seedStudent(in: context, firstName: "Leo", lastName: "Soto")
        return Family(context: context, maya: maya, leo: leo)
    }

    @discardableResult
    private func guardian(
        _ name: String, email: String, of student: CDStudent, in context: NSManagedObjectContext,
        relationship: GuardianRelationship = .mother
    ) -> CDGuardian {
        let row = CDGuardian(context: context)
        row.studentID = student.id?.uuidString ?? ""
        row.name = name
        row.email = email
        row.relationship = relationship
        return row
    }

    @Test("Editing a mother on one child changes her on the sibling")
    func editFollowsThePerson() async throws {
        let family = try makeFamily()
        let onMaya = guardian("Rosa Soto", email: "rosa@example.com", of: family.maya, in: family.context)
        let onLeo = guardian("Rosa Soto", email: "rosa@example.com", of: family.leo, in: family.context)
        let person = UUID().uuidString
        onMaya.personID = person
        onLeo.personID = person
        onLeo.notes = "Picks Leo up on Tuesdays."
        #expect(CoreDataTestHelpers.save(family.context))

        let tools = MCPNotebookTools.makeTools(context: { family.context })
        let update = try #require(tools.first { $0.name == "update_guardian" })
        _ = try await update.handler([
            "guardian_id": .string(try #require(onMaya.id).uuidString),
            "name": .string("Rosa Soto-Levy"),
            "email": .string("rosa.levy@example.com"),
            "receives_reports": .bool(false)
        ])

        #expect(onLeo.name == "Rosa Soto-Levy")
        #expect(onLeo.email == "rosa.levy@example.com")
        #expect(onLeo.receivesReports == false, "receiving reports follows the person")
        #expect(onLeo.notes == "Picks Leo up on Tuesdays.", "notes stay with the child's row")
    }
}
