//
//  MeetingRepository.swift
//  Maria's Notebook
//
//  Repository for StudentMeeting entity CRUD operations.
//  Follows the pattern established by WorkRepository.
//

import Foundation
import SwiftData

@MainActor
struct MeetingRepository: SavingRepository {
    typealias Model = StudentMeeting

    let context: ModelContext
    let saveCoordinator: SaveCoordinator?

    init(context: ModelContext, saveCoordinator: SaveCoordinator? = nil) {
        self.context = context
        self.saveCoordinator = saveCoordinator
    }

    // MARK: - Fetch

    /// Fetch a StudentMeeting by ID
    func fetchMeeting(id: UUID) -> StudentMeeting? {
        var descriptor = FetchDescriptor<StudentMeeting>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return context.safeFetchFirst(descriptor)
    }

    /// Fetch multiple StudentMeetings with optional filtering and sorting
    func fetchMeetings(
        predicate: Predicate<StudentMeeting>? = nil,
        sortBy: [SortDescriptor<StudentMeeting>] = [SortDescriptor(\.date, order: .reverse)]
    ) -> [StudentMeeting] {
        var descriptor = FetchDescriptor<StudentMeeting>()
        if let predicate = predicate {
            descriptor.predicate = predicate
        }
        descriptor.sortBy = sortBy
        return context.safeFetch(descriptor)
    }

    /// Fetch meetings for a specific student
    func fetchMeetings(forStudentID studentID: UUID) -> [StudentMeeting] {
        let studentIDString = studentID.uuidString
        let predicate = #Predicate<StudentMeeting> { $0.studentID == studentIDString }
        return fetchMeetings(predicate: predicate)
    }

    /// Fetch incomplete meetings
    func fetchIncompleteMeetings() -> [StudentMeeting] {
        let predicate = #Predicate<StudentMeeting> { !$0.completed }
        return fetchMeetings(predicate: predicate)
    }

    /// Fetch meetings for a date range
    func fetchMeetings(from startDate: Date, to endDate: Date) -> [StudentMeeting] {
        let predicate = #Predicate<StudentMeeting> { meeting in
            meeting.date >= startDate && meeting.date < endDate
        }
        return fetchMeetings(predicate: predicate, sortBy: [SortDescriptor(\.date)])
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
    ) -> StudentMeeting {
        let meeting = StudentMeeting(
            studentID: studentID,
            date: date,
            completed: completed,
            reflection: reflection,
            focus: focus,
            requests: requests,
            guideNotes: guideNotes
        )
        context.insert(meeting)
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

        if let date = date {
            meeting.date = date
        }
        if let completed = completed {
            meeting.completed = completed
        }
        if let reflection = reflection {
            meeting.reflection = reflection
        }
        if let focus = focus {
            meeting.focus = focus
        }
        if let requests = requests {
            meeting.requests = requests
        }
        if let guideNotes = guideNotes {
            meeting.guideNotes = guideNotes
        }

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
        do {
            try context.save()
        } catch {
            print("⚠️ [deleteMeeting] Failed to save context: \(error)")
            throw error
        }
    }
}
