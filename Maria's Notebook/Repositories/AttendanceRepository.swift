//
//  AttendanceRepository.swift
//  Maria's Notebook
//
//  Repository for AttendanceRecord entity CRUD operations.
//  Wraps the existing AttendanceStore and follows the repository pattern.
//

import Foundation
import OSLog
import SwiftData

@MainActor
struct AttendanceRepository: SavingRepository {
    typealias Model = AttendanceRecord

    private static let logger = Logger.database

    let context: ModelContext
    let saveCoordinator: SaveCoordinator?
    private let store: AttendanceStore

    init(context: ModelContext, saveCoordinator: SaveCoordinator? = nil, calendar: Calendar = .current) {
        self.context = context
        self.saveCoordinator = saveCoordinator
        self.store = AttendanceStore(context: context, calendar: calendar)
    }

    // MARK: - Fetch

    /// Fetch an AttendanceRecord by ID
    func fetchRecord(id: UUID) -> AttendanceRecord? {
        var descriptor = FetchDescriptor<AttendanceRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return context.safeFetchFirst(descriptor)
    }

    /// Fetch AttendanceRecords with optional filtering and sorting
    func fetchRecords(
        predicate: Predicate<AttendanceRecord>? = nil,
        sortBy: [SortDescriptor<AttendanceRecord>] = [SortDescriptor(\.date, order: .reverse)]
    ) -> [AttendanceRecord] {
        var descriptor = FetchDescriptor<AttendanceRecord>()
        if let predicate = predicate {
            descriptor.predicate = predicate
        }
        descriptor.sortBy = sortBy
        return context.safeFetch(descriptor)
    }

    /// Fetch records for a specific date
    func fetchRecords(forDate date: Date, calendar: Calendar = .current) -> [AttendanceRecord] {
        let normalizedDate = date.normalizedDay(using: calendar)
        let predicate = #Predicate<AttendanceRecord> { $0.date == normalizedDate }
        return fetchRecords(predicate: predicate, sortBy: [])
    }

    /// Fetch records for a specific student
    func fetchRecords(forStudentID studentID: UUID) -> [AttendanceRecord] {
        let studentIDString = studentID.uuidString
        let predicate = #Predicate<AttendanceRecord> { $0.studentID == studentIDString }
        return fetchRecords(predicate: predicate)
    }

    // MARK: - Create / Load

    /// Load or create attendance records for a date, ensuring one record per student
    /// - Returns: Tuple of (records, didInsertNew)
    @discardableResult
    func loadOrCreateRecords(forDate date: Date, students: [Student]) -> (records: [AttendanceRecord], didInsert: Bool) {
        do {
            return try store.loadOrCreateRecords(for: date, students: students)
        } catch {
            return ([], false)
        }
    }

    /// Create a new AttendanceRecord
    @discardableResult
    func createRecord(
        studentID: UUID,
        date: Date,
        status: AttendanceStatus = .unmarked,
        absenceReason: AbsenceReason = .none,
        note: String? = nil
    ) -> AttendanceRecord {
        let record = AttendanceRecord(
            studentID: studentID,
            date: date.normalizedDay(),
            status: status,
            absenceReason: absenceReason
        )
        context.insert(record)
        if let note {
            _ = record.setLegacyNoteText(note, in: context)
        }
        return record
    }

    // MARK: - Update

    /// Update status for a record
    @discardableResult
    func updateStatus(id: UUID, status: AttendanceStatus) -> Bool {
        guard let record = fetchRecord(id: id) else { return false }
        return store.updateStatus(record, to: status)
    }

    /// Update note for a record
    @discardableResult
    func updateNote(id: UUID, note: String?) -> Bool {
        guard let record = fetchRecord(id: id) else { return false }
        return store.updateNote(record, to: note)
    }

    /// Update absence reason for a record
    @discardableResult
    func updateAbsenceReason(id: UUID, reason: AbsenceReason) -> Bool {
        guard let record = fetchRecord(id: id) else { return false }
        return store.updateAbsenceReason(record, to: reason)
    }

    // MARK: - Bulk Operations

    /// Mark all students present for a date
    @discardableResult
    func markAllPresent(forDate date: Date, students: [Student]) -> [AttendanceRecord] {
        do {
            return try store.markAllPresent(for: date, students: students)
        } catch {
            return []
        }
    }

    /// Reset all records for a date to unmarked
    @discardableResult
    func resetDay(forDate date: Date, students: [Student]) -> [AttendanceRecord] {
        do {
            return try store.resetDay(for: date, students: students)
        } catch {
            return []
        }
    }

    // MARK: - Delete

    /// Delete an AttendanceRecord by ID
    func deleteRecord(id: UUID) throws {
        guard let record = fetchRecord(id: id) else { return }
        context.delete(record)
        do {
            try context.save()
        } catch {
            Self.logger.warning("Failed to save context: \(error, privacy: .public)")
            throw error
        }
    }
}
