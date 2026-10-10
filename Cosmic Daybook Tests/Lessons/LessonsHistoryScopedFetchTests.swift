import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

/// Pins that the `lessonID IN` scoped reads behind the Lessons screen give the
/// same counts as reading every assignment and filtering in memory.
@MainActor
struct LessonsHistoryScopedFetchTests {

    private func seed(_ context: NSManagedObjectContext) throws -> (requested: [UUID], all: [UUID]) {
        let lessonIDs = (0..<6).map { _ in UUID() }
        var day = 0.0
        for (index, lessonID) in lessonIDs.enumerated() {
            for copy in 0..<(index % 3 + 1) {
                let la = CDLessonAssignment(context: context)
                la.lessonID = lessonID.uuidString
                switch (index + copy) % 3 {
                case 0:
                    day += 1
                    la.markPresented(at: Date(timeIntervalSince1970: 1_780_000_000 + day * 86_400))
                case 1: la.markPreviouslyPresented()
                default: la.schedule(onDay: Date(timeIntervalSince1970: 1_790_000_000))
                }
            }
        }
        // A row whose lessonID differs only in case must stay excluded.
        let odd = CDLessonAssignment(context: context)
        odd.lessonID = lessonIDs[0].uuidString.lowercased()
        odd.markPresented()
        try context.save()
        // And an unsaved row must still be seen.
        let pending = CDLessonAssignment(context: context)
        pending.lessonID = lessonIDs[1].uuidString
        pending.markPresented(at: Date(timeIntervalSince1970: 1_800_000_000))
        let draft = CDLessonAssignment(context: context)
        draft.lessonID = lessonIDs[2].uuidString
        return (Array(lessonIDs.prefix(4)), lessonIDs)
    }

    @Test func statusCountsMatchWholeTableFilter() throws {
        let context = try CoreDataTestHelpers.makeSplitStoreContext()
        let ids = try seed(context)

        let scoped = LessonsViewModel().computeLessonStatusCounts(for: ids.requested, context: context)

        let wanted = Set(ids.requested.map(\.uuidString))
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "stateRaw != %@", LessonAssignmentState.presented.rawValue)
        var counts: [UUID: Int] = [:]
        for la in try context.fetch(request) {
            guard wanted.contains(la.lessonID), let uuid = UUID(uuidString: la.lessonID) else { continue }
            counts[uuid, default: 0] += 1
        }
        #expect(scoped == counts)
        #expect(!counts.isEmpty)
    }
}
