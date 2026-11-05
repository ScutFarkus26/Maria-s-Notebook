//
//  LessonEditDraft.swift
//  Cosmic Daybook
//
//  The lesson card's edit fields, held apart from the lesson until Save.
//
//  The draft remembers which lesson it was filled from, and Save writes it to
//  that lesson only. The Lessons pane once kept one card's state while the
//  guide clicked another lesson's pill, so Save wrote lesson A's name and
//  notes over lesson B (bug hunt 2026-10-10, #39). The pane now resets per
//  lesson; this is the second lock on the same door.
//
//  A move to another area or sub-area lands the lesson last there, as Add
//  Lesson and a drag do; it kept its old number and tied with or jumped
//  ahead of the lessons already there (bug hunt 2026-11-03, #7). The Pages
//  file's Import… and Remove wait here for Save too, so Cancel undoes them
//  (#17); they used to save at once.
//

import CoreData
import Foundation
import OSLog

struct LessonEditDraft: Equatable {
    /// The lesson these values came from; `apply(to:)` refuses any other.
    private(set) var lessonID: UUID?
    /// The lesson's stored personal kind, which may be unset; `personalKind`
    /// below is what the picker shows.
    private var storedPersonalKindRaw: String?
    /// What `restore` puts back: the draft has no field for these, but Save
    /// changes them (a move renumbers, the Pages file follows the form).
    private var storedOrderInSequence: Int64 = 0
    private var storedPagesBookmark: Data?
    private var storedPagesRelativePath: String?

    var name = ""
    var area = ""
    var sequence = ""
    var section = ""
    var writeUp = ""
    var suggestedFollowUpWork = ""
    var source: LessonSource = .album
    var personalKind: PersonalLessonKind = .personal
    var materials = ""
    var purpose = ""
    var ageRange = ""
    var teacherNotes = ""
    var lessonFormat: LessonFormat = .standard
    var parentStoryID: UUID?
    var practiceOverride: ProgressionOverride = .inherit
    var confirmationOverride: ProgressionOverride = .inherit
    var isKeyLesson = false
    /// Import… and Remove for the Pages file, written to the lesson on Save.
    var pagesFileChange: PagesFileChange = .unchanged

    /// A Pages file copied in by Import… while the form is open.
    struct PagesFileCopy: Equatable {
        var url: URL
        var bookmark: Data
        var relativePath: String
    }

    /// What the form did to the lesson's Pages file.
    enum PagesFileChange: Equatable {
        case unchanged
        case imported(PagesFileCopy)
        case removed
    }

    /// The copy Import… made and Save hasn't used yet: Cancel deletes it.
    var pendingPagesCopyURL: URL? {
        if case .imported(let copy) = pagesFileChange { return copy.url }
        return nil
    }

    init() {}

    /// The lesson's values as they stand.
    init(lesson: CDLesson) {
        lessonID = lesson.id
        name = lesson.name
        area = lesson.area
        sequence = lesson.sequence
        section = lesson.section
        writeUp = lesson.writeUp
        suggestedFollowUpWork = lesson.suggestedFollowUpWork
        source = lesson.source
        storedPersonalKindRaw = lesson.personalKindRaw
        personalKind = lesson.personalKind ?? .personal
        materials = lesson.materials
        purpose = lesson.purpose
        ageRange = lesson.ageRange
        teacherNotes = lesson.teacherNotes
        lessonFormat = lesson.lessonFormat
        parentStoryID = lesson.parentStoryUUID
        practiceOverride = lesson.practiceOverride
        confirmationOverride = lesson.confirmationOverride
        isKeyLesson = lesson.isKeyLesson
        storedOrderInSequence = lesson.orderInSequence
        storedPagesBookmark = lesson.pagesFileBookmark
        storedPagesRelativePath = lesson.pagesFileRelativePath
    }

    /// Whether this draft was filled from `lesson`.
    func belongs(to lesson: CDLesson) -> Bool {
        lessonID != nil && lessonID == lesson.id
    }

    /// Writes the draft to the lesson it came from, trimming the one-line
    /// fields. Returns false, touching nothing, for any other lesson; throws,
    /// touching nothing, when the new name or sub-area would file it beside a
    /// lesson of the same name (`LessonRepository.refuseDuplicateName`).
    @discardableResult
    func apply(to lesson: CDLesson) throws(LessonRepository.CreationError) -> Bool {
        guard belongs(to: lesson) else { return false }
        if let context = lesson.managedObjectContext {
            let repository = LessonRepository(context: context)
            try repository.refuseDuplicateName(
                filing: lesson, as: name.trimmed(), area: area.trimmed(), sequence: sequence.trimmed()
            )
            // Counted before the lesson takes its new filing, so it isn't
            // counted among the lessons it lands after.
            if movesFiling(of: lesson) {
                lesson.orderInSequence = Int64(repository.nextOrderInSequence(area: area, sequence: sequence))
            }
        }
        lesson.name = name.trimmed()
        lesson.area = area.trimmed()
        lesson.sequence = sequence.trimmed()
        lesson.section = section.trimmed()
        lesson.writeUp = writeUp
        lesson.suggestedFollowUpWork = suggestedFollowUpWork
        lesson.source = source
        lesson.personalKind = source == .personal ? personalKind : nil
        lesson.materials = materials
        lesson.purpose = purpose.trimmed()
        lesson.ageRange = ageRange.trimmed()
        lesson.teacherNotes = teacherNotes
        lesson.lessonFormat = lessonFormat
        lesson.parentStoryUUID = lessonFormat == .story ? parentStoryID : nil
        lesson.practiceOverride = practiceOverride
        lesson.confirmationOverride = confirmationOverride
        lesson.isKeyLesson = isKeyLesson
        switch pagesFileChange {
        case .unchanged:
            break
        case .imported(let copy):
            lesson.pagesFileBookmark = copy.bookmark
            lesson.pagesFileRelativePath = copy.relativePath
        case .removed:
            lesson.pagesFileBookmark = nil
            lesson.pagesFileRelativePath = nil
        }
        return true
    }

    /// Whether Save files the lesson in another area or sub-area, matched
    /// trimmed and in any case as the Lessons screen groups them.
    func movesFiling(of lesson: CDLesson) -> Bool {
        BulkLessonInsertion.orderKey(area: area, sequence: sequence)
            != BulkLessonInsertion.orderKey(area: lesson.area, sequence: lesson.sequence)
    }

    /// Puts back exactly what `init(lesson:)` read, so a failed save leaves
    /// the lesson as it was on disk rather than holding unsaved edits that
    /// the next unrelated save would write.
    func restore(_ lesson: CDLesson) {
        guard belongs(to: lesson) else { return }
        lesson.name = name
        lesson.area = area
        lesson.sequence = sequence
        lesson.section = section
        lesson.writeUp = writeUp
        lesson.suggestedFollowUpWork = suggestedFollowUpWork
        lesson.source = source
        lesson.personalKindRaw = storedPersonalKindRaw
        lesson.materials = materials
        lesson.purpose = purpose
        lesson.ageRange = ageRange
        lesson.teacherNotes = teacherNotes
        lesson.lessonFormat = lessonFormat
        lesson.parentStoryUUID = parentStoryID
        lesson.practiceOverride = practiceOverride
        lesson.confirmationOverride = confirmationOverride
        lesson.isKeyLesson = isKeyLesson
        lesson.orderInSequence = storedOrderInSequence
        lesson.pagesFileBookmark = storedPagesBookmark
        lesson.pagesFileRelativePath = storedPagesRelativePath
    }
}
