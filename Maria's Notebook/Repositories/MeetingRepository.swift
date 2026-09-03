//
//  MeetingRepository.swift
//  Maria's Notebook
//
//  Repository for CDStudentMeeting entity CRUD operations.
//

import Foundation
import OSLog
import CoreData

@MainActor
struct MeetingRepository: SavingRepository {
    typealias Model = CDStudentMeeting

    private static let logger = Logger.database

    let context: NSManagedObjectContext
    let saveCoordinator: SaveCoordinator?

    init(context: NSManagedObjectContext, saveCoordinator: SaveCoordinator? = nil) {
        self.context = context
        self.saveCoordinator = saveCoordinator
    }

    // MARK: - Fetch

    /// Fetch a CDStudentMeeting by ID
    func fetchMeeting(id: UUID) -> CDStudentMeeting? { fetch(id: id) }

    /// Fetch multiple StudentMeetings with optional filtering and sorting
    func fetchMeetings(
        predicate: NSPredicate? = nil,
        sortBy: [NSSortDescriptor] = [NSSortDescriptor(key: "date", ascending: false)]
    ) -> [CDStudentMeeting] {
        let request = CDFetchRequest(CDStudentMeeting.self)
        request.predicate = predicate
        request.sortDescriptors = sortBy
        request.fetchBatchSize = 20
        return context.safeFetch(request)
    }

    /// Fetch meetings for a specific student
    func fetchMeetings(forStudentID studentID: UUID) -> [CDStudentMeeting] {
        fetchMeetings(predicate: NSPredicate(format: "studentID == %@", studentID.uuidString))
    }

    /// Fetch meetings for a date range
    func fetchMeetings(from startDate: Date, to endDate: Date) -> [CDStudentMeeting] {
        fetchMeetings(
            predicate: NSPredicate(format: "date >= %@ AND date < %@", startDate as NSDate, endDate as NSDate),
            sortBy: [NSSortDescriptor(key: "date", ascending: true)]
        )
    }

    // MARK: - Update

    /// Mark a meeting as completed
    @discardableResult
    func markCompleted(id: UUID) -> Bool {
        guard let meeting = fetchMeeting(id: id) else { return false }
        meeting.completed = true
        return true
    }

    // MARK: - Delete

    /// Delete a CDStudentMeeting by ID
    func deleteMeeting(id: UUID) throws {
        guard let meeting = fetchMeeting(id: id) else { return }
        context.delete(meeting)
        try context.save()
    }
}
