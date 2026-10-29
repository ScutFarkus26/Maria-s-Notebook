import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-10-29, part 2 (data, sync and Claude's tools): a Replace
// restore from a backup older than a type emptied it (#1: Schedules before
// v42, the names people set before v38); a Replace put an assistant's old
// name back over her rename (#6); and a merge could leave a note with two
// links to one child (#7).

/// A context's rows as one backup, restored as a given format.
@MainActor
private enum Fix1029 {
    static let day = Date(timeIntervalSince1970: 1_790_000_000)

    /// Everything in `context` as one backup's rows, with no settings.
    static func payload(of context: NSManagedObjectContext) -> BackupPayload {
        var payload = BackupService().collectPayload(viewContext: context)
        payload.preferences = PreferencesDTO(values: [:])
        return payload
    }

    static func restore(
        _ payload: BackupPayload,
        format: Int = BackupWriter.formatVersion,
        into context: NSManagedObjectContext,
        mode: BackupService.RestoreMode
    ) async throws {
        let envelope = BackupEnvelope(
            formatVersion: format, encrypted: false, createdAt: day, fileName: "fix1029", entityCounts: [:]
        )
        _ = try await BackupService().importPayload(
            payload: payload, envelope: envelope, viewContext: context, mode: mode,
            appRouter: AppRouter(), progress: { _, _ in }
        )
    }

    static func count(_ entityName: String, in context: NSManagedObjectContext) throws -> Int {
        try context.count(for: NSFetchRequest<NSManagedObject>(entityName: entityName))
    }

    static let scheduleTypes = ["TimetableLane", "TimetableBlock", "TimetableChange", "TimetableBooking"]
}

@Suite("Restore fixes (2026-10-29): Replace and the types a backup predates", .serialized)
@MainActor
struct BackupReplaceOlderFormatTests {
    private typealias Support = ClassroomNamesTestSupport

    // MARK: - #1 Types the backup predates

    @Test("A Replace from a backup older than Schedules and names keeps them; one that holds them replaces them")
    func replaceKeepsTypesTheBackupCantHold() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Backed")
        try context.save()
        // A v37 backup: no Schedules (v42) and no names (v38).
        var old = Fix1029.payload(of: context)
        (old.timetableLanes, old.timetableBlocks, old.timetableChanges, old.timetableBookings) = (nil, nil, nil, nil)
        old.classroomPeople = nil

        // Since the backup: another child, the Schedules and Ana's name.
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Grace", lastName: "Since")
        for entity in Fix1029.scheduleTypes {
            NSEntityDescription.insertNewObject(forEntityName: entity, into: context).setValue(UUID(), forKey: "id")
        }
        Support.person("_ana", "Ana", role: .assistant, created: Support.at(0), in: context)
        try context.save()

        try await Fix1029.restore(old, format: 37, into: context, mode: .replace)
        let names = context.safeFetch(CDFetchRequest(CDStudent.self)).map(\.firstName)
        #expect(names == ["Ada"], "the children are the backup's: v37 holds children")
        for entity in Fix1029.scheduleTypes {
            #expect(try Fix1029.count(entity, in: context) == 1, "\(entity) kept: a v37 backup can't hold it")
        }
        #expect(ClassroomNames.name(forRecordName: "_ana", in: context) == "Ana", "her name kept")

        // The same rows as a current backup's: it holds Schedules, and has none.
        try await Fix1029.restore(old, into: context, mode: .replace)
        for entity in Fix1029.scheduleTypes {
            #expect(try Fix1029.count(entity, in: context) == 0, "\(entity) replaced by the backup's none")
        }
    }

    @Test("Replace's preview counts nothing removed of a type the backup predates, nor of the names")
    func previewMatchesTheReplace() throws {
        let context = try CoreDataTestHelpers.makeContext()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Here")
        let block = NSEntityDescription.insertNewObject(forEntityName: "TimetableBlock", into: context)
        block.setValue(UUID(), forKey: "id")
        Support.person("_ana", "Ana", role: .assistant, created: Support.at(0), in: context)
        try context.save()

        func deletes(format: Int) -> [String: Int] {
            BackupPreviewAnalyzer.analyze(
                digest: BackupPreviewDigest(), viewContext: context, mode: .replace,
                formatVersion: format, entityExists: { _, _ in false }
            ).deletes
        }
        let old = deletes(format: 41)
        #expect(old["Student"] == 1)
        #expect(old["TimetableBlock"] == nil, "left as it is, so not listed")
        #expect(old["ClassroomPerson"] == 0)
        let current = deletes(format: BackupWriter.formatVersion)
        #expect(current["TimetableBlock"] == 1)
        #expect(current["ClassroomPerson"] == 0, "updated in place, never removed")
    }

    @Test("Every type joined at a format the app reads, and the later ones at the format their notes give")
    func firstFormatsAreReadable() {
        let readable = BackupReader.supportedFormatVersions
        for entity in BackupEntityTable.entities where entity.firstFormat > 0 {
            #expect(readable.contains(entity.firstFormat), "\(entity.name): v\(entity.firstFormat)")
        }
        let since = Dictionary(uniqueKeysWithValues: BackupEntityTable.entities.map { ($0.name, $0.firstFormat) })
        #expect(since["Student"] == 0)
        #expect(since["ClassroomPerson"] == 38)
        for entity in Fix1029.scheduleTypes { #expect(since[entity] == 42, "\(entity)") }
        #expect(BackupEntityTable.entities.allSatisfy { $0.isCarried(by: BackupWriter.formatVersion) })
    }

    // MARK: - #6 Names

    @Test("A Replace keeps a rename made since the backup, and a name set since")
    func replaceKeepsANewerName() async throws {
        let (guideID, anaID) = (UUID(), UUID())
        let source = try CoreDataTestHelpers.makeContext()
        Support.person("_guide", "Danny", role: .leadGuide, created: Support.at(0), modified: Support.at(10),
                       id: guideID, in: source)
        Support.person("_ana", "Ana", role: .assistant, created: Support.at(0), modified: Support.at(10),
                       id: anaID, in: source)
        try source.save()
        let backup = Fix1029.payload(of: source)

        // Since the backup: Ana renamed herself, Bea joined, and the guide's
        // row went missing.
        let target = try CoreDataTestHelpers.makeContext()
        Support.person("_ana", "Annie", role: .assistant, created: Support.at(0), modified: Support.at(50),
                       id: anaID, in: target)
        Support.person("_bea", "Bea", role: .assistant, created: Support.at(60), in: target)
        try target.save()

        try await Fix1029.restore(backup, into: target, mode: .replace)
        #expect(ClassroomNames.name(forRecordName: "_ana", in: target) == "Annie", "her rename stands")
        #expect(ClassroomNames.name(forRecordName: "_bea", in: target) == "Bea", "a name set since stays")
        #expect(ClassroomNames.name(forRecordName: "_guide", in: target) == "Danny", "a missing row comes back")
        #expect(target.safeFetch(CDFetchRequest(CDClassroomPerson.self)).count == 3)
    }
}

@Suite("Restore fixes (2026-10-29): a note's links after a merge", .serialized)
@MainActor
struct BackupMergeNoteLinkTests {

    @Test("A merge leaves one link per child: the one every device keeps")
    func mergeLeavesOneLinkPerChild() async throws {
        let (maya, eli) = (UUID(), UUID())
        let noteID = UUID()
        let source = try CoreDataTestHelpers.makeContext()
        let backedUp = CoreDataTestHelpers.seedNote(in: source, body: "Both at the bead cabinet")
        backedUp.id = noteID
        backedUp.scope = .students([maya, eli])
        // Links as an older build made them: an id of their own each.
        for student in [maya, eli] {
            let link = CDNoteStudentLink(context: source)
            link.noteID = noteID.uuidString
            link.studentID = student.uuidString
            link.note = backedUp
        }
        try source.save()
        let backup = Fix1029.payload(of: source)

        // This device's copy of the note, linked as every note writer links now.
        let context = try CoreDataTestHelpers.makeContext()
        let local = CoreDataTestHelpers.seedNote(in: context, body: "Both at the bead cabinet")
        local.id = noteID
        local.scope = .students([maya, eli])
        local.syncStudentLinks(in: context)
        try context.save()

        try await Fix1029.restore(backup, into: context, mode: .merge)
        let note = try #require(context.safeFetch(CDFetchRequest(CDNote.self)).first { $0.id == noteID })
        let links = (note.studentLinks?.allObjects as? [CDNoteStudentLink] ?? []).filter { !$0.isDeleted }
        #expect(links.map(\.studentID).sorted() == [maya, eli].map(\.uuidString).sorted(), "each child once")
        let stable = Set([maya, eli].map { CDNoteStudentLink.stableID(noteID: noteID, studentID: $0) })
        #expect(Set(links.compactMap(\.id)) == stable, "the links every device keeps")
        #expect(!context.hasChanges, "saved")
    }

    @Test("A child the restored scope names but no link covers gets the link every device gives her")
    func newLinkHasTheStableID() async throws {
        let (maya, eli) = (UUID(), UUID())
        let noteID = UUID()
        let source = try CoreDataTestHelpers.makeContext()
        let backedUp = CoreDataTestHelpers.seedNote(in: source, body: "Both at the bead cabinet")
        backedUp.id = noteID
        backedUp.scope = .students([maya, eli])
        try source.save()
        var backup = Fix1029.payload(of: source)
        backup.noteStudentLinks = []

        let context = try CoreDataTestHelpers.makeContext()
        try await Fix1029.restore(backup, into: context, mode: .merge)
        let note = try #require(context.safeFetch(CDFetchRequest(CDNote.self)).first { $0.id == noteID })
        let links = (note.studentLinks?.allObjects as? [CDNoteStudentLink] ?? []).filter { !$0.isDeleted }
        let stable = Set([maya, eli].map { CDNoteStudentLink.stableID(noteID: noteID, studentID: $0) })
        #expect(Set(links.compactMap(\.id)) == stable)
        #expect(links.count == 2)
    }
}
