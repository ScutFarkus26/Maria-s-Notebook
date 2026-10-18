import Foundation
import CoreData

// MARK: - Checklist Matrix Builder

/// Builds the matrix of student/lesson states for the checklist grid.
/// Computes status for each cell based on LessonAssignments and WorkModels.
enum ChecklistMatrixBuilder {

    typealias Matrix = [UUID: [UUID: StudentChecklistRowState]]

    // MARK: - Build Matrix

    /// Builds the matrix of states for all students and lessons.
    ///
    /// - Parameters:
    ///   - students: Students to include in the matrix
    ///   - lessons: Lessons to include in the matrix
    ///   - context: Model context for fetching data
    /// - Returns: Dictionary mapping student ID -> lesson ID -> state
    static func buildMatrix(
        students: [CDStudent],
        lessons: [CDLesson],
        context: NSManagedObjectContext
    ) -> Matrix {
        guard lessons.contains(where: { $0.id != nil }) else { return [:] }
        let precedingLessonMap = BlockingAlgorithmEngine.buildPrecedingLessonCache(lessons)
        var matrix: Matrix = [:]
        for student in students {
            guard let studentID = student.id else { continue }
            matrix[studentID] = [:]
        }
        fillRows(
            &matrix, rowLessons: lessons, students: students,
            precedingLessonMap: precedingLessonMap, context: context
        )
        return matrix
    }

    // MARK: - Rebuild Rows

    /// Recomputes, in place, the rows a change to `touchedLessonIDs` can reach: each touched
    /// lesson's own row and the rows of the lessons that follow one in its sequence (their
    /// blocking reason reads the touched lesson's records). Only those lessons and their
    /// predecessors are fetched. The result is exactly what `buildMatrix` would give for those
    /// rows; every other row is left as it was.
    ///
    /// - Parameter lessons: The whole area, so "preceding lesson" means what it does in a full build.
    static func rebuildRows(
        in matrix: inout Matrix,
        touching touchedLessonIDs: Set<UUID>,
        students: [CDStudent],
        lessons: [CDLesson],
        context: NSManagedObjectContext
    ) {
        guard !touchedLessonIDs.isEmpty else { return }
        let precedingLessonMap = BlockingAlgorithmEngine.buildPrecedingLessonCache(lessons)
        let rowLessons = lessons.filter { lesson in
            guard let lessonID = lesson.id else { return false }
            if touchedLessonIDs.contains(lessonID) { return true }
            guard let precedingID = precedingLessonMap[lessonID]?.id else { return false }
            return touchedLessonIDs.contains(precedingID)
        }
        guard !rowLessons.isEmpty else { return }
        fillRows(
            &matrix, rowLessons: rowLessons, students: students,
            precedingLessonMap: precedingLessonMap, context: context
        )
    }

    /// Writes one state per (student, row lesson) into `matrix`, fetching the row lessons'
    /// records once, indexed by student, plus the row lessons' mastery marks in one more
    /// fetch, and the predecessors' record, work and recall checks for the readiness rule
    /// (`ReadyForNextEngine.readiness(of:)`) in a few more.
    private static func fillRows(
        _ matrix: inout Matrix,
        rowLessons: [CDLesson],
        students: [CDStudent],
        precedingLessonMap: [UUID: CDLesson],
        context: NSManagedObjectContext
    ) {
        let rowIDs = Set(rowLessons.compactMap { $0.id?.uuidString })
        var precedingIDs = Set<String>()
        var rowPrecedingMap: [UUID: CDLesson] = [:]
        for lesson in rowLessons {
            guard let lessonID = lesson.id else { continue }
            if let preceding = precedingLessonMap[lessonID] {
                rowPrecedingMap[lessonID] = preceding
                if let precedingID = preceding.id { precedingIDs.insert(precedingID.uuidString) }
            }
        }
        guard !rowIDs.isEmpty || !precedingIDs.isEmpty else { return }
        let records = loadRecords(rowIDs: rowIDs, context: context)
        let readiness = PrecedingReadiness(
            precedingIDs: precedingIDs, students: students, context: context
        )

        // Pre-compute staleness threshold date once instead of per-cell
        let calendar = AppCalendar.shared
        let today = calendar.startOfDay(for: Date())

        for student in students {
            guard let studentID = student.id else { continue }
            let studentKey = student.cloudKitKey
            var studentRow = matrix[studentID] ?? [:]
            for lesson in rowLessons {
                guard let lessonID = lesson.id else { continue }
                let lessonIDString = lessonID.uuidString
                let studentLAs = records.assignments[lessonIDString]?[studentKey] ?? []
                let studentWorks = records.works[lessonIDString]?[studentKey] ?? []

                // Only a cell not yet presented can be held back by the lesson before it,
                // and a plan the guide unlocked isn't, as in Presentations.
                let isPresented = studentLAs.contains { $0.isPresented }
                let isUnlocked = studentLAs.contains { !$0.isPresented && $0.manuallyUnblocked }
                let verdict = isPresented || isUnlocked ? CellReadiness.ready : readiness.cell(
                    precedingLessonID: rowPrecedingMap[lessonID]?.id?.uuidString, studentID: studentID
                )

                studentRow[lessonID] = buildCellState(
                    lesson: lesson,
                    studentLAs: studentLAs,
                    studentWorkModels: studentWorks,
                    calendar: calendar,
                    today: today,
                    blockingReason: verdict.blockingReason,
                    isMastered: records.masteryMarks[lessonIDString]?.contains(studentKey) ?? false,
                    checkFirstReasons: verdict.checkFirstReasons
                )
            }
            matrix[studentID] = studentRow
        }
    }

    // MARK: - Private Helpers

    /// A batch's assignments and work, by lesson ID string and then by student key, and
    /// the row lessons' mastery marks (lesson ID string → student keys).
    private struct LessonRecordIndex {
        let assignments: [String: [String: [CDLessonAssignment]]]
        let works: [String: [String: [CDWorkModel]]]
        let masteryMarks: [String: Set<String>]
    }

    /// The row lessons' records, in one fetch per entity, plus their mastery marks.
    private static func loadRecords(rowIDs: Set<String>, context: NSManagedObjectContext) -> LessonRecordIndex {
        let fetchIDs = Array(rowIDs)
        let assignments = fetchAssignments(lessonIDs: fetchIDs, context: context)
        let works = fetchWorks(lessonIDs: fetchIDs, context: context)
        return LessonRecordIndex(
            assignments: assignmentsByLesson(assignments),
            works: worksByLesson(works, visibility: WorkVisibility(rows: works)),
            masteryMarks: PresentationRecordIndex.masteryMarks(lessonIDs: rowIDs, in: context)
        )
    }

    // MARK: - Readiness

    /// What the readiness rule says about one unplanned cell, as the cell carries it.
    private struct CellReadiness {
        let blockingReason: BlockingReason
        let checkFirstReasons: [String]

        static let ready = CellReadiness(blockingReason: .none, checkFirstReasons: [])
    }

    /// The lesson before each row, read for the one readiness rule the Groups page and
    /// Today read (`ReadyForNextEngine.readiness(of:)`), so the checklist's Ready and
    /// "Not yet" can't disagree with them. Until 2026-10-18 this was the planner's rule
    /// (`BlockingAlgorithmEngine.readiness`), which the Inbox keeps for its drafts.
    ///
    /// Reads the predecessors' record for these children, and their work and recall
    /// checks, once for the whole batch.
    private struct PrecedingReadiness {
        let index: PresentationRecordIndex
        let record: PreviousLessonRecord

        init(precedingIDs: Set<String>, students: [CDStudent], context: NSManagedObjectContext) {
            let studentIDs = Set(students.compactMap { $0.id?.uuidString })
            guard !precedingIDs.isEmpty, !studentIDs.isEmpty else {
                index = PresentationRecordIndex(rows: PresentationRecordIndex.RecordRows(), students: [])
                record = PreviousLessonRecord(pairs: [], in: context)
                return
            }
            let index = PresentationRecordIndex(lessonIDs: precedingIDs, students: studentIDs, in: context)
            var pairs: [PreviousLessonRecord.Pair] = []
            for lessonID in precedingIDs {
                for studentID in (index.givenByLesson[lessonID] ?? [:]).keys {
                    pairs.append(PreviousLessonRecord.Pair(studentID: studentID, lessonID: lessonID))
                }
            }
            self.index = index
            record = PreviousLessonRecord(pairs: pairs, in: context)
        }

        /// Ready (with what to check first, if anything) or why not. The first lesson of a
        /// sequence (no preceding lesson) is always ready.
        func cell(precedingLessonID: String?, studentID: UUID) -> CellReadiness {
            guard let precedingLessonID else { return .ready }
            let student = studentID.uuidString
            guard let given = index.given(student: student, lesson: precedingLessonID) else {
                return CellReadiness(blockingReason: .prerequisiteNotPresented, checkFirstReasons: [])
            }
            let verdict = ReadyForNextEngine.readiness(
                of: record.status(student: student, lesson: precedingLessonID, given: given)
            )
            switch verdict.tier {
            case .notReady: return CellReadiness(blockingReason: .confirmationRequired, checkFirstReasons: [])
            case .almostReady: return CellReadiness(blockingReason: .none, checkFirstReasons: verdict.reasons)
            case .ready: return .ready
            }
        }
    }

    // MARK: - Cells

    /// Internal (not private) so the equivalence test can drive the legacy path through it.
    static func buildCellState(
        lesson: CDLesson,
        studentLAs: [CDLessonAssignment],
        studentWorkModels: [CDWorkModel],
        calendar: Calendar,
        today: Date,
        blockingReason: BlockingReason = .none,
        isMastered: Bool = false,
        checkFirstReasons: [String] = []
    ) -> StudentChecklistRowState {
        let nonPresented = studentLAs.filter { !$0.isPresented }
        let plannedCandidate = nonPresented.first
        let isScheduled = !nonPresented.isEmpty
        let isInboxPlan = isScheduled && (plannedCandidate?.scheduledFor == nil)
        let isPresented = studentLAs.contains { $0.isPresented }

        let workModelForLesson = cellWork(studentWorkModels)
        let isActive = workModelForLesson?.isOpen ?? false
        let isComplete = workModelForLesson?.status.isClosed == true
        let isWorkActive = studentWorkModels.contains { $0.status == WorkStatus.active }
        let isWorkReview = studentWorkModels.contains { $0.status == WorkStatus.review }

        // Compute staleness using pre-computed calendar & today (avoids per-cell allocation)
        let lastActivityDate = workModelForLesson?.lastTouchedAt ?? workModelForLesson?.createdAt
        let isStale = !isComplete && isStale(lastActivity: lastActivityDate, calendar: calendar, today: today)

        return StudentChecklistRowState(
            lessonID: lesson.id ?? UUID(),
            plannedItemID: plannedCandidate?.id,
            presentationLogID: nil,
            contractID: workModelForLesson?.id,
            isScheduled: isScheduled,
            isPresented: isPresented,
            isActive: isActive,
            isComplete: isComplete,
            isWorkActive: isWorkActive,
            isWorkReview: isWorkReview,
            lastActivityDate: lastActivityDate,
            isStale: isStale,
            isInboxPlan: isInboxPlan,
            blockingReason: blockingReason,
            isMastered: isMastered,
            checkFirstReasons: checkFirstReasons
        )
    }

    /// The one work row a cell reads its rung and staleness from: open work (Working or
    /// Needs Review) over closed, then the most recently touched. The fetch has no order,
    /// so taking `.first` let an old closed row hide new practice depending on the store.
    static func cellWork(_ works: [CDWorkModel]) -> CDWorkModel? {
        works.max { lhs, rhs in
            if lhs.status.isClosed != rhs.status.isClosed { return lhs.status.isClosed }
            let lhsDate = lastActivity(lhs), rhsDate = lastActivity(rhs)
            if lhsDate != rhsDate { return lhsDate < rhsDate }
            return (lhs.id?.uuidString ?? "") < (rhs.id?.uuidString ?? "")
        }
    }

    private static func lastActivity(_ work: CDWorkModel) -> Date {
        work.lastTouchedAt ?? work.completedAt ?? work.createdAt ?? .distantPast
    }
}

// MARK: - Batched Reads

extension ChecklistMatrixBuilder {

    /// One fetch for the lessons asked for (it used to be one per lesson).
    private static func fetchAssignments(lessonIDs: [String], context: NSManagedObjectContext) -> [CDLessonAssignment] {
        let request: NSFetchRequest<CDLessonAssignment> = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "lessonID IN %@", lessonIDs)
        return context.safeFetch(request)
    }

    /// Same for work, with participants prefetched so indexing doesn't fault a
    /// to-many relationship per work. Every row of each lesson, open and closed,
    /// which is what telling a linked copy from a shared row needs.
    private static func fetchWorks(lessonIDs: [String], context: NSManagedObjectContext) -> [CDWorkModel] {
        let request: NSFetchRequest<CDWorkModel> = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(format: "lessonID IN %@", lessonIDs)
        request.relationshipKeyPathsForPrefetching = ["participants"]
        return context.safeFetch(request)
    }

    /// Assignments indexed by lesson and then by student key. Each student's list
    /// keeps fetch order — the order its own `lessonID ==` fetch returned — so
    /// `.first` picks the same row as before; each assignment's students are
    /// decoded once, and no cell filters a lesson's list.
    private static func assignmentsByLesson(
        _ assignments: [CDLessonAssignment]
    ) -> [String: [String: [CDLessonAssignment]]] {
        var result: [String: [String: [CDLessonAssignment]]] = [:]
        for la in assignments {
            for studentKey in Set(la.studentIDs) {
                result[la.lessonID, default: [:]][studentKey, default: []].append(la)
            }
        }
        return result
    }

    /// Work indexed by lesson and then by the children each row counts for: a
    /// set of linked copies only for each copy's owner, a genuinely shared row
    /// for everyone on it (`WorkVisibility`). Filing a row under every
    /// participant showed a classmate's open copy as the child's own.
    private static func worksByLesson(
        _ works: [CDWorkModel], visibility: WorkVisibility
    ) -> [String: [String: [CDWorkModel]]] {
        var result: [String: [String: [CDWorkModel]]] = [:]
        for work in works {
            for studentID in WorkGrouping.studentIDs(of: work) where visibility.isVisible(work, to: studentID) {
                result[work.lessonID, default: [:]][studentID.uuidString, default: []].append(work)
            }
        }
        return result
    }
}
