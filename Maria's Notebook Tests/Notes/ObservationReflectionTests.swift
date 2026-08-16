import Foundation
import Testing
@testable import Maria_s_Notebook

@Suite("Observation Reflection Evidence")
@MainActor
final class ObservationReflectionTests {
    private func makeItems(count: Int = 3) throws -> [UnifiedObservationItem] {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        return (0..<count).map { index in
            let note = CDNote(context: context)
            note.body = "Factual classroom record \(index + 1)"
            return UnifiedObservationItem(
                id: note.id ?? UUID(),
                date: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + index)),
                body: note.body,
                tags: [],
                includeInReport: false,
                imagePath: nil,
                contextText: "Presentation: Golden Beads",
                studentIDs: [],
                source: .note(note)
            )
        }
    }

    @Test("Source packets retain stable keys, record IDs, dates, and context")
    func packetsPreserveEvidence() throws {
        let items = try makeItems()
        let packets = ObservationReflectionService.sourcePackets(from: items)

        #expect(packets.map(\.key) == ["O1", "O2", "O3"])
        #expect(packets.map(\.reference.entityID) == items.map(\.id))
        #expect(packets.map(\.reference.date) == items.map { Optional($0.date) })
        #expect(packets.allSatisfy { $0.reference.title == "Presentation: Golden Beads" })
    }

    @Test("Character budgeting drops excess records without breaking source mapping")
    func packetBudgetIsBounded() throws {
        let packets = ObservationReflectionService.sourcePackets(
            from: try makeItems(count: 10),
            maximumRecords: 10,
            maximumCharacters: 150
        )

        #expect(!packets.isEmpty)
        #expect(packets.map(\.key) == packets.indices.map { "O\($0 + 1)" })
        #expect(packets.map(\.promptText).joined().count <= 150)
    }

    @Test("Missing-observation check uses presentation links, not AI inference")
    func findsPresentationsWithoutLinkedObservation() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Stamp Game")
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada")
        let presentation = PresentationFactory.makePresented(
            lessonID: try #require(lesson.id),
            studentIDs: [try #require(student.id)],
            presentedAt: Date(),
            context: context
        )
        presentation.lesson = lesson

        let before = PresentationObservationCoverageService.missingObservationReferences(
            in: context,
            from: Date().addingTimeInterval(-60),
            through: Date().addingTimeInterval(60)
        )
        let presentationID = try #require(presentation.id)
        #expect(before.map(\.entityID) == [presentationID])

        _ = try PresentationOutcomePersistenceService.persistObservations(
            groupObservation: "Exchanged independently after the first reminder.",
            studentObservations: [:],
            studentIDs: presentation.studentUUIDs,
            presentationID: presentation.id,
            context: context
        )
        let after = PresentationObservationCoverageService.missingObservationReferences(
            in: context,
            from: Date().addingTimeInterval(-60),
            through: Date().addingTimeInterval(60)
        )
        #expect(after.isEmpty)
    }

    #if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
    @Test("Unknown source keys are discarded and patterns require two records")
    func validationRejectsUngroundedFindings() throws {
        let packets = ObservationReflectionService.sourcePackets(from: try makeItems())
        let digest = NotesDigest(
            factualObservations: [
                GroundedObservationFinding(text: "Supported", sourceKeys: ["O1", "FAKE"]),
                GroundedObservationFinding(text: "Unsupported", sourceKeys: ["FAKE"])
            ],
            repeatedPatterns: [
                GroundedObservationFinding(text: "Only one source", sourceKeys: ["O1"]),
                GroundedObservationFinding(text: "Repeated", sourceKeys: ["O1", "O2"])
            ],
            questionsToObserveNext: []
        )

        let validated = ObservationReflectionService.validate(digest, against: packets)
        #expect(validated.factualObservations.count == 1)
        #expect(validated.factualObservations.first?.sourceKeys == ["O1"])
        #expect(validated.repeatedPatterns.map(\.text) == ["Repeated"])
    }
    #endif
}
