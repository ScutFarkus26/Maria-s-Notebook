import Foundation
import SwiftData
import OSLog

/// Pure local computation service that assesses each student's readiness for new lessons.
/// Uses curriculum position data, work outcomes, practice sessions, and behavioral flags
/// to produce a `StudentReadinessProfile` per student. No API calls are made.
@MainActor
struct StudentReadinessAssessor {
    private static let logger = Logger.ai
    
    // MARK: - Public API
    
    /// Assesses readiness for a set of students.
    /// - Parameters:
    ///   - students: Students to assess
    ///   - modelContext: SwiftData model context for querying data
    /// - Returns: Array of readiness profiles, one per student
    static func assessReadiness(
        for students: [Student],
        modelContext: ModelContext
    ) -> [StudentReadinessProfile] {
        let allLessons = fetchAllLessons(modelContext: modelContext)
        let allPresentations = fetchPresentations(modelContext: modelContext)
        let allWork = fetchAllWork(modelContext: modelContext)
        let recentSessions = fetchRecentPracticeSessions(modelContext: modelContext, daysBefore: 30)
        let recentNotes = fetchRecentNotes(modelContext: modelContext, daysBefore: 30)
        
        return students.map { student in
            buildProfile(
                for: student,
                allLessons: allLessons,
                allPresentations: allPresentations,
                allWork: allWork,
                recentSessions: recentSessions,
                recentNotes: recentNotes
            )
        }
    }
    
    /// Assesses readiness for a single student.
    static func assessReadiness(
        for student: Student,
        modelContext: ModelContext
    ) -> StudentReadinessProfile {
        guard let profile = assessReadiness(for: [student], modelContext: modelContext).first else {
            logger.error("assessReadiness returned empty array for single student \(student.id)")
            return StudentReadinessProfile(
                studentID: student.id,
                studentName: student.firstName,
                level: "",
                subjectReadiness: [],
                practiceQualityAvg: nil,
                independenceAvg: nil,
                daysSinceLastPresentation: nil,
                activeWorkCount: 0,
                behavioralFlags: []
            )
        }
        return profile
    }
    
    // MARK: - Profile Building

    // swiftlint:disable:next function_parameter_count
    private static func buildProfile(
        for student: Student,
        allLessons: [Lesson],
        allPresentations: [LessonAssignment],
        allWork: [WorkModel],
        recentSessions: [PracticeSession],
        recentNotes: [Note]
    ) -> StudentReadinessProfile {
        let studentIDStr = student.id.uuidString
        let studentPresentations = allPresentations.filter { $0.studentIDs.contains(studentIDStr) }
        let studentWork = allWork.filter { $0.studentID == studentIDStr }
        let studentSessions = recentSessions.filter { $0.studentIDs.contains(studentIDStr) }
        let studentNotes = recentNotes.filter { note in
            note.searchIndexStudentID == student.id || note.scopeIsAll
        }
        let subjectReadiness = computeSubjectReadiness(
            student: student, allLessons: allLessons,
            presentations: studentPresentations, work: studentWork
        )
        let metrics = computePracticeMetrics(sessions: studentSessions)
        let daysSinceLastPresentation = computeDaysSinceLastPresentation(studentPresentations)
        let activeWorkCount = studentWork.filter { $0.status != .complete }.count
        let behavioralFlags = computeBehavioralFlags(sessions: studentSessions, studentNotes: studentNotes)
        return StudentReadinessProfile(
            studentID: student.id,
            studentName: student.fullName,
            level: student.level.rawValue,
            subjectReadiness: subjectReadiness,
            practiceQualityAvg: metrics.practiceQualityAvg,
            independenceAvg: metrics.independenceAvg,
            daysSinceLastPresentation: daysSinceLastPresentation,
            activeWorkCount: activeWorkCount,
            behavioralFlags: behavioralFlags
        )
    }

    private static func computePracticeMetrics(
        sessions: [PracticeSession]
    ) -> (practiceQualityAvg: Double?, independenceAvg: Double?) {
        let practiceQualities = sessions.compactMap { $0.practiceQuality }
        let practiceQualityAvg = practiceQualities.isEmpty
            ? nil
            : Double(practiceQualities.reduce(0, +)) / Double(practiceQualities.count)
        let independenceLevels = sessions.compactMap { $0.independenceLevel }
        let independenceAvg = independenceLevels.isEmpty
            ? nil
            : Double(independenceLevels.reduce(0, +)) / Double(independenceLevels.count)
        return (practiceQualityAvg, independenceAvg)
    }

    private static func computeBehavioralFlags(
        sessions: [PracticeSession], studentNotes: [Note]
    ) -> [String] {
        var flags: [String] = []
        let recent = sessions.prefix(10)
        if recent.contains(where: { $0.needsReteaching }) { flags.append("needs reteaching") }
        if recent.contains(where: { $0.readyForAssessment }) { flags.append("ready for assessment") }
        if recent.contains(where: { $0.readyForCheckIn }) { flags.append("ready for check-in") }
        if recent.contains(where: { $0.struggledWithConcept }) { flags.append("struggling with concept") }
        if recent.contains(where: { $0.madeBreakthrough }) { flags.append("recent breakthrough") }
        let behavioralNotes = studentNotes.filter { note in
            note.tags.contains { tag in
                let name = TagHelper.tagName(tag).lowercased()
                return name == "behavioral" || name == "emotional"
            }
        }
        if !behavioralNotes.isEmpty { flags.append("\(behavioralNotes.count) behavioral/emotional notes") }
        return flags
    }

    private static func computeDaysSinceLastPresentation(_ presentations: [LessonAssignment]) -> Int? {
        guard let lastDate = presentations.compactMap({ $0.presentedAt }).max() else { return nil }
        return Calendar.current.dateComponents([.day], from: lastDate, to: Date()).day
    }

    // MARK: - Subject Readiness Computation

    private static func computeSubjectReadiness(
        student: Student,
        allLessons: [Lesson],
        presentations: [LessonAssignment],
        work: [WorkModel]
    ) -> [SubjectReadiness] {
        let lessonsBySubjectGroup = Dictionary(grouping: allLessons) {
            SubjectGroupKey(subject: $0.subject.trimmed(), group: $0.group.trimmed())
        }
        var results: [SubjectReadiness] = []
        for (key, lessons) in lessonsBySubjectGroup {
            guard !key.subject.isEmpty, !key.group.isEmpty else { continue }
            let sorted = lessons.sorted { $0.orderInGroup < $1.orderInGroup }
            let groupProgress = scanLessonGroupProgress(sorted: sorted, presentations: presentations, work: work)
            let currentLesson = groupProgress.currentLesson
            var nextLesson = groupProgress.nextLesson
            if currentLesson == nil, let first = sorted.first { nextLesson = first }
            if let current = currentLesson, nextLesson == nil {
                nextLesson = PlanNextLessonService.findNextLesson(after: current, in: allLessons)
            }
            results.append(SubjectReadiness(
                subject: key.subject, group: key.group,
                currentLessonName: currentLesson?.name, currentLessonID: currentLesson?.id,
                nextLessonName: nextLesson?.name, nextLessonID: nextLesson?.id,
                proficiencySignal: groupProgress.proficiency,
                activeWorkCount: groupProgress.activeWorkInGroup,
                completedInGroup: groupProgress.completedInGroup, totalInGroup: sorted.count
            ))
        }
        return results.sorted { ($0.subject, $0.group) < ($1.subject, $1.group) }
    }

    private static func scanLessonGroupProgress(
        sorted: [Lesson], presentations: [LessonAssignment], work: [WorkModel]
    ) -> LessonGroupProgress {
        var progress = LessonGroupProgress()
        for lesson in sorted {
            let lessonIDStr = lesson.id.uuidString
            let presented = presentations.contains { la in
                la.lessonID == lessonIDStr && la.presentedAt != nil
            }
            if presented {
                progress.completedInGroup += 1
                progress.currentLesson = lesson
                let lessonWork = work.filter { $0.lessonID == lessonIDStr }
                let activeWork = lessonWork.filter { $0.status != .complete }
                progress.activeWorkInGroup += activeWork.count
                let completedWork = lessonWork.filter { $0.status == .complete }
                progress.proficiency = determineProficiency(activeWork: activeWork, completedWork: completedWork)
            } else if progress.currentLesson != nil && progress.nextLesson == nil {
                progress.nextLesson = lesson
            }
        }
        return progress
    }

    private static func determineProficiency(activeWork: [WorkModel], completedWork: [WorkModel]) -> ProficiencySignal {
        if let latest = completedWork.max(by: {
            ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast)
        }) {
            guard let outcome = latest.completionOutcome else { return .practicing }
            switch outcome {
            case .proficient: return .proficient
            case .needsMorePractice: return .needsMorePractice
            case .needsReview: return .needsReteaching
            case .incomplete: return .practicing
            case .notApplicable: return .presented
            }
        } else if !activeWork.isEmpty {
            return .practicing
        } else {
            return .presented
        }
    }

}

// MARK: - Compressed Summary

extension StudentReadinessAssessor {
    /// Creates a token-efficient text summary of readiness profiles for AI prompt inclusion.
    static func compressedSummary(of profiles: [StudentReadinessProfile]) -> String {
        var lines: [String] = []
        lines.append("STUDENT READINESS:")

        for profile in profiles {
            var studentLine = "\(profile.studentName) (\(profile.level))"

            var details: [String] = []
            if let days = profile.daysSinceLastPresentation {
                details.append("last presentation \(days)d ago")
            } else {
                details.append("no presentations")
            }
            details.append("\(profile.activeWorkCount) active work")

            if let pq = profile.practiceQualityAvg {
                details.append("quality \(String(format: "%.1f", pq))/5")
            }
            if let ind = profile.independenceAvg {
                details.append("independence \(String(format: "%.1f", ind))/5")
            }

            studentLine += " - \(details.joined(separator: ", "))"

            if !profile.behavioralFlags.isEmpty {
                studentLine += " [flags: \(profile.behavioralFlags.joined(separator: ", "))]"
            }

            lines.append(studentLine)

            // Only show subjects with a next lesson available (frontier)
            let frontierSubjects = profile.subjectReadiness
                .filter { $0.nextLessonID != nil }
            for sr in frontierSubjects.prefix(8) {
                let prog = "\(sr.completedInGroup)/\(sr.totalInGroup)"
                let current = sr.currentLessonName
                    .map { "current: \($0) (\(sr.proficiencySignal.shortCode))" }
                    ?? "not started"
                let next = sr.nextLessonName.map { "next: \($0)" } ?? ""
                lines.append("  \(sr.subject)/\(sr.group) \(prog) \(current) \(next)")
            }
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - Data Fetching

extension StudentReadinessAssessor {
    private static func fetchAllLessons(modelContext: ModelContext) -> [Lesson] {
        let descriptor = FetchDescriptor<Lesson>(
            sortBy: [
                SortDescriptor(\Lesson.subject),
                SortDescriptor(\Lesson.group),
                SortDescriptor(\Lesson.orderInGroup)
            ]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private static func fetchPresentations(modelContext: ModelContext) -> [LessonAssignment] {
        let descriptor = FetchDescriptor<LessonAssignment>()
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private static func fetchAllWork(modelContext: ModelContext) -> [WorkModel] {
        let descriptor = FetchDescriptor<WorkModel>()
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private static func fetchRecentPracticeSessions(modelContext: ModelContext, daysBefore: Int) -> [PracticeSession] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -daysBefore, to: Date()) ?? Date()
        let descriptor = FetchDescriptor<PracticeSession>(
            predicate: #Predicate<PracticeSession> { session in
                session.date >= cutoff
            },
            sortBy: [SortDescriptor(\PracticeSession.date, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private static func fetchRecentNotes(modelContext: ModelContext, daysBefore: Int) -> [Note] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -daysBefore, to: Date()) ?? Date()
        let descriptor = FetchDescriptor<Note>(
            predicate: #Predicate<Note> { note in
                note.createdAt >= cutoff
            },
            sortBy: [SortDescriptor(\Note.createdAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }
}

// MARK: - Helper Types

private struct SubjectGroupKey: Hashable {
    let subject: String
    let group: String
}

private struct LessonGroupProgress {
    var currentLesson: Lesson?
    var nextLesson: Lesson?
    var proficiency: ProficiencySignal = .notPresented
    var activeWorkInGroup: Int = 0
    var completedInGroup: Int = 0
}
