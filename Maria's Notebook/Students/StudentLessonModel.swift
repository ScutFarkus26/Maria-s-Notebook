//
//  StudentLessonModel.swift
//  Maria's Tool Box
//
//  Created by Danny De Berry on 11/28/25.
//

import Foundation
import SwiftData
@Model final class StudentLesson: Identifiable {
    var id: UUID = UUID()
    // CloudKit compatibility: Store UUIDs as strings
    var lessonID: String = ""
    // MIGRATION NOTE: The old database may have studentIDs stored as UUIDs instead of Strings.
    // We now store as JSON-encoded Data to avoid SwiftData type conflicts.
    @Attribute(.externalStorage) private var _studentIDsData: Data? = nil
    
    /// Student IDs stored as UUID strings. Uses JSON encoding to safely handle corrupted data.
    /// Marked as @Transient so SwiftData doesn't try to read the old stored property.
    @Transient
    var studentIDs: [String] {
        get {
            // Safely decode from JSON storage
            guard let data = _studentIDsData,
                  let array = try? JSONDecoder().decode([String].self, from: data) else {
                // If decoding fails (e.g., old corrupted data or nil), return empty array
                return []
            }
            return array
        }
        set {
            // Encode to JSON for storage
            if let data = try? JSONEncoder().encode(newValue) {
                _studentIDsData = data
            } else {
                _studentIDsData = nil
            }
        }
    }
    var createdAt: Date = Date()
    var scheduledFor: Date? {
        didSet {
            if let date = scheduledFor {
                scheduledForDay = AppCalendar.startOfDay(date)
            } else {
                scheduledForDay = Date.distantPast
            }
        }
    }
    // Denormalized start-of-day for efficient querying and sorting
    var scheduledForDay: Date = Date.distantPast
    var givenAt: Date?
    var isPresented: Bool = false
    var notes: String = ""
    var needsPractice: Bool = false
    var needsAnotherPresentation: Bool = false
    var followUpWork: String = ""
    var studentGroupKeyPersisted: String = ""

    @Transient var students: [Student] = []
    @Relationship var lesson: Lesson?

    // CloudKit compatibility: Relationship arrays must be optional
    @Relationship(deleteRule: .cascade, inverse: \ScopedNote.studentLesson) var scopedNotes: [ScopedNote]? = []
    
    // Computed property for backward compatibility with UUID
    var lessonIDUUID: UUID? {
        get { UUID(uuidString: lessonID) }
        set { lessonID = newValue?.uuidString ?? "" }
    }

    init(
        id: UUID = UUID(),
        lessonID: UUID,
        studentIDs: [UUID] = [],
        createdAt: Date = Date(),
        scheduledFor: Date? = nil,
        givenAt: Date? = nil,
        isPresented: Bool = false,
        notes: String = "",
        needsPractice: Bool = false,
        needsAnotherPresentation: Bool = false,
        followUpWork: String = ""
    ) {
        self.id = id
        // CloudKit compatibility: Store UUID as string
        self.lessonID = lessonID.uuidString
        // Convert UUIDs to strings for CloudKit compatibility and encode to Data
        let stringIDs = studentIDs.map { $0.uuidString }
        self._studentIDsData = try? JSONEncoder().encode(stringIDs)
        self.createdAt = createdAt
        self.scheduledFor = scheduledFor
        self.givenAt = givenAt
        self.scheduledForDay = scheduledFor.map { AppCalendar.startOfDay($0) } ?? Date.distantPast
        self.isPresented = isPresented
        self.notes = notes
        self.needsPractice = needsPractice
        self.needsAnotherPresentation = needsAnotherPresentation
        self.followUpWork = followUpWork
        self.scopedNotes = []
    }

    init(
        id: UUID = UUID(),
        lesson: Lesson?,
        students: [Student] = [],
        createdAt: Date = Date(),
        scheduledFor: Date? = nil,
        givenAt: Date? = nil,
        isPresented: Bool = false,
        notes: String = "",
        needsPractice: Bool = false,
        needsAnotherPresentation: Bool = false,
        followUpWork: String = ""
    ) {
        self.id = id
        self.lesson = lesson
        // CloudKit compatibility: Store UUID as string
        self.lessonID = lesson?.id.uuidString ?? UUID().uuidString
        self.students = students
        // Convert UUIDs to strings for CloudKit compatibility and encode to Data
        let stringIDs = students.map { $0.id.uuidString }
        self._studentIDsData = try? JSONEncoder().encode(stringIDs)
        self.createdAt = createdAt
        self.scheduledFor = scheduledFor
        self.givenAt = givenAt
        self.scheduledForDay = scheduledFor.map { AppCalendar.startOfDay($0) } ?? Date.distantPast
        self.isPresented = isPresented
        self.notes = notes
        self.needsPractice = needsPractice
        self.needsAnotherPresentation = needsAnotherPresentation
        self.followUpWork = followUpWork
        self.scopedNotes = []
    }

    func syncSnapshotsFromRelationships() {
        // CloudKit compatibility: Store UUID as string
        self.lessonID = self.lesson?.id.uuidString ?? self.lessonID
        // Convert UUIDs to strings for CloudKit compatibility
        let stringIDs = self.students.map { $0.id.uuidString }
        self.studentIDs = stringIDs // This will encode to _studentIDsData
        self.updateDenormalizedKeys()
    }

    var isScheduled: Bool { scheduledFor != nil }
    var isGiven: Bool { isPresented || givenAt != nil }
    
    func snapshot() -> StudentLessonSnapshot {
        // Convert string IDs to UUIDs for CloudKit compatibility
        let studentUUIDs = studentIDs.compactMap { UUID(uuidString: $0) }
        let lessonUUID = UUID(uuidString: lessonID) ?? UUID()
        return StudentLessonSnapshot(
            id: id,
            lessonID: lessonUUID,
            studentIDs: studentUUIDs,
            createdAt: createdAt,
            scheduledFor: scheduledFor,
            givenAt: givenAt,
            isPresented: isPresented,
            notes: notes,
            needsPractice: needsPractice,
            needsAnotherPresentation: needsAnotherPresentation,
            followUpWork: followUpWork
        )
    }

    func updateDenormalizedKeys() {
        let ids = self.resolvedStudentIDs.sorted { $0.uuidString < $1.uuidString }
        self.studentGroupKeyPersisted = ids.map { $0.uuidString }.joined(separator: ",")
    }
    
    func normalizeDenormalizedFields() {
        if let s = scheduledFor {
            scheduledForDay = AppCalendar.startOfDay(s)
        } else {
            scheduledForDay = Date.distantPast
        }
    }
    
    /// Sets `scheduledFor` and updates `scheduledForDay` using the provided calendar.
    func setScheduledFor(_ date: Date?, using calendar: Calendar) {
        if let date {
            self.scheduledFor = date
            self.scheduledForDay = AppCalendar.startOfDay(date)
        } else {
            self.scheduledFor = nil
            self.scheduledForDay = Date.distantPast
        }
    }
}

struct StudentLessonSnapshot: Identifiable {
    let id: UUID
    let lessonID: UUID
    let studentIDs: [UUID]
    let createdAt: Date
    let scheduledFor: Date?
    let givenAt: Date?
    let isPresented: Bool
    let notes: String
    let needsPractice: Bool
    let needsAnotherPresentation: Bool
    let followUpWork: String

    var isScheduled: Bool { scheduledFor != nil }
    var isGiven: Bool { isPresented || givenAt != nil }
}

