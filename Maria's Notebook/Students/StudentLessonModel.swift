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
    // Modern compound indexes for 2026 - optimized for common query patterns
    // Multiple indexes defined in one #Index macro (SwiftData limitation)
    #Index<StudentLesson>([\.lessonID, \.scheduledForDay], [\.scheduledForDay, \.isPresented], [\.isPresented], [\.createdAt])
    
    /// Logger for StudentLesson data issues
    nonisolated private static let logger = Logger.app(category: "StudentLesson")

    var id: UUID = UUID()
    // CloudKit compatibility: Store UUIDs as strings - indexed for lesson-specific queries
    var lessonID: String = ""
    // MIGRATION NOTE: The old database may have studentIDs stored as UUIDs instead of Strings.
    // We now store as JSON-encoded Data to avoid SwiftData type conflicts.
    @Attribute(.externalStorage) private var _studentIDsData: Data? = nil

    /// Student IDs stored as UUID strings. Uses JSON encoding via CloudKitStringArrayStorage.
    /// Marked as @Transient so SwiftData doesn't try to read the old stored property.
    @Transient
    var studentIDs: [String] {
        get { CloudKitStringArrayStorage.decode(from: _studentIDsData) }
        set { _studentIDsData = CloudKitStringArrayStorage.encode(newValue) }
    }
    var createdAt: Date = Date()
    // Indexed for inbox queries (used with isPresented and givenAt)
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
    // Denormalized start-of-day for efficient querying and sorting - indexed for date range queries
    var scheduledForDay: Date = Date.distantPast
    var givenAt: Date?
    // Indexed for presentation status filtering
    var isPresented: Bool = false
    var notes: String = ""
    var needsPractice: Bool = false
    var needsAnotherPresentation: Bool = false
    var followUpWork: String = ""
    var studentGroupKeyPersisted: String = ""
    /// Manual override to unblock this lesson even if prerequisite work is incomplete
    var manuallyUnblocked: Bool = false

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
        followUpWork: String = "",
        manuallyUnblocked: Bool = false
    ) {
        self.id = id
        // CloudKit compatibility: Store UUID as string
        self.lessonID = lessonID.uuidString
        // Convert UUIDs to strings for CloudKit compatibility and encode to Data
        self._studentIDsData = CloudKitStringArrayStorage.encode(studentIDs)
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
        self.manuallyUnblocked = manuallyUnblocked
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
        followUpWork: String = "",
        manuallyUnblocked: Bool = false
    ) {
        self.id = id
        self.lesson = lesson
        // CloudKit compatibility: Store UUID as string
        self.lessonID = lesson?.id.uuidString ?? UUID().uuidString
        self.students = students
        // Convert UUIDs to strings for CloudKit compatibility and encode to Data
        self._studentIDsData = CloudKitStringArrayStorage.encode(students.map(\.id))
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
        self.manuallyUnblocked = manuallyUnblocked
        self.unifiedNotes = []
    }

    // syncSnapshotsFromRelationships(), updateDenormalizedKeys(), normalizeDenormalizedFields(),
    // resolvedLessonID, and studentGroupKey are provided by DenormalizedSchedulable protocol.

    var isScheduled: Bool { scheduledFor != nil }
    var isGiven: Bool { isPresented || givenAt != nil }

    func snapshot() -> StudentLessonSnapshot {
        // Convert string IDs to UUIDs for CloudKit compatibility
        let studentUUIDs = studentIDs.compactMap { UUID(uuidString: $0) }
        
        // Priority: Use lesson relationship if available, otherwise use lessonID string
        let lessonUUID: UUID
        if let lesson = self.lesson {
            lessonUUID = lesson.id
            // Sync the lessonID field if it's missing or different
            if self.lessonID.isEmpty || self.lessonID != lesson.id.uuidString {
                self.lessonID = lesson.id.uuidString
            }
        } else if let uuid = UUID(uuidString: lessonID), !lessonID.isEmpty {
            lessonUUID = uuid
        } else {
            // Log error for debugging - lesson data is missing
            Self.logger.error("StudentLesson \(self.id) has no valid lessonID or lesson relationship")
            // Use a zero UUID as fallback to make it obvious something is wrong
            lessonUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        }
        
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

    /// Bridge: Convert to LessonAssignmentSnapshot for views that have been migrated.
    /// This will be removed once all callers use LessonAssignment directly.
    func toLessonAssignmentSnapshot() -> LessonAssignmentSnapshot {
        let snap = snapshot()
        return LessonAssignmentSnapshot(
            id: snap.id,
            lessonID: snap.lessonID,
            studentIDs: snap.studentIDs,
            createdAt: snap.createdAt,
            scheduledFor: snap.scheduledFor,
            presentedAt: snap.givenAt,
            state: snap.isPresented ? .presented : (snap.scheduledFor != nil ? .scheduled : .draft),
            notes: snap.notes,
            needsPractice: snap.needsPractice,
            needsAnotherPresentation: snap.needsAnotherPresentation,
            followUpWork: snap.followUpWork,
            manuallyUnblocked: false
        )
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
