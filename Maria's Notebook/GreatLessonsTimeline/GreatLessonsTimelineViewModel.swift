// GreatLessonsTimelineViewModel.swift
// ViewModel for the Five Great Lessons Timeline feature.
// Loads lessons, assignments, and work, then aggregates by Great Lesson branch.

import Foundation
import CoreData
import OSLog

@Observable
@MainActor
final class GreatLessonsTimelineViewModel {
    private static let logger = Logger.app_

    // MARK: - Outputs

    private(set) var branches: [GreatLessonBranch] = []
    private(set) var unmappedLessonCount: Int = 0
    private(set) var isLoading = false

    // MARK: - Filters

    var selectedStudentID: UUID?
    var searchText: String = ""

    var filteredBranches: [GreatLessonBranch] {
        guard !searchText.isEmpty else { return branches }
        let query = searchText.lowercased()
        return branches.filter { branch in
            branch.greatLesson.displayName.lowercased().contains(query) ||
            branch.areaSequences.contains { $0.area.lowercased().contains(query) }
        }
    }

    // MARK: - Data Loading

    // swiftlint:disable:next function_body_length
    func loadData(context: NSManagedObjectContext) {
        isLoading = true
        defer { isLoading = false }

        // 1. Fetch all data
        let allLessons = fetchAllLessons(context: context)
        let allAssignments = fetchPresentedAssignments(context: context)
        let allWork = fetchActiveWork(context: context)
        let allStudents = TestStudentsFilter.filterVisible(
            fetchAllStudents(context: context).filterEnrolled()
        )

        guard !allLessons.isEmpty else {
            branches = []
            unmappedLessonCount = 0
            return
        }

        // 2. Build lookup indices
        let _: [UUID: CDLesson] = Dictionary(
            uniqueKeysWithValues: allLessons.compactMap { lesson in
                guard let id = lesson.id else { return nil }
                return (id, lesson)
            }
        )

        // Assignments indexed by lessonID string
        let assignmentsByLessonID = Dictionary(grouping: allAssignments) { $0.lessonID }

        // Work indexed by lessonID string
        let workByLessonID = Dictionary(grouping: allWork) { $0.lessonID }

        // Student lookup
        let studentsByID: [UUID: CDStudent] = Dictionary(
            uniqueKeysWithValues: allStudents.compactMap { student in
                guard let id = student.id else { return nil }
                return (id, student)
            }
        )
        _ = Set(studentsByID.keys.map(\.uuidString))

        // 3. Resolve lessons to Great Lessons
        var lessonsByGreatLesson: [GreatLesson: [CDLesson]] = [:]
        var unmapped = 0

        for lesson in allLessons {
            let resolved = GreatLesson.resolve(for: lesson)
            if resolved.isEmpty {
                unmapped += 1
            } else {
                for gl in resolved {
                    lessonsByGreatLesson[gl, default: []].append(lesson)
                }
            }
        }

        unmappedLessonCount = unmapped

        // 4. Build branches
        var result: [GreatLessonBranch] = []

        for gl in GreatLesson.allCases {
            let lessons = lessonsByGreatLesson[gl] ?? []
            _ = Set(lessons.compactMap { $0.id })

            // Group by area → sequence
            let grouped = Dictionary(grouping: lessons) {
                "\($0.area.trimmed())|\($0.sequence.trimmed())"
            }

            let areaSequences: [BranchAreaSequence] = grouped.map { key, groupLessons in
                let parts = key.split(separator: "|", maxSplits: 1)
                let area = parts.count > 0 ? String(parts[0]) : ""
                let sequence = parts.count > 1 ? String(parts[1]) : ""

                let branchLessons = groupLessons
                    .sorted { $0.orderInSequence < $1.orderInSequence }
                    .compactMap { lesson -> BranchLesson? in
                        guard let id = lesson.id else { return nil }
                        return BranchLesson(
                            id: id,
                            name: lesson.name,
                            isExplicitlyTagged: lesson.greatLessonRaw != nil
                        )
                    }

                return BranchAreaSequence(
                    id: key,
                    area: area,
                    sequence: sequence,
                    lessons: branchLessons
                )
            }.sorted { ($0.area, $0.sequence) < ($1.area, $1.sequence) }

            // Per-student progress
            let studentProgress: [StudentBranchProgress] = allStudents.compactMap { student in
                guard let studentID = student.id else { return nil }

                // Filter by selected student if applicable
                if let selected = selectedStudentID, studentID != selected { return nil }

                let studentIDStr = studentID.uuidString
                var presented = 0
                var activeWork = 0
                var lastDate: Date?
                var presentedAreas = Set<String>()

                for lesson in lessons {
                    let lessonIDStr = lesson.id?.uuidString ?? ""

                    // Check if this student has a presented assignment for this lesson
                    let assignments = assignmentsByLessonID[lessonIDStr] ?? []
                    let studentAssignment = assignments.first { la in
                        la.presentedAt != nil && la.studentIDs.contains(studentIDStr)
                    }

                    if studentAssignment != nil {
                        presented += 1
                        presentedAreas.insert(lesson.area.trimmed())
                        if let date = studentAssignment?.presentedAt {
                            if lastDate == nil || date > lastDate! {
                                lastDate = date
                            }
                        }
                    }

                    // Count active work for this student + lesson
                    let work = workByLessonID[lessonIDStr] ?? []
                    activeWork += work.filter { w in
                        w.studentID == studentIDStr && w.status != .complete
                    }.count
                }

                let total = lessons.count
                let completion = total > 0 ? Double(presented) / Double(total) : 0

                // Find gap areas (areas in this branch with no presentations)
                let branchAreas = Set(lessons.map { $0.area.trimmed() })
                let gaps = branchAreas.subtracting(presentedAreas).sorted()

                return StudentBranchProgress(
                    id: studentID,
                    firstName: student.firstName,
                    lastName: student.lastName,
                    level: student.level,
                    presentedCount: presented,
                    totalLessons: total,
                    activeWorkCount: activeWork,
                    lastPresentedAt: lastDate,
                    completionPercentage: completion,
                    gapAreas: gaps
                )
            }

            result.append(GreatLessonBranch(
                id: gl.rawValue,
                greatLesson: gl,
                totalLessons: lessons.count,
                areaSequences: areaSequences,
                studentProgress: studentProgress.sorted { $0.completionPercentage > $1.completionPercentage }
            ))
        }

        branches = result
    }

    // MARK: - Data Fetching

    private func fetchAllLessons(context: NSManagedObjectContext) -> [CDLesson] {
        let request = NSFetchRequest<CDLesson>(entityName: "Lesson")
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \CDLesson.area, ascending: true),
            NSSortDescriptor(keyPath: \CDLesson.sequence, ascending: true),
            NSSortDescriptor(keyPath: \CDLesson.orderInSequence, ascending: true)
        ]
        return context.safeFetch(request)
    }

    private func fetchPresentedAssignments(context: NSManagedObjectContext) -> [CDLessonAssignment] {
        let request = NSFetchRequest<CDLessonAssignment>(entityName: "LessonAssignment")
        request.predicate = NSPredicate(format: "presentedAt != nil")
        return context.safeFetch(request)
    }

    private func fetchActiveWork(context: NSManagedObjectContext) -> [CDWorkModel] {
        let request = NSFetchRequest<CDWorkModel>(entityName: "WorkModel")
        return context.safeFetch(request)
    }

    private func fetchAllStudents(context: NSManagedObjectContext) -> [CDStudent] {
        let request = NSFetchRequest<CDStudent>(entityName: "Student")
        request.sortDescriptors = CDStudent.sortByName
        return context.safeFetch(request)
    }
}
