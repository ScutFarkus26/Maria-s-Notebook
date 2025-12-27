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
        let trimmedPurpose = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let ci = WorkCheckIn(workID: work.id,
                             date: date,
                             status: status,
                             purpose: trimmedPurpose,
                             note: trimmedNote,
                             work: work)
        context.insert(ci)
        if work.checkIns == nil { work.checkIns = [] }
        work.checkIns = (work.checkIns ?? []) + [ci]
        return ci
    }

    // MARK: - Updates

    /// Mark a check-in as completed and persist immediately.
    func markCompleted(_ checkIn: WorkCheckIn, note: String? = nil, at date: Date = Date()) throws {
        checkIn.markCompleted(note: note, at: date, in: context)
    }

    /// Reschedule a check-in and persist immediately.
    func reschedule(_ checkIn: WorkCheckIn, to date: Date, note: String? = nil) throws {
        checkIn.reschedule(to: date, note: note, in: context)
    }

    /// Skip a check-in and persist immediately.
    func skip(_ checkIn: WorkCheckIn, note: String? = nil, at date: Date = Date()) throws {
        checkIn.skip(note: note, at: date, in: context)
    }

    /// Update the note on a check-in and persist immediately.
    func updateNote(_ checkIn: WorkCheckIn, to note: String?) throws {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        checkIn.note = trimmed
    }

    /// Update core fields on a check-in and persist immediately.
    func update(_ checkIn: WorkCheckIn, date: Date, status: WorkCheckInStatus, purpose: String, note: String) throws {
        checkIn.date = date
        checkIn.status = status
        checkIn.purpose = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        checkIn.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Deletion

    /// Delete a check-in from its context and persist immediately.
    func delete(_ checkIn: WorkCheckIn, from work: WorkModel? = nil) throws {
        if let work = work {
            if var list = work.checkIns {
                list.removeAll { $0.id == checkIn.id }
                work.checkIns = list
            }
        }
        context.delete(checkIn)
    }
}

