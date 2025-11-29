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
    var notes: String
    var needsPractice: Bool
    var needsAnotherPresentation: Bool
    var followUpWork: String

    init(
        id: UUID = UUID(),
        lessonID: UUID,
        studentIDs: [UUID] = [],
        createdAt: Date = Date(),
        scheduledFor: Date? = nil,
        givenAt: Date? = nil,
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
        self.notes = notes
        self.needsPractice = needsPractice
        self.needsAnotherPresentation = needsAnotherPresentation
        self.followUpWork = followUpWork
    }

    var isScheduled: Bool { scheduledFor != nil }
    var isGiven: Bool { givenAt != nil }
}

