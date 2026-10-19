// CalendarNotePadCopy.swift
// One day note: the Calendar's notes join the day's pad (Simplify the app, Phase 7).

import CoreData
import Foundation
import OSLog

/// Copies each Calendar note (`CDCalendarNote`, kept by year, month and day)
/// into that day's pad (`CDDayPad`), the one day note that Today, the
/// Calendar and the Claude tools read and write from now on.
///
/// A note's text goes at the end of the day's pad, after a blank line, unless
/// the pad already has it (`PadText.contains`), so whatever she wrote on the
/// pad stays as it was. It writes through `TodayDataFetcher.appendPadText`,
/// which joins two devices' copies of a day first. Nothing here deletes a
/// Calendar note or changes its text: the old rows stay, for older builds and
/// backups.
///
/// It runs on every launch (`MigrationRunner.copyCalendarNotesToPads`), so a
/// note written later by a device still on an older build is copied too. What
/// it has done is kept on the note itself: a note whose text it adds to the
/// pad, or finds there already, gets `copiedMark` as its `modifiedAt`, in the
/// same save as the pad. A marked note is left alone, so a copied line she
/// edits or deletes on the pad never comes back, and a notebook with nothing
/// new costs one fetch that finds nothing. The mark goes wherever the note
/// goes: through iCloud to every device (a new or reinstalled Mac too, which
/// gets the notes and the pads together), and into backups and back out of
/// them with the pads.
///
/// - An older build that edits a note stamps it with the time (its Calendar
///   sets `modifiedAt = Date()` on an edit, and a note it makes gets the time
///   too), which takes the mark off: the new text is checked against the pad
///   and added if the pad doesn't have it.
/// - A restore, Replace or Merge, puts each backed-up note back as the backup
///   had it, mark and all (`BackupEntityImporter.importRows`, matched on `id`),
///   beside the backup's pads. A note backed up before it was copied comes
///   back unmarked, and the next launch checks it against its pad again: the
///   pad-text check keeps it from going in twice, and if she took the line off
///   the pad after that backup, it comes back, which is accepted: the restore
///   brought back the note as it was before it was copied.
///
/// Until a note is copied, the Calendar and `schedule_for_range` show its text
/// beside the day's pad, read-only (`uncopiedTexts`).
enum CalendarNotePadCopy {
    private static let logger = Logger.migration

    /// The `modifiedAt` a note gets once its text is in its day's pad: the
    /// first moment of 2001 (Core Data's reference date), which no edit stamps.
    nonisolated static let copiedMark = Date(timeIntervalSinceReferenceDate: 0)

    /// What one run did.
    struct Outcome: Equatable {
        /// Notes whose text was added to a pad.
        var copied = 0
        /// Notes whose text the day's pad already had.
        var alreadyThere = 0
        /// Notes with no text, or dated on a day the calendar doesn't have.
        var skipped = 0
    }

    /// Copies every note not marked yet into its day's pad, and marks each one
    /// whose text is now in the pad (`copiedMark`). Notes on the same day go in
    /// the order they were made. Doesn't save; a failed fetch changes nothing.
    /// A note with only spacing, or dated on a day the calendar doesn't have,
    /// is passed over and stays unmarked.
    static func run(in context: NSManagedObjectContext) -> Outcome {
        var outcome = Outcome()
        // Only notes not marked yet (the table is small: the live notebook
        // held a note or two when the copy was written).
        let request = CDFetchRequest(CDCalendarNote.self)
        request.predicate = notCopiedPredicate()
        let notes: [CDCalendarNote]
        do {
            notes = try context.fetch(request).filter { !$0.isDeleted && !isCopied($0) }
        } catch {
            logger.error("Couldn't read the calendar notes to copy into day pads: \(error)")
            return outcome
        }
        for note in notes.sorted(by: madeFirst) {
            let text = note.text.trimmed()
            guard !text.isEmpty else {
                outcome.skipped += 1
                continue
            }
            guard let day = cell(of: note).startOfDay() else {
                logger.warning("A calendar note is dated on a day the calendar doesn't have; it stays where it is")
                outcome.skipped += 1
                continue
            }
            let stored = TodayDataFetcher.fetchDayPad(day: day, context: context)?.body ?? ""
            if PadText.contains(text, in: stored) {
                outcome.alreadyThere += 1
            } else {
                TodayDataFetcher.appendPadText(text, day: day, context: context)
                outcome.copied += 1
            }
            note.modifiedAt = copiedMark
        }
        return outcome
    }

    // MARK: - The Mark

    /// Whether `note`'s text has gone into its day's pad (`copiedMark`).
    nonisolated static func isCopied(_ note: CDCalendarNote) -> Bool {
        note.modifiedAt == copiedMark
    }

    /// Notes with something written that aren't marked copied: what the copy
    /// reads, and what the Calendar and `schedule_for_range` fetch to show.
    /// Once the Mac has copied every note, it matches none.
    nonisolated static func notCopiedPredicate() -> NSPredicate {
        NSPredicate(
            format: "text != %@ AND (modifiedAt == nil OR modifiedAt != %@)", "", copiedMark as NSDate
        )
    }

    // MARK: - Not Yet Copied

    /// The text of each of `notes` (one day's) still to be copied into that
    /// day's pad: not marked, and not in `padText`. Trimmed, in the order the
    /// copy would add them, each text once.
    ///
    /// The iPhone and iPad never copy, and the Mac copies only once it has
    /// caught up with iCloud; meanwhile the Calendar and `schedule_for_range`
    /// show these beside the pad, read-only, so an old note doesn't look lost
    /// and isn't typed in again (which the copy, finding it reworded, would
    /// add a second time). A note copied and then edited off the pad is
    /// marked, and stays off.
    static func uncopiedTexts(of notes: [CDCalendarNote], padText: String) -> [String] {
        var seen = Set<String>()
        var texts: [String] = []
        for note in notes.sorted(by: madeFirst) where !note.isDeleted && !isCopied(note) {
            let text = note.text.trimmed()
            guard !text.isEmpty, !PadText.contains(text, in: padText),
                  seen.insert(PadText.normalized(text).lowercased()).inserted else { continue }
            texts.append(text)
        }
        return texts
    }

    /// `uncopiedTexts` for every day at once, as a grid shows them, keyed by
    /// day: `notes` is every note not marked (`notCopiedPredicate`), `padTexts`
    /// each day's pad.
    static func uncopiedTexts(
        of notes: some Sequence<CDCalendarNote>,
        padTexts: [CellID: String]
    ) -> [CellID: [String]] {
        var notesByCell: [CellID: [CDCalendarNote]] = [:]
        for note in notes where !note.isDeleted && !isCopied(note) {
            notesByCell[cell(of: note), default: []].append(note)
        }
        var lookup: [CellID: [String]] = [:]
        for (day, dayNotes) in notesByCell {
            let texts = uncopiedTexts(of: dayNotes, padText: padTexts[day] ?? "")
            if !texts.isEmpty { lookup[day] = texts }
        }
        return lookup
    }

    // MARK: - Waiting for iCloud

    /// Whether this launch has caught up with iCloud: an import into the
    /// notebook that began at or after `launchedAt` has finished (`lastImport`,
    /// its start, from `ImportWatermark`). Before then the Mac may hold an
    /// older copy of a pad than iCloud does, and adding to it would send that
    /// stale text back over an edit made on the iPad meanwhile.
    nonisolated static func caughtUp(lastImport: Date?, launchedAt: Date) -> Bool {
        lastImport.map { $0 >= launchedAt } ?? false
    }

    // MARK: - Ordering

    /// The grid cell a note is kept under.
    static func cell(of note: CDCalendarNote) -> CellID {
        CellID(year: Int(clamping: note.year), month: Int(clamping: note.month), day: Int(clamping: note.day))
    }

    /// Day first, then the note made first, then the lower id: the order the
    /// texts go into a pad, the same on every device.
    private static func madeFirst(_ lhs: CDCalendarNote, _ rhs: CDCalendarNote) -> Bool {
        let left = (lhs.year, lhs.month, lhs.day)
        let right = (rhs.year, rhs.month, rhs.day)
        if left != right { return left < right }
        let leftMade = lhs.createdAt ?? .distantPast
        let rightMade = rhs.createdAt ?? .distantPast
        if leftMade != rightMade { return leftMade < rightMade }
        return (lhs.id?.uuidString ?? "") < (rhs.id?.uuidString ?? "")
    }
}

// MARK: - Comparing Pad Text

/// Whether a day's pad already says what a note says.
nonisolated enum PadText {

    /// `text` with each run of spaces, tabs and line breaks made one space,
    /// and none at either end.
    static func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Whether `pad` has `text` in it, spacing and upper or lower case aside,
    /// as whole words: "Picture day" is in "Picture day, 9:00", but "PE" is not
    /// in "PEACE assembly", so a short note isn't taken as copied by accident.
    /// Empty text is in every pad.
    static func contains(_ text: String, in pad: String) -> Bool {
        let needle = normalized(text)
        guard let first = needle.first, let last = needle.last else { return true }
        let haystack = normalized(pad)
        var searchStart = haystack.startIndex
        while searchStart < haystack.endIndex,
              let found = haystack.range(
                of: needle, options: [.caseInsensitive], range: searchStart..<haystack.endIndex
              ) {
            let before = found.lowerBound > haystack.startIndex
                ? haystack[haystack.index(before: found.lowerBound)] : nil
            let after = found.upperBound < haystack.endIndex ? haystack[found.upperBound] : nil
            if !joinsWord(first, before), !joinsWord(last, after) { return true }
            searchStart = haystack.index(after: found.lowerBound)
        }
        return false
    }

    /// Whether `neighbor` would carry the word at the match's edge on, past
    /// the match: both are letters or digits.
    private static func joinsWord(_ edge: Character, _ neighbor: Character?) -> Bool {
        guard let neighbor else { return false }
        return isWordCharacter(edge) && isWordCharacter(neighbor)
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }
}
