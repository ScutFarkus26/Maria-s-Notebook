//
//  MeetingRepository.swift
//  Maria's Notebook
//
//  Repository for StudentMeeting entity CRUD operations.
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

    /// Fetch a StudentMeeting by ID
    func fetchMeeting(id: UUID) -> CDStudentMeeting? {
        let request = CDFetchRequest(CDStudentMeeting.self)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return context.safeFetchFirst(request)
    }

    /// Fetch multiple StudentMeetings with optional filtering and sorting
    func fetchMeetings(
        predicate: NSPredicate? = nil,
        sortBy: [NSSortDescriptor] = [NSSortDescriptor(key: "date", ascending: false)]
    ) -> [CDStudentMeeting] {
        let request = CDFetchRequest(CDStudentMeeting.self)
        request.predicate = predicate
        request.sortDescriptors = sortBy
        return context.safeFetch(request)
    }

    /// Fetch meetings for a specific student
    func fetchMeetings(forStudentID studentID: UUID) -> [CDStudentMeeting] {
        fetchMeetings(predicate: NSPredicate(format: "studentID == %@", studentID.uuidString))
    }

    /// Fetch incomplete meetings
    func fetchIncompleteMeetings() -> [CDStudentMeeting] {
        fetchMeetings(predicate: NSPredicate(format: "completed == NO"))
    }

    /// Fetch meetings for a date range
    func fetchMeetings(from startDate: Date, to endDate: Date) -> [CDStudentMeeting] {
        fetchMeetings(
            predicate: NSPredicate(format: "date >= %@ AND date < %@", startDate as NSDate, endDate as NSDate),
            sortBy: [NSSortDescriptor(key: "date", ascending: true)]
        )
    }

    // MARK: - Create

    /// Create a new StudentMeeting
    @discardableResult
    func createMeeting(
        studentID: UUID,
        date: Date = Date(),
        completed: Bool = false,
        reflection: String = "",
        focus: String = "",
        requests: String = "",
        guideNotes: String = ""
    ) -> CDStudentMeeting {
        let meeting = CDStudentMeeting(context: context)
        meeting.studentID = studentID.uuidString
        meeting.date = date
        meeting.completed = completed
        meeting.reflection = reflection
        meeting.focus = focus
        meeting.requests = requests
        meeting.guideNotes = guideNotes
        return meeting
    }

    // MARK: - Update

    /// Update an existing StudentMeeting's properties
    @discardableResult
    func updateMeeting(
        id: UUID,
        date: Date? = nil,
        completed: Bool? = nil,
        reflection: String? = nil,
        focus: String? = nil,
        requests: String? = nil,
        guideNotes: String? = nil
    ) -> Bool {
        guard let meeting = fetchMeeting(id: id) else { return false }

        if let date { meeting.date = date }
        if let completed { meeting.completed = completed }
        if let reflection { meeting.reflection = reflection }
        if let focus { meeting.focus = focus }
        if let requests { meeting.requests = requests }
        if let guideNotes { meeting.guideNotes = guideNotes }

        return true
    }

    /// Mark a meeting as completed
    @discardableResult
    func markCompleted(id: UUID) -> Bool {
        guard let meeting = fetchMeeting(id: id) else { return false }
        meeting.completed = true
        return true
    }

    // MARK: - Delete

    /// Delete a StudentMeeting by ID
    func deleteMeeting(id: UUID) throws {
        guard let meeting = fetchMeeting(id: id) else { return }
        context.delete(meeting)
        try context.save()
    }
}
