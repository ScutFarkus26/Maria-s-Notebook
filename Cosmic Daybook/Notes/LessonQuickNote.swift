//
//  LessonQuickNote.swift
//  Cosmic Daybook
//
//  "Given — quick note" on Today (plan "Cut unused features and close the
//  lesson loop", Phase 4): mark the lesson given and type a line about it in
//  one step. The note itself is `QuickNote` (tagged "to fill in", so the
//  end-of-day chat asks for the rest); this file is the action around it:
//  recording the lesson, remembering it, finding the lesson a menu command
//  means, and saving what was typed.
//
//  On the Mac the note is typed in a small window of its own
//  (`LessonQuickNoteWindow`), which reads the lesson from
//  `LessonQuickNoteTarget`; on the iPad and iPhone it is a sheet on Today.
//

import CoreData
import Foundation
import Observation

enum LessonQuickNote {

    /// The Mac window's scene id.
    static let windowID = "quick-note"

    /// Records `assignment` as given today for the children who were there,
    /// as "Mark Presented Now" does (`TodayMarkPresented`), and remembers it
    /// as the lesson just given. An absent child stays on the plan; the
    /// recorded presentation is still `assignment`, so the note goes on it.
    @MainActor
    static func markGiven(
        _ assignment: CDLessonAssignment,
        now: Date = Date(),
        context: NSManagedObjectContext,
        saveCoordinator: SaveCoordinator
    ) throws -> PresentationRecorder.Result {
        let result = try TodayMarkPresented.record(
            assignment, now: now, context: context, saveCoordinator: saveCoordinator
        )
        LessonQuickNoteTarget.shared.lastGivenID = assignment.id
        return result
    }

    /// Saves `text` as a quick note on the presentation with `presentationID`
    /// (`QuickNote.save`).
    ///
    /// - Returns: false when the presentation is gone, the text is empty, or
    ///   the save failed; nothing is left behind then.
    @discardableResult
    static func save(
        text: String,
        presentationID: UUID,
        context: NSManagedObjectContext,
        now: Date = Date()
    ) -> Bool {
        guard let presentation = context.object(CDLessonAssignment.self, id: presentationID),
              !presentation.isDeleted else { return false }
        return QuickNote.save(text: text, presentation: presentation, context: context, now: now) != nil
    }

    // MARK: - Which lesson the command means

    /// The lesson a quick note opened from the menu is about: the one just
    /// given (`lastGivenID`, while it was given today), else the first lesson
    /// planned for today and not given yet (the one in progress), else the
    /// lesson given today that was changed last. Nil on a day with none.
    static func target(
        lastGivenID: UUID?,
        now: Date = Date(),
        calendar: Calendar = AppCalendar.shared,
        context: NSManagedObjectContext
    ) -> UUID? {
        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }

        if let lastGivenID,
           let given = context.object(CDLessonAssignment.self, id: lastGivenID),
           !given.isDeleted, given.isPresented,
           let presentedAt = given.presentedAt, presentedAt >= start, presentedAt < end {
            return lastGivenID
        }

        let planned = CDFetchRequest(CDLessonAssignment.self)
        planned.predicate = NSPredicate(
            format: "scheduledFor >= %@ AND scheduledFor < %@", start as NSDate, end as NSDate
        )
        planned.sortDescriptors = [NSSortDescriptor(keyPath: \CDLessonAssignment.scheduledFor, ascending: true)]
        if let next = context.safeFetch(planned).first(where: { !$0.isDeleted && !$0.isPresented }) {
            return next.id
        }

        let given = CDFetchRequest(CDLessonAssignment.self)
        given.predicate = NSPredicate(
            format: "presentedAt >= %@ AND presentedAt < %@", start as NSDate, end as NSDate
        )
        return context.safeFetch(given)
            .filter { !$0.isDeleted && $0.isPresented }
            .max { ($0.modifiedAt ?? .distantPast) < ($1.modifiedAt ?? .distantPast) }?
            .id
    }

    // MARK: - Words

    /// The action's name on Today's rows and Next card.
    static let givenTitle = "Given — Quick Note"

    /// What the note's header says about the lesson: "Given today", or "Not
    /// marked given yet" for a lesson still in progress.
    static func statusLine(for presentation: CDLessonAssignment) -> String {
        presentation.isPresented ? "Given today" : "Not marked given yet"
    }
}

/// The lesson the Mac's quick-note window is about, and the lesson given
/// last. One per app: the window is one window, opened by Today's action and
/// the menu command.
@Observable @MainActor
final class LessonQuickNoteTarget {
    static let shared = LessonQuickNoteTarget()

    /// The presentation the window notes on; nil shows "no lesson today".
    private(set) var presentationID: UUID?
    /// Moves when the window is pointed at another lesson, so it starts a
    /// fresh note there. Opening it again on the same lesson keeps what was
    /// typed (a second ⌃⌘J mid-sentence must not wipe it).
    private(set) var openCount = 0
    /// The lesson given last through Today, for the menu command.
    var lastGivenID: UUID?

    /// Points the window at `presentationID`; the caller then opens it.
    func open(_ presentationID: UUID?) {
        guard presentationID != self.presentationID else { return }
        self.presentationID = presentationID
        openCount += 1
    }
}
