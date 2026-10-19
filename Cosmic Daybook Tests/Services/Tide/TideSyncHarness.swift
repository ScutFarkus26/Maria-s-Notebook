import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// One notebook, one fake Tide, one engine, as the Mac's service wires them.
@MainActor
final class TideSyncHarness {
    let context: NSManagedObjectContext
    let tide = FakeTide()
    let engine: TideSyncEngine
    var saved = TideSyncState()
    var settings = TideSyncSettings()
    let now: Date

    init(confirmed: Bool = true) throws {
        context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        now = try CoreDataTestHelpers.day("2026-10-19")
        var state = TideSyncState()
        if confirmed { state.firstRunConfirmedAt = now }
        let store = NotebookTideTodoStore(context: context, saveCoordinator: SaveCoordinator())
        var box: (TideSyncState) -> Void = { _ in }
        engine = TideSyncEngine(transport: tide, store: store, state: state, persist: { box($0) })
        settings.isOn = true
        box = { [unowned self] in self.saved = $0 }
    }

    @discardableResult
    func run() async -> TideSyncResult {
        await engine.run(settings, now: now)
    }

    @discardableResult
    func todo(_ title: String, students: [CDStudent] = [], workID: UUID? = nil, due: Date? = nil) -> CDTodoItem {
        let todo = CDTodoItem(context: context)
        todo.title = title
        todo.resolvedStudentIDs = students.compactMap(\.id)
        todo.linkedWorkItemID = workID?.uuidString
        todo.dueDate = due
        #expect(CoreDataTestHelpers.save(context))
        return todo
    }

    func student(_ first: String, _ last: String) -> CDStudent {
        let student = CDStudent(context: context)
        student.id = UUID()
        student.firstName = first
        student.lastName = last
        return student
    }

    var todos: [CDTodoItem] {
        let request = CDFetchRequest(CDTodoItem.self)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDTodoItem.createdAt, ascending: true)]
        return context.safeFetch(request)
    }

    func todo(linkedTo link: TideActionLink) -> CDTodoItem? {
        todos.first { $0.tideLink == link.string }
    }
}
