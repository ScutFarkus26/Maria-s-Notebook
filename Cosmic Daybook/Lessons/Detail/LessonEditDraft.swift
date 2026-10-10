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

import CoreData
import Foundation

struct LessonEditDraft: Equatable {
    /// The lesson these values came from; `apply(to:)` refuses any other.
    private(set) var lessonID: UUID?
    /// The lesson's stored personal kind, which may be unset; `personalKind`
    /// below is what the picker shows.
    private var storedPersonalKindRaw: String?

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
    }

    /// Whether this draft was filled from `lesson`.
    func belongs(to lesson: CDLesson) -> Bool {
        lessonID != nil && lessonID == lesson.id
    }

    /// Writes the draft to the lesson it came from, trimming the one-line
    /// fields. Returns false, touching nothing, for any other lesson.
    @discardableResult
    func apply(to lesson: CDLesson) -> Bool {
        guard belongs(to: lesson) else { return false }
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
        return true
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
    }
}
