// WorkCheckInService.swift
// Small persistence service for CDWorkCheckIn operations to keep model methods side-effect free.
// Behavior-preserving cleanup: comments and MARKs only.

import Foundation
import CoreData

/// A small service that centralizes persistence for CDWorkCheckIn operations.
///
/// This service ensures that model methods remain free of side-effects
/// (no implicit saves), while callers can perform explicit, transactional
/// operations that throw on failure.
/// This file includes only structural and documentation improvements; behavior is unchanged.
struct WorkCheckInService {
    let context: NSManagedObjectContext

    // MARK: - Creation

    /// Create and insert a new check-in for the given work.
    /// - Returns: The newly created CDWorkCheckIn.
    @discardableResult
    func createCheckIn(for work: CDWorkModel,
                       date: Date,
                       status: WorkCheckInStatus = .scheduled,
                       purpose: String = "",
                       note: String = "") throws -> CDWorkCheckIn {
        let trimmedNote = note.trimmed()
        let ci = CDWorkCheckIn.make(for: work, on: date, purpose: purpose, status: status, in: context)
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
}
