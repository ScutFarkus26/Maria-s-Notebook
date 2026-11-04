// PracticeCheckIns.swift
// Practice is a check-in (plan "Simplify the app, round two", Phase 2).
//
// A practice session used to be a record of its own (`PracticeSession`, now
// retired: its rows stay, unread). Record Practice now makes one completed
// check-in on each child's work, with the minutes in `durationMinutes`, and a
// note on it holding what was noticed: the ratings and the free words as its
// text, the signals ("Breakthrough", "Helped a peer", …) as its tags.
// `PracticeCheckInCopy` makes the same check-ins from the old rows.

import CoreData
import Foundation

/// What one practice was, for one child's work.
nonisolated struct PracticeRecord: Sendable, Equatable {
    var date: Date
    var minutes: Int?
    /// 1–5 (`PracticeSessionLabels.qualityLabel`), nil when unrated.
    var quality: Int?
    /// 1–5 (`PracticeSessionLabels.independenceLabel`), nil when unrated.
    var independence: Int?
    var askedForHelp = false
    var helpedPeer = false
    var struggled = false
    var madeBreakthrough = false
    var needsReteaching = false
    var readyForCheckIn = false
    var readyForAssessment = false
    var notes = ""
    var followUp = ""
    var materials = ""

    /// The signals that were noticed, as the note's tags.
    var signalTags: [String] {
        let noticed: [(Bool, PracticeSignal)] = [
            (askedForHelp, .askedForHelp),
            (helpedPeer, .helpedPeer),
            (struggled, .struggled),
            (madeBreakthrough, .madeBreakthrough),
            (needsReteaching, .needsReteaching),
            (readyForCheckIn, .readyForCheckIn),
            (readyForAssessment, .readyForAssessment)
        ]
        return noticed.compactMap { $0.0 ? $0.1.rawValue : nil }
    }

    /// The note's text: the ratings, then her own words, one to a line.
    var noteBody: String {
        var lines: [String] = []
        if let quality, quality > 0 {
            lines.append("Practice: \(PracticeSessionLabels.qualityLabel(for: quality))")
        }
        if let independence, independence > 0 {
            lines.append("Independence: \(PracticeSessionLabels.independenceLabel(for: independence))")
        }
        let notes = notes.trimmed()
        if !notes.isEmpty { lines.append(notes) }
        let followUp = followUp.trimmed()
        if !followUp.isEmpty { lines.append("Next: \(followUp)") }
        let materials = materials.trimmed()
        if !materials.isEmpty { lines.append("Materials: \(materials)") }
        return lines.joined(separator: "\n")
    }
}

/// What can be noticed in a practice; each is a tag on the check-in's note.
nonisolated enum PracticeSignal: String, CaseIterable, Sendable {
    case askedForHelp = "Asked for help"
    case helpedPeer = "Helped a peer"
    case struggled = "Struggled"
    case madeBreakthrough = "Breakthrough"
    case needsReteaching = "Needs reteaching"
    case readyForCheckIn = "Ready for a check-in"
    case readyForAssessment = "Ready for assessment"
}

nonisolated extension CDWorkCheckIn {
    /// The tags on this check-in's notes.
    var noteTags: [String] {
        ((notes as? Set<CDNote>) ?? []).filter { !$0.isDeleted }.flatMap(\.tagsArray)
    }

    /// The practice signals its notes carry.
    var practiceSignals: Set<PracticeSignal> {
        Set(noteTags.compactMap(PracticeSignal.init(rawValue:)))
    }
}

nonisolated enum PracticeCheckIns {
    /// The `purpose` a practice check-in carries.
    static let purpose = "Practice"

    /// Makes a completed practice check-in on `work`, and its note when the
    /// record says anything beyond the minutes. Does not save.
    ///
    /// - Parameters:
    ///   - checkInID: the check-in's id; the copy passes one worked out from
    ///     the session, so it can tell the check-in is already there.
    ///   - noteID: the note's id, likewise.
    @discardableResult
    static func record(
        _ record: PracticeRecord,
        on work: CDWorkModel,
        checkInID: UUID? = nil,
        noteID: UUID? = nil,
        in context: NSManagedObjectContext
    ) -> CDWorkCheckIn {
        let checkIn = CDWorkCheckIn.make(
            for: work, on: record.date, purpose: purpose, status: .completed, in: context
        )
        if let checkInID { checkIn.id = checkInID }
        checkIn.durationMinutesValue = record.minutes

        let body = record.noteBody
        let tags = record.signalTags
        guard !body.isEmpty || !tags.isEmpty else { return checkIn }
        let note = CDNote(context: context)
        if let noteID { note.id = noteID }
        note.body = body
        note.tagsArray = tags
        note.createdAt = record.date
        note.updatedAt = record.date
        if let studentID = UUID(uuidString: work.studentID) {
            note.scope = .student(studentID)
        } else {
            note.scope = .all
        }
        note.lessonID = work.lessonID
        note.work = work
        note.workCheckIn = checkIn
        note.syncStudentLinks(in: context)
        return checkIn
    }
}
