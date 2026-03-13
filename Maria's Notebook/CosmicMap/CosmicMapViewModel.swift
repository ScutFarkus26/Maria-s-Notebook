// CosmicMapViewModel.swift
// ViewModel for the Cosmic Education / Great Lessons Curriculum Map.
// Groups lessons by Great Lesson and computes student coverage.

import Foundation
import SwiftData
import SwiftUI

@Observable
@MainActor
final class CosmicMapViewModel {
    // MARK: - Outputs

    private(set) var lessonsByGreatLesson: [GreatLesson: [Lesson]] = [:]
    private(set) var untaggedCount: Int = 0
    private(set) var totalLessonCount: Int = 0
    private(set) var studentCoverage: [GreatLesson: Int] = [:]
    private(set) var totalStudentCount: Int = 0
    private(set) var isLoading = false

    // MARK: - Inputs

    var searchText: String = ""
    var selectedGreatLesson: GreatLesson?

    // MARK: - Computed

    var greatLessonCards: [GreatLessonCardData] {
        GreatLesson.allCases.map { gl in
            let lessons = lessonsByGreatLesson[gl] ?? []
            let subjects = Set(lessons.map(\.subject)).sorted()
            let studentsPresented = studentCoverage[gl] ?? 0

            return GreatLessonCardData(
                greatLesson: gl,
                lessonCount: lessons.count,
                subjects: subjects,
                studentsPresentedCount: studentsPresented,
                totalStudentCount: totalStudentCount
            )
        }
    }

    var taggedPercentage: Int {
        guard totalLessonCount > 0 else { return 0 }
        let tagged = totalLessonCount - untaggedCount
        return Int(Double(tagged) / Double(totalLessonCount) * 100)
    }

    // MARK: - Load Data

    func loadData(context: ModelContext) {
        isLoading = true
        defer { isLoading = false }

        // Fetch all lessons
        let lessonDescriptor = FetchDescriptor<Lesson>(sortBy: [SortDescriptor(\Lesson.subject), SortDescriptor(\Lesson.sortIndex)])
        let allLessons = context.safeFetch(lessonDescriptor)
        totalLessonCount = allLessons.count

        // Group by great lesson
        var grouped: [GreatLesson: [Lesson]] = [:]
        var untagged = 0
        for lesson in allLessons {
            if let gl = lesson.greatLesson {
                grouped[gl, default: []].append(lesson)
            } else {
                untagged += 1
            }
        }
        lessonsByGreatLesson = grouped
        untaggedCount = untagged

        // Fetch students for coverage
        let studentDescriptor = FetchDescriptor<Student>(sortBy: Student.sortByName)
        let students = TestStudentsFilter.filterVisible(context.safeFetch(studentDescriptor))
        totalStudentCount = students.count

        // Fetch presented assignments
        let assignmentDescriptor = FetchDescriptor<LessonAssignment>()
        let assignments = context.safeFetch(assignmentDescriptor)

        // Build lesson ID → Great Lesson lookup
        var lessonGreatLessonMap: [UUID: GreatLesson] = [:]
        for lesson in allLessons {
            if let gl = lesson.greatLesson {
                lessonGreatLessonMap[lesson.id] = gl
            }
        }

        // Compute student coverage per Great Lesson
        var coverageMap: [GreatLesson: Set<String>] = [:]
        for assignment in assignments {
            guard let lessonID = assignment.lesson?.id,
                  let gl = lessonGreatLessonMap[lessonID],
                  assignment.stateRaw == "presented" || assignment.stateRaw == "mastered"
            else { continue }

            let studentIDs = assignment.studentIDs
            for studentID in studentIDs {
                coverageMap[gl, default: []].insert(studentID)
            }
        }

        studentCoverage = coverageMap.mapValues(\.count)
    }

    // MARK: - Filtered Lessons

    func filteredLessons(for greatLesson: GreatLesson) -> [Lesson] {
        let lessons = lessonsByGreatLesson[greatLesson] ?? []
        guard !searchText.isEmpty else { return lessons }
        let query = searchText.lowercased()
        return lessons.filter {
            $0.name.lowercased().contains(query) ||
            $0.subject.lowercased().contains(query) ||
            $0.group.lowercased().contains(query)
        }
    }
}

// MARK: - Supporting Types

struct GreatLessonCardData: Identifiable {
    let id = UUID()
    let greatLesson: GreatLesson
    let lessonCount: Int
    let subjects: [String]
    let studentsPresentedCount: Int
    let totalStudentCount: Int

    var coveragePercentage: Double {
        guard totalStudentCount > 0 else { return 0 }
        return Double(studentsPresentedCount) / Double(totalStudentCount)
    }
}
