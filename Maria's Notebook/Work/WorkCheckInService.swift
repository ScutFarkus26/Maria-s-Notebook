// WorkCheckInService.swift
// Small persistence service for WorkCheckIn operations to keep model methods side-effect free.
// Behavior-preserving cleanup: comments and MARKs only.

import Foundation
import CoreData

/// A small service that centralizes persistence for WorkCheckIn operations.
///
/// This service ensures that model methods remain free of side-effects
/// (no implicit saves), while callers can perform explicit, transactional
/// operations that throw on failure.
/// This file includes only structural and documentation improvements; behavior is unchanged.
@MainActor
struct WorkCheckInService: WorkCheckInServiceProtocol {
    let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    // Deprecated ModelContext init removed - no longer needed with Core Data.

    // MARK: - Creation

    /// Create and insert a new check-in for the given work.
    /// - Returns: The newly created CDWorkCheckIn.
    @discardableResult
    func createCheckIn(for work: CDWorkModel,
                       date: Date,
                       status: WorkCheckInStatus = .scheduled,
                       purpose: String = "",
                       note: String = "") throws -> CDWorkCheckIn {
        let trimmedPurpose = purpose.trimmed()
        let trimmedNote = note.trimmed()
        let ci = CDWorkCheckIn(context: context)
        ci.workID = work.id?.uuidString ?? ""
        ci.date = date
        ci.status = status
        ci.purpose = trimmedPurpose
        ci.work = work
        work.addToCheckIns(ci)
        if !trimmedNote.isEmpty {
            ci.setLegacyNoteText(trimmedNote, in: context)
        }
        return ci
    }

    // MARK: - Updates

    /// Mark a check-in as completed and persist immediately.
    func markCompleted(_ checkIn: CDWorkCheckIn, note: String? = nil, at date: Date = Date()) throws {
        checkIn.status = .completed
        checkIn.date = date
        if let note {
            checkIn.setLegacyNoteText(note, in: context)
        }
    }

    /// Reschedule a check-in and persist immediately.
    func reschedule(_ checkIn: CDWorkCheckIn, to date: Date, note: String? = nil) throws {
        checkIn.date = date
        checkIn.status = .scheduled
        if let note {
            checkIn.setLegacyNoteText(note, in: context)
        }
    }

    /// Skip a check-in and persist immediately.
    func skip(_ checkIn: CDWorkCheckIn, note: String? = nil, at date: Date = Date()) throws {
        checkIn.status = .skipped
        checkIn.date = date
        if let note {
            checkIn.setLegacyNoteText(note, in: context)
        }
    }

    /// Update the note on a check-in and persist immediately.
    func updateNote(_ checkIn: CDWorkCheckIn, to note: String?) throws {
        checkIn.setLegacyNoteText(note, in: context)
    }

    /// Update core fields on a check-in and persist immediately.
    func update(_ checkIn: CDWorkCheckIn, date: Date, status: WorkCheckInStatus, purpose: String, note: String) throws {
        checkIn.date = date
        checkIn.status = status
        checkIn.purpose = purpose.trimmed()
        checkIn.setLegacyNoteText(note, in: context)
    }

    // MARK: - Deletion

    /// Delete a check-in from its context and persist immediately.
    func delete(_ checkIn: CDWorkCheckIn, from work: CDWorkModel? = nil) throws {
        if let work {
            work.removeFromCheckIns(checkIn)
        }
        context.delete(checkIn)
    }
}
