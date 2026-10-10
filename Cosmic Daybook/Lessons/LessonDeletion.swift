//
//  LessonDeletion.swift
//  Cosmic Daybook
//
//  Everything that goes, and everything that stays, when a lesson is deleted.
//
//  Nothing points at a lesson through a relationship except its attachments
//  and sample works: presentations, work and year-plan entries carry its id
//  as a string. `context.delete(lesson)` alone left planned presentations,
//  open work and year-plan entries behind, which Today then showed as
//  "Lesson" (bug hunt 2026-10-10, #46).
//
//  Danny's rule (2026-10-10): the guide is asked first, told what goes.
//  - Planned (not yet given) presentations go, through
//    `PresentationRecordCleanup` as any presentation delete does; a mastery
//    mark filed on one is kept as a mark of its own.
//  - Open work goes through `WorkDeletionService`, with its notes.
//  - The lesson's year-plan entries go.
//  - Given presentations and the mastery history (`CDLessonPresentation`)
//    stay: they happened. A given presentation keeps the lesson's name in
//    `lessonTitleSnapshot`, so it still reads right.
//  - Closed work stays, as history.
//  - Sequence- and area-wide attachments move to a sibling lesson in the same
//    sequence or area, so the rest of it keeps them; with no sibling they go.
//  - The lesson's files are trashed only after the save, and only when no
//    other record points at them (`LessonFileStorage+Removal`).
//
//  Nothing here saves; `LessonRepository.deleteLesson` does, and rolls the
//  whole change back if the save fails.
//

import CoreData
import Foundation

/// What a lesson delete will change, built before anything is touched so the
/// confirmation can name it.
struct LessonDeletionPlan {
    /// Every row with the lesson's id (a CloudKit duplicate included).
    var lessons: [CDLesson] = []
    var plannedPresentations: [CDLessonAssignment] = []
    var givenPresentations: [CDLessonAssignment] = []
    var openWork: [CDWorkModel] = []
    var yearPlanEntries: [CDYearPlanEntry] = []
    /// Notes that go with the planned presentations and the open work.
    var notes = 0
    /// Sequence- and area-wide attachments, each with the lesson it moves to.
    var handedOver: [(attachment: CDLessonAttachment, heir: CDLesson)] = []
    /// Relative paths of the files that leave with the lesson: its Pages file
    /// and the attachments that go with it.
    var filePaths: [String] = []

    var summary: LessonDeletionSummary {
        LessonDeletionSummary(
            plannedPresentations: plannedPresentations.count,
            openWork: openWork.count,
            yearPlanEntries: yearPlanEntries.count,
            notes: notes,
            givenPresentations: givenPresentations.count,
            files: filePaths.count,
            handedOver: handedOver.count
        )
    }
}

/// The counts the confirmation names, and its words.
struct LessonDeletionSummary: Equatable {
    var plannedPresentations = 0
    var openWork = 0
    var yearPlanEntries = 0
    var notes = 0
    var givenPresentations = 0
    var files = 0
    var handedOver = 0

    /// "It also removes 3 planned presentations, 2 open work items, 4 year-plan
    /// entries, and 5 notes written on them. …". `trashesFiles` is false in the
    /// Sample Class, where nothing on disk is touched.
    func message(trashesFiles: Bool) -> String {
        var going: [String] = []
        if plannedPresentations > 0 {
            going.append(Self.count(plannedPresentations, "planned presentation", "planned presentations"))
        }
        if openWork > 0 { going.append(Self.count(openWork, "open work item", "open work items")) }
        if yearPlanEntries > 0 {
            going.append(Self.count(yearPlanEntries, "year-plan entry", "year-plan entries"))
        }
        if notes > 0, !going.isEmpty { going.append(Self.count(notes, "note", "notes") + " written on them") }

        var sentences: [String] = []
        if !going.isEmpty {
            sentences.append("It also removes \(ListFormatter.localizedString(byJoining: going)).")
        }
        if givenPresentations > 0 {
            sentences.append("Presentations already given stay in each child's history.")
        }
        if handedOver > 0 {
            sentences.append("Files shared with its sequence or area stay with the other lessons.")
        }
        if files > 0, trashesFiles {
            sentences.append("Its own files go to the Trash.")
        }
        sentences.append("This can't be undone.")
        return sentences.joined(separator: " ")
    }

    private static func count(_ value: Int, _ one: String, _ many: String) -> String {
        "\(value) \(value == 1 ? one : many)"
    }
}

enum LessonDeletion {

    /// Gathers what deleting the lesson with `lessonID` changes. Touches nothing.
    static func plan(for lessonID: UUID, in context: NSManagedObjectContext) -> LessonDeletionPlan {
        var plan = LessonDeletionPlan()
        let lessonRequest = CDFetchRequest(CDLesson.self)
        lessonRequest.predicate = NSPredicate(format: "id == %@", lessonID as CVarArg)
        plan.lessons = context.safeFetch(lessonRequest).filter { !$0.isDeleted }
        guard !plan.lessons.isEmpty else { return plan }

        let idString = lessonID.uuidString
        let byLesson = NSPredicate(format: "lessonID ==[c] %@", idString)

        let assignments = fetch(CDLessonAssignment.self, byLesson, in: context)
        plan.plannedPresentations = assignments.filter { !$0.isPresented }
        plan.givenPresentations = assignments.filter(\.isPresented)

        plan.openWork = fetch(
            CDWorkModel.self,
            NSCompoundPredicate(andPredicateWithSubpredicates: [byLesson, WorkStatus.openPredicate]),
            in: context
        )
        plan.yearPlanEntries = fetch(CDYearPlanEntry.self, byLesson, in: context)

        let workService = WorkDeletionService(context: context)
        plan.notes = plan.openWork.reduce(0) { $0 + workService.cascade(for: $1).observations }
            + plan.plannedPresentations.reduce(0) { total, assignment in
                total + ((assignment.unifiedNotes as? Set<CDNote>) ?? [])
                    .filter { !$0.isDeleted && !$0.body.trimmed().isEmpty }.count
            }

        let leaving = Set(plan.lessons.map(\.objectID))
        for lesson in plan.lessons {
            if let path = LessonFileStorage.managedPagesPath(of: lesson) { plan.filePaths.append(path) }
            let attachments = ((lesson.attachments?.allObjects as? [CDLessonAttachment]) ?? [])
                .filter { !$0.isDeleted }
                .sorted { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }
            for attachment in attachments {
                if attachment.scope != .lesson,
                   let heir = heir(for: attachment.scope, of: lesson, excluding: leaving, in: context) {
                    plan.handedOver.append((attachment: attachment, heir: heir))
                } else if !attachment.fileRelativePath.trimmed().isEmpty {
                    plan.filePaths.append(attachment.fileRelativePath)
                }
            }
        }
        return plan
    }

    /// Makes the plan's changes. Does not save.
    static func apply(_ plan: LessonDeletionPlan, in context: NSManagedObjectContext) {
        guard let lesson = plan.lessons.first else { return }

        for (attachment, heir) in plan.handedOver where !attachment.isDeleted {
            attachment.lesson = heir
        }

        for given in plan.givenPresentations where !given.isDeleted {
            if given.lessonTitleSnapshot != lesson.name { given.lessonTitleSnapshot = lesson.name }
            if given.lessonSectionSnapshot != lesson.section { given.lessonSectionSnapshot = lesson.section }
        }

        for planned in plan.plannedPresentations where !planned.isDeleted {
            ChecklistRosterRemoval.keepMasteryMarks(on: planned, studentIDs: nil, in: context)
            PresentationRecordCleanup.prepareToDelete(planned, in: context)
            context.delete(planned)
        }

        // Never fails: the persist step is the caller's save.
        _ = try? WorkDeletionService(context: context).delete(plan.openWork.filter { !$0.isDeleted }) { true }

        for entry in plan.yearPlanEntries where !entry.isDeleted {
            context.delete(entry)
        }

        // The lesson's own attachments and sample works cascade with it.
        for row in plan.lessons where !row.isDeleted {
            context.delete(row)
        }
    }

    // MARK: - Pieces

    /// The lesson a sequence- or area-wide attachment moves to: one still
    /// filed in the same sequence (for the area, the same sequence first), the
    /// earliest in curriculum order, so the choice is the same every time.
    static func heir(
        for scope: AttachmentScope,
        of lesson: CDLesson,
        excluding leaving: Set<NSManagedObjectID>,
        in context: NSManagedObjectContext
    ) -> CDLesson? {
        let area = lesson.area.trimmed()
        let request = CDFetchRequest(CDLesson.self)
        // A superset in SQL (spacing and case differ between rows), narrowed below.
        request.predicate = area.isEmpty
            ? NSPredicate(format: "area MATCHES %@", "\\s*")
            : NSPredicate(format: "area CONTAINS[c] %@", area)
        let candidates = context.safeFetch(request).filter { candidate in
            guard !candidate.isDeleted, !leaving.contains(candidate.objectID),
                  LessonFileStorage.sameArea(candidate, lesson) else { return false }
            return scope == .area || LessonFileStorage.sameSequence(candidate, lesson)
        }
        return candidates.min { lhs, rhs in
            let lhsSame = LessonFileStorage.sameSequence(lhs, lesson)
            let rhsSame = LessonFileStorage.sameSequence(rhs, lesson)
            if lhsSame != rhsSame { return lhsSame }
            if lhs.sortIndex != rhs.sortIndex { return lhs.sortIndex < rhs.sortIndex }
            if lhs.orderInSequence != rhs.orderInSequence { return lhs.orderInSequence < rhs.orderInSequence }
            return LessonsViewModel.lessonNameOrder(lhs, rhs)
        }
    }

    private static func fetch<T: NSManagedObject>(
        _ type: T.Type, _ predicate: NSPredicate, in context: NSManagedObjectContext
    ) -> [T] {
        let request = CDFetchRequest(type)
        request.predicate = predicate
        return context.safeFetch(request).filter { !$0.isDeleted }
    }
}
