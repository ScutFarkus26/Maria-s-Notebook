//
//  StudentLessonModel.swift
//  Maria's Tool Box
//
//  Created by Danny De Berry on 11/28/25.
//

import Foundation
import SwiftData
@Model final class StudentLesson: Identifiable {
    @Attribute(.unique) var id: UUID
    var lessonID: UUID
    // CloudKit compatibility: Store UUIDs as strings
    var studentIDs: [String] = []
    var createdAt: Date
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
    var notes: String
    var needsPractice: Bool
    var needsAnotherPresentation: Bool
    var followUpWork: String
    var studentGroupKeyPersisted: String = ""

    @Transient var students: [Student] = []
    @Relationship var lesson: Lesson?

    // CloudKit compatibility: Relationship arrays must be optional
    @Relationship(deleteRule: .cascade, inverse: \ScopedNote.studentLesson) var scopedNotes: [ScopedNote]? = []

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
        self.lessonID = lessonID
        // Convert UUIDs to strings for CloudKit compatibility
        self.studentIDs = studentIDs.map { $0.uuidString }
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
        self.lessonID = lesson?.id ?? UUID()
        self.students = students
        // Convert UUIDs to strings for CloudKit compatibility
        self.studentIDs = students.map { $0.id.uuidString }
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
        self.lessonID = self.lesson?.id ?? self.lessonID
        // Convert UUIDs to strings for CloudKit compatibility
        self.studentIDs = self.students.map { $0.id.uuidString }
        self.updateDenormalizedKeys()
    }

    var isScheduled: Bool { scheduledFor != nil }
    var isGiven: Bool { isPresented || givenAt != nil }
    
    func snapshot() -> StudentLessonSnapshot {
        // Convert string IDs to UUIDs for CloudKit compatibility
        let studentUUIDs = studentIDs.compactMap { UUID(uuidString: $0) }
        return StudentLessonSnapshot(
            id: id,
            lessonID: lessonID,
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

