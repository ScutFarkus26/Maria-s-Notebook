//
//  PresentationRecordIndex+Rows.swift
//  Cosmic Daybook
//
//  The columns the index folds, and the two ways of reading them.
//
//  The fold needs a handful of columns from three tables. The whole-record
//  build (Today's ready queue after any change to its inputs, the MCP
//  `students_ready` and `mastery_candidates` sweeps, the inbox sheet's
//  one-child record) used to fetch every CDLessonPresentation,
//  CDLessonAssignment and CDYearPlanEntry as a managed object on the calling
//  context, usually the view context: every column of a few thousand rows
//  faulted in and registered there until the run loop's pool let them go
//  (2,563 objects and about 2 MB at April's size). A dictionary fetch of just
//  those columns reads the same rows without making a managed object.
//
//  A dictionary fetch reads the store, not the context, so it can stand in
//  for the objects only when the context holds no unsaved insert, update or
//  delete of the three entities. That is the split the dedup pre-checks make
//  (`DataCleanupService.sameNameLessonObjectIDs`), narrowed to the entities
//  read here through `ManagedObjectChangeFlag.hasPendingChanges`. With such an
//  edit pending, in a child context, and for every lesson-scoped build (a
//  handful of rows, which the regive guard turns back into objects), the
//  managed-object read runs as it always has. Either reader hands the one
//  fold the same plain rows, in fetch order.
//

import CoreData
import Foundation
import OSLog

nonisolated extension PresentationRecordIndex {

    // MARK: - Rows

    /// One `CDLessonPresentation`: one child, one lesson.
    struct PresentationRow: Sendable, Equatable {
        let studentID: String
        let lessonID: String
        let presentedAt: Date?
        /// `masteredAt` is set, or the state is proficient.
        let mastered: Bool
    }

    /// One `CDLessonAssignment`: one lesson and the children on it.
    struct AssignmentRow: Sendable, Equatable {
        let objectID: NSManagedObjectID
        let lessonID: String
        let studentIDs: [String]
        let isPresented: Bool
        let presentedAt: Date?
        /// Empty on an unpresented row, which the fold never asks about.
        let confirmedStudentIDs: [String]
        /// The day and time it is planned for; nil on an undated draft.
        let scheduledFor: Date?
    }

    /// One `CDYearPlanEntry`.
    struct PlanEntryRow: Sendable, Equatable {
        let studentID: String
        let lessonID: String
        let isSkipped: Bool
        /// Promoted to a presentation, which then speaks for the plan.
        let isPromoted: Bool
        let plannedDate: Date?
    }

    /// The three tables' rows, each in its fetch's order.
    struct RecordRows: Sendable, Equatable {
        var presentations: [PresentationRow] = []
        var assignments: [AssignmentRow] = []
        var planEntries: [PlanEntryRow] = []
    }

    /// Where a build reads its rows from.
    enum ReadPath: Sendable, Equatable {
        /// Managed objects through the context, unsaved edits included.
        case objects
        /// Dictionary rows from the store; nothing is registered in the context.
        case columns
    }

    // MARK: - Choosing a Path

    /// `.columns` for a whole-record build on a context that reads straight
    /// from its coordinator and holds no unsaved edit to the three entities;
    /// `.objects` otherwise. Call on `context`'s queue.
    static func readPath(lessonIDs: Set<String>?, in context: NSManagedObjectContext) -> ReadPath {
        guard lessonIDs == nil, context.parent == nil else { return .objects }
        let entityNames = Set([
            CDFetchRequest(CDLessonPresentation.self).entityName,
            CDFetchRequest(CDLessonAssignment.self).entityName,
            CDFetchRequest(CDYearPlanEntry.self).entityName
        ].compactMap { $0 })
        return ManagedObjectChangeFlag.hasPendingChanges(to: entityNames, in: context) ? .objects : .columns
    }

    /// The rows for a build. A column read that fails falls back to the
    /// object read, the old path unchanged (a failed fetch there logs and
    /// reads nothing, as it always did).
    static func readRows(lessonIDs: Set<String>?, in context: NSManagedObjectContext) -> RecordRows {
        if readPath(lessonIDs: lessonIDs, in: context) == .columns, let rows = readColumns(in: context) {
            return rows
        }
        return readObjects(lessonIDs: lessonIDs, in: context)
    }

    // MARK: - Managed Objects

    /// Every row of the three entities (or of the scoped lessons) as managed
    /// objects through `context`, unsaved edits included.
    static func readObjects(lessonIDs: Set<String>?, in context: NSManagedObjectContext) -> RecordRows {
        let presentations = fetchObjects(CDLessonPresentation.self, lessonIDs: lessonIDs, in: context).map { row in
            PresentationRow(
                studentID: row.studentID,
                lessonID: row.lessonID,
                presentedAt: row.presentedAt,
                mastered: row.masteredAt != nil || row.state == .proficient
            )
        }
        let assignments = fetchObjects(CDLessonAssignment.self, lessonIDs: lessonIDs, in: context).map { row in
            AssignmentRow(
                objectID: row.objectID,
                lessonID: row.lessonID,
                studentIDs: row.studentIDs,
                isPresented: row.isPresented,
                presentedAt: row.presentedAt,
                confirmedStudentIDs: row.isPresented ? row.confirmedStudentIDs : [],
                scheduledFor: row.scheduledFor
            )
        }
        let planEntries = fetchObjects(CDYearPlanEntry.self, lessonIDs: lessonIDs, in: context).map { row in
            PlanEntryRow(
                studentID: row.studentID,
                lessonID: row.lessonID,
                isSkipped: row.status == .skipped,
                isPromoted: row.status == .promoted,
                plannedDate: row.plannedDate
            )
        }
        return RecordRows(presentations: presentations, assignments: assignments, planEntries: planEntries)
    }

    private static func fetchObjects<T: NSManagedObject>(
        _ type: T.Type, lessonIDs: Set<String>?, in context: NSManagedObjectContext
    ) -> [T] {
        let request = CDFetchRequest(T.self)
        if let lessonIDs {
            request.predicate = NSPredicate(format: "lessonID IN %@", Array(lessonIDs))
        }
        return context.safeFetch(request).filter { !$0.isDeleted }
    }

    // MARK: - Columns

    /// The attribute names read, as the model spells them.
    private enum Column {
        static let objectID = "objectID"
        static let studentID = "studentID"
        static let lessonID = "lessonID"
        static let presentedAt = "presentedAt"
        static let masteredAt = "masteredAt"
        static let stateRaw = "stateRaw"
        static let statusRaw = "statusRaw"
        static let scheduledFor = "scheduledFor"
        static let plannedDate = "plannedDate"
        static let studentIDsData = "_studentIDsData"
        static let confirmedStudentIDsData = "_confirmedStudentIDsData"
    }

    /// Every row of the three entities as dictionaries of the columns the
    /// fold reads, straight from the store. Nil when a fetch fails or a row
    /// comes back without its object ID.
    static func readColumns(in context: NSManagedObjectContext) -> RecordRows? {
        let objectID = NSExpressionDescription()
        objectID.name = Column.objectID
        objectID.expression = NSExpression.expressionForEvaluatedObject()
        objectID.expressionResultType = .objectIDAttributeType

        guard let presentationRows = fetchColumns(
                CDLessonPresentation.self,
                [Column.studentID, Column.lessonID, Column.presentedAt, Column.masteredAt, Column.stateRaw],
                in: context
              ),
              let assignmentRows = fetchColumns(
                CDLessonAssignment.self,
                [objectID, Column.lessonID, Column.stateRaw, Column.presentedAt,
                 Column.studentIDsData, Column.confirmedStudentIDsData, Column.scheduledFor],
                in: context
              ),
              let planEntryRows = fetchColumns(
                CDYearPlanEntry.self,
                [Column.studentID, Column.lessonID, Column.statusRaw, Column.plannedDate],
                in: context
              )
        else { return nil }

        var assignments: [AssignmentRow] = []
        assignments.reserveCapacity(assignmentRows.count)
        for row in assignmentRows {
            guard let assignment = assignmentRow(row) else { return nil }
            assignments.append(assignment)
        }
        return RecordRows(
            presentations: presentationRows.map(presentationRow),
            assignments: assignments,
            planEntries: planEntryRows.map(planEntryRow)
        )
    }

    /// The entity's accessors, over a dictionary row: `state` reads an
    /// unknown raw value as presented.
    private static func presentationRow(_ row: NSDictionary) -> PresentationRow {
        let state = LessonPresentationState(rawValue: string(row, Column.stateRaw)) ?? .presented
        return PresentationRow(
            studentID: string(row, Column.studentID),
            lessonID: string(row, Column.lessonID),
            presentedAt: row[Column.presentedAt] as? Date,
            mastered: row[Column.masteredAt] is Date || state == .proficient
        )
    }

    /// `state` reads an unknown raw value as a draft; the ID lists decode
    /// with the entity's own decoder.
    private static func assignmentRow(_ row: NSDictionary) -> AssignmentRow? {
        guard let objectID = row[Column.objectID] as? NSManagedObjectID else { return nil }
        let isPresented = (LessonAssignmentState(rawValue: string(row, Column.stateRaw)) ?? .draft) == .presented
        return AssignmentRow(
            objectID: objectID,
            lessonID: string(row, Column.lessonID),
            studentIDs: CloudKitStringArrayStorage.decode(from: row[Column.studentIDsData] as? Data),
            isPresented: isPresented,
            presentedAt: row[Column.presentedAt] as? Date,
            confirmedStudentIDs: isPresented
                ? CloudKitStringArrayStorage.decode(from: row[Column.confirmedStudentIDsData] as? Data)
                : [],
            scheduledFor: row[Column.scheduledFor] as? Date
        )
    }

    /// `status` reads an unknown raw value as planned.
    private static func planEntryRow(_ row: NSDictionary) -> PlanEntryRow {
        let status = YearPlanEntryStatus(rawValue: string(row, Column.statusRaw)) ?? .planned
        return PlanEntryRow(
            studentID: string(row, Column.studentID),
            lessonID: string(row, Column.lessonID),
            isSkipped: status == .skipped,
            isPromoted: status == .promoted,
            plannedDate: row[Column.plannedDate] as? Date
        )
    }

    /// A dictionary row leaves a NULL column out; the entity's non-optional
    /// `String` accessor reads the same NULL as "".
    private static func string(_ row: NSDictionary, _ column: String) -> String {
        row[column] as? String ?? ""
    }

    private static func fetchColumns<T: NSManagedObject>(
        _ type: T.Type, _ columns: [Any], in context: NSManagedObjectContext
    ) -> [NSDictionary]? {
        guard let entityName = CDFetchRequest(type).entityName else { return nil }
        let request = NSFetchRequest<NSDictionary>(entityName: entityName)
        request.resultType = .dictionaryResultType
        // What a dictionary fetch does anyway: it reads the store, never the
        // context's unsaved changes, which is why `readPath` checks for them.
        request.includesPendingChanges = false
        request.propertiesToFetch = columns
        do {
            return try context.fetch(request)
        } catch {
            let reason = error.localizedDescription
            Logger.database.error(
                "PresentationRecordIndex: \(entityName, privacy: .public) columns failed (\(reason, privacy: .public))"
            )
            return nil
        }
    }
}
