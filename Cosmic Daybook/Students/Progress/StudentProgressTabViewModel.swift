// StudentProgressTabViewModel.swift
// ViewModel for StudentProgressTab - handles data loading and business logic

import SwiftUI
import CoreData
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@Observable
final class StudentProgressTabViewModel {
    // MARK: - Public State
    private(set) var activeEnrollments: [CDStudentTrackEnrollmentEntity] = []
    private(set) var activeProjects: [CDProject] = []
    private(set) var activeReports: [CDWorkModel] = []
    private(set) var tracksByID: [String: CDTrackEntity] = [:]
    /// Per-enrollment stats/progress, precomputed once in loadData so the view
    /// doesn't recompute them for every enrollment on every render.
    private(set) var statsByEnrollment: [UUID: (stats: TrackStats, progress: TrackProgress)] = [:]

    // MARK: - Private State
    private var studentID: UUID?
    private var context: NSManagedObjectContext?
    /// Lessons looked up by id on demand (`nil` remembers a miss). The tab
    /// only ever needs the next lesson of each active track and the lesson
    /// behind an untitled report, so the lesson table is never loaded whole.
    private var lessonsByID: [UUID: CDLesson?] = [:]
    /// Steps of the student's active tracks whose `track.steps` set is empty
    /// (cross-zone twins); the fallback `trackProgress` reads.
    private var allTrackSteps: [CDTrackStep] = []
    /// This student's presentation marks.
    private var allLessonPresentations: [CDLessonPresentation] = []
    /// Presented assignments on the student's active tracks (any roster;
    /// `trackStats` still checks the roster for this student).
    private var allLessonAssignments: [CDLessonAssignment] = []
    /// This student's work rows.
    private var allWorkModels: [CDWorkModel] = []
    /// Notes attached to one of the student's active track enrollments.
    private var allNotes: [CDNote] = []

    // MARK: - Initialization

    func configure(for student: CDStudent, context: NSManagedObjectContext) {
        self.studentID = student.id
        loadData(for: student, context: context)
    }

    // MARK: - Data Loading

    /// Every fetch is scoped to the student (or to the student's active
    /// tracks) with the same sort the whole-table fetches used, so the
    /// filtered results below are the same rows in the same order; only the
    /// classmates' rows stop being materialised.
    func loadData(for student: CDStudent, context: NSManagedObjectContext) {
        self.context = context
        lessonsByID = [:]
        let studentIDString = student.id?.uuidString ?? ""

        let enrollmentDescriptor: NSFetchRequest<CDStudentTrackEnrollmentEntity> = NSFetchRequest(
            entityName: "StudentTrackEnrollment"
        )
        enrollmentDescriptor.predicate = NSPredicate(format: "studentID == %@ AND isActive == YES", studentIDString)
        enrollmentDescriptor.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        activeEnrollments = context.safeFetch(enrollmentDescriptor)

        let allTracks = fetchTrackScopedRows(studentIDString: studentIDString, context: context)

        let projectDescriptor = CDFetchRequest(CDProject.self)
        projectDescriptor.predicate = NSPredicate(format: "isActive == YES")
        projectDescriptor.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        let allProjects = context.safeFetch(projectDescriptor)

        // Compute filtered results
        activeProjects = allProjects.filter { $0.memberStudentIDsArray.contains(studentIDString) && $0.isActive }
        activeReports = allWorkModels.filter {
            $0.studentID == studentIDString && $0.kind == .report && $0.status.isOpen
        }
        // Use uniquingKeysWith to handle CloudKit sync duplicates
        tracksByID = Dictionary(
            allTracks.compactMap { t in t.id.map { ($0.uuidString, t) } },
            uniquingKeysWith: { first, _ in first }
        )

        // Precompute per-enrollment stats/progress once, instead of recomputing
        // them for every enrollment on every view render.
        var computed: [UUID: (stats: TrackStats, progress: TrackProgress)] = [:]
        for enrollment in activeEnrollments {
            guard let enrollmentID = enrollment.id,
                  let track = tracksByID[enrollment.trackID] else { continue }
            computed[enrollmentID] = (
                stats: trackStats(for: enrollment, track: track),
                progress: trackProgress(for: track)
            )
        }
        statsByEnrollment = computed
    }

    /// Loads the rows that hang off the student's active tracks and returns
    /// those tracks, sorted by title.
    private func fetchTrackScopedRows(
        studentIDString: String, context: NSManagedObjectContext
    ) -> [CDTrackEntity] {
        let activeTrackIDStrings = Array(Set(activeEnrollments.map(\.trackID)))
        let activeTrackUUIDs = activeTrackIDStrings.compactMap(UUID.init(uuidString:))

        let trackDescriptor: NSFetchRequest<CDTrackEntity> = NSFetchRequest(entityName: "Track")
        trackDescriptor.predicate = NSPredicate(format: "id IN %@", activeTrackUUIDs)
        trackDescriptor.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true)]
        let allTracks = context.safeFetch(trackDescriptor)

        // Roster membership lives in an encoded blob, so the roster check
        // stays in `trackStats`; the track and state columns are indexed here.
        let assignmentDescriptor = CDFetchRequest(CDLessonAssignment.self)
        assignmentDescriptor.predicate = NSPredicate(
            format: "trackID IN %@ AND stateRaw == %@",
            activeTrackIDStrings, LessonAssignmentState.presented.rawValue
        )
        assignmentDescriptor.sortDescriptors = [NSSortDescriptor(key: "presentedAt", ascending: false)]
        allLessonAssignments = context.safeFetch(assignmentDescriptor)

        let workDescriptor = CDFetchRequest(CDWorkModel.self)
        workDescriptor.predicate = NSPredicate(format: "studentID == %@", studentIDString)
        workDescriptor.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        allWorkModels = context.safeFetch(workDescriptor)

        // `[c]` because the enrollment link is resolved through
        // `UUID(uuidString:)`, which accepts either case.
        let enrollmentIDStrings = activeEnrollments.compactMap { $0.id?.uuidString }
        let noteDescriptor = CDFetchRequest(CDNote.self)
        noteDescriptor.predicate = NSPredicate(format: "studentTrackEnrollmentID IN[c] %@", enrollmentIDStrings)
        noteDescriptor.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
        allNotes = context.safeFetch(noteDescriptor)

        let stepDescriptor: NSFetchRequest<CDTrackStep> = NSFetchRequest(entityName: "TrackStep")
        stepDescriptor.predicate = NSPredicate(format: "track.id IN %@", activeTrackUUIDs)
        stepDescriptor.sortDescriptors = [NSSortDescriptor(key: "orderIndex", ascending: true)]
        allTrackSteps = context.safeFetch(stepDescriptor)

        let lpDescriptor = CDFetchRequest(CDLessonPresentation.self)
        lpDescriptor.predicate = NSPredicate(format: "studentID == %@", studentIDString)
        allLessonPresentations = context.safeFetch(lpDescriptor)

        return allTracks
    }

    /// The lesson with this id, fetched once per load. Matches what the
    /// name-sorted whole-table scan returned: the first by name when a
    /// duplicate exists.
    private func lesson(for lessonID: UUID) -> CDLesson? {
        if let cached = lessonsByID[lessonID] { return cached }
        guard let context else { return nil }
        let request = CDFetchRequest(CDLesson.self)
        request.predicate = NSPredicate(format: "id == %@", lessonID as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        request.fetchLimit = 1
        let lesson = context.safeFetchFirst(request)
        lessonsByID[lessonID] = .some(lesson)
        return lesson
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

        let currentLesson = currentStep?.lessonTemplateID.flatMap { lesson(for: $0) }

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
           let lesson = lesson(for: lessonID) {
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
        Color.windowBackgroundColor()
    }

    // MARK: - Auto-Complete CDTrackEntity

    func autoCompleteTrackIfNeeded(
        enrollment: CDStudentTrackEnrollmentEntity,
        progress: TrackProgress,
        context: NSManagedObjectContext
    ) {
        if progress.isComplete && enrollment.isActive {
            enrollment.isActive = false
            context.safeSave()
        }
    }
}
