//
//  AttendanceRepository.swift
//  Maria's Notebook
//
//  Repository for CDAttendanceRecord entity CRUD operations.
//  Wraps the existing AttendanceStore and follows the repository pattern.
//

import Foundation
import OSLog
import CoreData

@MainActor
struct AttendanceRepository: SavingRepository {
    typealias Model = CDAttendanceRecord

    private static let logger = Logger.database

    let context: NSManagedObjectContext
    let saveCoordinator: SaveCoordinator?
    private let store: CDAttendanceStore

    init(context: NSManagedObjectContext, saveCoordinator: SaveCoordinator? = nil, calendar: Calendar = .current) {
        self.context = context
        self.saveCoordinator = saveCoordinator
        self.store = CDAttendanceStore(context: context, calendar: calendar)
    }

    // MARK: - Fetch

    /// Fetch an CDAttendanceRecord by ID
    func fetchRecord(id: UUID) -> CDAttendanceRecord? {
        let request = CDFetchRequest(CDAttendanceRecord.self)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return context.safeFetchFirst(request)
    }

    /// Fetch AttendanceRecords with optional filtering and sorting
    func fetchRecords(
        predicate: NSPredicate? = nil,
        sortBy: [NSSortDescriptor] = [NSSortDescriptor(key: "date", ascending: false)]
    ) -> [CDAttendanceRecord] {
        let request = CDFetchRequest(CDAttendanceRecord.self)
        request.predicate = predicate
        request.sortDescriptors = sortBy
        return context.safeFetch(request)
    }

    /// Fetch records for a specific date
    func fetchRecords(forDate date: Date, calendar: Calendar = .current) -> [CDAttendanceRecord] {
        let normalizedDate = date.normalizedDay(using: calendar)
        return fetchRecords(predicate: NSPredicate(format: "date == %@", normalizedDate as NSDate), sortBy: [])
    }

    /// Fetch records for a specific student
    func fetchRecords(forStudentID studentID: UUID) -> [CDAttendanceRecord] {
        fetchRecords(predicate: NSPredicate(format: "studentID == %@", studentID.uuidString))
    }

    // MARK: - Create / Load

    /// Load or create attendance records for a date, ensuring one record per student
    @discardableResult
    func loadOrCreateRecords(
        forDate date: Date,
        students: [CDStudent]
    ) -> (records: [CDAttendanceRecord], didInsert: Bool) {
        do {
            return try store.loadOrCreateRecords(for: date, students: students)
        } catch {
            return ([], false)
        }
    }

    /// Create a new CDAttendanceRecord
    @discardableResult
    func createRecord(
        studentID: UUID,
        date: Date,
        status: AttendanceStatus = .unmarked,
        absenceReason: AbsenceReason = .none,
        note: String? = nil
    ) -> CDAttendanceRecord {
        let record = CDAttendanceRecord(context: context)
        record.studentID = studentID.uuidString
        record.date = date.normalizedDay()
        record.status = status
        record.absenceReason = absenceReason
        if let note {
            record.setLegacyNoteText(note, in: context)
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
    func markAllPresent(forDate date: Date, students: [CDStudent]) -> [CDAttendanceRecord] {
        do {
            return try store.markAllPresent(for: date, students: students)
        } catch {
            return []
        }
    }

    /// Reset all records for a date to unmarked
    @discardableResult
    func resetDay(forDate date: Date, students: [CDStudent]) -> [CDAttendanceRecord] {
        do {
            return try store.resetDay(for: date, students: students)
        } catch {
            return []
        }
    }

    // MARK: - Delete

    /// Delete an CDAttendanceRecord by ID
    func deleteRecord(id: UUID) throws {
        guard let record = fetchRecord(id: id) else { return }
        context.delete(record)
        try context.save()
    }
}
