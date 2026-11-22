//
//  QuickNote.swift
//  Cosmic Daybook
//
//  A quick note at the lesson (plan "Cut unused features and close the lesson
//  loop", 2026-11-21): a line typed as the lesson ends, linked to the
//  presentation and its children, waiting for the guide to say more.
//
//  It is an ordinary note carrying the tag "to fill in", so there is no new
//  field and nothing new to back up or sync. `needsFollowUp` was ruled out: it
//  already means the follow-up inbox. The end-of-day chat lists the notes with
//  the tag (`schedule_for_range` › `unrecorded`), and replacing a note's
//  words through `update_observation` takes the tag off.
//
//  Tags are stored "name|Color" once the notebook has seen them, so a note
//  is matched by the tag's name, never its stored spelling.
//

import CoreData
import Foundation

enum QuickNote {

    /// The tag's name, as the guide reads it.
    static let tagName = "to fill in"

    /// The tag as it is stored on a new quick note.
    static let tag = TagHelper.createTag(name: tagName, color: .orange)

    /// Whether `tag`, in any color or capitalization, is the quick-note tag.
    static func isTag(_ tag: String) -> Bool {
        TagHelper.tagName(tag).trimmed().caseInsensitiveCompare(tagName) == .orderedSame
    }

    /// Whether the note is a quick note still waiting to be filled in.
    static func isWaiting(_ note: CDNote) -> Bool {
        !note.isDeleted && note.tagsArray.contains(where: isTag)
    }

    /// `tags` without the quick-note tag.
    static func removingTag(from tags: [String]) -> [String] {
        tags.filter { !isTag($0) }
    }

    /// Files a quick note on `presentation`, about `students` (the
    /// presentation's children when empty), dated the day it was given, or
    /// now while it hasn't been. Saves.
    ///
    /// - Returns: the note, or nil when `text` is empty or the save failed
    ///   (the note is taken back then).
    @discardableResult
    static func save(
        text: String,
        presentation: CDLessonAssignment,
        students: [UUID] = [],
        context: NSManagedObjectContext,
        now: Date = Date()
    ) -> CDNote? {
        let body = text.trimmed()
        guard !body.isEmpty else { return nil }
        let note = insert(body: body, presentation: presentation, students: students, context: context, now: now)
        guard context.safeSave() else {
            context.delete(note)
            return nil
        }
        return note
    }

    /// The note `save` writes, inserted and not saved.
    static func insert(
        body: String,
        presentation: CDLessonAssignment,
        students: [UUID],
        context: NSManagedObjectContext,
        now: Date = Date()
    ) -> CDNote {
        var seen = Set<UUID>()
        let chosen = (students.isEmpty ? presentation.resolvedStudentIDs : students).filter { seen.insert($0).inserted }
        let note = CDNote(context: context)
        note.body = body
        note.createdAt = presentation.presentedAt ?? now
        switch chosen.count {
        case 0: note.scope = .all
        case 1: note.scope = .student(chosen[0])
        default: note.scope = .students(chosen.sorted { $0.uuidString < $1.uuidString })
        }
        note.tagsArray = [tag]
        note.lessonID = presentation.lessonID
        note.lessonAssignment = presentation
        note.syncStudentLinks(in: context)
        return note
    }

    /// The quick notes still waiting, written on or after `start` and before
    /// `end`, oldest first. Tags are transformable and can't be asked for in a
    /// predicate, so the fetch is held to notes on a presentation in the span
    /// and the tag is read from each.
    static func waiting(from start: Date, before end: Date, in context: NSManagedObjectContext) -> [CDNote] {
        let request = CDFetchRequest(CDNote.self)
        request.predicate = NSPredicate(
            format: "lessonAssignment != nil AND createdAt >= %@ AND createdAt < %@",
            start as NSDate, end as NSDate
        )
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDNote.createdAt, ascending: true)]
        return context.safeFetch(request).filter(isWaiting)
    }
}
