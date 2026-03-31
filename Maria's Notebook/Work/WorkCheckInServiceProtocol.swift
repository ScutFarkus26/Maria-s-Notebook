//
//  WorkCheckInServiceProtocol.swift
//  Maria's Notebook
//
//  Created by Architecture Migration - Phase 1
//  Protocol-based service architecture for WorkCheckInService
//

import Foundation
import CoreData

// MARK: - Protocol Definition

/// Protocol for WorkCheckIn operations
/// Defines the interface for creating, updating, and deleting work check-ins
protocol WorkCheckInServiceProtocol {
    var context: NSManagedObjectContext { get }

    // MARK: - Creation

    /// Create and insert a new check-in for the given work
    /// - Parameters:
    ///   - work: The work item to create a check-in for
    ///   - date: The date of the check-in
    ///   - status: The status of the check-in (default: .scheduled)
    ///   - purpose: The purpose of the check-in
    ///   - note: Additional notes for the check-in
    /// - Returns: The newly created CDWorkCheckIn
    /// - Throws: Core Data persistence errors
    @discardableResult
    func createCheckIn(for work: CDWorkModel,
                       date: Date,
                       status: WorkCheckInStatus,
                       purpose: String,
                       note: String) throws -> CDWorkCheckIn

    // MARK: - Updates

    /// Mark a check-in as completed
    func markCompleted(_ checkIn: CDWorkCheckIn, note: String?, at date: Date) throws

    /// Reschedule a check-in to a new date
    func reschedule(_ checkIn: CDWorkCheckIn, to date: Date, note: String?) throws

    /// Skip a check-in
    func skip(_ checkIn: CDWorkCheckIn, note: String?, at date: Date) throws

    /// Update the note on a check-in
    func updateNote(_ checkIn: CDWorkCheckIn, to note: String?) throws

    /// Update core fields on a check-in
    func update(_ checkIn: CDWorkCheckIn, date: Date, status: WorkCheckInStatus, purpose: String, note: String) throws

    // MARK: - Deletion

    /// Delete a check-in
    func delete(_ checkIn: CDWorkCheckIn, from work: CDWorkModel?) throws
}

// MARK: - Concrete Implementation

/// Concrete implementation that delegates to WorkCheckInService.
/// Now works directly with Core Data types (no adapter bridging needed).
@MainActor
final class CDWorkCheckInServiceImpl: WorkCheckInServiceProtocol {
    let context: NSManagedObjectContext
    private let cdService: WorkCheckInService

    init(context: NSManagedObjectContext) {
        self.context = context
        self.cdService = WorkCheckInService(context: context)
    }

    // MARK: - Creation

    @discardableResult
    func createCheckIn(for work: CDWorkModel,
                       date: Date = Date(),
                       status: WorkCheckInStatus = .scheduled,
                       purpose: String = "",
                       note: String = "") throws -> CDWorkCheckIn {
        try cdService.createCheckIn(for: work, date: date, status: status, purpose: purpose, note: note)
    }

    // MARK: - Updates

    func markCompleted(_ checkIn: CDWorkCheckIn, note: String? = nil, at date: Date = Date()) throws {
        try cdService.markCompleted(checkIn, note: note, at: date)
    }

    func reschedule(_ checkIn: CDWorkCheckIn, to date: Date, note: String? = nil) throws {
        try cdService.reschedule(checkIn, to: date, note: note)
    }

    func skip(_ checkIn: CDWorkCheckIn, note: String? = nil, at date: Date = Date()) throws {
        try cdService.skip(checkIn, note: note, at: date)
    }

    func updateNote(_ checkIn: CDWorkCheckIn, to note: String?) throws {
        try cdService.updateNote(checkIn, to: note)
    }

    func update(_ checkIn: CDWorkCheckIn, date: Date, status: WorkCheckInStatus, purpose: String, note: String) throws {
        try cdService.update(checkIn, date: date, status: status, purpose: purpose, note: note)
    }

    // MARK: - Deletion

    func delete(_ checkIn: CDWorkCheckIn, from work: CDWorkModel? = nil) throws {
        try cdService.delete(checkIn, from: work)
    }
}

// MARK: - Mock for Testing

#if DEBUG
/// Mock implementation for testing
/// Provides in-memory implementation without actual persistence
final class MockWorkCheckInService: WorkCheckInServiceProtocol {
    let context: NSManagedObjectContext
    var createdCheckIns: [CDWorkCheckIn] = []
    var deletedCheckInIDs: [UUID] = []
    var completedCheckInIDs: [UUID] = []

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    @discardableResult
    func createCheckIn(for work: CDWorkModel,
                       date: Date = Date(),
                       status: WorkCheckInStatus = .scheduled,
                       purpose: String = "",
                       note: String = "") throws -> CDWorkCheckIn {
        let checkIn = CDWorkCheckIn(context: context)
        checkIn.id = UUID()
        checkIn.workID = work.id?.uuidString ?? ""
        checkIn.date = date
        checkIn.status = status
        checkIn.purpose = purpose
        checkIn.work = work
        let trimmedNote = note.trimmed()
        if !trimmedNote.isEmpty {
            checkIn.setLegacyNoteText(trimmedNote, in: context)
        }
        createdCheckIns.append(checkIn)
        return checkIn
    }

    func markCompleted(_ checkIn: CDWorkCheckIn, note: String? = nil, at date: Date = Date()) throws {
        if let id = checkIn.id { completedCheckInIDs.append(id) }
        checkIn.status = .completed
    }

    func reschedule(_ checkIn: CDWorkCheckIn, to date: Date, note: String? = nil) throws {
        checkIn.date = date
    }

    func skip(_ checkIn: CDWorkCheckIn, note: String? = nil, at date: Date = Date()) throws {
        checkIn.status = .skipped
    }

    func updateNote(_ checkIn: CDWorkCheckIn, to note: String?) throws {
        checkIn.setLegacyNoteText(note, in: context)
    }

    func update(_ checkIn: CDWorkCheckIn, date: Date, status: WorkCheckInStatus, purpose: String, note: String) throws {
        checkIn.date = date
        checkIn.status = status
        checkIn.purpose = purpose
        checkIn.setLegacyNoteText(note, in: context)
    }

    func delete(_ checkIn: CDWorkCheckIn, from work: CDWorkModel? = nil) throws {
        if let id = checkIn.id { deletedCheckInIDs.append(id) }
    }
}
#endif
