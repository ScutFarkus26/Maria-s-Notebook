import Foundation
import CoreData
import OSLog

/// Pure local computation service that assembles factual planning evidence.
/// Curriculum position, presentation history, active-work counts, and explicit
/// guide decisions are included. Practice ratings, work outcomes, behavior labels,
/// and emotional tags are deliberately excluded from readiness inference.
@MainActor
struct StudentReadinessAssessor {
    private static let logger = Logger.ai

    // MARK: - Public API

    /// Assembles planning evidence for a set of students.
    /// - Parameters:
    ///   - students: Students to assess
    ///   - context: The Core Data managed object context for querying data
    /// - Returns: Array of factual planning profiles, one per student
    static func assessReadiness(
        for students: [CDStudent],
        context: NSManagedObjectContext
    ) -> [StudentReadinessProfile] {
        let allLessons = fetchAllLessons(context: context)
        let allPresentations = fetchPresentations(context: context)
        let allWork = fetchAllWork(context: context)

        return students.map { student in
            buildProfile(
                for: student,
                allLessons: allLessons,
                allPresentations: allPresentations,
                allWork: allWork
            )
        }
    }

    /// Assembles planning evidence for a single student.
    static func assessReadiness(
        for student: CDStudent,
        context: NSManagedObjectContext
    ) -> StudentReadinessProfile {
        guard let profile = assessReadiness(for: [student], context: context).first else {
            logger.error("assessReadiness returned empty array for single student \(student.id?.uuidString ?? "nil")")
            return StudentReadinessProfile(
                studentID: student.id ?? UUID(),
                studentName: student.firstName,
                level: "",
                areaReadiness: [],
                daysSinceLastPresentation: nil,
                activeWorkCount: 0
            )
        }
        return profile
    }

    // Deprecated SwiftData API removed - use Core Data overloads.
    
    // MARK: - Profile Building

    // swiftlint:disable:next function_parameter_count
    private static func buildProfile(
        for student: CDStudent,
        allLessons: [CDLesson],
        allPresentations: [CDLessonAssignment],
        allWork: [CDWorkModel]
    ) -> StudentReadinessProfile {
        let studentIDStr = student.id?.uuidString ?? ""
        let studentPresentations = allPresentations.filter { $0.studentIDs.contains(studentIDStr) }
        let studentWork = allWork.filter { $0.studentID == studentIDStr }
        let areaReadiness = computeAreaReadiness(
            studentID: student.id ?? UUID(), allLessons: allLessons,
            presentations: studentPresentations, work: studentWork
        )
        let daysSinceLastPresentation = computeDaysSinceLastPresentation(studentPresentations)
        let activeWorkCount = studentWork.filter { $0.status != WorkStatus.complete }.count
        return StudentReadinessProfile(
            studentID: student.id ?? UUID(),
            studentName: student.fullName,
            level: student.level.rawValue,
            areaReadiness: areaReadiness,
            daysSinceLastPresentation: daysSinceLastPresentation,
            activeWorkCount: activeWorkCount
        )
    }

    private static func computeDaysSinceLastPresentation(_ presentations: [CDLessonAssignment]) -> Int? {
        guard let lastDate = presentations.compactMap({ $0.presentedAt }).max() else { return nil }
        // Clamped to the school-year counter epoch (see `SchoolYearCounters`) so the planner
        // doesn't read a summer gap as a child who has been ignored for months.
        let from = SchoolYearCounters.countFrom(lastDate)
        return Calendar.current.dateComponents([.day], from: from, to: Date()).day
    }

    // MARK: - Area Readiness Computation

    private static func computeAreaReadiness(
        studentID: UUID,
        allLessons: [CDLesson],
        presentations: [CDLessonAssignment],
        work: [CDWorkModel]
    ) -> [AreaReadiness] {
        let lessonsByAreaSequence = Dictionary(grouping: allLessons) {
            AreaSequenceKey(area: $0.area.trimmed(), sequence: $0.sequence.trimmed())
        }
        var results: [AreaReadiness] = []
        for (key, lessons) in lessonsByAreaSequence {
            guard !key.area.isEmpty, !key.sequence.isEmpty else { continue }
            let sorted = lessons.sorted { $0.orderInSequence < $1.orderInSequence }
            let groupProgress = scanLessonSequenceProgress(
                studentID: studentID,
                sorted: sorted,
                presentations: presentations,
                work: work
            )
            let currentLesson = groupProgress.currentLesson
            var nextLesson = groupProgress.nextLesson
            if currentLesson == nil, let first = sorted.first { nextLesson = first }
            if let current = currentLesson, nextLesson == nil {
                nextLesson = PlanNextLessonService.findNextLesson(after: current, in: allLessons)
            }
            results.append(AreaReadiness(
                area: key.area, sequence: key.sequence,
                currentLessonName: currentLesson?.name, currentLessonID: currentLesson?.id,
                nextLessonName: nextLesson?.name, nextLessonID: nextLesson?.id,
                proficiencySignal: groupProgress.proficiency,
                evidenceAvailability: groupProgress.evidenceAvailability,
                activeWorkCount: groupProgress.activeWorkInGroup,
                presentedInSequence: groupProgress.presentedInSequence, totalInSequence: sorted.count
            ))
        }
        return results.sorted { ($0.area, $0.sequence) < ($1.area, $1.sequence) }
    }

    private static func scanLessonSequenceProgress(
        studentID: UUID,
        sorted: [CDLesson],
        presentations: [CDLessonAssignment],
        work: [CDWorkModel]
    ) -> LessonSequenceProgress {
        var progress = LessonSequenceProgress()
        for lesson in sorted {
            let lessonIDStr = lesson.id?.uuidString ?? ""
            // Match on state too: "Previously Presented" records are undated, and a
            // date-only check would re-suggest already-presented historical lessons.
            let presented = presentations.contains { la in
                la.lessonID == lessonIDStr && (la.isPresented || la.presentedAt != nil)
            }
            if presented {
                progress.presentedInSequence += 1
                progress.currentLesson = lesson
                let lessonWork = work.filter { $0.lessonID == lessonIDStr }
                let activeWork = lessonWork.filter { $0.status != WorkStatus.complete }
                progress.activeWorkInGroup += activeWork.count
                progress.proficiency = determinePlanningSignal(
                    studentID: studentID,
                    lessonID: lessonIDStr,
                    presentations: presentations
                )
                progress.evidenceAvailability = evidenceAvailability(
                    for: progress.proficiency,
                    hasPresentation: true
                )
            } else if progress.currentLesson != nil && progress.nextLesson == nil {
                progress.nextLesson = lesson
            }
        }
        return progress
    }

    /// Returns only facts explicitly recorded by the guide on the presentation.
    /// Work completion, practice quality, and behavior fields never enter this decision.
    private static func determinePlanningSignal(
        studentID: UUID,
        lessonID: String,
        presentations: [CDLessonAssignment]
    ) -> ProficiencySignal {
        let matching = presentations.filter {
            $0.lessonID == lessonID && ($0.isPresented || $0.presentedAt != nil)
        }
        guard let latest = matching.max(by: {
            ($0.presentedAt ?? $0.createdAt ?? .distantPast)
                < ($1.presentedAt ?? $1.createdAt ?? .distantPast)
        }) else {
            return .notPresented
        }

        if latest.needsAnotherPresentation { return .needsReteaching }
        if latest.needsPractice { return .needsMorePractice }
        if latest.isStudentConfirmed(studentID) { return .proficient }
        return .presented
    }

    private static func evidenceAvailability(
        for signal: ProficiencySignal,
        hasPresentation: Bool
    ) -> EvidenceAvailability {
        switch signal {
        case .proficient, .needsMorePractice, .needsReteaching:
            return .strong
        case .presented, .practicing:
            return hasPresentation ? .some : .insufficient
        case .notPresented:
            return .insufficient
        }
    }

}

// MARK: - Compressed Summary

extension StudentReadinessAssessor {
    /// Creates a token-efficient summary of factual planning evidence.
    static func compressedSummary(of profiles: [StudentReadinessProfile]) -> String {
        var lines: [String] = []
        lines.append("STUDENT EVIDENCE:")

        for profile in profiles {
            var studentLine = "\(profile.studentName) (\(profile.level))"

            var details: [String] = []
            if let days = profile.daysSinceLastPresentation {
                details.append("last presentation \(days)d ago")
            } else {
                details.append("no presentations")
            }
            details.append("\(profile.activeWorkCount) active work")

            studentLine += " - \(details.joined(separator: ", "))"

            lines.append(studentLine)

            // Only show areas with a next lesson available (frontier)
            let frontierAreas = profile.areaReadiness
                .filter { $0.nextLessonID != nil }
            for sr in frontierAreas.prefix(8) {
                let prog = "\(sr.presentedInSequence)/\(sr.totalInSequence) presented"
                let current = sr.currentLessonName
                    .map {
                        "current: \($0) (\(sr.proficiencySignal.shortCode), "
                            + "evidence:\(sr.evidenceAvailability.rawValue))"
                    }
                    ?? "not started"
                let next = sr.nextLessonName.map { "next: \($0)" } ?? ""
                lines.append("  \(sr.area)/\(sr.sequence) \(prog) \(current) \(next)")
            }
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - Core Data Fetching

extension StudentReadinessAssessor {
    private static func fetchAllLessons(context: NSManagedObjectContext) -> [CDLesson] {
        let request = CDFetchRequest(CDLesson.self)
        request.sortDescriptors = [
            NSSortDescriptor(key: "area", ascending: true),
            NSSortDescriptor(key: "sequence", ascending: true),
            NSSortDescriptor(key: "orderInSequence", ascending: true)
        ]
        return context.safeFetch(request)
    }

    private static func fetchPresentations(context: NSManagedObjectContext) -> [CDLessonAssignment] {
        let request = CDFetchRequest(CDLessonAssignment.self)
        return context.safeFetch(request)
    }

    private static func fetchAllWork(context: NSManagedObjectContext) -> [CDWorkModel] {
        let request = CDFetchRequest(CDWorkModel.self)
        return context.safeFetch(request)
    }

}

// Deprecated SwiftData fetching methods removed - Core Data versions are used.

// MARK: - Helper Types

private struct AreaSequenceKey: Hashable {
    let area: String
    let sequence: String
}

private struct LessonSequenceProgress {
    var currentLesson: CDLesson?
    var nextLesson: CDLesson?
    var proficiency: ProficiencySignal = .notPresented
    var evidenceAvailability: EvidenceAvailability = .insufficient
    var activeWorkInGroup: Int = 0
    var presentedInSequence: Int = 0
}
