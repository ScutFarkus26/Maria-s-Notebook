//
//  StudentLessonModel.swift
//  Maria's Tool Box
//
//  Created by Danny De Berry on 11/28/25.
//

import Foundation
import SwiftData
import OSLog

@Model final class StudentLesson: Identifiable {
    /// Logger for StudentLesson data issues
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.mariasnotebook", category: "StudentLesson")

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
            // Handle nil data (normal case for new records)
            guard let data = _studentIDsData else {
                return []
            }

            // Attempt to decode, logging errors if decoding fails
            do {
                return try JSONDecoder().decode([String].self, from: data)
            } catch {
                // Log the error so we can diagnose data corruption issues
                Self.logger.error("Failed to decode studentIDs for StudentLesson \(self.id): \(error.localizedDescription). Data size: \(data.count) bytes.")
                return []
            }
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
                // Use AppCalendar for consistent date normalization across the app
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
    @Relationship(deleteRule: .cascade, inverse: \Note.studentLesson) var unifiedNotes: [Note]? = []
    
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
        // Use AppCalendar for consistent date normalization across the app
        self.scheduledForDay = scheduledFor.map { AppCalendar.startOfDay($0) } ?? Date.distantPast
        self.isPresented = isPresented
        self.notes = notes
        self.needsPractice = needsPractice
        self.needsAnotherPresentation = needsAnotherPresentation
        self.followUpWork = followUpWork
        self.unifiedNotes = []
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
        // Use AppCalendar for consistent date normalization across the app
        self.scheduledForDay = scheduledFor.map { AppCalendar.startOfDay($0) } ?? Date.distantPast
        self.isPresented = isPresented
        self.notes = notes
        self.needsPractice = needsPractice
        self.needsAnotherPresentation = needsAnotherPresentation
        self.followUpWork = followUpWork
        self.unifiedNotes = []
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
            // Use AppCalendar for consistent date normalization across the app
            scheduledForDay = AppCalendar.startOfDay(s)
        } else {
            scheduledForDay = Date.distantPast
        }
    }
    
    /// Sets `scheduledFor` and updates `scheduledForDay` using the provided calendar.
    func setScheduledFor(_ date: Date?, using calendar: Calendar) {
        if let date {
            self.scheduledFor = date
            // Use the passed-in calendar instead of AppCalendar
            self.scheduledForDay = calendar.startOfDay(for: date)
        } else {
            self.scheduledFor = nil
            self.scheduledForDay = Date.distantPast
        }
    }
    
    #if DEBUG
    /// Debug-only invariant check: verifies that scheduling state is consistent with inbox filter logic.
    /// The inbox filter is: scheduledFor == nil && !isGiven
    func checkInboxInvariant() {
        let wouldBeInInbox = scheduledFor == nil && !isGiven
        
        if scheduledFor != nil {
            // If scheduled, it must NOT be in inbox
            assert(!wouldBeInInbox, "StudentLesson \(id): scheduledFor != nil but would be in inbox (isGiven=\(isGiven))")
        } else if !isGiven {
            // If unscheduled and not given, it must be eligible for inbox (basic filter passes)
            assert(wouldBeInInbox, "StudentLesson \(id): scheduledFor == nil && !isGiven but would not be in inbox")
        }
    }
    #endif
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
