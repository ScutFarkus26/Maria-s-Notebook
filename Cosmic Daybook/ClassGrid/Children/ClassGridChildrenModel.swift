// ClassGridChildrenModel.swift
// Loads per-student progression data for the Class Grid's Children view (once the
// Progress Dashboard's view model).
//
// For every enrolled student, finds the subjects (lesson.area) and sequences (lesson.sequence)
// the student has "started" — meaning at least one of: a presented assignment, a scheduled or
// draft assignment, or an active (non-complete) work item. Within each sequence, every lesson
// becomes a mark with its status by the Checklist's rule (`LessonNodeStatus.resolve`, drawn as
// `ChecklistDisplayStatus`), as StudentAreaProgressionViewModel does: only a mastery mark is
// Mastered, closed work without one is Reviewing; a plan waiting undated in the inbox is Planned.
// The area menu, search and children filter narrow the cards (`groups`), grouped by level.

import Foundation
import CoreData
import OSLog

@Observable
final class ClassGridChildrenModel {
    // MARK: - Outputs

    private(set) var studentCards: [StudentProgressionCard] = []
    private(set) var isLoading = false

    // MARK: - Filters

    /// One level's children, in the attendance roll's level order.
    struct LevelGroup: Identifiable {
        let level: AttendanceEmailLevel
        let cards: [StudentProgressionCard]
        var id: String { level.rawValue }
    }

    /// The cards the Class Grid's filters leave, grouped by level: only the strips in
    /// `area` (nil for all), only children whose name matches `query`, only `childIDs`
    /// (empty for all). A child with no strip left goes.
    func groups(area: String?, query: String, childIDs: Set<UUID>) -> [LevelGroup] {
        let areaKey = area.map(ClassGridEngine.filingKey)
        let tokens = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        let cards: [StudentProgressionCard] = studentCards.compactMap { card in
            if !childIDs.isEmpty, !childIDs.contains(card.id) { return nil }
            if !tokens.isEmpty {
                let names = [card.firstName, card.lastName, card.nickname ?? ""].joined(separator: " ").lowercased()
                guard tokens.allSatisfy(names.contains) else { return nil }
            }
            guard let areaKey else { return card }
            let narrowed = card.keepingSubjects { ClassGridEngine.filingKey($0.area) == areaKey }
            return narrowed.subjects.isEmpty ? nil : narrowed
        }
        return AttendanceLevelGroups.grouped(cards, level: \.level).map {
            LevelGroup(level: $0.level, cards: $0.items)
        }
    }

    // MARK: - Data Loading

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    func loadData(context: NSManagedObjectContext) {
        isLoading = true
        defer { isLoading = false }

        let queries = DataQueryService(context: context)
        let visibleStudents = queries.fetchAllStudents(
            excludeTest: true, excludeWithdrawn: true, sortBy: CDStudent.sortByName
        )
        let allLessons = queries.fetchAllLessons(sortBy: CDLesson.sortByCurriculumOrder, batchSize: 200)
        let allAssignments = fetchAllAssignments(context: context)
        let allWork = fetchAllWork(context: context)

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
        // lessonID → the children with a mastery mark on it: the Checklist's "Mastered".
        let masteryMarks = PresentationRecordIndex.masteryMarks(
            lessonIDs: Set(lessonsByPair.values.joined().compactMap { $0.id?.uuidString }), in: context
        )

        // Each assignment's studentIDs blob decoded once, not once per student;
        // each student's slice keeps the fetch order the per-student filter had.
        let assignmentsByStudent = Self.groupByStudent(allAssignments)
        let workByStudent = Self.groupByStudent(allWork, visibility: WorkVisibility(rows: allWork))

        // Cards
        var cards: [StudentProgressionCard] = []
        let today = Date()
        let calendar = AppCalendar.shared

        for student in visibleStudents {
            guard let studentID = student.id else { continue }
            let studentIDStr = studentID.uuidString

            let assignmentsForStudent = assignmentsByStudent[studentIDStr] ?? []
            let workForStudent = workByStudent[studentIDStr] ?? []
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
            for work in workForStudent where work.status.isOpen {
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
                    // Planned and not yet given: on a day, or a draft in the inbox.
                    let planned = assignmentsForStudent.filter {
                        $0.lessonID == lessonIDStr && !$0.isPresented && $0.presentedAt == nil
                    }
                    let status = ChecklistDisplayStatus(LessonNodeStatus.resolve(
                        isPresented: presentation != nil,
                        scheduledFor: planned.compactMap(\.scheduledFor).min(),
                        isPlanned: !planned.isEmpty,
                        isMastered: masteryMarks[lessonIDStr]?.contains(studentIDStr) ?? false,
                        workStatuses: (workByLesson[lessonIDStr] ?? []).map(\.status)
                    ))

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
                yearInClass: student.dateStarted.map {
                    CurriculumTimeline.enrollmentYear(anchor: $0, on: today, calendar: calendar)
                },
                subjects: subjects
            ))
        }

        studentCards = cards
    }

    // MARK: - Grouping

    /// studentID → the assignments naming her, in `assignments` order — the
    /// same rows, in the same order, as `assignments.filter { $0.studentIDs.contains(id) }`,
    /// with each assignment listed once however often its roster names her.
    static func groupByStudent(_ assignments: [CDLessonAssignment]) -> [String: [CDLessonAssignment]] {
        var grouped: [String: [CDLessonAssignment]] = [:]
        for assignment in assignments {
            for studentID in Set(assignment.studentIDs) {
                grouped[studentID, default: []].append(assignment)
            }
        }
        return grouped
    }

    /// studentID → the work that counts as hers, by the Checklist's rule
    /// (`WorkVisibility`): the rows she owns, and a shared row she is on (project
    /// work: one row, several children) even though another child owns it. Filing
    /// work by owner alone left a child's shared project work off her card (bug
    /// hunt 2026-10-29 #16); a classmate's linked copy that names her still isn't hers.
    static func groupByStudent(_ works: [CDWorkModel], visibility: WorkVisibility) -> [String: [CDWorkModel]] {
        var grouped: [String: [CDWorkModel]] = [:]
        for work in works {
            for studentID in WorkGrouping.studentIDs(of: work) where visibility.isVisible(work, to: studentID) {
                grouped[studentID.uuidString, default: []].append(work)
            }
        }
        return grouped
    }

    // MARK: - Fetching

    private func fetchAllAssignments(context: NSManagedObjectContext) -> [CDLessonAssignment] {
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.fetchBatchSize = 200
        return context.safeFetch(request)
    }

    /// Every row, open and closed, with who is on it: a child's closed copy is what
    /// tells her classmate's open copy apart from a row she shares.
    private func fetchAllWork(context: NSManagedObjectContext) -> [CDWorkModel] {
        let request = CDFetchRequest(CDWorkModel.self)
        request.fetchBatchSize = 200
        request.relationshipKeyPathsForPrefetching = ["participants"]
        return context.safeFetch(request).filter { !$0.isDeleted }
    }
}
