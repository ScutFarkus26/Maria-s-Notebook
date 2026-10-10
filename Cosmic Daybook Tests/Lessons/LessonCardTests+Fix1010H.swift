import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The lesson card and its files (bug hunt 2026-10-10, #39, #40, #47): an edit can
/// only be saved onto the lesson it was started on; sequence- and area-wide
/// attachments show on every lesson they reach; a Sample Class copy of a lesson
/// deleted from My Class lets go of the real notebook's files.
@Suite("Lesson card and shared files (fix 10-10 H)")
@MainActor
struct LessonCardFix1010HTests {

    @Test("Switching lessons mid-edit can't save one lesson's edits over another")
    func draftOnlySavesToItsLesson() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let lessonA = CoreDataTestHelpers.seedLesson(in: context, name: "Golden Beads")
        lessonA.writeUp = "A's write-up"
        let lessonB = CoreDataTestHelpers.seedLesson(in: context, name: "Bank Game")
        lessonB.writeUp = "B's write-up"

        var draft = LessonEditDraft(lesson: lessonA)
        draft.name = "Golden Beads, revised"
        draft.writeUp = "New notes for A"

        #expect(!draft.apply(to: lessonB))
        #expect(lessonB.name == "Bank Game")
        #expect(lessonB.writeUp == "B's write-up")

        #expect(draft.apply(to: lessonA))
        #expect(lessonA.name == "Golden Beads, revised")
        #expect(lessonA.writeUp == "New notes for A")
    }

    @Test("A failed save puts the lesson back as it was")
    func restoreUndoesTheApply() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Golden Beads")
        lesson.source = .personal
        lesson.personalKindRaw = nil
        let onDisk = LessonEditDraft(lesson: lesson)

        var draft = onDisk
        draft.name = "  Renamed  "
        draft.source = .album
        draft.isKeyLesson = true
        #expect(draft.apply(to: lesson))
        #expect(lesson.name == "Renamed")

        onDisk.restore(lesson)
        #expect(lesson.name == "Golden Beads")
        #expect(lesson.source == .personal)
        #expect(lesson.personalKindRaw == nil)
        #expect(!lesson.isKeyLesson)
    }

    @Test("Sequence- and area-wide attachments show on every lesson they reach")
    func sharedAttachmentsReachTheirLessons() throws {
        let context = try CoreDataTestHelpers.makeContext()
        func lesson(_ name: String, _ area: String, _ sequence: String) -> CDLesson {
            CoreDataTestHelpers.seedLesson(in: context, name: name, area: area, sequence: sequence)
        }
        let holder = lesson("Golden Beads", "Math", "Decimal")
        let sameSequence = lesson("Bank Game", "math ", "decimal")
        let sameArea = lesson("Stamp Game", "Math", "Operations")
        let otherArea = lesson("Noun", "Language", "Grammar")
        func attach(_ name: String, _ scope: AttachmentScope) -> CDLessonAttachment {
            let attachment = CDLessonAttachment(context: context)
            attachment.fileName = name
            attachment.fileRelativePath = "Math/Decimal/\(name)"
            attachment.scope = scope
            attachment.lesson = holder
            return attachment
        }
        let own = attach("Card.pdf", .lesson)
        let sequenceWide = attach("[Sequence] Chart.pdf", .sequence)
        let areaWide = attach("[Area] Facts.pdf", .area)
        try context.save()

        func names(_ lesson: CDLesson) -> Set<String> {
            Set(LessonFileStorage.getAttachments(forLesson: lesson).map(\.fileName))
        }
        #expect(names(holder) == [own.fileName, sequenceWide.fileName, areaWide.fileName])
        #expect(names(sameSequence) == [sequenceWide.fileName, areaWide.fileName])
        #expect(names(sameArea) == [areaWide.fileName])
        #expect(names(otherArea).isEmpty)
        #expect(LessonFileStorage.getAttachments(forLesson: sameSequence, includeInherited: false).isEmpty)
    }

    @Test("A Sample Class copy of a lesson deleted from My Class lets go of its files")
    func sampleCopyReleasesFiles() throws {
        let real = try CoreDataTestHelpers.makeContext()
        let sample = try CoreDataTestHelpers.makeContext()
        let deleted = CoreDataTestHelpers.seedLesson(in: real, name: "Golden Beads")
        deleted.pagesFileRelativePath = "Math/Counting/Golden Beads.pages"
        let kept = CoreDataTestHelpers.seedLesson(in: real, name: "Bank Game")
        for lesson in [deleted, kept] {
            let attachment = CDLessonAttachment(context: real)
            attachment.fileRelativePath = "Math/Counting/\(lesson.name).pdf"
            attachment.lesson = lesson
        }
        try real.save()
        try SampleClassroomSeeder.mirror(lessons: SampleClassroomSeeder.lessonSnapshots(from: real), into: sample)
        let madeInSample = CoreDataTestHelpers.seedLesson(in: sample, name: "Sample-only lesson")
        try sample.save()

        real.delete(deleted)
        try real.save()
        try SampleClassroomSeeder.mirror(lessons: SampleClassroomSeeder.lessonSnapshots(from: real), into: sample)
        try sample.save()

        let copies = sample.safeFetch(CDFetchRequest(CDLesson.self))
        let deletedCopy = try #require(copies.first { $0.name == "Golden Beads" })
        let keptCopy = try #require(copies.first { $0.name == "Bank Game" })
        #expect(deletedCopy.pagesFileRelativePath == nil)
        #expect((deletedCopy.attachments?.count ?? 0) == 0)
        #expect(keptCopy.attachments?.count == 1)
        #expect(copies.contains { $0.objectID == madeInSample.objectID })
    }
}
