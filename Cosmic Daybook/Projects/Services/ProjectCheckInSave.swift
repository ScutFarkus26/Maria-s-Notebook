import CoreData
import Foundation

/// Saving a project check-in's page: the project's "last active" stamp, and
/// the field notes typed on the page.
@MainActor
enum ProjectCheckInSave {

    // MARK: - The Project's Stamp

    /// Gets a save of the check-in page ready: when the check-in, its project
    /// or its follow-up work holds an unsaved change, stamps the project active
    /// (`modifiedAt`, which the Projects list and the school-year lens read)
    /// and says to save.
    ///
    /// Only a real change counts. The page used to stamp the project on every
    /// visit, so just opening last year's check-in made a dormant project
    /// "Running" again and brought it into this year (bug hunt 2026-10-11 #66).
    static func prepareSave(_ session: CDProjectSession, works: [CDWorkModel]) -> Bool {
        guard hasChanges(session, works: works) else { return false }
        session.project?.modifiedAt = Date()
        return true
    }

    /// Whether the check-in, its project, its field notes, or any of `works`
    /// with their steps, notes, participants and check-ins hold an unsaved
    /// change. A deleted object still counts until the save.
    static func hasChanges(_ session: CDProjectSession, works: [CDWorkModel]) -> Bool {
        if session.hasChanges || session.project?.hasChanges == true { return true }
        if members(session.noteItems).contains(where: \.hasChanges) { return true }
        return works.contains { work in
            work.hasChanges
                || members(work.steps).contains(where: \.hasChanges)
                || members(work.unifiedNotes).contains(where: \.hasChanges)
                || members(work.participants).contains(where: \.hasChanges)
                || members(work.checkIns).contains(where: \.hasChanges)
        }
    }

    private static func members(_ set: NSSet?) -> [NSManagedObject] {
        (set?.allObjects as? [NSManagedObject]) ?? []
    }

    // MARK: - Field Notes

    /// The note to write back from a field that loaded `base`, now holds
    /// `typed`, while the store holds `stored`; nil to leave the stored note
    /// as it is.
    ///
    /// A field she hasn't changed writes nothing, so a page left open on one
    /// device can't put its old text over a newer edit made on another (bug
    /// hunt 2026-10-11 #73). When both changed, her addition goes after the
    /// stored text, the Day Pad's rule (`TodayDataFetcher.mergedPadText`).
    static func noteToWrite(typed: String, base: String, stored: String) -> String? {
        let typed = typed.trimmed()
        let base = base.trimmed()
        let stored = stored.trimmed()
        guard typed != base else { return nil }
        let text = TodayDataFetcher.mergedPadText(typed: typed, base: base, stored: stored)
        return text == stored ? nil : text
    }
}
