// ThreePeriodViewModel.swift
// ViewModel for the Three-Period Lesson Tracker view.

import SwiftData
import SwiftUI

@Observable
@MainActor
final class ThreePeriodViewModel {
    var summaries: [ThreePeriodSummary] = []
    var stageCountsByStudent: [UUID: [ThreePeriodStage: Int]] = [:]

    // Filters
    var selectedStudentID: UUID?
    var selectedSubject: String?
    var selectedStage: ThreePeriodStage?
    var searchText: String = ""

    var availableSubjects: [String] = []
    var availableStudents: [(id: UUID, name: String)] = []

    var filteredSummaries: [ThreePeriodSummary] {
        summaries.filter { summary in
            if let studentID = selectedStudentID, summary.studentID != studentID {
                return false
            }
            if let subject = selectedSubject, summary.lessonSubject != subject {
                return false
            }
            if let stage = selectedStage, summary.stage != stage {
                return false
            }
            if !searchText.isEmpty {
                let query = searchText.lowercased()
                if !summary.lessonName.lowercased().contains(query) &&
                    !summary.studentName.lowercased().contains(query) {
                    return false
                }
            }
            return true
        }
    }

    var summariesByStudent: [UUID: [ThreePeriodSummary]] {
        Dictionary(grouping: filteredSummaries, by: \.studentID)
    }

    func loadData(context: ModelContext) {
        let presentationDescriptor = FetchDescriptor<LessonPresentation>(
            sortBy: [SortDescriptor(\.presentedAt, order: .reverse)]
        )
        let presentations = context.safeFetch(presentationDescriptor)

        let studentDescriptor = FetchDescriptor<Student>(sortBy: Student.sortByName)
        let students = TestStudentsFilter.filterVisible(context.safeFetch(studentDescriptor))

        let lessonDescriptor = FetchDescriptor<Lesson>()
        let lessons = context.safeFetch(lessonDescriptor)

        let studentsByID = Dictionary(uniqueKeysWithValues: students.map { ($0.id, $0) })
        let lessonsByID = Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) })

        let visibleStudentIDs = Set(students.map(\.id))

        var built: [ThreePeriodSummary] = []
        var counts: [UUID: [ThreePeriodStage: Int]] = [:]

        for pres in presentations {
            guard let studentUUID = UUID(uuidString: pres.studentID),
                  visibleStudentIDs.contains(studentUUID),
                  let lessonUUID = UUID(uuidString: pres.lessonID),
                  let student = studentsByID[studentUUID],
                  let lesson = lessonsByID[lessonUUID] else { continue }

            let stage = ThreePeriodStage.from(state: pres.state)
            let name = "\(student.firstName) \(student.lastName.prefix(1))."

            built.append(ThreePeriodSummary(
                id: pres.id,
                studentID: studentUUID,
                studentName: name,
                lessonID: lessonUUID,
                lessonName: lesson.name,
                lessonSubject: lesson.subject,
                stage: stage,
                presentedAt: pres.presentedAt,
                lastObservedAt: pres.lastObservedAt,
                presentationState: pres.state
            ))

            counts[studentUUID, default: [:]][stage, default: 0] += 1
        }

        summaries = built
        stageCountsByStudent = counts
        availableSubjects = Array(Set(built.map(\.lessonSubject))).filter { !$0.isEmpty }.sorted()
        availableStudents = students.map { (id: $0.id, name: "\($0.firstName) \($0.lastName.prefix(1)).") }
    }

    func advanceStage(presentationID: UUID, context: ModelContext) {
        let descriptor = FetchDescriptor<LessonPresentation>(
            predicate: #Predicate { $0.id == presentationID }
        )
        guard let pres = context.safeFetch(descriptor).first else { return }

        let nextState: LessonPresentationState
        switch pres.state {
        case .presented:
            nextState = .practicing
        case .practicing:
            nextState = .readyForAssessment
        case .readyForAssessment:
            nextState = .proficient
            pres.masteredAt = Date()
        case .proficient:
            return
        }

        pres.state = nextState
        pres.lastObservedAt = Date()
        context.safeSave()
        loadData(context: context)
    }
}
