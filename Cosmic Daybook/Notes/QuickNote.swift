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
    /// presentation's children when empty), stamped the moment it was
    /// written; on the day it was given when that was another day. Saves.
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
        note.createdAt = stamp(given: presentation.presentedAt, now: now)
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

    /// When a note written at `now` about a lesson given at `given` is
    /// stamped: `now`, or, for a lesson given on another day, that day at
    /// `now`'s time of day. A recorded lesson's day is midnight, and a note
    /// stamped with it sorted first in its day.
    static func stamp(given: Date?, now: Date) -> Date {
        guard let given, !AppCalendar.isSameDay(given, now) else { return now }
        let calendar = AppCalendar.shared
        let time = calendar.dateComponents([.hour, .minute, .second], from: now)
        return calendar.date(
            bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0, of: given
        ) ?? given
    }

    /// The quick notes still waiting, written before `end`, oldest first. A
    /// note stays until it is filled in or deleted, however old, and also
    /// once its lesson was discarded (`keep(from:)` leaves it on the lesson
    /// alone). Tags are transformable and can't be asked for in a predicate,
    /// so the fetch is held to notes on a lesson and the tag is read from each.
    static func waiting(before end: Date, in context: NSManagedObjectContext) -> [CDNote] {
        let request = CDFetchRequest(CDNote.self)
        request.predicate = NSPredicate(
            format: "(lessonAssignment != nil OR lessonID != nil) AND createdAt < %@", end as NSDate
        )
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDNote.createdAt, ascending: true)]
        request.fetchBatchSize = 200
        return context.safeFetch(request).filter(isWaiting)
    }

    /// Takes the quick notes still to fill in off `presentation` before it is
    /// deleted, so they don't go with it (its notes cascade). Each keeps its
    /// lesson and children and stays on the end-of-day list. Returns how many.
    @discardableResult
    static func keep(from presentation: CDLessonAssignment) -> Int {
        let waiting = ((presentation.unifiedNotes as? Set<CDNote>) ?? []).filter(isWaiting)
        for note in waiting {
            if (note.lessonID ?? "").isEmpty { note.lessonID = presentation.lessonID }
            note.lessonAssignment = nil
        }
        return waiting.count
    }
}
