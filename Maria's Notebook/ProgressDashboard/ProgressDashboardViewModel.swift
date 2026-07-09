// ProgressDashboardViewModel.swift
// Loads per-student progression data for the map-style dashboard.
//
// For every enrolled student, finds the subjects (lesson.area) and sequences (lesson.sequence)
// the student has "started" — meaning at least one of: a presented assignment, a scheduled or
// draft assignment, or an active (non-complete) work item. Within each sequence, every lesson
// becomes a pill with its progression status derived the same way StudentAreaProgressionViewModel
// derives it: presentation present → presented/practicing/reviewing/completed based on work;
// no presentation but scheduled → scheduled; otherwise → notStarted.

import Foundation
import CoreData
import OSLog

@Observable
@MainActor
final class ProgressDashboardViewModel {
    private static let logger = Logger.app_

    // MARK: - Outputs

    private(set) var studentCards: [StudentProgressionCard] = []
    private(set) var isLoading = false

    // MARK: - Filters

    var searchText: String = ""
    var levelFilter: LevelFilter = .all

    var filteredCards: [StudentProgressionCard] {
        var cards = studentCards

        if levelFilter != .all {
            cards = cards.filter { levelFilter.matches($0.level) }
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            cards = cards.filter { card in
                card.firstName.lowercased().contains(query) ||
                card.lastName.lowercased().contains(query) ||
                (card.nickname?.lowercased().contains(query) ?? false)
            }
        }

        return cards
    }

    // MARK: - Data Loading

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    func loadData(context: NSManagedObjectContext) {
        isLoading = true
        defer { isLoading = false }

        let allStudents = fetchAllStudents(context: context)
        let allLessons = fetchAllLessons(context: context)
        let allAssignments = fetchAllAssignments(context: context)
        let allWork = fetchAllWork(context: context)

        let visibleStudents = TestStudentsFilter.filterVisible(allStudents)

        // Build an O(1) lookup dictionary once — replaces allLessons.first(where:) linear
        // scans that ran O(assignments × lessons) and O(work × lessons) per student.
        let lessonByID: [UUID: CDLesson] = Dictionary(
            allLessons.compactMap { l -> (UUID, CDLesson)? in
                guard let id = l.id else { return nil }
                return (id, l)
            },
            uniquingKeysWith: { first, _ in first }
        )

        // Group lessons by area+sequence using display casing.
        struct AreaSeqKey: Hashable { let area: String; let sequence: String }
        let lessonsByPair: [AreaSeqKey: [CDLesson]] = Dictionary(
            grouping: allLessons.filter { !$0.area.trimmed().isEmpty && !$0.sequence.trimmed().isEmpty },
            by: { AreaSeqKey(area: $0.area.trimmed(), sequence: $0.sequence.trimmed()) }
        )

        // Cards
        var cards: [StudentProgressionCard] = []

        for student in visibleStudents {
            guard let studentID = student.id else { continue }
            let studentIDStr = studentID.uuidString

            let assignmentsForStudent = allAssignments.filter { $0.studentIDs.contains(studentIDStr) }
            let workForStudent = allWork.filter { $0.studentID == studentIDStr }
            let openWorkByLesson = Dictionary(
                grouping: workForStudent.filter { $0.status != .complete },
                by: { $0.lessonID }
            )
            let workByLesson = Dictionary(grouping: workForStudent) { $0.lessonID }

            // Find every (area, sequence) pair this student is active in.
            var activePairs = Set<AreaSeqKey>()

            // From assignments (both presented and pending).
            for la in assignmentsForStudent {
                guard let lessonIDUUID = la.lessonIDUUID,
                      let lesson = lessonByID[lessonIDUUID] else { continue }
                let area = lesson.area.trimmed()
                let sequence = lesson.sequence.trimmed()
                guard !area.isEmpty, !sequence.isEmpty else { continue }
                activePairs.insert(AreaSeqKey(area: area, sequence: sequence))
            }

            // From open (non-complete) work items.
            for work in workForStudent where work.status != .complete {
                guard let lessonIDUUID = UUID(uuidString: work.lessonID),
                      let lesson = lessonByID[lessonIDUUID] else { continue }
                let area = lesson.area.trimmed()
                let sequence = lesson.sequence.trimmed()
                guard !area.isEmpty, !sequence.isEmpty else { continue }
                activePairs.insert(AreaSeqKey(area: area, sequence: sequence))
            }

            guard !activePairs.isEmpty else { continue }

            // Build SequenceProgression for every active pair.
            var sequencesByArea: [String: [SequenceProgression]] = [:]

            for pair in activePairs {
                guard let lessonsInSequence = lessonsByPair[pair] else { continue }
                let sortedLessons = lessonsInSequence.sorted { $0.orderInSequence < $1.orderInSequence }

                var pills: [LessonPillState] = []
                for lesson in sortedLessons {
                    guard let lessonID = lesson.id else { continue }
                    let lessonIDStr = lessonID.uuidString

                    // "Previously Presented" records are deliberately undated (state ==
                    // .presented, presentedAt == nil), so match on state as well — a
                    // date-only check renders bulk-marked historical lessons as Not Started.
                    let presentation = assignmentsForStudent.first {
                        $0.lessonID == lessonIDStr && ($0.isPresented || $0.presentedAt != nil)
                    }
                    let scheduledPresentation = assignmentsForStudent.first {
                        $0.lessonID == lessonIDStr && $0.isScheduled
                    }
                    let lessonWork = workByLesson[lessonIDStr] ?? []
                    let openLessonWork = openWorkByLesson[lessonIDStr] ?? []

                    let status: LessonNodeStatus = Self.resolveStatus(
                        presentation: presentation,
                        scheduledPresentation: scheduledPresentation,
                        lessonWork: lessonWork,
                        openLessonWork: openLessonWork
                    )

                    pills.append(LessonPillState(
                        id: lessonID,
                        lessonID: lessonID,
                        name: lesson.name,
                        status: status,
                        orderInSequence: Int(lesson.orderInSequence)
                    ))
                }

                guard !pills.isEmpty else { continue }

                let sequenceProgression = SequenceProgression(
                    id: "\(studentID)|\(pair.area)|\(pair.sequence)",
                    studentID: studentID,
                    area: pair.area,
                    sequence: pair.sequence,
                    pills: pills
                )

                sequencesByArea[pair.area, default: []].append(sequenceProgression)
            }

            // Sort sequences within each subject alphabetically.
            let subjects: [SubjectProgression] = sequencesByArea
                .map { area, seqs in
                    SubjectProgression(
                        id: "\(studentID)|\(area)",
                        area: area,
                        sequences: seqs.sorted {
                            $0.sequence.localizedCaseInsensitiveCompare($1.sequence) == .orderedAscending
                        }
                    )
                }
                .sorted { $0.area.localizedCaseInsensitiveCompare($1.area) == .orderedAscending }

            cards.append(StudentProgressionCard(
                id: studentID,
                firstName: student.firstName,
                lastName: student.lastName,
                nickname: student.nickname,
                level: student.level,
                subjects: subjects
            ))
        }

        studentCards = cards
    }

    // MARK: - Status Resolution

    /// Same shape as StudentAreaProgressionViewModel so colors and labels stay consistent.
    private static func resolveStatus(
        presentation: CDLessonAssignment?,
        scheduledPresentation: CDLessonAssignment?,
        lessonWork: [CDWorkModel],
        openLessonWork: [CDWorkModel]
    ) -> LessonNodeStatus {
        if presentation != nil {
            let allComplete = !lessonWork.isEmpty && lessonWork.allSatisfy { $0.status == .complete }
            let hasReview = lessonWork.contains { $0.status == .review }
            let hasActive = !openLessonWork.isEmpty

            if allComplete {
                return .completed
            } else if hasReview {
                return .reviewing
            } else if hasActive {
                return .practicing
            } else {
                return .presented
            }
        } else if let scheduled = scheduledPresentation, let date = scheduled.scheduledFor {
            return .scheduled(date)
        } else {
            return .notStarted
        }
    }

    // MARK: - Fetching

    private func fetchAllStudents(context: NSManagedObjectContext) -> [CDStudent] {
        let request = NSFetchRequest<CDStudent>(entityName: "Student")
        request.sortDescriptors = CDStudent.sortByName
        return context.safeFetch(request).filterEnrolled()
    }

    private func fetchAllLessons(context: NSManagedObjectContext) -> [CDLesson] {
        let request = NSFetchRequest<CDLesson>(entityName: "Lesson")
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \CDLesson.area, ascending: true),
            NSSortDescriptor(keyPath: \CDLesson.sequence, ascending: true),
            NSSortDescriptor(keyPath: \CDLesson.orderInSequence, ascending: true)
        ]
        request.fetchBatchSize = 200
        return context.safeFetch(request)
    }

    private func fetchAllAssignments(context: NSManagedObjectContext) -> [CDLessonAssignment] {
        let request = NSFetchRequest<CDLessonAssignment>(entityName: "LessonAssignment")
        request.fetchBatchSize = 200
        return context.safeFetch(request)
    }

    private func fetchAllWork(context: NSManagedObjectContext) -> [CDWorkModel] {
        let request = NSFetchRequest<CDWorkModel>(entityName: "WorkModel")
        request.fetchBatchSize = 200
        return context.safeFetch(request)
    }
}
