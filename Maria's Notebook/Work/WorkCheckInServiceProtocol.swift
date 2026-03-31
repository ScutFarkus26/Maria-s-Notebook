//
//  WorkCheckInServiceProtocol.swift
//  Maria's Notebook
//
//  Created by Architecture Migration - Phase 1
//  Protocol-based service architecture for WorkCheckInService
//

import Foundation
import SwiftData
import CoreData

// MARK: - Protocol Definition

/// Protocol for WorkCheckIn operations
/// Defines the interface for creating, updating, and deleting work check-ins
protocol WorkCheckInServiceProtocol {
    var context: ModelContext { get }
    
    // MARK: - Creation
    
    /// Create and insert a new check-in for the given work
    /// - Parameters:
    ///   - work: The work item to create a check-in for
    ///   - date: The date of the check-in
    ///   - status: The status of the check-in (default: .scheduled)
    ///   - purpose: The purpose of the check-in
    ///   - note: Additional notes for the check-in
    /// - Returns: The newly created WorkCheckIn
    /// - Throws: SwiftData persistence errors
    @discardableResult
    func createCheckIn(for work: WorkModel,
                       date: Date,
                       status: WorkCheckInStatus,
                       purpose: String,
                       note: String) throws -> WorkCheckIn
    
    // MARK: - Updates
    
    /// Mark a check-in as completed
    /// - Parameters:
    ///   - checkIn: The check-in to mark as completed
    ///   - note: Optional note about completion
    ///   - date: The completion date (default: now)
    /// - Throws: SwiftData persistence errors
    func markCompleted(_ checkIn: WorkCheckIn, note: String?, at date: Date) throws
    
    /// Reschedule a check-in to a new date
    /// - Parameters:
    ///   - checkIn: The check-in to reschedule
    ///   - date: The new date
    ///   - note: Optional note about rescheduling
    /// - Throws: SwiftData persistence errors
    func reschedule(_ checkIn: WorkCheckIn, to date: Date, note: String?) throws
    
    /// Skip a check-in
    /// - Parameters:
    ///   - checkIn: The check-in to skip
    ///   - note: Optional note about skipping
    ///   - date: The skip date (default: now)
    /// - Throws: SwiftData persistence errors
    func skip(_ checkIn: WorkCheckIn, note: String?, at date: Date) throws
    
    /// Update the note on a check-in
    /// - Parameters:
    ///   - checkIn: The check-in to update
    ///   - note: The new note content
    /// - Throws: SwiftData persistence errors
    func updateNote(_ checkIn: WorkCheckIn, to note: String?) throws
    
    /// Update core fields on a check-in
    /// - Parameters:
    ///   - checkIn: The check-in to update
    ///   - date: The new date
    ///   - status: The new status
    ///   - purpose: The new purpose
    ///   - note: The new note
    /// - Throws: SwiftData persistence errors
    func update(_ checkIn: WorkCheckIn, date: Date, status: WorkCheckInStatus, purpose: String, note: String) throws
    
    // MARK: - Deletion
    
    /// Delete a check-in
    /// - Parameters:
    ///   - checkIn: The check-in to delete
    ///   - work: Optional work item to update relationships
    /// - Throws: SwiftData persistence errors
    func delete(_ checkIn: WorkCheckIn, from work: WorkModel?) throws
}

// MARK: - Adapter Implementation

/// Adapter that wraps the existing WorkCheckInService struct
/// Provides protocol-based interface for dependency injection and testing.
/// Bridges SwiftData types to Core Data internally during the transition.
@MainActor
final class WorkCheckInServiceAdapter: WorkCheckInServiceProtocol {
    let context: ModelContext
    private let cdService: WorkCheckInService
    private let cdContext: NSManagedObjectContext

    init(context: ModelContext) {
        self.context = context
        self.cdContext = AppBootstrapping.getSharedCoreDataStack().viewContext
        self.cdService = WorkCheckInService(context: cdContext)
    }

    // MARK: - CD Lookup Helpers

    private func cdWork(for work: WorkModel) -> CDWorkModel? {
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(format: "id == %@", work.id as CVarArg)
        request.fetchLimit = 1
        return cdContext.safeFetchFirst(request)
    }

    private func cdCheckIn(for checkIn: WorkCheckIn) -> CDWorkCheckIn? {
        let request = CDFetchRequest(CDWorkCheckIn.self)
        request.predicate = NSPredicate(format: "id == %@", checkIn.id as CVarArg)
        request.fetchLimit = 1
        return cdContext.safeFetchFirst(request)
    }

    // MARK: - Creation

    @discardableResult
    func createCheckIn(for work: WorkModel,
                       date: Date = Date(),
                       status: WorkCheckInStatus = .scheduled,
                       purpose: String = "",
                       note: String = "") throws -> WorkCheckIn {
        guard let cdW = cdWork(for: work) else {
            throw NSError(domain: "WorkCheckInServiceAdapter", code: 1, userInfo: [NSLocalizedDescriptionKey: "CDWorkModel not found"])
        }
        let cdCI = try cdService.createCheckIn(for: cdW, date: date, status: status, purpose: purpose, note: note)
        // Return a SwiftData WorkCheckIn for protocol conformance
        let swiftDataCI = WorkCheckIn(workID: work.id, date: date, status: status, purpose: purpose, work: work)
        swiftDataCI.id = cdCI.id ?? UUID()
        context.insert(swiftDataCI)
        return swiftDataCI
    }

    // MARK: - Updates

    func markCompleted(_ checkIn: WorkCheckIn, note: String? = nil, at date: Date = Date()) throws {
        guard let cdCI = cdCheckIn(for: checkIn) else { return }
        try cdService.markCompleted(cdCI, note: note, at: date)
    }

    func reschedule(_ checkIn: WorkCheckIn, to date: Date, note: String? = nil) throws {
        guard let cdCI = cdCheckIn(for: checkIn) else { return }
        try cdService.reschedule(cdCI, to: date, note: note)
    }

    func skip(_ checkIn: WorkCheckIn, note: String? = nil, at date: Date = Date()) throws {
        guard let cdCI = cdCheckIn(for: checkIn) else { return }
        try cdService.skip(cdCI, note: note, at: date)
    }

    func updateNote(_ checkIn: WorkCheckIn, to note: String?) throws {
        guard let cdCI = cdCheckIn(for: checkIn) else { return }
        try cdService.updateNote(cdCI, to: note)
    }

    func update(_ checkIn: WorkCheckIn, date: Date, status: WorkCheckInStatus, purpose: String, note: String) throws {
        guard let cdCI = cdCheckIn(for: checkIn) else { return }
        try cdService.update(cdCI, date: date, status: status, purpose: purpose, note: note)
    }

    // MARK: - Deletion

    func delete(_ checkIn: WorkCheckIn, from work: WorkModel? = nil) throws {
        guard let cdCI = cdCheckIn(for: checkIn) else { return }
        let cdW = work.flatMap { cdWork(for: $0) }
        try cdService.delete(cdCI, from: cdW)
    }
}

// MARK: - Mock for Testing

#if DEBUG
/// Mock implementation for testing
/// Provides in-memory implementation without actual persistence
final class MockWorkCheckInService: WorkCheckInServiceProtocol {
    let context: ModelContext
    var createdCheckIns: [WorkCheckIn] = []
    var deletedCheckInIDs: [UUID] = []
    var completedCheckInIDs: [UUID] = []
    
    init(context: ModelContext) {
        self.context = context
    }
    
    @discardableResult
    func createCheckIn(for work: WorkModel,
                       date: Date = Date(),
                       status: WorkCheckInStatus = .scheduled,
                       purpose: String = "",
                       note: String = "") throws -> WorkCheckIn {
        let trimmedNote = note.trimmed()
        let checkIn = WorkCheckIn(workID: work.id, date: date, status: status, purpose: purpose, work: work)
        if !trimmedNote.isEmpty {
            checkIn.setLegacyNoteText(trimmedNote, in: context)
        }
        createdCheckIns.append(checkIn)
        return checkIn
    }
    
    func markCompleted(_ checkIn: WorkCheckIn, note: String? = nil, at date: Date = Date()) throws {
        completedCheckInIDs.append(checkIn.id)
        checkIn.status = .completed
    }
    
    func reschedule(_ checkIn: WorkCheckIn, to date: Date, note: String? = nil) throws {
        checkIn.date = date
    }
    
    func skip(_ checkIn: WorkCheckIn, note: String? = nil, at date: Date = Date()) throws {
        checkIn.status = .skipped
    }
    
    func updateNote(_ checkIn: WorkCheckIn, to note: String?) throws {
        checkIn.setLegacyNoteText(note, in: context)
    }

    func update(_ checkIn: WorkCheckIn, date: Date, status: WorkCheckInStatus, purpose: String, note: String) throws {
        checkIn.date = date
        checkIn.status = status
        checkIn.purpose = purpose
        checkIn.setLegacyNoteText(note, in: context)
    }
    
    func delete(_ checkIn: WorkCheckIn, from work: WorkModel? = nil) throws {
        deletedCheckInIDs.append(checkIn.id)
    }
}
#endif
