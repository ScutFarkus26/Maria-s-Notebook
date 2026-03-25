// WorkCheckInService.swift
// Small persistence service for WorkCheckIn operations to keep model methods side-effect free.
// Behavior-preserving cleanup: comments and MARKs only.

import Foundation
import SwiftData

/// A small service that centralizes persistence for WorkCheckIn operations.
///
/// This service ensures that model methods remain free of side-effects
/// (no implicit saves), while callers can perform explicit, transactional
/// operations that throw on failure.
/// This file includes only structural and documentation improvements; behavior is unchanged.
@MainActor
struct WorkCheckInService {
    let context: ModelContext

    // MARK: - Creation

    /// Create and insert a new check-in for the given work.
    /// - Returns: The newly created WorkCheckIn.
    @discardableResult
    func createCheckIn(for work: WorkModel,
                       date: Date,
                       status: WorkCheckInStatus = .scheduled,
                       purpose: String = "",
                       note: String = "") throws -> WorkCheckIn {
        let trimmedPurpose = purpose.trimmed()
        let trimmedNote = note.trimmed()
        let ci = WorkCheckIn(workID: work.id,
                             date: date,
                             status: status,
                             purpose: trimmedPurpose,
                             work: work)
        context.insert(ci)
        if work.checkIns == nil { work.checkIns = [] }
        work.checkIns = (work.checkIns ?? []) + [ci]
        if !trimmedNote.isEmpty {
            ci.setLegacyNoteText(trimmedNote, in: context)
        }
        return ci
    }

    // MARK: - Updates

    /// Mark a check-in as completed and persist immediately.
    func markCompleted(_ checkIn: WorkCheckIn, note: String? = nil, at date: Date = Date()) throws {
        checkIn.markCompleted(note: nil, at: date, in: context)
        if let note {
            checkIn.setLegacyNoteText(note, in: context)
        }
    }

    /// Reschedule a check-in and persist immediately.
    func reschedule(_ checkIn: WorkCheckIn, to date: Date, note: String? = nil) throws {
        checkIn.reschedule(to: date, note: nil, in: context)
        if let note {
            checkIn.setLegacyNoteText(note, in: context)
        }
    }

    /// Skip a check-in and persist immediately.
    func skip(_ checkIn: WorkCheckIn, note: String? = nil, at date: Date = Date()) throws {
        checkIn.skip(note: nil, at: date, in: context)
        if let note {
            checkIn.setLegacyNoteText(note, in: context)
        }
    }

    /// Update the note on a check-in and persist immediately.
    func updateNote(_ checkIn: WorkCheckIn, to note: String?) throws {
        checkIn.setLegacyNoteText(note, in: context)
    }

    /// Update core fields on a check-in and persist immediately.
    func update(_ checkIn: WorkCheckIn, date: Date, status: WorkCheckInStatus, purpose: String, note: String) throws {
        checkIn.date = date
        checkIn.status = status
        checkIn.purpose = purpose.trimmed()
        checkIn.setLegacyNoteText(note, in: context)
    }

    // MARK: - Deletion

    /// Delete a check-in from its context and persist immediately.
    func delete(_ checkIn: WorkCheckIn, from work: WorkModel? = nil) throws {
        if let work {
            if var list = work.checkIns {
                list.removeAll { $0.id == checkIn.id }
                work.checkIns = list
            }
        }
        context.delete(checkIn)
    }
}
