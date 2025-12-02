//
//  StudentLessonModel.swift
//  Maria's Tool Box
//
//  Created by Danny De Berry on 11/28/25.
//

import Foundation
import SwiftData
@Model final class StudentLesson: Identifiable {
    var id: UUID
    var lessonID: UUID
    var studentIDs: [UUID]
    var createdAt: Date
    var scheduledFor: Date?
    var givenAt: Date?
    var isPresented: Bool = false
    var notes: String
    var needsPractice: Bool
    var needsAnotherPresentation: Bool
    var followUpWork: String

    @Transient var students: [Student] = []
    @Transient var lesson: Lesson?

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
        self.studentIDs = studentIDs
        self.createdAt = createdAt
        self.scheduledFor = scheduledFor
        self.givenAt = givenAt
        self.isPresented = isPresented
        self.notes = notes
        self.needsPractice = needsPractice
        self.needsAnotherPresentation = needsAnotherPresentation
        self.followUpWork = followUpWork
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
        self.studentIDs = students.map { $0.id }
        self.createdAt = createdAt
        self.scheduledFor = scheduledFor
        self.givenAt = givenAt
        self.isPresented = isPresented
        self.notes = notes
        self.needsPractice = needsPractice
        self.needsAnotherPresentation = needsAnotherPresentation
        self.followUpWork = followUpWork
    }

    func syncSnapshotsFromRelationships() {
        self.lessonID = self.lesson?.id ?? self.lessonID
        self.studentIDs = self.students.map { $0.id }
    }

    var isScheduled: Bool { scheduledFor != nil }
    var isGiven: Bool { isPresented || givenAt != nil }
    
    func snapshot() -> StudentLessonSnapshot {
        StudentLessonSnapshot(
            id: id,
            lessonID: lessonID,
            studentIDs: studentIDs,
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
