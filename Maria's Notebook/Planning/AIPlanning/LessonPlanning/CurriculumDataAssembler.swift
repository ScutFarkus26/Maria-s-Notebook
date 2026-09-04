import Foundation
import CoreData
import OSLog

/// Assembles factual curriculum history across students.
/// Presentation history and explicit guide decisions determine the displayed signal;
/// work outcomes and practice ratings are never treated as proficiency evidence.
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
        for students: [CDStudent],
        context: NSManagedObjectContext
    ) -> CurriculumMap {
        let allLessons = fetchAllLessons(context: context)
        let allPresentations = fetchAllPresentations(context: context)

        let studentIDs = Set(students.compactMap { $0.id?.uuidString })
        let studentNameMap = Dictionary(
            uniqueKeysWithValues: students.compactMap { student -> (String, String)? in
                guard let idString = student.id?.uuidString else { return nil }
                return (idString, student.fullName)
            }
        )

        // Group lessons by area → sequence
        let lessonsByArea = Dictionary(grouping: allLessons) { $0.area.trimmed() }

        var areaMaps: [CurriculumMap.AreaMap] = []

        for (area, areaLessons) in lessonsByArea.sorted(by: { $0.key < $1.key }) {
            let lessonsBySequence = Dictionary(grouping: areaLessons) { $0.sequence.trimmed() }

            var groupMaps: [CurriculumMap.SequenceMap] = []

            for (sequence, groupLessons) in lessonsBySequence.sorted(by: { $0.key < $1.key }) {
                let sortedLessons = groupLessons.sorted { $0.orderInSequence < $1.orderInSequence }

                var lessonPositions: [CurriculumMap.LessonPosition] = []
                var presentedCount = 0

                for lesson in sortedLessons {
                    guard let lessonID = lesson.id else { continue }
                    var studentStatuses: [CurriculumMap.PresentationStatus] = []

                    for studentIDString in studentIDs {
                        let proficiency = determineProficiency(
                            lessonID: lessonID,
                            studentID: studentIDString,
                            presentations: allPresentations
                        )

                        let name = studentNameMap[studentIDString] ?? "Unknown"
                        studentStatuses.append(.init(
                            studentID: UUID(uuidString: studentIDString) ?? UUID(),
                            studentName: name,
                            proficiency: proficiency
                        ))
                    }

                    // Count only the factual event: every included student has a
                    // presentation record for this lesson.
                    let allPresented = studentStatuses.allSatisfy { $0.proficiency != .notPresented }
                    if allPresented && !studentStatuses.isEmpty {
                        presentedCount += 1
                    }

                    lessonPositions.append(.init(
                        lessonID: lessonID,
                        lessonName: lesson.name,
                        orderInSequence: Int(lesson.orderInSequence),
                        studentStatuses: studentStatuses
                    ))
                }

                groupMaps.append(.init(
                    sequence: sequence,
                    lessons: lessonPositions,
                    presentedCount: presentedCount,
                    totalCount: sortedLessons.count
                ))
            }

            areaMaps.append(.init(area: area, groups: groupMaps))
        }

        return CurriculumMap(areas: areaMaps)
    }

    // MARK: - Token-Compressed Summary

    /// Creates a token-compressed text summary of the curriculum map.
    /// Uses hierarchical summarization: area-level overview with frontier-only detail.
    /// - Parameters:
    ///   - map: The full curriculum map
    ///   - maxTokenBudget: Approximate token budget for the summary
    /// - Returns: Compressed text suitable for AI prompt inclusion
    static func compressedSummary(of map: CurriculumMap, maxTokenBudget: Int = 2000) -> String {
        var lines: [String] = []
        lines.append("CURRICULUM STATUS:")

        for area in map.areas {
            var areaLine = "\(area.area):"
            var groupDetails: [String] = []

            for sequence in area.groups {
                let progress = "\(sequence.presentedCount)/\(sequence.totalCount) presented"

                // Show lessons that remain relevant at the curriculum frontier.
                let frontierLessons = sequence.lessons.filter { lesson in
                    lesson.studentStatuses.contains { status in
                        status.proficiency == .notPresented
                            || status.proficiency == .practicing
                            || status.proficiency == .needsMorePractice
                            || status.proficiency == .needsReteaching
                    }
                }.prefix(3)

                if frontierLessons.isEmpty {
                    groupDetails.append("  \(sequence.sequence) \(progress)")
                } else {
                    var detail = "  \(sequence.sequence) \(progress):"
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

            areaLine += " \(area.groups.count) groups"
            lines.append(areaLine)
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
            NSSortDescriptor(key: "area", ascending: true),
            NSSortDescriptor(key: "sequence", ascending: true),
            NSSortDescriptor(key: "orderInSequence", ascending: true)
        ]
        return context.safeFetch(request)
    }

    private static func fetchAllPresentations(context: NSManagedObjectContext) -> [CDLessonAssignment] {
        let request = CDFetchRequest(CDLessonAssignment.self)
        return context.safeFetch(request)
    }

    /// Returns a factual signal for a student's lesson history. Strong states
    /// come only from explicit fields set by the guide on a presentation.
    private static func determineProficiency(
        lessonID: UUID,
        studentID: String,
        presentations: [CDLessonAssignment]
    ) -> ProficiencySignal {
        let lessonIDStr = lessonID.uuidString

        // Find relevant presentations for this lesson + student
        let relevantPresentations = presentations.filter { la in
            la.lessonID == lessonIDStr && la.studentIDs.contains(studentID)
        }

        let presented = relevantPresentations.filter { $0.isPresented || $0.presentedAt != nil }
        guard let latest = presented.max(by: {
            ($0.presentedAt ?? $0.createdAt ?? .distantPast)
                < ($1.presentedAt ?? $1.createdAt ?? .distantPast)
        }) else {
            return .notPresented
        }

        if latest.needsAnotherPresentation { return .needsReteaching }
        if latest.needsPractice { return .needsMorePractice }
        if latest.confirmedStudentIDs.contains(studentID) { return .proficient }
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
        case .proficient: return "GC"
        case .needsMorePractice: return "NMP"
        case .needsReteaching: return "RP"
        }
    }
}
