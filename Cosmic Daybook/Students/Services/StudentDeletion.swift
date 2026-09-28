//
//  StudentDeletion.swift
//  Cosmic Daybook
//
//  Everything that goes when a child is deleted.
//
//  Almost nothing points at a student through a relationship: some thirty
//  kinds of record carry her id as a string, alone (`studentID`) or in a list
//  (`studentIDs`). `context.delete(student)` therefore cascades nothing, and a
//  delete that stops there leaves attendance, presentations, notes, meetings
//  and work naming a child who no longer exists — rows every screen then has
//  to skip or show as "Unknown".
//
//  The rule has two halves. A record that is hers alone goes with her. A
//  record she shares — a group presentation, a note about several children, a
//  todo, a project — loses her and stays for everyone else, and is deleted
//  only when she was the last child on it and it means nothing without one.
//
//  Nothing here saves; `StudentRepository.deleteStudent` does, and rolls the
//  whole change back if the save fails.
//

import CoreData
import Foundation
import OSLog

/// How many records of each kind a student deletion removed or edited.
struct StudentDeletionReport: Equatable {
    /// Rows deleted, by entity name.
    var deleted: [String: Int] = [:]
    /// Shared rows she was taken off, by entity name.
    var detached: [String: Int] = [:]
    /// On-disk files of her documents, removed once the deletion is saved.
    var documentFiles: [URL] = []

    var deletedTotal: Int { deleted.values.reduce(0, +) }
    var detachedTotal: Int { detached.values.reduce(0, +) }

    fileprivate mutating func countDeleted(_ entity: String, _ count: Int = 1) {
        guard count > 0 else { return }
        deleted[entity, default: 0] += count
    }

    fileprivate mutating func countDetached(_ entity: String, _ count: Int = 1) {
        guard count > 0 else { return }
        detached[entity, default: 0] += count
    }

    var logLine: String {
        let parts = deleted.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }
        let edits = detached.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }
        return "deleted [\(parts.joined(separator: ", "))] detached [\(edits.joined(separator: ", "))]"
    }
}

enum StudentDeletion {

    private static let logger = Logger.students

    /// Entities whose rows belong to one child through a `studentID` string
    /// and go with her. Documents, notes, work, meetings and the student row
    /// itself need more than a delete and are handled separately.
    static let ownedEntities = [
        "AttendanceRecord",
        "LessonPresentation",
        "StudentTrackEnrollment",
        "DevelopmentSnapshot",
        "ScheduleSlot",
        "WorkCompletionRecord",
        "JobAssignment",
        "TransitionPlan",
        "ProjectWeekRoleAssignment",
        "StudentFocusItem",
        "ScheduledMeeting",
        "YearPlanEntry",
        "WorkCycleEntry",
        "Guardian",
        "ParentCommunication",
        "LessonRecallCheck"
    ]

    /// Deletes every student row with `studentID` (a CloudKit duplicate
    /// included) and everything that is hers alone, and takes her off every
    /// record she shares. Does not save.
    static func deleteEverything(for studentID: UUID, in context: NSManagedObjectContext) -> StudentDeletionReport {
        var report = StudentDeletionReport()
        let idString = studentID.uuidString

        // Work first: `WorkDeletionService` resolves ownership and linked
        // copies from participant rows and completion records that the
        // owned-entity sweep below would otherwise delete out from under it.
        detachFromWork(studentID, in: context, report: &report)

        for entity in ownedEntities {
            for row in fetch(entity, studentID: idString, in: context) {
                context.delete(row)
                report.countDeleted(entity)
            }
        }

        // Her meetings take their notes and work reviews with them (cascade).
        for meeting in fetch("StudentMeeting", studentID: idString, in: context) {
            context.delete(meeting)
            report.countDeleted("StudentMeeting")
        }

        for row in fetch("Document", studentID: idString, in: context) {
            if let document = row as? CDDocument,
               let url = StudentDocumentFileStorage.resolveURL(
                   bookmark: document.pdfFileBookmark,
                   relativePath: document.pdfFileRelativePath
               ) {
                report.documentFiles.append(url)
            }
            context.delete(row)
            report.countDeleted("Document")
        }

        detachFromNotes(studentID, in: context, report: &report)
        detachFromSharedLists(studentID, in: context, report: &report)

        let students = CDFetchRequest(CDStudent.self)
        students.predicate = NSPredicate(format: "id == %@", studentID as CVarArg)
        for student in context.safeFetch(students) {
            context.delete(student)
            report.countDeleted("Student")
        }

        logger.notice("Student deletion: \(report.logLine, privacy: .public)")
        return report
    }

    // MARK: - Work

    private static func detachFromWork(
        _ studentID: UUID, in context: NSManagedObjectContext, report: inout StudentDeletionReport
    ) {
        let idString = studentID.uuidString
        let owned = CDFetchRequest(CDWorkModel.self)
        owned.predicate = NSPredicate(format: "studentID ==[c] %@", idString)
        let participantRows = CDFetchRequest(CDWorkParticipantEntity.self)
        participantRows.predicate = NSPredicate(format: "studentID ==[c] %@", idString)

        var works = context.safeFetch(owned)
        works += context.safeFetch(participantRows).compactMap(\.work)
        var seen = Set<NSManagedObjectID>()
        works = works.filter { seen.insert($0.objectID).inserted }
        guard !works.isEmpty else { return }

        let before = works.filter { !$0.isDeleted }.count
        WorkDeletionService.removeWithoutSaving(studentID: studentID, from: works, in: context)
        let deleted = works.filter(\.isDeleted).count
        report.countDeleted("WorkModel", deleted)
        report.countDetached("WorkModel", before - deleted)
    }

    // MARK: - Notes

    /// A note about her alone goes; a note about several children loses her,
    /// and goes only if she was the last one it named.
    private static func detachFromNotes(
        _ studentID: UUID, in context: NSManagedObjectContext, report: inout StudentDeletionReport
    ) {
        let idString = studentID.uuidString
        let single = CDFetchRequest(CDNote.self)
        single.predicate = NSPredicate(format: "searchIndexStudentID == %@", studentID as CVarArg)
        var notes = context.safeFetch(single)

        let links = CDFetchRequest(CDNoteStudentLink.self)
        links.predicate = NSPredicate(format: "studentID ==[c] %@", idString)
        notes += context.safeFetch(links).compactMap(\.note)

        // Multi-child notes written before links were kept have neither
        // field; their scope is the only record of who they are about.
        let multi = CDFetchRequest(CDNote.self)
        multi.predicate = NSPredicate(format: "scopeIsAll == NO AND searchIndexStudentID == nil")
        notes += context.safeFetch(multi).filter { $0.scope.names(studentID) }

        var seen = Set<NSManagedObjectID>()
        for note in notes where seen.insert(note.objectID).inserted && !note.isDeleted {
            switch note.scope {
            case .all:
                continue
            case .student(let id):
                guard id == studentID else { continue }
                context.delete(note)
                report.countDeleted("Note")
            case .students(let ids):
                let remaining = ids.filter { $0 != studentID }
                if remaining.isEmpty {
                    context.delete(note)
                    report.countDeleted("Note")
                } else {
                    note.scope = remaining.count == 1 ? .student(remaining[0]) : .students(remaining)
                    note.syncStudentLinks(in: context)
                    report.countDetached("Note")
                }
            }
        }

        // Links left behind by a scope edit that never synced them.
        for link in context.safeFetch(links) where !link.isDeleted {
            context.delete(link)
        }
    }

    // MARK: - Shared lists

    private static func detachFromSharedLists(
        _ studentID: UUID, in context: NSManagedObjectContext, report: inout StudentDeletionReport
    ) {
        let idString = studentID.uuidString
        detachFromPresentations(idString, in: context, report: &report)

        // Group records with nobody left on them mean nothing and go.
        detach(idString, from: \CDIssue.studentIDs,
               deleteWhenEmpty: true, in: context, report: &report)
        detach(idString, from: \CDPlanningRecommendation.studentIDs,
               deleteWhenEmpty: true, in: context, report: &report)
        detach(idString, from: \CDPracticeSession.studentIDsArray,
               deleteWhenEmpty: true, in: context, report: &report)

        // The rest stand without her: a todo, a template, an outing or a
        // project is still the guide's with no child on it.
        detach(idString, from: \CDTodoItem.studentIDsArray,
               deleteWhenEmpty: false, in: context, report: &report)
        detach(idString, from: \CDTodoTemplate.defaultStudentIDsArray,
               deleteWhenEmpty: false, in: context, report: &report)
        detach(idString, from: \CDGoingOut.studentIDsArray,
               deleteWhenEmpty: false, in: context, report: &report)
        detach(idString, from: \CDProject.memberStudentIDsArray,
               deleteWhenEmpty: false, in: context, report: &report)
        detachFromSingleFields(studentID, in: context, report: &report)
    }

    /// A presentation with nobody left on it is a lesson given to no one; it
    /// goes, and its notes cascade with it.
    private static func detachFromPresentations(
        _ idString: String, in context: NSManagedObjectContext, report: inout StudentDeletionReport
    ) {
        for assignment in context.safeFetch(CDFetchRequest(CDLessonAssignment.self)) {
            let roster = removing(idString, from: assignment.studentIDs)
            let confirmed = removing(idString, from: assignment.confirmedStudentIDs)
            guard roster != nil || confirmed != nil else { continue }
            if let roster, roster.isEmpty {
                context.delete(assignment)
                report.countDeleted("LessonAssignment")
            } else {
                if let roster { assignment.studentIDs = roster }
                if let confirmed { assignment.confirmedStudentIDs = confirmed }
                report.countDetached("LessonAssignment")
            }
        }
    }

    /// Fields that name one child on a record that stands without her.
    private static func detachFromSingleFields(
        _ studentID: UUID, in context: NSManagedObjectContext, report: inout StudentDeletionReport
    ) {
        let idString = studentID.uuidString
        let checklist = CDFetchRequest(CDGoingOutChecklistItem.self)
        checklist.predicate = NSPredicate(format: "assignedToStudentID ==[c] %@", idString)
        for item in context.safeFetch(checklist) {
            item.assignedToStudentID = nil
            report.countDetached("GoingOutChecklistItem")
        }
        for session in context.safeFetch(CDFetchRequest(CDBookClubSession.self))
        where session.studentIDs.contains(studentID) {
            session.studentIDs = session.studentIDs.filter { $0 != studentID }
            report.countDetached("BookClubSession")
        }
        let led = CDFetchRequest(CDBookClubMeeting.self)
        led.predicate = NSPredicate(format: "leaderStudentID ==[c] %@", idString)
        for meeting in context.safeFetch(led) {
            meeting.leaderStudentID = ""
            report.countDetached("BookClubMeeting")
        }
    }

    /// Takes her off `list` on every `T` that names her, deleting a row left
    /// with nobody when `deleteWhenEmpty`.
    private static func detach<T: NSManagedObject>(
        _ idString: String,
        from list: ReferenceWritableKeyPath<T, [String]>,
        deleteWhenEmpty: Bool,
        in context: NSManagedObjectContext,
        report: inout StudentDeletionReport
    ) {
        for row in context.safeFetch(CDFetchRequest(T.self)) {
            guard let remaining = removing(idString, from: row[keyPath: list]) else { continue }
            let entity = row.entity.name ?? String(describing: T.self)
            if remaining.isEmpty && deleteWhenEmpty {
                context.delete(row)
                report.countDeleted(entity)
            } else {
                row[keyPath: list] = remaining
                report.countDetached(entity)
            }
        }
    }

    // MARK: - Helpers

    private static func fetch(
        _ entity: String, studentID: String, in context: NSManagedObjectContext
    ) -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: entity)
        request.predicate = NSPredicate(format: "studentID ==[c] %@", studentID)
        return context.safeFetch(request)
    }

    /// `ids` without `idString`, or nil when `ids` never named her.
    private static func removing(_ idString: String, from ids: [String]) -> [String]? {
        let remaining = ids.filter { $0.caseInsensitiveCompare(idString) != .orderedSame }
        return remaining.count == ids.count ? nil : remaining
    }
}

private extension NoteScope {
    func names(_ studentID: UUID) -> Bool {
        switch self {
        case .all: false
        case .student(let id): id == studentID
        case .students(let ids): ids.contains(studentID)
        }
    }
}
