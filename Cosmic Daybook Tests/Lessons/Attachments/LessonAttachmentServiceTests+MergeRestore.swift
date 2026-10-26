import CoreData
import CoreGraphics
import Foundation
import Testing
@testable import CosmicDaybook

/// A merge restore over lesson files that changed since the backup (review
/// of 2026-10-25, finding 3). A backup carries a file's record, never the
/// file or its bookmark, so a row from before a replace or a rename names a
/// file that has since gone to the Trash or moved; the record keeps the file
/// it has now.
extension LessonAttachmentServiceTests {

    /// The context's records as a backup file carries them: written by the
    /// live writer and read back by the live reader.
    static func backup(of context: NSManagedObjectContext) throws -> BackupPayload {
        var payload = BackupService().collectPayload(viewContext: context)
        payload.preferences = PreferencesDTO(values: [:])
        let entries = try BackupWriter.serializeEntries(from: payload)
        let manifest = BackupArchiveManifest(
            formatVersion: BackupWriter.formatVersion, createdAt: Date(),
            appVersion: "", appBuild: "", device: "", entityCounts: [:], originStores: [:]
        )
        let decoded = BackupReader.DecodedBackup(manifest: manifest, entries: entries, preferences: nil)
        let (read, warnings) = BackupImporter.reconstructPayload(from: decoded)
        #expect(warnings.isEmpty, "\(warnings)")
        return read
    }

    /// Merges `payload` into the scratch notebook, checking lesson files in
    /// its scratch Lesson Files folder.
    static func mergeRestore(_ payload: BackupPayload, into scratch: Scratch) async throws {
        let envelope = BackupEnvelope(
            formatVersion: BackupWriter.formatVersion, encrypted: false, createdAt: Date(),
            fileName: "lesson-files", entityCounts: [:]
        )
        let context = scratch.context
        _ = try await BackupLessonFiles.$storage.withValue(scratch.storage) {
            try await BackupService().importPayload(
                payload: payload, envelope: envelope, viewContext: context, mode: .merge,
                appRouter: AppRouter(), progress: { _, _ in }
            )
        }
    }

    @Test("A merge restore of a backup from before a replace keeps the record on the file it has now")
    func mergeRestoreAfterAReplace() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let allowed = LessonAttachmentService.pdfOrImage
        let attachment = try scratch.service().add(
            fileAt: try scratch.write(Self.pdf(), named: "circle.pdf"), to: scratch.lesson,
            title: "Area of a Circle", notes: "From the album", allowedTypes: allowed
        )
        attachment.modifiedAt = Self.earlier
        try scratch.context.save()
        let backedUpPath = attachment.fileRelativePath
        let backup = try Self.backup(of: scratch.context)

        let newBytes = Self.pdf(size: CGSize(width: 1224, height: 1584), shade: 0.2)
        _ = try await scratch.service().replace(
            attachment, withFileAt: try scratch.write(newBytes, named: "circle-v2.pdf"), notes: "Remade",
            allowedTypes: allowed
        )
        let livePath = attachment.fileRelativePath
        let liveModifiedAt = try #require(attachment.modifiedAt)
        try #require(livePath != backedUpPath)
        #expect(!FileManager.default.fileExists(atPath: try scratch.storage.resolve(relativePath: backedUpPath).path))

        try await Self.mergeRestore(backup, into: scratch)

        #expect(attachment.fileRelativePath == livePath)
        #expect(attachment.fileSizeBytes == Int64(newBytes.count))
        #expect(attachment.fileType == "pdf")
        #expect(attachment.fileName == "Area of a Circle.pdf")
        #expect(attachment.modifiedAt == liveModifiedAt, "the later of the two")
        #expect(attachment.notes == "From the album", "the rest of the row is the backup's")
        #expect(try Data(contentsOf: scratch.file(of: attachment)) == newBytes)
        #expect(!scratch.context.hasChanges)
        #expect(try scratch.persisted(attachment.id)?.path == livePath)
    }

    @Test("A merge restore of a backup from before a rename keeps the renamed file and its name")
    func mergeRestoreAfterARename() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let attachment = try scratch.service().add(
            fileAt: try scratch.write(Self.png(), named: "chart.png"), to: scratch.lesson,
            allowedTypes: LessonAttachmentService.pdfOrImage
        )
        let backup = try Self.backup(of: scratch.context)
        #expect(try scratch.service().rename(attachment, to: "Bead Chart — tens"))
        let livePath = attachment.fileRelativePath

        try await Self.mergeRestore(backup, into: scratch)

        #expect(attachment.fileRelativePath == livePath)
        #expect(attachment.fileName == "Bead Chart — tens.png")
        #expect(FileManager.default.fileExists(atPath: try scratch.file(of: attachment).path))
    }

    @Test("A row whose file is still here is restored as the backup has it")
    func mergeRestoreWhenTheBackedUpFileIsStillHere() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let allowed = LessonAttachmentService.pdfOrImage
        let attachment = try scratch.service().add(
            fileAt: try scratch.write(Self.pdf(), named: "circle.pdf"), to: scratch.lesson, allowedTypes: allowed
        )
        // Another record uses the same file, so a replace keeps it on disk.
        let sharer = CDLessonAttachment(context: scratch.context)
        sharer.fileName = "circle.pdf"
        sharer.fileRelativePath = attachment.fileRelativePath
        sharer.lesson = CoreDataTestHelpers.seedLesson(in: scratch.context, name: "Circumference")
        try scratch.context.save()
        let backedUpPath = attachment.fileRelativePath
        let backedUpSize = attachment.fileSizeBytes
        let backup = try Self.backup(of: scratch.context)
        _ = try await scratch.service().replace(
            attachment, withFileAt: try scratch.write(Self.png(), named: "circle.png"), allowedTypes: allowed
        )
        #expect(attachment.fileRelativePath != backedUpPath)

        try await Self.mergeRestore(backup, into: scratch)

        #expect(attachment.fileRelativePath == backedUpPath)
        #expect(attachment.fileSizeBytes == backedUpSize)
        #expect(attachment.fileType == "pdf")
    }
}
