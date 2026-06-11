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

/// Protocol for CDWorkCheckIn operations
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

// MARK: - Mock for Testing

#if DEBUG
#endif
