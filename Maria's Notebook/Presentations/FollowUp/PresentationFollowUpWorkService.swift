import CoreData
import Foundation

/// Creates the child's explicitly named work after a presentation.
///
/// Guide follow-up (watch, check, support, or plan next) remains a separate
/// responsibility. This service only creates `CDWorkModel` rows, which makes
/// the child's work immediately available to the existing Open Work screen.
struct PresentationFollowUpWorkService {
    struct CreationResult {
        struct Item {
            let studentID: UUID
            let work: CDWorkModel
            let wasCreated: Bool
        }

        let items: [Item]

        var works: [CDWorkModel] {
            items.map(\.work)
        }

        var created: [CDWorkModel] {
            items.compactMap { $0.wasCreated ? $0.work : nil }
        }

        var existing: [CDWorkModel] {
            items.compactMap { $0.wasCreated ? nil : $0.work }
        }

        var createdCount: Int { created.count }
        var existingCount: Int { existing.count }
    }

    struct CheckInResult {
        struct Item {
            let studentID: UUID
            let work: CDWorkModel
            let checkIn: CDWorkCheckIn
            let wasCreated: Bool
            let wasRescheduled: Bool
        }

        let items: [Item]
        let rowsWithoutLinkedWork: [CDLessonPresentation]

        var created: [CDWorkCheckIn] {
            items.compactMap { $0.wasCreated ? $0.checkIn : nil }
        }

        var existing: [CDWorkCheckIn] {
            items.compactMap { $0.wasCreated ? nil : $0.checkIn }
        }

        var createdCount: Int { created.count }
        var existingCount: Int { existing.count }
        var rescheduledCount: Int { items.filter(\.wasRescheduled).count }
    }

    enum ServiceError: LocalizedError, Equatable {
        case emptyTitle
        case noChildrenSelected
        case rowOutsidePresentation
        case rowOutsideLesson
        case invalidStudentID
        case saveFailed

        var errorDescription: String? {
            switch self {
            case .emptyTitle:
                return "Describe the work before adding it."
            case .noChildrenSelected:
                return "Choose at least one child for this work."
            case .rowOutsidePresentation:
                return "This child is not part of the presentation being followed."
            case .rowOutsideLesson:
                return "This child’s presentation does not match this lesson."
            case .invalidStudentID:
                return "One of the selected children could not be identified."
            case .saveFailed:
                return "The follow-up work could not be saved."
            }
        }
    }

    let context: NSManagedObjectContext

    /// Adds one Open Work item per child in `rows`.
    ///
    /// Repeating the same submission returns the already-open item instead of
    /// inserting a duplicate. A different title or kind remains a distinct,
    /// intentional piece of work.
    @discardableResult
    func createWork(
        title: String,
        kind: WorkKind,
        for rows: [CDLessonPresentation],
        presentationID: UUID,
        lessonID: UUID,
        sampleWorkID: UUID? = nil,
        persist: (() -> Bool)? = nil
    ) throws -> CreationResult {
        let storedTitle = title.trimmed()
        guard !storedTitle.isEmpty else { throw ServiceError.emptyTitle }

        let studentIDs = try validatedStudentIDs(
            in: rows,
            presentationID: presentationID,
            lessonID: lessonID
        )
        guard !studentIDs.isEmpty else { throw ServiceError.noChildrenSelected }

        let repository = WorkRepository(context: context)
        var candidates = linkedOpenWork(
            for: rows,
            presentationID: presentationID,
            lessonID: lessonID
        )
        let transaction = ContextMutationTransaction(context: context)
        var items: [CreationResult.Item] = []

        do {
            for studentID in studentIDs {
                if let existing = candidates.first(where: {
                    isDuplicate(
                        $0,
                        title: storedTitle,
                        kind: kind,
                        studentID: studentID,
                        presentationID: presentationID,
                        lessonID: lessonID
                    )
                }) {
                    items.append(.init(
                        studentID: studentID,
                        work: existing,
                        wasCreated: false
                    ))
                    continue
                }

                let work = try repository.createWork(
                    studentID: studentID,
                    lessonID: lessonID,
                    title: storedTitle,
                    kind: kind,
                    presentationID: presentationID,
                    sampleWorkID: sampleWorkID,
                    saveImmediately: false
                )
                work.sourceContextType = .presentation
                work.sourceContextID = presentationID.uuidString

                candidates.append(work)
                items.append(.init(
                    studentID: studentID,
                    work: work,
                    wasCreated: true
                ))
            }
        } catch {
            transaction.rollback()
            throw error
        }

        guard items.contains(where: \.wasCreated) else {
            transaction.commit()
            return CreationResult(items: items)
        }

        let didSave = persist?() ?? context.safeSave()
        guard didSave else {
            transaction.rollback()
            throw ServiceError.saveFailed
        }

        transaction.commit()
        return CreationResult(items: items)
    }

    /// Returns the work that the existing Open Work screen will consider open,
    /// limited to the exact presentation, lesson, and selected children.
    func linkedOpenWork(
        for rows: [CDLessonPresentation],
        presentationID: UUID,
        lessonID: UUID
    ) -> [CDWorkModel] {
        let studentIDs = Set(rows.compactMap { row -> String? in
            guard row.presentationID.flatMap(UUID.init(uuidString:)) == presentationID,
                  UUID(uuidString: row.lessonID) == lessonID,
                  let studentID = UUID(uuidString: row.studentID) else {
                return nil
            }
            return studentID.uuidString
        })
        guard !studentIDs.isEmpty else { return [] }

        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(
            format: "presentationID == %@ AND lessonID == %@ AND studentID IN %@ AND statusRaw != %@",
            presentationID.uuidString,
            lessonID.uuidString,
            Array(studentIDs),
            WorkStatus.complete.rawValue
        )
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \CDWorkModel.createdAt, ascending: false)
        ]
        return context.safeFetch(request).uniqueByID
    }

    /// Schedules the guide's requested review for every distinct work item the
    /// selected children actually have from this presentation.
    ///
    /// It deliberately does not invent generic practice work. Children without
    /// linked work are returned to the caller so the sheet can explain what still
    /// needs attention. Each work item reuses its existing pending check-in,
    /// moving that check-in when the guide chooses a different review day.
    @discardableResult
    func scheduleCheckIns(
        for rows: [CDLessonPresentation],
        presentationID: UUID,
        lessonID: UUID,
        calendar: Calendar = AppCalendar.shared,
        persist: (() -> Bool)? = nil
    ) throws -> CheckInResult {
        _ = try validatedStudentIDs(
            in: rows,
            presentationID: presentationID,
            lessonID: lessonID
        )

        let eligibleRows = rows.filter {
            $0.followUpAction == .checkWork && $0.followUpReviewAt != nil
        }
        guard !eligibleRows.isEmpty else {
            return CheckInResult(items: [], rowsWithoutLinkedWork: [])
        }

        let linkedWork = linkedOpenWork(
            for: eligibleRows,
            presentationID: presentationID,
            lessonID: lessonID
        )
        let workByStudentID = Dictionary(grouping: linkedWork, by: \.studentID)
        let checkInService = WorkCheckInService(context: context)
        let transaction = ContextMutationTransaction(context: context)
        var items: [CheckInResult.Item] = []
        var rowsWithoutLinkedWork: [CDLessonPresentation] = []
        var handledWorkDays = Set<String>()
        var didMutate = false

        do {
            for row in eligibleRows {
                guard let studentID = UUID(uuidString: row.studentID),
                      let reviewAt = row.followUpReviewAt else {
                    continue
                }
                let works = workByStudentID[studentID.uuidString] ?? []
                guard !works.isEmpty else {
                    if !rowsWithoutLinkedWork.contains(where: { $0.objectID == row.objectID }) {
                        rowsWithoutLinkedWork.append(row)
                    }
                    continue
                }

                let reviewDay = calendar.startOfDay(for: reviewAt)
                for work in works {
                    let workKey = work.id?.uuidString ?? work.objectID.uriRepresentation().absoluteString
                    let dayKey = "\(workKey)|\(reviewDay.timeIntervalSinceReferenceDate)"
                    guard handledWorkDays.insert(dayKey).inserted else { continue }

                    let scheduled = scheduledCheckIns(for: work)
                    if let existing = scheduled.first(where: {
                        calendar.isDate($0.date ?? .distantPast, inSameDayAs: reviewDay)
                    }) ?? scheduled.first {
                        if existing.work !== work {
                            existing.work = work
                            work.addToCheckIns(existing)
                            didMutate = true
                        }
                        let wasRescheduled = !calendar.isDate(
                            existing.date ?? .distantPast,
                            inSameDayAs: reviewDay
                        )
                        if wasRescheduled {
                            try checkInService.reschedule(existing, to: reviewDay)
                            didMutate = true
                        }
                        items.append(.init(
                            studentID: studentID,
                            work: work,
                            checkIn: existing,
                            wasCreated: false,
                            wasRescheduled: wasRescheduled
                        ))
                        continue
                    }

                    let checkIn = try checkInService.createCheckIn(
                        for: work,
                        date: reviewDay,
                        purpose: "Review \(work.title)"
                    )
                    didMutate = true
                    items.append(.init(
                        studentID: studentID,
                        work: work,
                        checkIn: checkIn,
                        wasCreated: true,
                        wasRescheduled: false
                    ))
                }
            }
        } catch {
            transaction.rollback()
            throw error
        }

        guard didMutate else {
            transaction.commit()
            return CheckInResult(
                items: items,
                rowsWithoutLinkedWork: rowsWithoutLinkedWork
            )
        }

        let didSave = persist?() ?? context.safeSave()
        guard didSave else {
            transaction.rollback()
            throw ServiceError.saveFailed
        }

        transaction.commit()
        return CheckInResult(
            items: items,
            rowsWithoutLinkedWork: rowsWithoutLinkedWork
        )
    }
}

private extension PresentationFollowUpWorkService {
    func validatedStudentIDs(
        in rows: [CDLessonPresentation],
        presentationID: UUID,
        lessonID: UUID
    ) throws -> [UUID] {
        var seen = Set<UUID>()
        var studentIDs: [UUID] = []

        for row in rows {
            guard row.presentationID.flatMap(UUID.init(uuidString:)) == presentationID else {
                throw ServiceError.rowOutsidePresentation
            }
            guard UUID(uuidString: row.lessonID) == lessonID else {
                throw ServiceError.rowOutsideLesson
            }
            guard let studentID = UUID(uuidString: row.studentID) else {
                throw ServiceError.invalidStudentID
            }
            if seen.insert(studentID).inserted {
                studentIDs.append(studentID)
            }
        }

        return studentIDs
    }

    func isDuplicate(
        _ work: CDWorkModel,
        title: String,
        kind: WorkKind,
        studentID: UUID,
        presentationID: UUID,
        lessonID: UUID
    ) -> Bool {
        work.status != .complete
            && work.studentID == studentID.uuidString
            && work.presentationID == presentationID.uuidString
            && work.lessonID == lessonID.uuidString
            && work.kind == kind
            && normalizedTitle(work.title) == normalizedTitle(title)
    }

    func normalizedTitle(_ title: String) -> String {
        title
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
    }

    func scheduledCheckIns(for work: CDWorkModel) -> [CDWorkCheckIn] {
        var candidates = (work.checkIns?.allObjects as? [CDWorkCheckIn]) ?? []

        if let workID = work.id?.uuidString {
            let request = CDFetchRequest(CDWorkCheckIn.self)
            request.predicate = NSPredicate(
                format: "workID == %@ AND statusRaw == %@",
                workID,
                WorkCheckInStatus.scheduled.rawValue
            )
            request.sortDescriptors = [
                NSSortDescriptor(keyPath: \CDWorkCheckIn.date, ascending: true)
            ]
            candidates.append(contentsOf: context.safeFetch(request))
        }

        var seen = Set<NSManagedObjectID>()
        return candidates
            .filter { $0.status == .scheduled }
            .filter { seen.insert($0.objectID).inserted }
            .sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }
}

/// Captures only the Core Data mutations made by one service operation.
///
/// The view context can already contain the guide's unsaved notes or edits, so
/// `rollback()` would be too broad. A temporary undo manager restores inserts,
/// updates, relationships, and deletes made after this transaction begins while
/// leaving the context's earlier pending changes alone.
private final class ContextMutationTransaction {
    private let context: NSManagedObjectContext
    private let previousUndoManager: UndoManager?
    private let operationUndoManager = UndoManager()
    private var isFinished = false

    init(context: NSManagedObjectContext) {
        self.context = context
        context.processPendingChanges()
        previousUndoManager = context.undoManager
        operationUndoManager.groupsByEvent = false
        context.undoManager = operationUndoManager
        operationUndoManager.beginUndoGrouping()
    }

    func commit() {
        guard !isFinished else { return }
        finishCapturing()
        operationUndoManager.removeAllActions()
        restorePreviousUndoManager()
    }

    func rollback() {
        guard !isFinished else { return }
        finishCapturing()
        if operationUndoManager.canUndo {
            operationUndoManager.undo()
            context.processPendingChanges()
        }
        operationUndoManager.removeAllActions()
        restorePreviousUndoManager()
    }

    private func finishCapturing() {
        context.processPendingChanges()
        if operationUndoManager.groupingLevel > 0 {
            operationUndoManager.endUndoGrouping()
        }
        isFinished = true
    }

    private func restorePreviousUndoManager() {
        context.undoManager = previousUndoManager
    }
}
