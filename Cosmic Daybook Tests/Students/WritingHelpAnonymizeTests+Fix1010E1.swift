import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-10-10, P2 #11 and #16. Writing Help's Anonymize hid only the
// "Student:" line; the names in the notes themselves went to Apple
// Intelligence as written. And the Observations list's chips for a child who
// had left were blank: it looked students up among enrolled children only.

@Suite("Writing Help anonymize and withdrawn names (Fix1010E1)")
@MainActor
struct WritingHelpAnonymizeTests {

    @Test("Anonymize replaces the children's names inside the notes")
    func namesInBodies() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Smith")
        let will = CoreDataTestHelpers.seedStudent(in: context, firstName: "Will", lastName: "Adler")
        let note = CoreDataTestHelpers.seedNote(
            in: context, body: "Maya Smith showed Will the chain. Maya S says she will try. MAYA laughed."
        )
        note.scope = .students([try #require(maya.id), try #require(will.id)])

        let text = SmartNoteFormatter(students: [maya, will], anonymize: true).generateContext(from: [note])

        #expect(!text.contains("Maya"))
        #expect(!text.contains("MAYA"))
        #expect(!text.contains("Smith"))
        #expect(!text.contains("Will "))
        #expect(text.contains("Student M showed Student W the chain."))
        #expect(text.contains("Student M says she will try."), "the word \"will\" isn't a name")
        #expect(text.contains("Student: Group of 2 students"))
    }

    @Test("Without Anonymize the text is untouched and a group reads by short names")
    func plainText() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let sarahK = CoreDataTestHelpers.seedStudent(in: context, firstName: "Sarah", lastName: "Katz")
        let sarahM = CoreDataTestHelpers.seedStudent(in: context, firstName: "Sarah", lastName: "Mizrahi")
        let note = CoreDataTestHelpers.seedNote(in: context, body: "Sarah K helped Sarah M.")
        note.scope = .students([try #require(sarahK.id), try #require(sarahM.id)])

        let text = SmartNoteFormatter(students: [sarahK, sarahM], anonymize: false).generateContext(from: [note])

        #expect(text.contains("Note: Sarah K helped Sarah M."))
        let studentLine = try #require(text.split(separator: "\n").first { $0.hasPrefix("Student:") })
        #expect(studentLine.contains("Sarah K") && studentLine.contains("Sarah M"))
    }

    @Test("The Observations list names a child who has left")
    func withdrawnChildNamed() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let left = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Ora", lastName: "Pardo", enrollmentStatus: .withdrawn
        )
        let note = CoreDataTestHelpers.seedNote(in: context, body: "Last day.")
        let leftID = try #require(left.id)
        note.scope = .student(leftID)
        #expect(CoreDataTestHelpers.save(context))

        let items = ObservationsDataLoader.loadAllNotes(context: context)
        let cache = ObservationsDataLoader.loadStudents(for: items, existingCache: [:], context: context)
        #expect(cache[leftID]?.firstName == "Ora")
    }
}
