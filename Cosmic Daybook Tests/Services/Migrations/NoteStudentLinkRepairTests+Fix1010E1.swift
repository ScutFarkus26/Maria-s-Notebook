import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-10-10, P2 #2. Quick Note and the note editor never made the
// student links a multi-child note is found by, re-scoping left the old ones,
// and a group check-in's note had none, so such notes showed on none of the
// children's Notes tabs (or on a tab they no longer named). A one-time repair
// per device gives each `.students` note exactly the links its scope names,
// through the same diff the writers use, and waits for the first download.

@Suite("Multi-child note link repair (Fix1010E1)")
@MainActor
struct NoteStudentLinkRepairTests {

    private func isolatedDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "NoteStudentLinkRepairTests.\(UUID().uuidString)"))
    }

    private func linkedStudents(of note: CDNote) -> [String] {
        ((note.studentLinks?.allObjects as? [CDNoteStudentLink]) ?? [])
            .filter { !$0.isDeleted }
            .map { $0.studentID.uppercased() }
            .sorted()
    }

    /// A multi-child note with no links (Quick Note), one with a stale link
    /// (re-scoped in the editor), one already right, a one-child note and a
    /// whole-class note.
    private struct Seeded {
        let missing: CDNote
        let stale: CDNote
        let right: CDNote
        let single: CDNote
        let wholeClass: CDNote
        let etty: UUID
        let ora: UUID
        let tiffy: UUID
    }

    private func seed(_ context: NSManagedObjectContext) -> Seeded {
        let etty = UUID()
        let ora = UUID()
        let tiffy = UUID()
        func link(_ note: CDNote, to student: UUID) {
            let link = CDNoteStudentLink(context: context)
            link.noteID = note.id?.uuidString ?? ""
            link.studentID = student.uuidString
            link.note = note
        }
        let missing = CoreDataTestHelpers.seedNote(in: context, body: "Etty and Ora built the cube.")
        missing.scope = .students([etty, ora])
        let stale = CoreDataTestHelpers.seedNote(in: context, body: "Ora and Tiffy sorted shells.")
        stale.scope = .students([ora, tiffy])
        link(stale, to: etty)
        link(stale, to: ora)
        let right = CoreDataTestHelpers.seedNote(in: context, body: "All three read together.")
        right.scope = .students([etty, ora, tiffy])
        for student in [etty, ora, tiffy] { link(right, to: student) }
        let single = CoreDataTestHelpers.seedNote(in: context, body: "Etty finished the map.")
        single.scope = .student(etty)
        let wholeClass = CoreDataTestHelpers.seedNote(in: context, body: "Fire drill at 10.")
        wholeClass.scope = .all
        return Seeded(
            missing: missing, stale: stale, right: right, single: single, wholeClass: wholeClass,
            etty: etty, ora: ora, tiffy: tiffy
        )
    }

    @Test("Missing links are added, stale ones removed, other notes left alone; a second run finds nothing")
    func repairMatchesLinksToScope() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let seeded = seed(context)
        #expect(CoreDataTestHelpers.save(context))
        let rightLinks = Set((seeded.right.studentLinks?.allObjects as? [CDNoteStudentLink])?.map(\.objectID) ?? [])

        #expect(DataCleanupService.repairNoteStudentLinks(using: context) == 2)
        #expect(CoreDataTestHelpers.save(context))

        #expect(linkedStudents(of: seeded.missing) == [seeded.etty, seeded.ora].map(\.uuidString).sorted())
        #expect(linkedStudents(of: seeded.stale) == [seeded.ora, seeded.tiffy].map(\.uuidString).sorted())
        let rightAfter = Set((seeded.right.studentLinks?.allObjects as? [CDNoteStudentLink])?.map(\.objectID) ?? [])
        #expect(rightAfter == rightLinks, "a note already right isn't written")
        #expect(linkedStudents(of: seeded.single).isEmpty)
        #expect(linkedStudents(of: seeded.wholeClass).isEmpty)
        #expect(seeded.single.scope == .student(seeded.etty))
        #expect(seeded.wholeClass.scope == .all)

        #expect(DataCleanupService.repairNoteStudentLinks(using: context) == 0)
        #expect(!context.hasChanges)
    }

    @Test("The repair runs once per device, saves, and then stays done")
    func runsOnce() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let defaults = try isolatedDefaults()
        let seeded = seed(context)
        #expect(CoreDataTestHelpers.save(context))

        let first = DataCleanupService.repairNoteStudentLinksIfDue(
            using: context, firstDownloadPending: false, defaults: defaults
        )
        #expect(first == 2)
        #expect(!context.hasChanges, "it saves its own changes")
        #expect(defaults.bool(forKey: UserDefaultsKeys.noteStudentLinkRepairDone))

        // A link lost after the run isn't the repair's to restore again.
        seeded.missing.scope = .students([seeded.etty, seeded.ora, seeded.tiffy])
        #expect(CoreDataTestHelpers.save(context))
        let again = DataCleanupService.repairNoteStudentLinksIfDue(
            using: context, firstDownloadPending: false, defaults: defaults
        )
        #expect(again == nil)
        #expect(linkedStudents(of: seeded.missing).count == 2)
    }

    @Test("Reset Local Cache forgets the repair ran, so a fresh download is checked again")
    func resetLocalCacheClearsFlag() throws {
        let defaults = try isolatedDefaults()
        defaults.set(true, forKey: UserDefaultsKeys.noteStudentLinkRepairDone)
        CoreDataStack.clearLocalCacheResetFlags(in: defaults)
        #expect(!defaults.bool(forKey: UserDefaultsKeys.noteStudentLinkRepairDone))
    }

    @Test("While the first download is pending the repair waits and isn't marked done")
    func waitsForFirstDownload() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let defaults = try isolatedDefaults()
        let seeded = seed(context)
        #expect(CoreDataTestHelpers.save(context))

        let pending = DataCleanupService.repairNoteStudentLinksIfDue(
            using: context, firstDownloadPending: true, defaults: defaults
        )
        #expect(pending == nil)
        #expect(linkedStudents(of: seeded.missing).isEmpty)
        #expect(!defaults.bool(forKey: UserDefaultsKeys.noteStudentLinkRepairDone))

        let later = DataCleanupService.repairNoteStudentLinksIfDue(
            using: context, firstDownloadPending: false, defaults: defaults
        )
        #expect(later == 2)
    }

    @Test("A pass whose earlier steps left unsaved changes doesn't run it")
    func skipsWithLeftoverChanges() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let defaults = try isolatedDefaults()
        let seeded = seed(context)
        #expect(CoreDataTestHelpers.save(context))
        CoreDataTestHelpers.seedNote(in: context, body: "Left unsaved by an earlier step.")

        let result = DataCleanupService.repairNoteStudentLinksIfDue(
            using: context, firstDownloadPending: false, defaults: defaults
        )
        #expect(result == nil)
        #expect(linkedStudents(of: seeded.missing).isEmpty)
        #expect(!defaults.bool(forKey: UserDefaultsKeys.noteStudentLinkRepairDone))
    }

    @Test("On a background context, as the launch pass runs it, the view context sees the links")
    func backgroundContextRun() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let seeded = seed(stack.viewContext)
        #expect(CoreDataTestHelpers.save(stack.viewContext))
        let suiteName = "NoteStudentLinkRepairTests.\(UUID().uuidString)"

        let background = stack.newBackgroundContext()
        let changed: Int? = await background.perform {
            guard let defaults = UserDefaults(suiteName: suiteName) else { return nil }
            return DataCleanupService.repairNoteStudentLinksIfDue(
                using: background, firstDownloadPending: false, defaults: defaults
            )
        }
        #expect(changed == 2)
        stack.viewContext.refreshAllObjects()
        #expect(linkedStudents(of: seeded.missing) == [seeded.etty, seeded.ora].map(\.uuidString).sorted())
    }
}
