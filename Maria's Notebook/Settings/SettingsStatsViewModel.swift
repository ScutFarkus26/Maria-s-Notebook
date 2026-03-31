import Foundation
import CoreData
import SwiftUI

/// ViewModel for efficiently loading and caching Settings statistics
/// Optimizes SettingsView by avoiding loading entire tables just for counts
@Observable
@MainActor
class SettingsStatsViewModel {
    // MARK: - Teaching
    var studentsCount: Int = 0
    var lessonsCount: Int = 0
    // Legacy count removed — use presentations instead
    var plannedCount: Int = 0
    var givenCount: Int = 0
    var workModelsCount: Int = 0
    var presentationsCount: Int = 0
    var notesCount: Int = 0
    var meetingsCount: Int = 0
    var practiceSessionsCount: Int = 0

    // MARK: - Planning
    var todoItemsCount: Int = 0
    var todoCompletedCount: Int = 0
    var remindersCount: Int = 0
    var tracksCount: Int = 0
    var trackEnrollmentsCount: Int = 0
    var calendarEventsCount: Int = 0
    var projectsCount: Int = 0

    // MARK: - Classroom
    var attendanceRecordsCount: Int = 0
    var suppliesCount: Int = 0
    var issuesCount: Int = 0
    var issuesResolvedCount: Int = 0
    var communityTopicsCount: Int = 0
    var proceduresCount: Int = 0
    var nonSchoolDaysCount: Int = 0

    // MARK: - Storage & Templates
    var documentsCount: Int = 0
    var lessonAttachmentsCount: Int = 0
    var communityAttachmentsCount: Int = 0
    var noteTemplatesCount: Int = 0
    var meetingTemplatesCount: Int = 0
    var todoTemplatesCount: Int = 0
    var developmentSnapshotsCount: Int = 0

    var isLoading: Bool = false

    /// Total count for Teaching section
    var teachingTotal: Int {
        studentsCount + lessonsCount + presentationsCount
            + notesCount + meetingsCount + workModelsCount
            + practiceSessionsCount
    }

    /// Total count for Planning section
    var planningTotal: Int {
        todoItemsCount + remindersCount + tracksCount
            + calendarEventsCount + projectsCount
    }

    /// Total count for Classroom section
    var classroomTotal: Int {
        attendanceRecordsCount + suppliesCount + issuesCount
            + communityTopicsCount + proceduresCount
            + nonSchoolDaysCount
    }

    /// Total count for Storage & Templates section
    var storageTotal: Int {
        documentsCount + lessonAttachmentsCount
            + communityAttachmentsCount + noteTemplatesCount
            + meetingTemplatesCount + todoTemplatesCount
            + developmentSnapshotsCount
    }

    /// Total count of all records across all entities
    var totalRecordsCount: Int {
        teachingTotal + planningTotal + classroomTotal + storageTotal
            + plannedCount + givenCount + trackEnrollmentsCount
    }
    
    private var lastLoadDate: Date?
    private let cacheDuration: TimeInterval = 30 // Cache for 30 seconds
    
    // Load all statistics efficiently
    // swiftlint:disable:next function_body_length
    func loadCounts(context: NSManagedObjectContext) {
        // Use cached data if recent
        if let lastLoad = lastLoadDate,
           Date().timeIntervalSince(lastLoad) < cacheDuration {
            return
        }
        
        isLoading = true
        
        Task {
            // Load counts serially on the MainActor.
            // Parallel execution (async let) on a single NSManagedObjectContext is not thread-safe
            // and causes Sendable errors because NSManagedObjectContext is confined to the actor that created it.
            
            // Teaching
            let students = loadCount(for: CDStudent.self, context: context)
            let lessons = loadCount(for: CDLesson.self, context: context)
            let workModels = loadCount(for: CDWorkModel.self, context: context)
            let presentations = loadCount(for: CDLessonAssignment.self, context: context)
            let notes = loadCount(for: CDNote.self, context: context)
            let meetings = loadCount(for: CDStudentMeeting.self, context: context)
            let noteTemplates = loadCount(for: CDNoteTemplate.self, context: context)
            let meetingTemplates = loadCount(for: CDMeetingTemplate.self, context: context)
            let practiceSessions = loadCount(for: CDPracticeSession.self, context: context)

            // Planning
            let todoItems = loadCount(for: CDTodoItem.self, context: context)
            let todoCompleted = loadFilteredCount(
                for: CDTodoItem.self,
                predicate: NSPredicate(format: "isCompleted == YES"),
                context: context
            )
            let reminders = loadCount(for: CDReminder.self, context: context)
            let tracks = loadCount(for: CDTrackEntity.self, context: context)
            let trackEnrollments = loadCount(for: CDStudentTrackEnrollmentEntity.self, context: context)
            let calendarEvents = loadCount(for: CDCalendarEvent.self, context: context)
            let projects = loadCount(for: CDProject.self, context: context)

            // Classroom
            let attendanceRecords = loadCount(for: CDAttendanceRecord.self, context: context)
            let supplies = loadCount(for: CDSupply.self, context: context)
            let issues = loadCount(for: CDIssue.self, context: context)
            let issuesResolved = loadFilteredCount(
                for: CDIssue.self,
                predicate: NSPredicate(format: "resolvedAt != nil"),
                context: context
            )
            let communityTopics = loadCount(for: CDCommunityTopicEntity.self, context: context)
            let procedures = loadCount(for: CDProcedure.self, context: context)
            let nonSchoolDays = loadCount(for: CDNonSchoolDay.self, context: context)

            // Storage & Templates
            let documents = loadCount(for: CDDocument.self, context: context)
            let lessonAttachments = loadCount(for: LessonAttachment.self, context: context)
            let communityAttachments = loadCount(for: CommunityAttachment.self, context: context)
            let todoTemplates = loadCount(for: CDTodoTemplate.self, context: context)
            let developmentSnapshots = loadCount(for: DevelopmentSnapshot.self, context: context)

            // Load filtered counts (using CDLessonAssignment as primary source)
            let planned = loadFilteredCount(
                for: CDLessonAssignment.self,
                predicate: NSPredicate(format: "presentedAt == nil"),
                context: context
            )
            let given = loadFilteredCount(
                for: CDLessonAssignment.self,
                predicate: NSPredicate(format: "presentedAt != nil"),
                context: context
            )
            
            // Update state - Teaching
            self.studentsCount = students
            self.lessonsCount = lessons
            self.plannedCount = planned
            self.givenCount = given
            self.workModelsCount = workModels
            self.presentationsCount = presentations
            self.notesCount = notes
            self.meetingsCount = meetings
            self.noteTemplatesCount = noteTemplates
            self.meetingTemplatesCount = meetingTemplates
            self.practiceSessionsCount = practiceSessions

            // Update state - Planning
            self.todoItemsCount = todoItems
            self.todoCompletedCount = todoCompleted
            self.remindersCount = reminders
            self.tracksCount = tracks
            self.trackEnrollmentsCount = trackEnrollments
            self.calendarEventsCount = calendarEvents
            self.projectsCount = projects

            // Update state - Classroom
            self.attendanceRecordsCount = attendanceRecords
            self.suppliesCount = supplies
            self.issuesCount = issues
            self.issuesResolvedCount = issuesResolved
            self.communityTopicsCount = communityTopics
            self.proceduresCount = procedures
            self.nonSchoolDaysCount = nonSchoolDays

            // Update state - Storage & Templates
            self.documentsCount = documents
            self.lessonAttachmentsCount = lessonAttachments
            self.communityAttachmentsCount = communityAttachments
            self.todoTemplatesCount = todoTemplates
            self.developmentSnapshotsCount = developmentSnapshots
            
            self.lastLoadDate = Date()
            self.isLoading = false
        }
    }
    
    /// Load count for a model type
    /// CDNote: NSManagedObjectContext access is assumed to be fast for counts, keeping this synchronous on MainActor is safe.
    private func loadCount<T: NSManagedObject>(
        for type: T.Type,
        context: NSManagedObjectContext
    ) -> Int {
        // NSManagedObjectContext must be accessed on MainActor
        let descriptor = T.fetchRequest() as! NSFetchRequest<T>
        // CDNote: SwiftData doesn't have direct count, so we fetch and count
        // For large datasets, this could be optimized further with sampling
        return context.safeFetch(descriptor).count
    }
    
    /// Load count for a filtered model type
    private func loadFilteredCount<T: NSManagedObject>(
        for type: T.Type,
        predicate: NSPredicate,
        context: NSManagedObjectContext
    ) -> Int {
        let request = T.fetchRequest()
        request.predicate = predicate
        return (try? context.count(for: request)) ?? 0
    }
}
