import Foundation
import SwiftData

/// Per-student progress tracking for a lesson presentation.
/// Tracks individual student state through the lesson lifecycle.
@Model
final class LessonPresentation: Identifiable {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    
    // CloudKit compatibility: Store UUIDs as strings
    var studentID: String = ""              // student UUID string
    var lessonID: String = ""               // lesson UUID string (same as Presentation.lessonID)
    var presentationID: String?       // Presentation.id.uuidString
    var trackID: String?              // Track.id.uuidString (optional, used later)
    var trackStepID: String?          // TrackStep.id.uuidString (optional, used later)
    
    var stateRaw: String = LessonPresentationState.presented.rawValue
    var presentedAt: Date = Date()
    var lastObservedAt: Date?
    var masteredAt: Date? // swiftlint:disable:this inclusive_language — persisted SwiftData property name
    var notes: String?
    
    var state: LessonPresentationState {
        get { LessonPresentationState(rawValue: stateRaw) ?? .presented }
        set { stateRaw = newValue.rawValue }
    }
    
    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        studentID: String,
        lessonID: String,
        presentationID: String? = nil,
        trackID: String? = nil,
        trackStepID: String? = nil,
        state: LessonPresentationState = .presented,
        presentedAt: Date = Date(),
        lastObservedAt: Date? = nil,
        masteredAt: Date? = nil, // swiftlint:disable:this inclusive_language — persisted SwiftData property name
        notes: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.studentID = studentID
        self.lessonID = lessonID
        self.presentationID = presentationID
        self.trackID = trackID
        self.trackStepID = trackStepID
        self.stateRaw = state.rawValue
        self.presentedAt = presentedAt
        self.lastObservedAt = lastObservedAt
        self.masteredAt = masteredAt
        self.notes = notes
    }
}

enum LessonPresentationState: String, Codable, CaseIterable, Sendable {
    case presented
    case practicing
    case readyForAssessment
    case proficient = "mastered"
}
