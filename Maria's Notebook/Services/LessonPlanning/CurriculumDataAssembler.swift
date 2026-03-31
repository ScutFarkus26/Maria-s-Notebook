import Foundation
import CoreData
import OSLog

/// Assembles curriculum data across students by querying lessons, presentations, and work outcomes.
/// Produces a `CurriculumMap` that summarizes each student's position within the curriculum,
/// with token-efficient compression for AI prompt construction.
@MainActor
struct CurriculumDataAssembler {
    private static let logger = Logger.ai

    // MARK: - Public API

    /// Assembles a curriculum map for the given students.
    /// - Parameters:
    ///   - students: The students to include in the map
    ///   - context: The Core Data managed object context for fetching data
    /// - Returns: A `CurriculumMap` with per-student lesson statuses
    // swiftlint:disable:next function_body_length
    static func assembleCurriculumMap(
        for students: [Student],
        context: NSManagedObjectContext
    ) -> CurriculumMap {
        let allLessons = fetchAllLessons(context: context)
        let allPresentations = fetchAllPresentations(context: context)
        let allWork = fetchActiveWork(context: context)

        let studentIDs = Set(students.compactMap { $0.id?.uuidString })
        let studentNameMap = Dictionary(
            uniqueKeysWithValues: students.compactMap { student -> (String, String)? in
                guard let idString = student.id?.uuidString else { return nil }
                return (idString, student.fullName)
            }
        )

        // Group lessons by subject → group
        let lessonsBySubject = Dictionary(grouping: allLessons) { $0.subject.trimmed() }

        var subjectMaps: [CurriculumMap.SubjectMap] = []

        for (subject, subjectLessons) in lessonsBySubject.sorted(by: { $0.key < $1.key }) {
            let lessonsByGroup = Dictionary(grouping: subjectLessons) { $0.group.trimmed() }

            var groupMaps: [CurriculumMap.GroupMap] = []

            for (group, groupLessons) in lessonsByGroup.sorted(by: { $0.key < $1.key }) {
                let sortedLessons = groupLessons.sorted { $0.orderInGroup < $1.orderInGroup }

                var lessonPositions: [CurriculumMap.LessonPosition] = []
                var completedCount = 0

                for lesson in sortedLessons {
                    guard let lessonID = lesson.id else { continue }
                    var studentStatuses: [CurriculumMap.PresentationStatus] = []

                    for studentIDString in studentIDs {
                        let proficiency = determineProficiency(
                            lessonID: lessonID,
                            studentID: studentIDString,
                            presentations: allPresentations,
                            work: allWork
                        )

                        let name = studentNameMap[studentIDString] ?? "Unknown"
                        studentStatuses.append(.init(
                            studentID: UUID(uuidString: studentIDString) ?? UUID(),
                            studentName: name,
                            proficiency: proficiency
                        ))
                    }

                    // Count as completed if all students have been presented or beyond
                    let allPresented = studentStatuses.allSatisfy { $0.proficiency != .notPresented }
                    if allPresented && !studentStatuses.isEmpty {
                        completedCount += 1
                    }

                    lessonPositions.append(.init(
                        lessonID: lessonID,
                        lessonName: lesson.name,
                        orderInGroup: Int(lesson.orderInGroup),
                        studentStatuses: studentStatuses
                    ))
                }

                groupMaps.append(.init(
                    group: group,
                    lessons: lessonPositions,
                    completedCount: completedCount,
                    totalCount: sortedLessons.count
                ))
            }

            subjectMaps.append(.init(subject: subject, groups: groupMaps))
        }

        return CurriculumMap(subjects: subjectMaps)
    }

    // MARK: - Token-Compressed Summary

    /// Creates a token-compressed text summary of the curriculum map.
    /// Uses hierarchical summarization: subject-level overview with frontier-only detail.
    /// - Parameters:
    ///   - map: The full curriculum map
    ///   - maxTokenBudget: Approximate token budget for the summary
    /// - Returns: Compressed text suitable for AI prompt inclusion
    static func compressedSummary(of map: CurriculumMap, maxTokenBudget: Int = 2000) -> String {
        var lines: [String] = []
        lines.append("CURRICULUM STATUS:")

        for subject in map.subjects {
            var subjectLine = "\(subject.subject):"
            var groupDetails: [String] = []

            for group in subject.groups {
                let progress = "\(group.completedCount)/\(group.totalCount)"

                // Only show frontier lessons (first not-presented or practicing)
                let frontierLessons = group.lessons.filter { lesson in
                    lesson.studentStatuses.contains { status in
                        status.proficiency == .notPresented
                            || status.proficiency == .practicing
                            || status.proficiency == .needsMorePractice
                    }
                }.prefix(3)

                if frontierLessons.isEmpty {
                    groupDetails.append("  \(group.group) \(progress) complete")
                } else {
                    var detail = "  \(group.group) \(progress):"
                    for lesson in frontierLessons {
                        let studentSummaries = lesson.studentStatuses
                            .filter { $0.proficiency != .proficient }
                            .map {
                                let name = $0.studentName.components(separatedBy: " ").first ?? $0.studentName
                                return "\(name):\($0.proficiency.shortCode)"
                            }
                        if !studentSummaries.isEmpty {
                            detail += " \(lesson.lessonName)[\(studentSummaries.joined(separator: ","))]"
                        }
                    }
                    groupDetails.append(detail)
                }
            }

            subjectLine += " \(subject.groups.count) groups"
            lines.append(subjectLine)
            lines.append(contentsOf: groupDetails)
        }

        let result = lines.joined(separator: "\n")

        // Check token budget
        if !TokenEstimator.isWithinBudget(result, budget: maxTokenBudget) {
            let tokens = TokenEstimator.estimateTokens(for: result)
            Self.logger.info("Curriculum summary exceeds token budget (\(tokens)/\(maxTokenBudget))")
        }

        return result
    }

    // MARK: - Core Data Fetching

    private static func fetchAllLessons(context: NSManagedObjectContext) -> [CDLesson] {
        let request = CDFetchRequest(CDLesson.self)
        request.sortDescriptors = [
            NSSortDescriptor(key: "subject", ascending: true),
            NSSortDescriptor(key: "group", ascending: true),
            NSSortDescriptor(key: "orderInGroup", ascending: true)
        ]
        return context.safeFetch(request)
    }

    private static func fetchAllPresentations(context: NSManagedObjectContext) -> [CDLessonAssignment] {
        let request = CDFetchRequest(CDLessonAssignment.self)
        return context.safeFetch(request)
    }

    private static func fetchActiveWork(context: NSManagedObjectContext) -> [CDWorkModel] {
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(format: "statusRaw != %@", "complete")
        return context.safeFetch(request)
    }

    /// Determines the proficiency signal for a specific student on a specific lesson.
    private static func determineProficiency(
        lessonID: UUID,
        studentID: String,
        presentations: [CDLessonAssignment],
        work: [CDWorkModel]
    ) -> ProficiencySignal {
        let lessonIDStr = lessonID.uuidString

        // Find relevant presentations for this lesson + student
        let relevantPresentations = presentations.filter { la in
            la.lessonID == lessonIDStr && la.studentIDs.contains(studentID)
        }

        // Check if any presentation has been given
        let hasBeenPresented = relevantPresentations.contains { $0.presentedAt != nil }

        if !hasBeenPresented {
            // Check if there's a draft/scheduled presentation
            let hasPending = relevantPresentations.contains { $0.presentedAt == nil }
            if hasPending {
                return .notPresented // Scheduled but not yet presented
            }
            return .notPresented
        }

        // Has been presented - check work outcomes
        let relevantWork = work.filter { w in
            w.lessonID == lessonIDStr && w.studentID == studentID
        }

        // Deduplicate
        let allRelevantWork = Array(Set(relevantWork.compactMap(\.id)).compactMap { id in
            relevantWork.first { $0.id == id }
        })

        // Check completion outcomes
        for w in allRelevantWork {
            if let outcome = w.completionOutcome {
                switch outcome {
                case .proficient:
                    return .proficient
                case .needsMorePractice:
                    return .needsMorePractice
                case .needsReview:
                    return .needsReteaching
                case .incomplete:
                    return .practicing
                case .notApplicable:
                    continue
                }
            }
        }

        // Has active work but no completion outcome yet
        if !allRelevantWork.isEmpty {
            return .practicing
        }

        // Presented but no work created yet
        return .presented
    }
}

// MARK: - ProficiencySignal Short Codes

extension ProficiencySignal {
    /// Short code for compressed summaries
    var shortCode: String {
        switch self {
        case .notPresented: return "NP"
        case .presented: return "P"
        case .practicing: return "PR"
        case .proficient: return "M"
        case .needsMorePractice: return "NMP"
        case .needsReteaching: return "NR"
        }
    }
}
