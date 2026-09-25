//
//  AttendanceRepository.swift
//  Cosmic Daybook
//
//  Repository for CDAttendanceRecord entity CRUD operations.
//  Wraps the existing AttendanceStore and follows the repository pattern.
//

import Foundation
import OSLog
import CoreData

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
    func fetchRecord(id: UUID) -> CDAttendanceRecord? { fetch(id: id) }

    // MARK: - Create / Load

    /// Fetch-or-create the single record for (student, day). Callers save afterwards.
    @discardableResult
    func ensureRecord(forDate date: Date, student: CDStudent) -> CDAttendanceRecord? {
        do {
            return try store.ensureRecord(for: student, on: date)
        } catch {
            Self.logger.warning("Failed to ensure attendance record: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Update

    /// Update status for a record
    @discardableResult
    func updateStatus(id: UUID, status: AttendanceStatus) -> Bool {
        guard let record = fetchRecord(id: id) else { return false }
        return store.updateStatus(record, to: status)
    }
}
