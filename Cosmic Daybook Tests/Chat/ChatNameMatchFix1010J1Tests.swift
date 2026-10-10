import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-10, Part 2 #85: asking chat about "Etty D" also loaded the
/// other Etty, "Etty doing" matched Etty D, and notes about several children
/// never reached a child's details.
@Suite("Chat names and notes (fix 10-10 J1)")
@MainActor
struct ChatNameMatchFix1010J1Tests {

    private struct Class {
        let dechter: CDStudent
        let krinsky: CDStudent
        let ora: CDStudent
        var all: [CDStudent] { [dechter, krinsky, ora] }
    }

    private func seedClass(in context: NSManagedObjectContext) -> Class {
        let dechter = CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Dechter")
        let krinsky = CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Krinsky")
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Pardo")
        return Class(dechter: dechter, krinsky: krinsky, ora: ora)
    }

    private func names(_ question: String, in group: Class) -> [String] {
        ChatContextAssembler.matchStudents(in: question, from: group.all).map(\.fullName).sorted()
    }

    @Test("A first name with a last initial names that child alone")
    func initialPicksOneChild() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let group = seedClass(in: context)
        #expect(names("How is Etty D doing with fractions?", in: group) == [group.dechter.fullName])
        #expect(names("What has Etty Krinsky worked on?", in: group) == [group.krinsky.fullName])
    }

    @Test("A bare first name names every child who has it, and words aren't read as initials")
    func bareFirstName() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let group = seedClass(in: context)
        #expect(names("How is Etty doing?", in: group) == [group.dechter.fullName, group.krinsky.fullName].sorted())
        #expect(names("Compare Etty D and Ora", in: group) == [group.dechter.fullName, group.ora.fullName].sorted())
        #expect(names("Any notes on the orange beads?", in: group).isEmpty)
    }

    @Test("A child's recent notes include notes about several children")
    func multiChildNotesIncluded() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let group = seedClass(in: context)
        let ettyID = try #require(group.dechter.id)
        let oraID = try #require(group.ora.id)
        let alone = CoreDataTestHelpers.seedNote(in: context, body: "Worked alone on the bead frame.")
        alone.scope = .student(ettyID)
        alone.createdAt = Date().addingTimeInterval(-3600)
        let together = CoreDataTestHelpers.seedNote(in: context, body: "Etty and Ora built the timeline together.")
        together.scope = .students([ettyID, oraID])
        together.createdAt = Date()
        together.syncStudentLinks(in: context)
        #expect(CoreDataTestHelpers.save(context))

        let notes = ChatContextAssembler(context: context).fetchRecentNotes(for: ettyID, limit: 5)

        #expect(notes.map(\.body) == [together.body, alone.body])
    }
}
