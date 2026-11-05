// PracticeCheckInCopy.swift
// Old practice sessions become check-ins (plan "Simplify the app, round two", Phase 2).

import CryptoKit
import CoreData
import Foundation
import OSLog

/// Copies each retired practice session (`PracticeSession`, read by entity
/// name: its class is gone) into a completed practice check-in on every work
/// row it names (`PracticeCheckIns.record`), and moves the session's notes
/// onto the first of them (`Note.workCheckIn`). A moved note leaves its
/// session, whose `notes` cascade, so deleting the session (a child's
/// deletion, or an older build) can't take a note that now belongs to a
/// check-in. Nothing here deletes a session: the rows stay, for older builds.
///
/// It runs on every launch (`MigrationRunner`'s launch sweep) and after every
/// restore (`BackupService`), so a session that arrives later from a device
/// still on an older build is copied too, and a Replace restore of an older
/// backup (which clears check-ins and skips practice sessions) gets its
/// copies back at once.
///
/// What it has done is told by the ids: each check-in's id, and its note's,
/// is worked out from the session's id and the work's (`derivedID`), so a
/// session whose check-in is already here is left alone. The same ids on two
/// devices that both copied are one record to the launch dedup, and a backup
/// made after the copy restores them without a second copy. A check-in she
/// deletes comes back on the next launch while its session is here.
enum PracticeCheckInCopy {
    nonisolated private static let logger = Logger.migration

    /// The retired entity's name, fetched as plain `NSManagedObject`s.
    nonisolated static let sessionEntityName = "PracticeSession"

    nonisolated struct Outcome: Equatable, Sendable {
        /// Check-ins made.
        var copied = 0
        /// Notes moved from a session onto its check-in.
        var notesRelinked = 0
    }

    /// Makes the missing check-ins and relinks notes. Does not save.
    @discardableResult
    nonisolated static func run(in context: NSManagedObjectContext) -> Outcome {
        var outcome = Outcome()
        let request = NSFetchRequest<NSManagedObject>(entityName: sessionEntityName)
        let sessions = context.safeFetch(request).filter { !$0.isDeleted }
        guard !sessions.isEmpty else { return outcome }

        for session in sessions {
            guard let sessionID = session.value(forKey: "id") as? UUID else { continue }
            let works = (session.value(forKey: "workItemIDs") as? [String] ?? [])
                .compactMap(UUID.init(uuidString:))
                .sorted { $0.uuidString < $1.uuidString }
                .compactMap { context.object(CDWorkModel.self, id: $0) }
                .filter { !$0.isDeleted }
            guard !works.isEmpty else { continue }

            var checkIns: [CDWorkCheckIn] = []
            for work in works {
                guard let workID = work.id else { continue }
                let checkInID = derivedID(sessionID, workID, "check-in")
                if let existing = context.object(CDWorkCheckIn.self, id: checkInID), !existing.isDeleted {
                    checkIns.append(existing)
                    continue
                }
                checkIns.append(PracticeCheckIns.record(
                    record(from: session),
                    on: work,
                    checkInID: checkInID,
                    noteID: derivedID(sessionID, workID, "note"),
                    in: context
                ))
                outcome.copied += 1
            }

            guard let first = checkIns.first else { continue }
            let notes = (session.value(forKey: "notes") as? Set<CDNote>) ?? []
            for note in notes where !note.isDeleted && note.workCheckIn == nil {
                note.workCheckIn = first
                note.setValue(nil, forKey: "practiceSession")
                outcome.notesRelinked += 1
            }
        }
        if outcome != Outcome() {
            let message = "Practice sessions: \(outcome.copied) check-in(s) made, "
                + "\(outcome.notesRelinked) note(s) moved"
            logger.notice("\(message, privacy: .public)")
        }
        return outcome
    }

    /// `run`, then a save of what it made; rolled back if the save fails, so
    /// the next launch tries again. Returns nil when it didn't run: the
    /// context holds someone else's unsaved change.
    @discardableResult
    nonisolated static func runAndSave(in context: NSManagedObjectContext) -> Outcome? {
        guard !context.hasChanges else { return nil }
        let outcome = run(in: context)
        guard context.hasChanges else { return outcome }
        guard context.safeSave() else {
            context.rollback()
            logger.error("Practice sessions couldn't be saved as check-ins; they're tried again next launch")
            return nil
        }
        return outcome
    }

    /// The session's fields, as one practice record.
    nonisolated static func record(from session: NSManagedObject) -> PracticeRecord {
        func flag(_ key: String) -> Bool { (session.value(forKey: key) as? Bool) ?? false }
        func level(_ key: String) -> Int? {
            (session.value(forKey: key) as? NSNumber).map(\.intValue).flatMap { $0 > 0 ? $0 : nil }
        }
        let seconds = (session.value(forKey: "duration") as? NSNumber)?.doubleValue ?? 0
        return PracticeRecord(
            date: (session.value(forKey: "date") as? Date)
                ?? (session.value(forKey: "createdAt") as? Date) ?? Date(),
            minutes: seconds > 0 ? max(1, Int((seconds / 60).rounded())) : nil,
            quality: level("practiceQuality"),
            independence: level("independenceLevel"),
            askedForHelp: flag("askedForHelp"),
            helpedPeer: flag("helpedPeer"),
            struggled: flag("struggledWithConcept"),
            madeBreakthrough: flag("madeBreakthrough"),
            needsReteaching: flag("needsReteaching"),
            readyForCheckIn: flag("readyForCheckIn"),
            readyForAssessment: flag("readyForAssessment"),
            notes: session.value(forKey: "sharedNotes") as? String ?? "",
            followUp: session.value(forKey: "followUpActions") as? String ?? "",
            materials: session.value(forKey: "materialsUsed") as? String ?? ""
        )
    }

    /// A UUID fixed by the session, the work and what it names, so every
    /// device and every run works out the same one.
    nonisolated static func derivedID(_ sessionID: UUID, _ workID: UUID, _ kind: String) -> UUID {
        let seed = "practice-check-in|\(sessionID.uuidString)|\(workID.uuidString)|\(kind)"
        var bytes = Array(SHA256.hash(data: Data(seed.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50  // version 5 (name-based)
        bytes[8] = (bytes[8] & 0x3F) | 0x80  // RFC 4122 variant
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
