// RecallQueueViewModel.swift
// Loads the lesson-recall queue: for every visible student, the mastered lessons that are due
// for a recall check, collapsed to each strand's frontier. Mirrors ProgressDashboardViewModel's
// fetch-then-compute shape; the frontier math itself lives in the pure RecallFrontierEngine.
//
// Recall keys off *today's* school year (schoolYearStore.current), not the viewing lens — a
// recall check is something you do in the present about prior mastery, so all proficient
// presentations are considered regardless of which year they were mastered in.

import Foundation
import CoreData
import OSLog

/// One student's section in the recall queue.
struct RecallStudentSection: Identifiable {
    let id: String          // normalized studentID
    let studentName: String
    let entries: [RecallQueueEntry]
}

/// Per-student retention row for the summary.
struct RecallStudentRetention: Identifiable {
    let id: String
    let name: String
    let observedCount: Int
    let percent: Int?
}

@Observable
@MainActor
final class RecallQueueViewModel {
    private static let logger = Logger.app_

    private(set) var sections: [RecallStudentSection] = []
    private(set) var isLoading = false
    private(set) var summary: RecallRetentionStats.Summary?
    private(set) var fadeOverSummerPercent: Int?
    private(set) var retentionByStudent: [RecallStudentRetention] = []

    var totalDue: Int { sections.reduce(0) { $0 + $1.entries.count } }
    var hasContent: Bool { !sections.isEmpty }

    func loadData(context: NSManagedObjectContext, schoolYearStore: SchoolYearStore) {
        isLoading = true
        defer { isLoading = false }

        let visibleStudents = TestStudentsFilter.filterVisible(fetchStudents(context: context))
        var nameByID: [String: String] = [:]
        var visibleIDs = Set<String>()
        for student in visibleStudents {
            guard let id = student.id else { continue }
            let key = RecallFrontierEngine.normalize(id.uuidString)
            nameByID[key] = student.fullName
            visibleIDs.insert(key)
        }

        let lessons: [RecallLesson] = fetchLessons(context: context).compactMap { lesson in
            guard let id = lesson.id else { return nil }
            let area = lesson.area.trimmed()
            let sequence = lesson.sequence.trimmed()
            guard !area.isEmpty, !sequence.isEmpty else { return nil }
            return RecallLesson(
                id: id, name: lesson.name, area: area, sequence: sequence,
                orderInSequence: Int(lesson.orderInSequence)
            )
        }

        let mastered: [RecallMastery] = fetchMasteredPresentations(context: context)
            .filter { visibleIDs.contains(RecallFrontierEngine.normalize($0.studentID)) }
            .map { RecallMastery(studentID: $0.studentID, lessonID: $0.lessonID, masteredAt: $0.masteredAt) }

        let currentYear = schoolYearStore.current

        // Fetch all recall checks for stats (needs cross-year data for fade-over-summer).
        let recallRows = fetchAllRecallChecks(context: context)
        let existing: [RecallExisting] = recallRows.map {
            RecallExisting(
                studentID: $0.studentID, lessonID: $0.lessonID,
                schoolYearKey: $0.schoolYearKey, source: $0.source, checkedAt: $0.checkedAt
            )
        }
        let statRows: [RecallStatRow] = recallRows.map {
            RecallStatRow(
                studentID: RecallFrontierEngine.normalize($0.studentID), outcome: $0.outcome,
                source: $0.source, schoolYearKey: $0.schoolYearKey,
                originalMasteredAt: $0.originalMasteredAt, checkedAt: $0.checkedAt
            )
        }

        let intervalDays = UserDefaults.standard.object(forKey: UserDefaultsKeys.recallSpacedIntervalDays) as? Int ?? 90
        let config = RecallConfig(
            schoolYearStart: currentYear.start,
            schoolYearKey: currentYear.key,
            spacedInterval: TimeInterval(intervalDays) * 86_400,
            now: Date()
        )

        let entries = RecallFrontierEngine.buildQueue(
            lessons: lessons, mastered: mastered, existing: existing, config: config
        )

        let grouped = Dictionary(grouping: entries) { $0.studentID }
        sections = grouped.map { studentID, entries in
            RecallStudentSection(
                id: studentID,
                studentName: nameByID[studentID] ?? "Unknown",
                entries: entries
            )
        }
        .sorted { $0.studentName.localizedCaseInsensitiveCompare($1.studentName) == .orderedAscending }

        summary = RecallRetentionStats.summary(rows: statRows, schoolYearKey: currentYear.key)
        fadeOverSummerPercent = RecallRetentionStats.fadeOverSummerPercent(
            rows: statRows, schoolYearKey: currentYear.key, yearStart: currentYear.start
        )
        retentionByStudent = RecallRetentionStats.perStudent(rows: statRows, schoolYearKey: currentYear.key)
            .map {
                RecallStudentRetention(
                    id: $0.id, name: nameByID[$0.id] ?? "Unknown",
                    observedCount: $0.observedCount, percent: $0.percent
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Fetching

    private func fetchStudents(context: NSManagedObjectContext) -> [CDStudent] {
        let request = NSFetchRequest<CDStudent>(entityName: "Student")
        request.sortDescriptors = CDStudent.sortByName
        return context.safeFetch(request).filterEnrolled()
    }

    private func fetchLessons(context: NSManagedObjectContext) -> [CDLesson] {
        let request = NSFetchRequest<CDLesson>(entityName: "Lesson")
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \CDLesson.area, ascending: true),
            NSSortDescriptor(keyPath: \CDLesson.sequence, ascending: true),
            NSSortDescriptor(keyPath: \CDLesson.orderInSequence, ascending: true)
        ]
        return context.safeFetch(request)
    }

    private func fetchMasteredPresentations(context: NSManagedObjectContext) -> [CDLessonPresentation] {
        let request = NSFetchRequest<CDLessonPresentation>(entityName: "LessonPresentation")
        request.predicate = NSPredicate(
            format: "stateRaw == %@", LessonPresentationState.proficient.rawValue
        )
        return context.safeFetch(request)
    }

    /// Fetches all recall checks, batched to keep memory footprint low.
    /// Cross-year data is required for fade-over-summer stats.
    private func fetchAllRecallChecks(context: NSManagedObjectContext) -> [CDLessonRecallCheck] {
        let request = NSFetchRequest<CDLessonRecallCheck>(entityName: "LessonRecallCheck")
        request.fetchBatchSize = 200
        return context.safeFetch(request)
    }
}
