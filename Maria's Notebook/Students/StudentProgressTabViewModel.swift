// StudentProgressTabViewModel.swift
// ViewModel for StudentProgressTab - handles data loading and business logic

import SwiftUI
import SwiftData
import Combine
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
final class StudentProgressTabViewModel: ObservableObject {
    // MARK: - Public State
    @Published private(set) var activeEnrollments: [StudentTrackEnrollment] = []
    @Published private(set) var activeProjects: [Project] = []
    @Published private(set) var activeReports: [WorkModel] = []
    @Published private(set) var tracksByID: [String: Track] = [:]

    // MARK: - Private State
    private var studentID: UUID?
    private var allLessons: [Lesson] = []
    private var allTrackSteps: [TrackStep] = []
    private var allLessonPresentations: [LessonPresentation] = []
    private var allLessonAssignments: [LessonAssignment] = []
    private var allWorkModels: [WorkModel] = []
    private var allNotes: [Note] = []

    // MARK: - Initialization

    func configure(for student: Student, context: ModelContext) {
        self.studentID = student.id
        loadData(for: student, context: context)
    }

    // MARK: - Data Loading

    func loadData(for student: Student, context: ModelContext) {
        let studentIDString = student.id.uuidString

        // Fetch all needed data
        let enrollmentDescriptor = FetchDescriptor<StudentTrackEnrollment>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let allEnrollments = context.safeFetch(enrollmentDescriptor)

        let trackDescriptor = FetchDescriptor<Track>(
            sortBy: [SortDescriptor(\.title)]
        )
        let allTracks = context.safeFetch(trackDescriptor)

        let projectDescriptor = FetchDescriptor<Project>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let allProjects = context.safeFetch(projectDescriptor)

        // Fetch LessonAssignments (unified model)
        let assignmentDescriptor = FetchDescriptor<LessonAssignment>(
            sortBy: [SortDescriptor(\.presentedAt, order: .reverse)]
        )
        allLessonAssignments = context.safeFetch(assignmentDescriptor)

        let workDescriptor = FetchDescriptor<WorkModel>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        allWorkModels = context.safeFetch(workDescriptor)

        let noteDescriptor = FetchDescriptor<Note>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        allNotes = context.safeFetch(noteDescriptor)

        let stepDescriptor = FetchDescriptor<TrackStep>(
            sortBy: [SortDescriptor(\.orderIndex)]
        )
        allTrackSteps = context.safeFetch(stepDescriptor)

        let lessonDescriptor = FetchDescriptor<Lesson>(
            sortBy: [SortDescriptor(\.name)]
        )
        allLessons = context.safeFetch(lessonDescriptor)

        let lpDescriptor = FetchDescriptor<LessonPresentation>()
        allLessonPresentations = context.safeFetch(lpDescriptor)

        // Compute filtered results
        activeEnrollments = allEnrollments.filter { $0.studentID == studentIDString && $0.isActive }
        activeProjects = allProjects.filter { $0.memberStudentIDs.contains(studentIDString) && $0.isActive }
        activeReports = allWorkModels.filter {
            $0.studentID == studentIDString && $0.kind == .report && $0.status != .complete
        }
        // Use uniquingKeysWith to handle CloudKit sync duplicates
        tracksByID = Dictionary(allTracks.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: - Track Stats Computation

    struct TrackStats {
        let lessonAssignments: [LessonAssignment]
        let workModels: [WorkModel]
        let notes: [Note]
        let presentationCount: Int
        let workCount: Int
        let noteCount: Int
        let totalActivity: Int
        let lastActivityDate: Date?
    }

    func trackStats(for enrollment: StudentTrackEnrollment, track: Track) -> TrackStats {
        guard let studentID = studentID else {
            return TrackStats(
                lessonAssignments: [], workModels: [], notes: [],
                presentationCount: 0, workCount: 0, noteCount: 0,
                totalActivity: 0, lastActivityDate: nil
            )
        }

        let studentIDString = studentID.uuidString
        let trackIDString = track.id.uuidString

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
            dates.append(contentsOf: lessonAssignments.compactMap { $0.presentedAt })
            dates.append(contentsOf: workModels.compactMap { $0.completedAt ?? $0.createdAt })
            dates.append(contentsOf: notes.map { $0.updatedAt })
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
        let trackSteps: [TrackStep]
        let completedStepIDs: Set<String>
        let masteredCount: Int
        let totalSteps: Int
        let progressPercent: Double
        let isComplete: Bool
        let currentStep: TrackStep?
        let currentLesson: Lesson?
    }

    func trackProgress(for track: Track) -> TrackProgress {
        guard let studentID = studentID else {
            return TrackProgress(
                trackSteps: [], completedStepIDs: [],
                masteredCount: 0, totalSteps: 0, progressPercent: 0,
                isComplete: false, currentStep: nil, currentLesson: nil
            )
        }

        let studentIDString = studentID.uuidString

        // Get track steps
        let trackSteps: [TrackStep] = {
            if let steps = track.steps, !steps.isEmpty {
                return steps.sorted { $0.orderIndex < $1.orderIndex }
            }
            return allTrackSteps
                .filter { $0.track?.id == track.id }
                .sorted { $0.orderIndex < $1.orderIndex }
        }()

        // Get lesson IDs for this track's steps
        let trackLessonIDs = Set(trackSteps.compactMap { $0.lessonTemplateID?.uuidString })

        // Get this student's LessonPresentation records for track lessons
        let studentLessonPresentations = allLessonPresentations.filter {
            $0.studentID == studentIDString && trackLessonIDs.contains($0.lessonID)
        }

        // Count mastered lessons
        let masteredLessonIDs = Set(studentLessonPresentations
            .filter { $0.state == .mastered }
            .map { $0.lessonID })

        // Find which steps are completed (lesson is mastered)
        let completedStepIDs = Set(trackSteps
            .filter { step in
                guard let lessonID = step.lessonTemplateID?.uuidString else { return false }
                return masteredLessonIDs.contains(lessonID)
            }
            .map { $0.id.uuidString })

        let masteredCount = completedStepIDs.count
        let totalSteps = trackSteps.count
        let progressPercent = totalSteps > 0 ? Double(masteredCount) / Double(totalSteps) : 0.0
        let isComplete = masteredCount == totalSteps && totalSteps > 0

        // Find current/next step (first step whose lesson is not mastered)
        let currentStep = trackSteps.first { step in
            guard let lessonID = step.lessonTemplateID?.uuidString else { return true }
            return !masteredLessonIDs.contains(lessonID)
        }

        let currentLesson = currentStep?.lessonTemplateID.flatMap { lessonID in
            allLessons.first { $0.id == lessonID }
        }

        return TrackProgress(
            trackSteps: trackSteps,
            completedStepIDs: completedStepIDs,
            masteredCount: masteredCount,
            totalSteps: totalSteps,
            progressPercent: progressPercent,
            isComplete: isComplete,
            currentStep: currentStep,
            currentLesson: currentLesson
        )
    }

    // MARK: - Report Helpers

    func reportTitle(for report: WorkModel) -> String {
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

    // MARK: - Auto-Complete Track

    func autoCompleteTrackIfNeeded(enrollment: StudentTrackEnrollment, progress: TrackProgress, context: ModelContext) {
        if progress.isComplete && enrollment.isActive {
            enrollment.isActive = false
            try? context.save()
        }
    }
}
