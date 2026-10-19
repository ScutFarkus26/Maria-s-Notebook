import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Simplify the app, Phase 7 review: the copy's mark is the note's own
/// `modifiedAt` (`CalendarNotePadCopy.copiedMark`), so a backup carries it
/// beside the pads it describes, and a restore puts both back together. These
/// run the app's backup writer and restore, Replace and Merge.
@Suite("Calendar notes copied into day pads: backups", .serialized)
@MainActor
struct CalendarNotePadCopyBackupTests {

    private let fieldTrip = CellID(year: 2026, month: 10, day: 20)
    private let pictureDay = CellID(year: 2026, month: 10, day: 21)
    private let formsDay = CellID(year: 2026, month: 10, day: 22)
    private let fixtures = CalendarNotePadCopyTests()

    private func note(_ id: UUID?, in context: NSManagedObjectContext) throws -> CDCalendarNote {
        try #require(try BackupTestUtil.fetchByID(CDCalendarNote.self, id, entityName: "CalendarNote", in: context))
    }

    @Test("The mark is backed up: a new Mac restoring the backup copies only what was waiting, and keeps lines off")
    func markSurvivesARoundTrip() async throws {
        let source = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let photos = fixtures.note("Picture day", on: pictureDay, in: source)
        #expect(CoreDataTestHelpers.save(source))
        #expect(fixtures.copy(source) == CalendarNotePadCopy.Outcome(copied: 1))
        // She takes the copied line off the pad, and an older build writes a
        // note on another day, not copied yet.
        let picturePad = try #require(try fixtures.pads(on: pictureDay, in: source).first)
        picturePad.setBody("Photos moved to 11/2")
        let forms = fixtures.note("Bring forms", on: formsDay, made: 3600, in: source)
        #expect(CoreDataTestHelpers.save(source))

        let url = BackupTestUtil.tempBackupURL()
        defer { BackupTestUtil.cleanup(url) }
        try await BackupTestUtil.writeCurrentBackup(from: source, to: url)
        let restored = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        try await BackupTestUtil.importCurrentBackup(from: url, into: restored, mode: .replace)

        let backPhotos = try note(photos.id, in: restored)
        #expect(backPhotos.modifiedAt == CalendarNotePadCopy.copiedMark)
        #expect(CalendarNotePadCopy.isCopied(backPhotos))
        let backForms = try note(forms.id, in: restored)
        #expect(backForms.modifiedAt == forms.modifiedAt)
        #expect(!CalendarNotePadCopy.isCopied(backForms))

        #expect(fixtures.copy(restored) == CalendarNotePadCopy.Outcome(copied: 1))
        #expect(try fixtures.body(on: pictureDay, in: restored) == "Photos moved to 11/2")
        #expect(try fixtures.body(on: formsDay, in: restored) == "Bring forms")
        #expect(fixtures.copy(restored) == CalendarNotePadCopy.Outcome())
    }

    @Test("A Merge restore from before the copy brings its notes back unmarked; checked again, none goes in twice")
    func mergeRestoreFromBeforeTheCopy() async throws {
        // The backup, from before the copy: the picture-day pad held only her
        // line, and the field trip's day had no pad.
        let picturePadID = UUID()
        let source = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        try fixtures.pad("Call Maya's dad", on: pictureDay, id: picturePadID, in: source)
        let photos = fixtures.note("Picture day", on: pictureDay, in: source)
        let trip = fixtures.note("Field trip to the zoo", on: fieldTrip, in: source)
        #expect(CoreDataTestHelpers.save(source))
        let url = BackupTestUtil.tempBackupURL()
        defer { BackupTestUtil.cleanup(url) }
        try await BackupTestUtil.writeCurrentBackup(from: source, to: url)

        // Since then, on the Mac: the copy ran (with a note written after the
        // backup), then she took "Picture day" off its pad.
        let target = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let picturePad = try fixtures.pad("Call Maya's dad", on: pictureDay, id: picturePadID, in: target)
        fixtures.note("Picture day", on: pictureDay, id: try #require(photos.id), in: target)
        fixtures.note("Field trip to the zoo", on: fieldTrip, id: try #require(trip.id), in: target)
        let later = fixtures.note("Bring forms", on: formsDay, made: 3600, in: target)
        #expect(CoreDataTestHelpers.save(target))
        #expect(fixtures.copy(target) == CalendarNotePadCopy.Outcome(copied: 3))
        picturePad.setBody("Call Maya's dad")
        #expect(CoreDataTestHelpers.save(target))
        #expect(fixtures.copy(target) == CalendarNotePadCopy.Outcome())

        try await BackupTestUtil.importCurrentBackup(from: url, into: target, mode: .merge)

        // The backed-up notes are back as the backup had them, unmarked; the
        // one it didn't carry keeps its mark.
        #expect(!CalendarNotePadCopy.isCopied(try note(photos.id, in: target)))
        #expect(!CalendarNotePadCopy.isCopied(try note(trip.id, in: target)))
        #expect(CalendarNotePadCopy.isCopied(try note(later.id, in: target)))

        // The next launch checks them against the pads: the field trip's pad,
        // made by the copy after the backup, still has its line and gets it no
        // second time; the line she took off after the backup comes back, once,
        // since the restore brought back the note from before it was copied.
        #expect(fixtures.copy(target) == CalendarNotePadCopy.Outcome(copied: 1, alreadyThere: 1))
        #expect(try fixtures.body(on: fieldTrip, in: target) == "Field trip to the zoo")
        #expect(try fixtures.body(on: pictureDay, in: target) == "Call Maya's dad\n\nPicture day")
        #expect(try fixtures.body(on: formsDay, in: target) == "Bring forms")
        #expect(fixtures.copy(target) == CalendarNotePadCopy.Outcome())
    }

    @Test("A Merge restore of a backup made after the copy keeps the mark, and a line she took off since stays off")
    func mergeRestoreFromAfterTheCopy() async throws {
        let source = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let photos = fixtures.note("Picture day", on: pictureDay, in: source)
        #expect(CoreDataTestHelpers.save(source))
        #expect(fixtures.copy(source) == CalendarNotePadCopy.Outcome(copied: 1))
        let url = BackupTestUtil.tempBackupURL()
        defer { BackupTestUtil.cleanup(url) }
        try await BackupTestUtil.writeCurrentBackup(from: source, to: url)

        // Into a notebook where she has since taken the line off: the backup's
        // pad comes back with it (the restore's own doing), and the marked note
        // adds nothing to it, then or after she takes it off again.
        let picturePad = try #require(try fixtures.pads(on: pictureDay, in: source).first)
        picturePad.setBody("Photos moved to 11/2")
        #expect(CoreDataTestHelpers.save(source))
        try await BackupTestUtil.importCurrentBackup(from: url, into: source, mode: .merge)
        #expect(CalendarNotePadCopy.isCopied(try note(photos.id, in: source)))
        #expect(fixtures.copy(source) == CalendarNotePadCopy.Outcome())
        let padAfterRestore = try #require(try fixtures.pads(on: pictureDay, in: source).first)
        #expect(padAfterRestore.body == "Picture day")
        padAfterRestore.setBody("Photos moved to 11/2")
        #expect(CoreDataTestHelpers.save(source))
        #expect(fixtures.copy(source) == CalendarNotePadCopy.Outcome())
        #expect(padAfterRestore.body == "Photos moved to 11/2")
    }
}
