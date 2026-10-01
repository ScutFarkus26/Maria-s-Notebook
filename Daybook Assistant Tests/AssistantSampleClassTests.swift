import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

// The join screen's Try a Sample Class, which is how App Review sees the app:
// a full made-up roster, no classroom behind it, a Late phase that can't leak
// into the real class's, and marks kept on the iPhone through the day.
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

    @Test("The saved sample keeps the day's marks when it opens again")
    func savedSampleKeepsMarks() throws {
        let (url, defaults) = try savedSampleLocation()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let day = try AssistantTestSupport.day("2026-09-29")

        let first = try AssistantSampleClass.openSaved(at: url, today: "today", defaults: defaults)
        let marked = try markFirstPresent(in: first, on: day, defaults: defaults)
        close(first)

        let again = try AssistantSampleClass.openSaved(at: url, today: "today", defaults: defaults)
        defer { close(again) }
        let students = try again.viewContext.fetch(CDStudent.fetchRequest())
        #expect(students.count == AssistantSampleClass.names.count)
        #expect(status(of: marked, on: day, in: again) == .present)
    }

    @Test("The saved sample starts fresh on another day")
    func savedSampleFreshNextDay() throws {
        let (url, defaults) = try savedSampleLocation()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let day = try AssistantTestSupport.day("2026-09-29")

        let first = try AssistantSampleClass.openSaved(at: url, today: "monday", defaults: defaults)
        let marked = try markFirstPresent(in: first, on: day, defaults: defaults)
        AttendanceLatePhase.setLate(true, on: day, defaults: defaults)
        close(first)

        let next = try AssistantSampleClass.openSaved(at: url, today: "tuesday", defaults: defaults)
        defer { close(next) }
        let students = try next.viewContext.fetch(CDStudent.fetchRequest())
        #expect(students.count == AssistantSampleClass.names.count)
        #expect(status(of: marked, on: day, in: next) == nil)
        #expect(!AttendanceLatePhase.isLate(on: day, defaults: defaults))
        #expect(defaults.string(forKey: AssistantSampleClass.seededDayKey) == "tuesday")
    }

    // MARK: - Helpers

    private func savedSampleLocation() throws -> (URL, UserDefaults) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("AssistantSampleClassTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return (folder.appendingPathComponent("sample.sqlite"), AssistantTestSupport.makeDefaults())
    }

    /// Taps the first child present; returns their name, which outlives
    /// the store (the reopened one has new object IDs).
    private func markFirstPresent(in stack: CoreDataStack, on day: Date, defaults: UserDefaults) throws -> String {
        let model = AssistantAttendanceViewModel(
            context: stack.viewContext, container: nil, date: day, defaults: defaults
        )
        model.load()
        let row = try #require(model.rows.first)
        model.tap(row)
        #expect(model.rows.first?.status == .present)
        #expect(!stack.viewContext.hasChanges)
        return "\(row.student.firstName) \(row.student.lastName)"
    }

    private func status(of name: String, on day: Date, in stack: CoreDataStack) -> AttendanceStatus? {
        let context = stack.viewContext
        let students = context.safeFetch(CDFetchRequest(CDStudent.self))
        guard let student = students.first(where: { "\($0.firstName) \($0.lastName)" == name }),
              let id = student.id?.uuidString else { return nil }
        let records = context.safeFetch(CDFetchRequest(CDAttendanceRecord.self))
        return records.first {
            $0.studentID == id && Calendar.current.isDate($0.date ?? .distantPast, inSameDayAs: day)
        }?.status
    }

    private func close(_ stack: CoreDataStack) {
        let coordinator = stack.container.persistentStoreCoordinator
        for store in coordinator.persistentStores { try? coordinator.remove(store) }
    }
}
