import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// `View.onPresentationDataChange` bumps a screen's change token from the
// object sets a context's change and save notifications carry. These pin
// the filter behind it: an edit is seen before it is saved, only the watched
// entities count, and a context reset counts as touching everything.

@Suite("Managed object change scope")
@MainActor
struct ManagedObjectChangeScopeTests {

    /// Main-actor mailbox for the touched-name sets computed from each
    /// notification as it is posted (the view context posts on the main queue).
    @MainActor
    private final class Mailbox {
        var touched: [Set<String>] = []
    }

    private func observe(
        _ name: Notification.Name,
        on context: NSManagedObjectContext,
        watching entityNames: Set<String>,
        into mailbox: Mailbox
    ) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(forName: name, object: context, queue: nil) { note in
            let names = ManagedObjectChangeScope.touched(entityNames, in: note.userInfo)
            MainActor.assumeIsolated { mailbox.touched.append(names) }
        }
    }

    @Test("An unsaved insert is reported as a change to its entity only")
    func unsavedInsertIsSeen() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let mailbox = Mailbox()
        let observer = observe(
            .NSManagedObjectContextObjectsDidChange, on: context,
            watching: ["Student", "WorkModel"], into: mailbox
        )
        defer { NotificationCenter.default.removeObserver(observer) }

        CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "S")
        context.processPendingChanges()

        #expect(mailbox.touched.last == ["Student"])
    }

    @Test("A change to an unwatched entity reports nothing")
    func unwatchedEntityIsIgnored() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let mailbox = Mailbox()
        let observer = observe(
            .NSManagedObjectContextObjectsDidChange, on: context,
            watching: ["WorkModel"], into: mailbox
        )
        defer { NotificationCenter.default.removeObserver(observer) }

        CoreDataTestHelpers.seedLesson(in: context, name: "Rectangle")
        context.processPendingChanges()

        let nothingTouched = mailbox.touched.allSatisfy(\.isEmpty)
        #expect(nothingTouched)
    }

    @Test("A save reports the saved entities among the watched set")
    func saveReportsSavedEntities() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let mailbox = Mailbox()
        let observer = observe(
            .NSManagedObjectContextDidSave, on: context,
            watching: ["Lesson", "Student", "WorkModel"], into: mailbox
        )
        defer { NotificationCenter.default.removeObserver(observer) }

        CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "S")
        CoreDataTestHelpers.seedLesson(in: context, name: "Rectangle")
        CoreDataTestHelpers.save(context)

        #expect(mailbox.touched.last == ["Lesson", "Student"])
    }

    @Test("A context reset counts as touching every watched entity")
    func resetTouchesEverything() throws {
        let context = try CoreDataTestHelpers.makeContext()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "S")
        CoreDataTestHelpers.save(context)

        let mailbox = Mailbox()
        let observer = observe(
            .NSManagedObjectContextObjectsDidChange, on: context,
            watching: ["LessonAssignment", "WorkModel"], into: mailbox
        )
        defer { NotificationCenter.default.removeObserver(observer) }

        context.reset()

        #expect(mailbox.touched.last == ["LessonAssignment", "WorkModel"])
    }

    @Test("No userInfo means nothing touched")
    func missingUserInfo() {
        #expect(ManagedObjectChangeScope.touched(["Student"], in: nil).isEmpty)
        #expect(ManagedObjectChangeScope.touched(["Student"], in: [:]).isEmpty)
    }
}
