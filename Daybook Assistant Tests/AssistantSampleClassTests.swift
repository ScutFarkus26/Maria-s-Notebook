import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

// The join screen's Try a Sample Class, which is how App Review sees the app:
// a full made-up roster in memory, no classroom behind it, and a Late phase
// that can't leak into the real class's.
@Suite("Assistant sample class")
@MainActor
struct AssistantSampleClassTests {

    @Test("The sample is a full class in memory with no classroom behind it")
    func fullClassNoMembership() throws {
        let stack = try AssistantSampleClass.makeStack()
        let context = stack.viewContext

        let students = try context.fetch(CDStudent.fetchRequest())
        #expect(students.count == AssistantSampleClass.names.count)
        #expect(students.count == 22)

        let membership = CDClassroomMembership.ownRowsRequest()
        #expect(context.safeFetchFirst(membership) == nil)

        // Nothing on disk: every store is in memory.
        let stores = stack.container.persistentStoreCoordinator.persistentStores
        #expect(!stores.isEmpty)
        #expect(stores.allSatisfy { $0.type == NSInMemoryStoreType })
    }

    @Test("Opening the sample starts its own Late phase fresh, apart from the real class's")
    func latePhaseKeptApart() throws {
        let today = Date()
        AttendanceLatePhase.setLate(true, on: today, defaults: AssistantSampleClass.defaults)
        #expect(AssistantSampleClass.defaults !== UserDefaults.standard)

        _ = try AssistantSampleClass.makeStack()

        #expect(!AttendanceLatePhase.isLate(on: today, defaults: AssistantSampleClass.defaults))
    }

    @Test("The sample's marks save with no share to attach to")
    func marksSaveWithoutShare() throws {
        let stack = try AssistantSampleClass.makeStack()
        // A Tuesday, so the test doesn't land on a weekend's day off.
        let model = AssistantAttendanceViewModel(
            context: stack.viewContext,
            container: nil,
            date: try AssistantTestSupport.day("2026-09-29"),
            defaults: AssistantSampleClass.defaults
        )
        model.load()
        let first = try #require(model.rows.first)
        model.tap(first)
        #expect(model.rows.first?.status == .present)
        #expect(!stack.viewContext.hasChanges)
    }
}
