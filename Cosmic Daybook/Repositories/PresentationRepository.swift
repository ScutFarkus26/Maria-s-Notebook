//
//  PresentationRepository.swift
//  Cosmic Daybook
//
//  Repository for CDLessonAssignment (Presentation) CRUD operations.
//

import Foundation
import OSLog
import CoreData

struct PresentationRepository: SavingRepository {
    typealias Model = CDLessonAssignment

    private static let logger = Logger.database

    let context: NSManagedObjectContext
    let saveCoordinator: SaveCoordinator?

    init(context: NSManagedObjectContext, saveCoordinator: SaveCoordinator? = nil) {
        self.context = context
        self.saveCoordinator = saveCoordinator
    }

    // MARK: - Fetch

    /// Fetch a CDLessonAssignment by ID
    func fetchLessonAssignment(id: UUID) -> CDLessonAssignment? { fetch(id: id) }

    // MARK: - Update

    /// Schedule a CDLessonAssignment
    @discardableResult
    func schedule(id: UUID, for date: Date, using calendar: Calendar = AppCalendar.shared) -> Bool {
        guard let la = fetchLessonAssignment(id: id) else { return false }
        la.schedule(for: date, using: calendar)
        return true
    }

    /// Unschedule a CDLessonAssignment (move back to draft)
    @discardableResult
    func unschedule(id: UUID) -> Bool {
        guard let la = fetchLessonAssignment(id: id) else { return false }
        la.unschedule()
        return true
    }

    /// Mark a CDLessonAssignment as presented
    @discardableResult
    func markPresented(id: UUID, presentedAt: Date = Date()) -> Bool {
        guard let la = fetchLessonAssignment(id: id) else { return false }
        la.markPresented(at: presentedAt)
        return true
    }

}
