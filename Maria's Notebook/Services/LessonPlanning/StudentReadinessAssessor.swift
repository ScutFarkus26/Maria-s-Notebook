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
        assessReadiness(for: [student], modelContext: modelContext).first!
    }
    
    // MARK: - Profile Building
    
    private static func buildProfile(
        for student: Student,
        allLessons: [Lesson],
        allPresentations: [LessonAssignment],
        allWork: [WorkModel],
        recentSessions: [PracticeSession],
        recentNotes: [Note]
    ) -> StudentReadinessProfile {
        let studentIDStr = student.id.uuidString
        
        // Filter data for this student
        let studentPresentations = allPresentations.filter { $0.studentIDs.contains(studentIDStr) }
        let studentWork = allWork.filter { $0.studentID == studentIDStr }
        let studentSessions = recentSessions.filter { $0.studentIDs.contains(studentIDStr) }
        let studentNotes = recentNotes.filter { note in
            note.searchIndexStudentID == student.id || note.scopeIsAll
        }
        
        // Compute per-subject readiness
        let subjectReadiness = computeSubjectReadiness(
            student: student,
            allLessons: allLessons,
            presentations: studentPresentations,
            work: studentWork
        )
        
        // Compute practice quality averages
        let practiceQualities = studentSessions.compactMap { $0.practiceQuality }
        let practiceQualityAvg = practiceQualities.isEmpty ? nil : Double(practiceQualities.reduce(0, +)) / Double(practiceQualities.count)
        
        let independenceLevels = studentSessions.compactMap { $0.independenceLevel }
        let independenceAvg = independenceLevels.isEmpty ? nil : Double(independenceLevels.reduce(0, +)) / Double(independenceLevels.count)
        
        // Days since last presentation
        let lastPresentedDate = studentPresentations
            .compactMap { $0.presentedAt }
            .max()
        let daysSinceLastPresentation: Int?
        if let lastDate = lastPresentedDate {
            daysSinceLastPresentation = Calendar.current.dateComponents([.day], from: lastDate, to: Date()).day
        } else {
            daysSinceLastPresentation = nil
        }
        
        // Active work count
        let activeWorkCount = studentWork.filter { $0.status != .complete }.count
        
        // Behavioral flags from recent practice sessions
        var behavioralFlags: [String] = []
        let recentFlags = studentSessions.prefix(10)
        if recentFlags.contains(where: { $0.needsReteaching }) {
            behavioralFlags.append("needs reteaching")
        }
        if recentFlags.contains(where: { $0.readyForAssessment }) {
            behavioralFlags.append("ready for assessment")
        }
        if recentFlags.contains(where: { $0.readyForCheckIn }) {
            behavioralFlags.append("ready for check-in")
        }
        if recentFlags.contains(where: { $0.struggledWithConcept }) {
            behavioralFlags.append("struggling with concept")
        }
        if recentFlags.contains(where: { $0.madeBreakthrough }) {
            behavioralFlags.append("recent breakthrough")
        }
        
        // Check notes for behavioral indicators
        let behavioralNotes = studentNotes.filter { note in
            note.tags.contains { tag in
                let name = TagHelper.tagName(tag).lowercased()
                return name == "behavioral" || name == "emotional"
            }
        }
        if !behavioralNotes.isEmpty {
            behavioralFlags.append("\(behavioralNotes.count) behavioral/emotional notes")
        }
        
        return StudentReadinessProfile(
            studentID: student.id,
            studentName: student.fullName,
            level: student.level.rawValue,
            subjectReadiness: subjectReadiness,
            practiceQualityAvg: practiceQualityAvg,
            independenceAvg: independenceAvg,
            daysSinceLastPresentation: daysSinceLastPresentation,
            activeWorkCount: activeWorkCount,
            behavioralFlags: behavioralFlags
        )
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
            
            // Find the furthest presented lesson for this student in this group
            var currentLesson: Lesson?
            var nextLesson: Lesson?
            var mastery: MasterySignal = .notPresented
            var activeWorkInGroup = 0
            var completedInGroup = 0
            
            for lesson in sorted {
                let lessonIDStr = lesson.id.uuidString
                let presented = presentations.contains { la in
                    la.lessonID == lessonIDStr && la.presentedAt != nil
                }
                
                if presented {
                    completedInGroup += 1
                    currentLesson = lesson
                    
                    // Check work outcomes for this lesson
                    let lessonWork = work.filter { $0.lessonID == lessonIDStr }
                    let activeWork = lessonWork.filter { $0.status != .complete }
                    activeWorkInGroup += activeWork.count
                    
                    // Determine mastery for current lesson
                    let completedWork = lessonWork.filter { $0.status == .complete }
                    if let latest = completedWork.max(by: { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }) {
                        if let outcome = latest.completionOutcome {
                            switch outcome {
                            case .mastered: mastery = .mastered
                            case .needsMorePractice: mastery = .needsMorePractice
                            case .needsReview: mastery = .needsReteaching
                            case .incomplete: mastery = .practicing
                            case .notApplicable: mastery = .presented
                            }
                        } else {
                            mastery = .practicing
                        }
                    } else if !activeWork.isEmpty {
                        mastery = .practicing
                    } else {
                        mastery = .presented
                    }
                } else if currentLesson != nil && nextLesson == nil {
                    // First unpresented lesson after the current one is the "next"
                    nextLesson = lesson
                }
            }
            
            // If no lesson has been presented, first lesson is "next"
            if currentLesson == nil, let first = sorted.first {
                nextLesson = first
            }
            
            // Only find next via PlanNextLessonService if we have a current lesson but no next yet
            if let current = currentLesson, nextLesson == nil {
                nextLesson = PlanNextLessonService.findNextLesson(after: current, in: allLessons)
            }
            
            results.append(SubjectReadiness(
                subject: key.subject,
                group: key.group,
                currentLessonName: currentLesson?.name,
                currentLessonID: currentLesson?.id,
                nextLessonName: nextLesson?.name,
                nextLessonID: nextLesson?.id,
                masterySignal: mastery,
                activeWorkCount: activeWorkInGroup,
                completedInGroup: completedInGroup,
                totalInGroup: sorted.count
            ))
        }
        
        return results.sorted { ($0.subject, $0.group) < ($1.subject, $1.group) }
    }
    
    // MARK: - Compressed Summary
    
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
            let frontierSubjects = profile.subjectReadiness.filter { $0.nextLessonID != nil }
            for sr in frontierSubjects.prefix(8) {
                let progress = "\(sr.completedInGroup)/\(sr.totalInGroup)"
                let current = sr.currentLessonName.map { "current: \($0) (\(sr.masterySignal.shortCode))" } ?? "not started"
                let next = sr.nextLessonName.map { "next: \($0)" } ?? ""
                lines.append("  \(sr.subject)/\(sr.group) \(progress) \(current) \(next)")
            }
        }
        
        return lines.joined(separator: "\n")
    }
    
    // MARK: - Data Fetching
    
    private static func fetchAllLessons(modelContext: ModelContext) -> [Lesson] {
        let descriptor = FetchDescriptor<Lesson>(
            sortBy: [SortDescriptor(\Lesson.subject), SortDescriptor(\Lesson.group), SortDescriptor(\Lesson.orderInGroup)]
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
