import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

// Logic-break sweep 2026-09-29, B6. Work assigned to a group is usually one
// row per child (linked copies), each listing every classmate as a
// participant. Readiness counted any row that listed the child, so Ben's
// unfinished copy blocked Ada, who had finished her own. A child is now
// gated by the rows they own, and only falls back to rows that merely name
// them (a shared row, a legacy row) when they own none.
@Suite("Blocking by a child's own work")
@MainActor
struct BlockingOwnWorkTests {

    private let ada = UUID()
    private let ben = UUID()

    /// One linked copy: owned by `owner`, listing both children.
    private func copy(
        owner: UUID, presentationID: String, done: Set<UUID>, in context: NSManagedObjectContext
    ) -> CDWorkModel {
        let work = CoreDataTestHelpers.seedWorkModel(in: context, title: "Checkerboard work", studentID: owner)
        work.presentationID = presentationID
        for child in [ada, ben] {
            let participant = CDWorkParticipantEntity(context: context)
            participant.id = UUID()
            participant.studentID = child.uuidString
            participant.completedAt = done.contains(child) ? Date() : nil
            participant.work = work
        }
        return work
    }

    @Test("A child is gated by the copy they own, not a classmate's")
    func gatingWorkIsTheOwnedCopy() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let adaCopy = copy(owner: ada, presentationID: "p", done: [ada], in: context)
        let benCopy = copy(owner: ben, presentationID: "p", done: [], in: context)

        #expect(BlockingAlgorithmEngine.gatingWork(for: ada, among: [adaCopy, benCopy]) == [adaCopy])
        #expect(BlockingAlgorithmEngine.gatingWork(for: ben, among: [adaCopy, benCopy]) == [benCopy])

        // A shared row owned by Ben still gates Ada, who owns nothing.
        #expect(BlockingAlgorithmEngine.gatingWork(for: ada, among: [benCopy]) == [benCopy])
    }

    @Test("The planning cache blocks only the child whose own copy is open")
    func cacheBlocksOnlyTheOpenCopysOwner() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let first = CoreDataTestHelpers.seedLesson(in: context, name: "First", area: "Math", sequence: "Counting")
        first.id = UUID()
        first.orderInSequence = 1
        let second = CoreDataTestHelpers.seedLesson(in: context, name: "Second", area: "Math", sequence: "Counting")
        second.id = UUID()
        second.orderInSequence = 2
        for student in [(ada, "Ada"), (ben, "Ben")] {
            CoreDataTestHelpers.seedStudent(in: context, firstName: student.1).id = student.0
        }

        let given = PresentationFactory.makeScheduled(
            lessonID: try #require(first.id), studentIDs: [ada, ben], scheduledFor: Date(), context: context
        )
        _ = try LifecycleService.recordPresentation(from: given, presentedAt: Date(), modelContext: context)
        let next = PresentationFactory.makeScheduled(
            lessonID: try #require(second.id), studentIDs: [ada, ben], scheduledFor: Date(), context: context
        )
        next.scheduledFor = nil
        let presentationID = try #require(given.id?.uuidString)
        let works = [
            copy(owner: ada, presentationID: presentationID, done: [ada], in: context),
            copy(owner: ben, presentationID: presentationID, done: [], in: context)
        ]

        let cache = BlockingCacheBuilder.buildCache(
            lessonAssignments: [given, next],
            lessons: [first, second],
            workModels: works,
            openWorkByPresentationID: [:]
        )

        let nextID = try #require(next.id)
        let blocking = try #require(cache[nextID])
        #expect(blocking[ben] === works[1])
        #expect(blocking[ada] == nil)
    }
}
