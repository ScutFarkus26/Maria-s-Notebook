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
    /// records and their predecessors' (for the blocking reason) once, indexed by student,
    /// plus the row lessons' mastery marks in one more fetch, and the work on the
    /// predecessors' presentations in one more.
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
        let records = loadRecords(rowIDs: rowIDs, precedingIDs: precedingIDs, context: context)
        let rulesMap = progressionRules(for: rowPrecedingMap, context: context)

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

                // Only a cell not yet presented can be blocked by the lesson before it,
                // and a plan the guide unlocked isn't blocked, as in Presentations
                // (BlockingAlgorithmEngine.checkBlocking).
                let isPresented = studentLAs.contains { $0.isPresented }
                let isUnlocked = studentLAs.contains { !$0.isPresented && $0.manuallyUnblocked }
                let blockingReason: BlockingReason = isPresented || isUnlocked ? .none : computeBlockingReason(
                    precedingLesson: rowPrecedingMap[lessonID], rules: rulesMap[lessonID],
                    studentID: studentID, records: records
                )

                studentRow[lessonID] = buildCellState(
                    lesson: lesson,
                    studentLAs: studentLAs,
                    studentWorkModels: studentWorks,
                    calendar: calendar,
                    today: today,
                    blockingReason: blockingReason,
                    isMastered: records.masteryMarks[lessonIDString]?.contains(studentKey) ?? false
                )
            }
            matrix[studentID] = studentRow
        }
    }

    /// Rules for each lesson's predecessor. The sequence-settings lookup is
    /// shared by every predecessor filed under the same area + sequence, so it
    /// runs once per pair instead of once per lesson.
    private static func progressionRules(
        for precedingLessonMap: [UUID: CDLesson],
        context: NSManagedObjectContext
    ) -> [UUID: LessonProgressionRules.ResolvedRules] {
        var rules: [UUID: LessonProgressionRules.ResolvedRules] = [:]
        var settingsByGroup: [SettingsKey: CDLessonSequenceSettings?] = [:]
        for (lessonID, preceding) in precedingLessonMap {
            rules[lessonID] = LessonProgressionRules.resolve(for: preceding) {
                let key = SettingsKey(area: preceding.area, sequence: preceding.sequence)
                if let cached = settingsByGroup[key] { return cached }
                let found = CDLessonSequenceSettings.find(
                    area: preceding.area, sequence: preceding.sequence, context: context
                )
                settingsByGroup[key] = .some(found)
                return found
            }
        }
        return rules
    }

    // MARK: - Private Helpers

    /// A batch's assignments and work, by lesson ID string and then by student key, the
    /// row lessons' mastery marks (lesson ID string → student keys), and what the
    /// readiness rule reads for the predecessors: their givings by lesson ID string,
    /// and the work on those givings by presentation ID string.
    private struct LessonRecordIndex {
        let assignments: [String: [String: [CDLessonAssignment]]]
        let works: [String: [String: [CDWorkModel]]]
        let masteryMarks: [String: Set<String>]
        let precedingGivings: [String: [CDLessonAssignment]]
        let precedingWork: [String: [CDWorkModel]]
    }

    /// Exact (case-preserving) area + sequence, the arguments `find` receives.
    private struct SettingsKey: Hashable {
        let area: String
        let sequence: String
    }

    /// The row lessons' records and their predecessors', in one fetch per
    /// entity, plus the row lessons' mastery marks and the work on the
    /// predecessors' givings.
    private static func loadRecords(
        rowIDs: Set<String>, precedingIDs: Set<String>, context: NSManagedObjectContext
    ) -> LessonRecordIndex {
        let fetchIDs = Array(rowIDs.union(precedingIDs))
        let assignments = fetchAssignments(lessonIDs: fetchIDs, context: context)
        let works = fetchWorks(lessonIDs: fetchIDs, context: context)
        let precedingGivings = presentedGivings(in: assignments, lessonIDs: precedingIDs)
        return LessonRecordIndex(
            assignments: assignmentsByLesson(assignments),
            works: worksByLesson(works, visibility: WorkVisibility(rows: works)),
            masteryMarks: PresentationRecordIndex.masteryMarks(lessonIDs: rowIDs, in: context),
            precedingGivings: precedingGivings,
            precedingWork: workByPresentationID(on: precedingGivings, context: context)
        )
    }

    // MARK: - Readiness

    /// Why a child isn't ready for a lesson yet, by the planner's own rule
    /// (`BlockingAlgorithmEngine.readiness`), so the checklist's "Not yet" and
    /// Presentations' Ready can't disagree. This used to be an older copy of
    /// that rule: it read the first giving in fetch order, took a confirmation
    /// only on that one, read no work as needing practice, and counted a
    /// classmate's copy. The first lesson of a sequence (no preceding lesson)
    /// is never blocked.
    private static func computeBlockingReason(
        precedingLesson: CDLesson?,
        rules: LessonProgressionRules.ResolvedRules?,
        studentID: UUID,
        records: LessonRecordIndex
    ) -> BlockingReason {
        guard let precedingLesson, let rules, rules.requiresPractice || rules.requiresTeacherConfirmation else {
            return .none
        }

        let givings = BlockingAlgorithmEngine.givings(
            for: studentID, among: records.precedingGivings[precedingLesson.id?.uuidString ?? ""] ?? []
        )
        guard !givings.isEmpty else {
            // Preceding lesson hasn't been presented to this student
            return .prerequisiteNotPresented
        }

        let readiness = BlockingAlgorithmEngine.readiness(
            of: studentID, givings: givings, rules: rules, workByPresentationID: records.precedingWork
        ).readiness
        switch (readiness.workComplete, readiness.teacherConfirmed) {
        case (false, false): return .practiceAndConfirmation
        case (false, true): return .practiceRequired
        case (true, false): return .confirmationRequired
        case (true, true): return .none
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
        isMastered: Bool = false
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
            isMastered: isMastered
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

    /// The given presentations of `lessonIDs`, by lesson: what the planner's
    /// readiness rule reads a child's givings from.
    private static func presentedGivings(
        in assignments: [CDLessonAssignment], lessonIDs: Set<String>
    ) -> [String: [CDLessonAssignment]] {
        var result: [String: [CDLessonAssignment]] = [:]
        for la in assignments where la.isPresented && lessonIDs.contains(la.lessonID) {
            result[la.lessonID, default: []].append(la)
        }
        return result
    }

    /// The work on those presentations, open and closed, by presentation id.
    /// The rule needs the closed rows: a child whose practice is done has only
    /// closed work there, and with open work alone she read as having none.
    private static func workByPresentationID(
        on givings: [String: [CDLessonAssignment]], context: NSManagedObjectContext
    ) -> [String: [CDWorkModel]] {
        let presentationIDs = Set(givings.values.joined().compactMap { $0.id?.uuidString })
        guard !presentationIDs.isEmpty else { return [:] }
        let request: NSFetchRequest<CDWorkModel> = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(format: "presentationID IN %@", Array(presentationIDs))
        request.relationshipKeyPathsForPrefetching = ["participants"]
        return Dictionary(grouping: context.safeFetch(request)) { $0.presentationID ?? "" }
    }
}
