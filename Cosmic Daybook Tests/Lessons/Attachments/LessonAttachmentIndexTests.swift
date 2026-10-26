import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Lesson file attachments, Phase 3: the paperclip on the library's pills
/// comes from one set of lessons with a file of their own, read with one
/// fetch and read again only after a save that touched an attachment.
@Suite("Lesson files: the paperclip index")
@MainActor
struct LessonAttachmentIndexTests {

    /// Counts the index's reads, each one the real fetch.
    final class FetchCounter {
        private(set) var count = 0

        func fetch(_ context: NSManagedObjectContext) -> Set<NSManagedObjectID> {
            count += 1
            return LessonAttachmentIndex.fetchLessonIDs(in: context)
        }
    }

    private struct Fixture {
        let stack: CoreDataStack
        let circle: CDLesson
        let square: CDLesson
        let counter = FetchCounter()
        let index: LessonAttachmentIndex

        var context: NSManagedObjectContext { stack.viewContext }

        init() throws {
            stack = try CoreDataTestHelpers.makeInMemoryStack()
            circle = CoreDataTestHelpers.seedLesson(
                in: stack.viewContext, name: "Area of a Circle", area: "Geometry", sequence: "Circle"
            )
            square = CoreDataTestHelpers.seedLesson(
                in: stack.viewContext, name: "Area of a Square", area: "Geometry", sequence: "Circle"
            )
            try stack.viewContext.save()
            let counter = counter
            index = LessonAttachmentIndex(context: stack.viewContext) { counter.fetch($0) }
        }

        @discardableResult
        func attach(to lesson: CDLesson, scope: AttachmentScope = .lesson) -> CDLessonAttachment {
            let attachment = CDLessonAttachment(context: context)
            attachment.fileName = "Plan.pdf"
            attachment.fileType = "pdf"
            attachment.scope = scope
            attachment.lesson = lesson
            return attachment
        }
    }

    // MARK: - What it holds

    @Test("A file added to a lesson badges it after the save")
    func addBadges() async throws {
        let fixture = try Fixture()
        #expect(!fixture.index.hasFile(fixture.circle))

        fixture.attach(to: fixture.circle)
        try fixture.context.save()
        await fixture.index.settle()

        #expect(fixture.index.hasFile(fixture.circle))
        #expect(!fixture.index.hasFile(fixture.square))
    }

    @Test("Removing a lesson's last file takes its paperclip away; one of two left keeps it")
    func removeLastUnbadges() async throws {
        let fixture = try Fixture()
        let first = fixture.attach(to: fixture.circle)
        let second = fixture.attach(to: fixture.circle)
        try fixture.context.save()
        await fixture.index.settle()
        #expect(fixture.index.hasFile(fixture.circle))

        fixture.context.delete(first)
        try fixture.context.save()
        await fixture.index.settle()
        #expect(fixture.index.hasFile(fixture.circle), "one file is still there")

        fixture.context.delete(second)
        try fixture.context.save()
        await fixture.index.settle()
        #expect(!fixture.index.hasFile(fixture.circle))
    }

    @Test("A sequence- or area-wide file badges neither the lesson holding it nor its siblings")
    func sharedFilesDoNotBadge() async throws {
        let fixture = try Fixture()
        fixture.attach(to: fixture.circle, scope: .sequence)
        fixture.attach(to: fixture.square, scope: .area)
        try fixture.context.save()
        await fixture.index.settle()

        #expect(fixture.counter.count == 2, "the save was read")
        #expect(fixture.index.lessonIDs.isEmpty)
        #expect(!fixture.index.hasFile(fixture.circle))
        #expect(!fixture.index.hasFile(fixture.square))
    }

    @Test("A record whose scope can't be read counts as the lesson's own, as the Files card reads it")
    func unreadableScopeIsLessonScope() async throws {
        let fixture = try Fixture()
        fixture.attach(to: fixture.circle).scopeRaw = ""
        try fixture.context.save()
        await fixture.index.settle()

        #expect(fixture.index.hasFile(fixture.circle))
    }

    // MARK: - How often it reads

    @Test("One fetch when made, one per refresh, and the fetch registers no objects")
    func oneFetchPerRefresh() async throws {
        let fixture = try Fixture()
        #expect(fixture.counter.count == 1, "made with one read")

        for _ in 0..<3 { fixture.attach(to: fixture.circle) }
        fixture.attach(to: fixture.square)
        try fixture.context.save()
        await fixture.index.settle()
        #expect(fixture.counter.count == 2, "the save is one read, not one per file or lesson")

        fixture.context.reset()
        #expect(fixture.context.registeredObjects.isEmpty)
        fixture.index.refresh()
        #expect(fixture.counter.count == 3)
        #expect(fixture.index.lessonIDs.count == 2)
        #expect(fixture.context.registeredObjects.isEmpty, "a dictionary fetch, not one object per row")
    }

    @Test("Several saves in one turn are read once")
    func burstIsOneRead() async throws {
        let fixture = try Fixture()
        for lesson in [fixture.circle, fixture.square, fixture.circle] {
            fixture.attach(to: lesson)
            try fixture.context.save()
        }
        await fixture.index.settle()

        #expect(fixture.counter.count == 2, "the first read plus one for the three saves")
        #expect(fixture.index.hasFile(fixture.circle))
        #expect(fixture.index.hasFile(fixture.square))
    }

    @Test("A save that touches no attachment doesn't read")
    func otherSavesDoNotRead() async throws {
        let fixture = try Fixture()
        fixture.circle.name = "Area of a Circle (2)"
        try fixture.context.save()
        await fixture.index.settle()

        #expect(fixture.counter.count == 1)
    }

    @Test("A save in another store doesn't read")
    func otherStoreDoesNotRead() async throws {
        let fixture = try Fixture()
        let other = try CoreDataTestHelpers.makeInMemoryStack()
        let lesson = CoreDataTestHelpers.seedLesson(in: other.viewContext, name: "Elsewhere")
        let attachment = CDLessonAttachment(context: other.viewContext)
        attachment.lesson = lesson
        try other.viewContext.save()
        await fixture.index.settle()

        #expect(fixture.counter.count == 1)
    }

    @Test("A save on a background context of the same store (an import, Claude) badges the lesson")
    func backgroundSaveBadges() async throws {
        let fixture = try Fixture()
        let background = fixture.stack.container.newBackgroundContext()
        let lessonID = fixture.circle.objectID
        try await background.perform {
            guard let lesson = try background.existingObject(with: lessonID) as? CDLesson else { return }
            let attachment = CDLessonAttachment(context: background)
            attachment.fileName = "Plan.pdf"
            attachment.lesson = lesson
            try background.save()
        }

        // The background save hands its notice to the main actor; give it a moment.
        for _ in 0..<100 where !fixture.index.hasFile(fixture.circle) {
            try await Task.sleep(for: .milliseconds(20))
            await fixture.index.settle()
        }
        #expect(fixture.index.hasFile(fixture.circle))
    }

    @Test("The save filter reads object IDs of LessonAttachment in this store only")
    func saveFilter() throws {
        let fixture = try Fixture()
        let attachment = fixture.attach(to: fixture.circle)
        try fixture.context.save()
        let stores = Set(fixture.stack.container.persistentStoreCoordinator.persistentStores.map(ObjectIdentifier.init))

        let touching: [AnyHashable: Any] = [NSUpdatedObjectIDsKey: Set([attachment.objectID])]
        let lessonOnly: [AnyHashable: Any] = [NSInsertedObjectIDsKey: Set([fixture.circle.objectID])]
        #expect(LessonAttachmentIndex.touchesAttachments(touching, stores: stores))
        #expect(!LessonAttachmentIndex.touchesAttachments(lessonOnly, stores: stores))
        #expect(!LessonAttachmentIndex.touchesAttachments(touching, stores: []), "another store's save")
        #expect(!LessonAttachmentIndex.touchesAttachments(nil, stores: stores))
    }
}

/// The lines under an attachment's name on the Files card.
@Suite("Lesson files: the Files card row's text")
@MainActor
struct AttachmentRowTextTests {
    private let october25 = Date(timeIntervalSince1970: 1_792_929_600) // 2026-10-25 12:00 UTC

    private func attachment(
        attachedAt: Date?, modifiedAt: Date?, notes: String = "", in context: NSManagedObjectContext
    ) -> CDLessonAttachment {
        let attachment = CDLessonAttachment(context: context)
        attachment.fileSizeBytes = 605_635
        attachment.attachedAt = attachedAt
        attachment.modifiedAt = modifiedAt
        attachment.notes = notes
        return attachment
    }

    private func day(_ date: Date) -> String {
        DateFormatters.shortMonthDay.string(from: date)
    }

    @Test("A file not changed since it was attached reads \"Added <day>\" after its size")
    func added() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let file = attachment(attachedAt: october25, modifiedAt: october25, in: context)

        #expect(AttachmentRow.changeLine(for: file, now: october25) == "Added \(day(october25))")
        #expect(
            AttachmentRow.detailLine(for: file, now: october25)
                == "\(file.fileSizeFormatted) · Added \(day(october25))"
        )
    }

    @Test("A file replaced, renamed or annotated later reads \"Updated <day>\"")
    func updated() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let later = october25.addingTimeInterval(86_400)
        let file = attachment(attachedAt: october25, modifiedAt: later, in: context)

        #expect(AttachmentRow.changeLine(for: file, now: later) == "Updated \(day(later))")
    }

    @Test("A record from before schema 21 reads its attached day; one from another year has the year")
    func olderRecords() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let predated = attachment(attachedAt: october25, modifiedAt: nil, in: context)
        #expect(AttachmentRow.changeLine(for: predated, now: october25) == "Added \(day(october25))")

        let lastYear = october25.addingTimeInterval(-400 * 86_400)
        let old = attachment(attachedAt: lastYear, modifiedAt: lastYear, in: context)
        #expect(
            AttachmentRow.changeLine(for: old, now: october25)
                == "Added \(DateFormatters.mediumDate.string(from: lastYear))"
        )

        let undated = attachment(attachedAt: nil, modifiedAt: nil, in: context)
        #expect(AttachmentRow.changeLine(for: undated, now: october25) == nil)
        #expect(AttachmentRow.detailLine(for: undated, now: october25) == undated.fileSizeFormatted)
    }

    @Test("The note shows trimmed, and not at all when it's blank")
    func note() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let noted = attachment(
            attachedAt: october25, modifiedAt: october25, notes: "  From the remade Geometry album \n", in: context
        )
        let blank = attachment(attachedAt: october25, modifiedAt: october25, notes: " \n ", in: context)

        #expect(AttachmentRow.noteLine(for: noted) == "From the remade Geometry album")
        #expect(AttachmentRow.noteLine(for: blank) == nil)
    }
}

/// Replace with Newer Version…: the service's outcome reaches the guide as a
/// plain toast.
@Suite("Lesson files: Replace with Newer Version… toasts")
@MainActor
struct AttachmentReplacementTests {
    private typealias Scratch = LessonAttachmentServiceTests.Scratch

    /// One PDF's bytes: two renders differ in their embedded creation dates.
    private static let pdfBytes = LessonAttachmentServiceTests.pdf()

    private func added(_ scratch: Scratch) throws -> CDLessonAttachment {
        let source = try scratch.write(Self.pdfBytes, named: "circle.pdf")
        return try scratch.service().add(
            fileAt: source, to: scratch.lesson, title: "Area of a Circle — remade album pages",
            allowedTypes: LessonAttachmentService.pdfOrImage
        )
    }

    @Test("A newer file replaces the record's file and says \"Replaced <title>\"")
    func replaced() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let attachment = try added(scratch)
        let oldPath = attachment.fileRelativePath
        let newer = try scratch.write(
            LessonAttachmentServiceTests.pdf(size: CGSize(width: 600, height: 800)), named: "circle v2.pdf"
        )
        let toasts = ToastService(handOffDelay: .zero)

        await AttachmentReplacement.replace(
            attachment, withPicked: .success([newer]), using: scratch.service(), toasts: toasts
        )

        #expect(toasts.currentToast?.message == "Replaced Area of a Circle — remade album pages")
        #expect(toasts.currentToast?.type == .success)
        #expect(attachment.fileRelativePath != oldPath)
        #expect(try Data(contentsOf: scratch.file(of: attachment)) == Data(contentsOf: newer))
    }

    @Test("The same file says nothing changed and writes nothing")
    func unchanged() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let attachment = try added(scratch)
        let path = attachment.fileRelativePath
        let modified = attachment.modifiedAt
        let same = try scratch.write(Self.pdfBytes, named: "circle again.pdf")
        let toasts = ToastService(handOffDelay: .zero)

        await AttachmentReplacement.replace(
            attachment, withPicked: .success([same]), using: scratch.service(), toasts: toasts
        )

        #expect(toasts.currentToast?.message == AttachmentReplacement.sameFileMessage)
        #expect(toasts.currentToast?.type == .info)
        #expect(attachment.fileRelativePath == path)
        #expect(attachment.modifiedAt == modified)
    }

    @Test("A refused file says why in plain words and leaves the record as it was")
    func refused() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let attachment = try added(scratch)
        let path = attachment.fileRelativePath
        let notAPDF = try scratch.write(Data("plain text".utf8), named: "fake.pdf")
        let toasts = ToastService(handOffDelay: .zero)

        await AttachmentReplacement.replace(
            attachment, withPicked: .success([notAPDF]), using: scratch.service(), toasts: toasts
        )

        let message = try #require(toasts.currentToast?.message)
        #expect(message == LessonAttachmentService.Problem.notReadable(kind: "a PDF").errorDescription)
        #expect(toasts.currentToast?.type == .error)
        #expect(attachment.fileRelativePath == path)
        #expect(!scratch.context.hasChanges)
    }

    @Test("The Sample Class can't replace a file, and says so")
    func sampleClassRefused() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let attachment = try added(scratch)
        let newer = try scratch.write(LessonAttachmentServiceTests.png(), named: "circle.png")
        let toasts = ToastService(handOffDelay: .zero)

        await AttachmentReplacement.replace(
            attachment, withPicked: .success([newer]), using: scratch.service(isSampleClassroom: true), toasts: toasts
        )

        #expect(toasts.currentToast?.message == LessonAttachmentService.Problem.sampleClassMessage)
    }

    @Test("A cancelled picker shows nothing")
    func cancelled() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let attachment = try added(scratch)
        let toasts = ToastService(handOffDelay: .zero)

        await AttachmentReplacement.replace(
            attachment, withPicked: .failure(CocoaError(.userCancelled)), using: scratch.service(), toasts: toasts
        )

        #expect(toasts.currentToast == nil)
    }
}
