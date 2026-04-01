// StudentProgressTabViewModel.swift
// ViewModel for StudentProgressTab - handles data loading and business logic

import OSLog
import SwiftUI
import CoreData
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@Observable
@MainActor
final class StudentProgressTabViewModel {
    private static let logger = Logger.students

    // MARK: - Public State
    private(set) var activeEnrollments: [CDStudentTrackEnrollmentEntity] = []
    private(set) var activeProjects: [CDProject] = []
    private(set) var activeReports: [CDWorkModel] = []
    private(set) var tracksByID: [String: CDTrackEntity] = [:]

    // MARK: - Private State
    private var studentID: UUID?
    private var allLessons: [CDLesson] = []
    private var allTrackSteps: [CDTrackStep] = []
    private var allLessonPresentations: [CDLessonPresentation] = []
    private var allLessonAssignments: [CDLessonAssignment] = []
    private var allWorkModels: [CDWorkModel] = []
    private var allNotes: [CDNote] = []

    // MARK: - Initialization

    func configure(for student: CDStudent, context: NSManagedObjectContext) {
        self.studentID = student.id
        loadData(for: student, context: context)
    }

    // MARK: - Data Loading

    func loadData(for student: CDStudent, context: NSManagedObjectContext) {
        let studentIDString = student.id?.uuidString ?? ""

        // Fetch all needed data
        let enrollmentDescriptor: NSFetchRequest<CDStudentTrackEnrollmentEntity> = NSFetchRequest(entityName: "StudentTrackEnrollment")
        enrollmentDescriptor.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        let allEnrollments = context.safeFetch(enrollmentDescriptor)

        let trackDescriptor: NSFetchRequest<CDTrackEntity> = NSFetchRequest(entityName: "Track")
        trackDescriptor.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true)]
        let allTracks = context.safeFetch(trackDescriptor)

        let projectDescriptor: NSFetchRequest<CDProject> = NSFetchRequest(entityName: "Project")
        projectDescriptor.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        let allProjects = context.safeFetch(projectDescriptor)

        // Fetch LessonAssignments (unified model)
        let assignmentDescriptor: NSFetchRequest<CDLessonAssignment> = NSFetchRequest(entityName: "LessonAssignment")
        assignmentDescriptor.sortDescriptors = [NSSortDescriptor(key: "presentedAt", ascending: false)]
        allLessonAssignments = context.safeFetch(assignmentDescriptor)

        let workDescriptor: NSFetchRequest<CDWorkModel> = NSFetchRequest(entityName: "WorkModel")
        workDescriptor.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        allWorkModels = context.safeFetch(workDescriptor)

        let noteDescriptor: NSFetchRequest<CDNote> = NSFetchRequest(entityName: "Note")
        noteDescriptor.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
        allNotes = context.safeFetch(noteDescriptor)

        let stepDescriptor: NSFetchRequest<CDTrackStep> = NSFetchRequest(entityName: "TrackStep")
        stepDescriptor.sortDescriptors = [NSSortDescriptor(key: "orderIndex", ascending: true)]
        allTrackSteps = context.safeFetch(stepDescriptor)

        let lessonDescriptor: NSFetchRequest<CDLesson> = NSFetchRequest(entityName: "Lesson")
        lessonDescriptor.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        allLessons = context.safeFetch(lessonDescriptor)

        let lpDescriptor = NSFetchRequest<CDLessonPresentation>(entityName: "LessonPresentation")
        allLessonPresentations = context.safeFetch(lpDescriptor)

        // Compute filtered results
        activeEnrollments = allEnrollments.filter { $0.studentID == studentIDString && $0.isActive }
        activeProjects = allProjects.filter { $0.memberStudentIDsArray.contains(studentIDString) && $0.isActive }
        activeReports = allWorkModels.filter {
            $0.studentID == studentIDString && $0.kind == .report && $0.status != .complete
        }
        // Use uniquingKeysWith to handle CloudKit sync duplicates
        tracksByID = Dictionary(allTracks.compactMap { t in t.id.map { ($0.uuidString, t) } }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: - CDTrackEntity Stats Computation

    struct TrackStats {
        let lessonAssignments: [CDLessonAssignment]
        let workModels: [CDWorkModel]
        let notes: [CDNote]
        let presentationCount: Int
        let workCount: Int
        let noteCount: Int
        let totalActivity: Int
        let lastActivityDate: Date?
    }

    func trackStats(for enrollment: CDStudentTrackEnrollmentEntity, track: CDTrackEntity) -> TrackStats {
        guard let studentID else {
            return TrackStats(
                lessonAssignments: [], workModels: [], notes: [],
                presentationCount: 0, workCount: 0, noteCount: 0,
                totalActivity: 0, lastActivityDate: nil
            )
        }

        let studentIDString = studentID.uuidString
        let trackIDString = track.id?.uuidString ?? ""

        // Get LessonAssignments (unified model) for this track and student
        let lessonAssignments = allLessonAssignments.filter {
            $0.trackID == trackIDString && $0.studentIDs.contains(studentIDString) && $0.state == .presented
        }

        let workModels = allWorkModels.filter {
            $0.trackID == trackIDString && $0.studentID == studentIDString
        }
        let notes = allNotes.filter {
            $0.studentTrackEnrollment?.id == enrollment.id
        }

        let presentationCount = lessonAssignments.count
        let workCount = workModels.count
        let noteCount = notes.count
        let totalActivity = presentationCount + workCount + noteCount

        let lastActivityDate: Date? = {
            var dates: [Date] = []
            dates.append(contentsOf: lessonAssignments.compactMap(\.presentedAt))
            dates.append(contentsOf: workModels.compactMap { $0.completedAt ?? $0.createdAt })
            dates.append(contentsOf: notes.compactMap(\.updatedAt))
            return dates.max()
        }()

        return TrackStats(
            lessonAssignments: lessonAssignments,
            workModels: workModels,
            notes: notes,
            presentationCount: presentationCount,
            workCount: workCount,
            noteCount: noteCount,
            totalActivity: totalActivity,
            lastActivityDate: lastActivityDate
        )
    }

    // MARK: - Progress Computation

    struct TrackProgress {
        let trackSteps: [CDTrackStep]
        let completedStepIDs: Set<String>
        let proficientCount: Int
        let totalSteps: Int
        let progressPercent: Double
        let isComplete: Bool
        let currentStep: CDTrackStep?
        let currentLesson: CDLesson?
    }

    func trackProgress(for track: CDTrackEntity) -> TrackProgress {
        guard let studentID else {
            return TrackProgress(
                trackSteps: [], completedStepIDs: [],
                proficientCount: 0, totalSteps: 0, progressPercent: 0,
                isComplete: false, currentStep: nil, currentLesson: nil
            )
        }

        let studentIDString = studentID.uuidString

        // Get track steps
        let trackSteps: [CDTrackStep] = {
            let stepsArray = (track.steps?.allObjects as? [CDTrackStep]) ?? []
            if !stepsArray.isEmpty {
                return stepsArray.sorted { $0.orderIndex < $1.orderIndex }
            }
            return allTrackSteps
                .filter { $0.track?.id != nil && $0.track?.id == track.id }
                .sorted { $0.orderIndex < $1.orderIndex }
        }()

        // Get lesson IDs for this track's steps
        let trackLessonIDs = Set(trackSteps.compactMap { $0.lessonTemplateID?.uuidString })

        // Get this student's CDLessonPresentation records for track lessons
        let filteredPresentations = allLessonPresentations.filter {
            $0.studentID == studentIDString && trackLessonIDs.contains($0.lessonID)
        }

        // Count mastered lessons
        let proficientLessonIDs = Set(filteredPresentations
            .filter { $0.state == .proficient }
            .map(\.lessonID))

        // Find which steps are completed (lesson is mastered)
        let completedStepIDs = Set(trackSteps
            .filter { step in
                guard let lessonID = step.lessonTemplateID?.uuidString else { return false }
                return proficientLessonIDs.contains(lessonID)
            }
            .compactMap { $0.id?.uuidString })

        let proficientCount = completedStepIDs.count
        let totalSteps = trackSteps.count
        let progressPercent = totalSteps > 0 ? Double(proficientCount) / Double(totalSteps) : 0.0
        let isComplete = proficientCount == totalSteps && totalSteps > 0

        // Find current/next step (first step whose lesson is not mastered)
        let currentStep = trackSteps.first { step in
            guard let lessonID = step.lessonTemplateID?.uuidString else { return true }
            return !proficientLessonIDs.contains(lessonID)
        }

        let currentLesson = currentStep?.lessonTemplateID.flatMap { lessonID in
            allLessons.first { $0.id == lessonID }
        }

        return TrackProgress(
            trackSteps: trackSteps,
            completedStepIDs: completedStepIDs,
            proficientCount: proficientCount,
            totalSteps: totalSteps,
            progressPercent: progressPercent,
            isComplete: isComplete,
            currentStep: currentStep,
            currentLesson: currentLesson
        )
    }

    // MARK: - Report Helpers

    func reportTitle(for report: CDWorkModel) -> String {
        let title = report.title.trimmed()
        if !title.isEmpty { return title }
        if let lessonID = UUID(uuidString: report.lessonID),
           let lesson = allLessons.first(where: { $0.id == lessonID }) {
            return lesson.name
        }
        return "Untitled Report"
    }

    // MARK: - Color Helpers

    func trackColor(for title: String) -> Color {
        let hash = title.hash
        let colors: [Color] = [
            .blue, .purple, .pink, .orange, .green, .mint, .teal, .cyan, .indigo
        ]
        let index = abs(hash) % colors.count
        return colors[index]
    }

    var cardBackgroundColor: Color {
        #if os(macOS)
        return Color(NSColor.windowBackgroundColor)
        #else
        return Color(uiColor: .systemBackground)
        #endif
    }

    // MARK: - Auto-Complete CDTrackEntity

    func autoCompleteTrackIfNeeded(enrollment: CDStudentTrackEnrollmentEntity, progress: TrackProgress, context: NSManagedObjectContext) {
        if progress.isComplete && enrollment.isActive {
            enrollment.isActive = false
            do {
                try context.save()
            } catch {
                Self.logger.warning("Failed to save track completion: \(error)")
            }
        }
    }
}
