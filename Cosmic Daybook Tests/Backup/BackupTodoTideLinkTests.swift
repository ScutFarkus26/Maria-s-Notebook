import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// A to-do's `tideLink` (backup v41) names the Tide action it is shared with.
/// A merge restore must not blank a link the to-do gained after the backup
/// was taken, or the sync sends the finished to-do to Tide as a new action.
@Suite("Backup: a to-do's Tide link", .serialized)
@MainActor
struct BackupTodoTideLinkTests {

    private func makeTodo(link: String?, in context: NSManagedObjectContext) -> CDTodoItem {
        let todo = CDTodoItem(context: context)
        todo.id = UUID()
        todo.title = "Plan the field trip"
        todo.tideLink = link
        return todo
    }

    private func restored(
        _ id: UUID?, in context: NSManagedObjectContext
    ) throws -> CDTodoItem? {
        try BackupTestUtil.fetchByID(CDTodoItem.self, id, entityName: "TodoItem", in: context)
    }

    @Test("A merge keeps the link a to-do gained since the backup was taken")
    func mergeKeepsALaterLink() async throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let todo = makeTodo(link: nil, in: context)
        #expect(CoreDataTestHelpers.save(context))

        let url = BackupTestUtil.tempBackupURL()
        defer { BackupTestUtil.cleanup(url) }
        try await BackupTestUtil.writeCurrentBackup(from: context, to: url)

        todo.tideLink = "tide://action/field-trip"
        #expect(CoreDataTestHelpers.save(context))
        try await BackupTestUtil.importCurrentBackup(from: url, into: context, mode: .merge)

        let back = try #require(try restored(todo.id, in: context))
        #expect(back.tideLink == "tide://action/field-trip")
    }

    @Test("A merge still takes the backup's link over a different one")
    func mergeTakesTheBackupsLink() async throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let todo = makeTodo(link: "tide://action/from-backup", in: context)
        #expect(CoreDataTestHelpers.save(context))

        let url = BackupTestUtil.tempBackupURL()
        defer { BackupTestUtil.cleanup(url) }
        try await BackupTestUtil.writeCurrentBackup(from: context, to: url)

        todo.tideLink = "tide://action/other"
        #expect(CoreDataTestHelpers.save(context))
        try await BackupTestUtil.importCurrentBackup(from: url, into: context, mode: .merge)

        let back = try #require(try restored(todo.id, in: context))
        #expect(back.tideLink == "tide://action/from-backup")
    }

    @Test("A Replace restore brings back exactly what the backup had, a link or none")
    func replaceIsExact() async throws {
        let source = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let linked = makeTodo(link: "tide://action/linked", in: source)
        let plain = makeTodo(link: nil, in: source)
        #expect(CoreDataTestHelpers.save(source))

        let url = BackupTestUtil.tempBackupURL()
        defer { BackupTestUtil.cleanup(url) }
        try await BackupTestUtil.writeCurrentBackup(from: source, to: url)

        let target = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let stale = makeTodo(link: "tide://action/stale", in: target)
        stale.id = plain.id
        #expect(CoreDataTestHelpers.save(target))
        try await BackupTestUtil.importCurrentBackup(from: url, into: target, mode: .replace)

        #expect(try restored(linked.id, in: target)?.tideLink == "tide://action/linked")
        let back = try #require(try restored(plain.id, in: target))
        #expect(back.tideLink == nil, "replace does not keep the record it replaced")
    }
}
