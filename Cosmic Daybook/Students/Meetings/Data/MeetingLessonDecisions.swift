import CoreData
import Foundation

/// Re-present and Ready for Next on a meeting's work cards: what filing the
/// meeting plans, and what Clear takes back. Both decisions close their work
/// the moment the card is tapped but plan their lessons only when the meeting
/// is filed, and they ride in the child's stored draft until then.
///
/// The Meetings workflow's draft model and the student record's Meetings tab
/// both come through here, so the tab's Clear and Save to History treat the
/// two decisions the way the workflow does (bug hunt 2026-10-09, #8).
enum MeetingLessonDecisions {
    typealias Draft = MeetingPersistenceService.CurrentMeetingData

    // MARK: - Clear

    /// Puts the Re-present and Ready for Next work in `draft` back as it was
    /// before the meeting, through each card's `WorkLogService` receipt. Work
    /// changed after the meeting is left alone and named in a toast; work
    /// whose receipt can't be read (a draft saved before receipts were kept)
    /// goes back to Working as it always has. One save; nothing is written
    /// when it fails.
    static func takeBack(_ draft: Draft, context: NSManagedObjectContext) {
        let pending = workIDs(draft.representWorkIDs).union(workIDs(draft.readyWorkIDs))
        guard !pending.isEmpty else { return }
        let tokens = draft.closeTokens ?? [:]
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(format: "id IN %@", Array(pending))
        let works = context.safeFetch(request).filter { !$0.isDeleted }

        let transaction = ContextMutationTransaction(context: context)
        var reopen: [CDWorkModel] = []
        var leftAlone: [CDWorkModel] = []
        for work in works {
            let receipts = work.id.flatMap { tokens[$0.uuidString] } ?? []
            switch MeetingCloseToken.takeBack(receipts, of: work, in: context) {
            case .takenBack:
                break
            case .changedSince:
                leftAlone.append(work)
            case .nothing, .unreadable:
                if work.status.isClosed { reopen.append(work) }
            }
        }
        do {
            if !reopen.isEmpty {
                try WorkLogService.log(
                    reopen.map { .init(work: $0, status: .active) }, context: context, saveImmediately: false
                )
            }
            guard context.safeSave() else { throw WorkLogService.LogError.saveFailed }
            transaction.commit()
        } catch {
            transaction.rollback()
            ToastService.shared.showError("Couldn't put the work back to Working. Open it to change it by hand.")
            return
        }
        if let message = leftAloneMessage(leftAlone, context: context) {
            ToastService.shared.showInfo(message, duration: 4)
        }
    }

    /// "<Lesson> was changed after the meeting, so it was left as it is."
    static func leftAloneMessage(_ works: [CDWorkModel], context: NSManagedObjectContext) -> String? {
        let names = works.map { lessonName(of: $0, context: context) }
        guard let first = names.first else { return nil }
        guard names.count > 1 else { return "\(first) was changed after the meeting, so it was left as it is." }
        let list = ListFormatter.localizedString(byJoining: names)
        return "\(list) were changed after the meeting, so they were left as they are."
    }

    // MARK: - File

    /// Plans each re-presented work's lesson again as a second pass, and puts
    /// each ready work's next lesson On Deck. Nothing here saves; the caller
    /// files it with the meeting in one save. Returns the lessons planned (or
    /// found already planned), so a lesson request for one isn't filed twice.
    static func file(_ draft: Draft, studentID: UUID, context: NSManagedObjectContext) throws -> Set<UUID> {
        try planRepresentations(workIDs(draft.representWorkIDs), studentID: studentID, context: context)
            .union(planNextLessons(workIDs(draft.readyWorkIDs), studentID: studentID, context: context))
    }

    /// The student record's Meetings tab's Save to History: the tab's fields
    /// as the history entry, with the workflow's Re-present and Ready for Next
    /// decisions filed the way Complete files them. Unlike Complete it doesn't
    /// save work reviews or clear today's booking. One save; false (nothing
    /// written) when there was nothing to file or the save failed.
    static func saveTabMeeting(studentID: UUID, tabData: Draft, context: NSManagedObjectContext) -> Bool {
        let stored = MeetingPersistenceService.loadCurrent(studentID: studentID)
        let transaction = ContextMutationTransaction(context: context)
        guard MeetingPersistenceService.saveToHistory(
            studentID: studentID, data: tabData, context: context, save: false
        ) != nil else {
            transaction.rollback()
            return false
        }
        do {
            _ = try file(stored, studentID: studentID, context: context)
            guard context.safeSave() else { throw WorkLogService.LogError.saveFailed }
        } catch {
            transaction.rollback()
            ToastService.shared.showError("Couldn't save the meeting. Try again.")
            return false
        }
        transaction.commit()
        return true
    }

    // MARK: - Re-present

    private static func planRepresentations(
        _ workIDs: Set<UUID>, studentID: UUID, context: NSManagedObjectContext
    ) throws -> Set<UUID> {
        var lessonIDs: Set<UUID> = []
        for workID in workIDs {
            guard let (work, lesson) = workAndLesson(workID, context: context),
                  let lessonID = lesson.id else { continue }
            if let presentation = presentation(of: work, context: context) {
                try flagForAnotherPresentation(presentation, studentID: studentID, context: context)
            }
            try CaptureFollowUpPersistence.createRepresentationIfNeeded(
                studentID: studentID, lesson: lesson, context: context
            )
            lessonIDs.insert(lessonID)
        }
        return lessonIDs
    }

    /// Records that the presentation didn't take for her (bug hunt
    /// 2026-10-09, #12): her own follow-up row is resolved as Re-present, the
    /// way a presentation review's Re-present resolves it, starting a
    /// follow-up on a row that had none. The shared flag says the same of
    /// everyone on the presentation, so it is set only when she had it alone.
    private static func flagForAnotherPresentation(
        _ presentation: CDLessonAssignment, studentID: UUID, context: NSManagedObjectContext
    ) throws {
        let now = Date()
        let alone = Set(presentation.resolvedStudentIDs) == [studentID]
        if alone {
            presentation.needsAnotherPresentation = true
            presentation.modifiedAt = now
        }
        let row = try ownRow(on: presentation, studentID: studentID, createIfMissing: !alone, context: context)
        guard let row else { return }
        if row.followUpActionRaw == nil {
            PresentationFollowUpService.beginFollowing(row, at: now)
        }
        PresentationFollowUpService.resolve(.supportOrRepresent, row: row, at: now)
    }

    /// Her `CDLessonPresentation` row on the presentation. A group
    /// presentation marked given without its rows (an edit in the detail
    /// sheet, or an undated "previously presented" mark) gets hers, keyed as
    /// `LifecycleService` keys it (presentation and child), so the re-present
    /// has somewhere to live. It takes the presentation's day; an undated
    /// presentation's row stays undated, as the record reads an undated mark,
    /// rather than inventing a day, and a later recording dates it in place.
    private static func ownRow(
        on presentation: CDLessonAssignment, studentID: UUID, createIfMissing: Bool, context: NSManagedObjectContext
    ) throws -> CDLessonPresentation? {
        guard let presentationID = presentation.id?.uuidString else { return nil }
        let request = CDFetchRequest(CDLessonPresentation.self)
        request.predicate = NSPredicate(
            format: "presentationID == %@ AND studentID == %@", presentationID, studentID.uuidString
        )
        request.fetchLimit = 1
        if let row = try context.fetch(request).first { return row }
        guard createIfMissing, presentation.isPresented,
              presentation.resolvedStudentIDs.contains(studentID) else { return nil }
        let row = try LifecycleService.upsertLessonPresentation(
            presentationID: presentationID,
            studentID: studentID.uuidString,
            lessonID: presentation.lessonID,
            presentedAt: presentation.presentedAt ?? Date(),
            context: context
        )
        if presentation.presentedAt == nil {
            row.presentedAt = nil
            row.lastObservedAt = nil
        }
        return row
    }

    // MARK: - Ready for Next

    /// Confirms her on each ready work's lesson (not a mastery mark) and puts
    /// the next lesson in its sequence On Deck, unless she already has it
    /// planned, or has had it or mastered it already (bug hunt 2026-10-09, #11).
    private static func planNextLessons(
        _ workIDs: Set<UUID>, studentID: UUID, context: NSManagedObjectContext
    ) -> Set<UUID> {
        guard !workIDs.isEmpty else { return [] }
        var lessonIDs: Set<UUID> = []
        let allLessons = context.safeFetch(CDFetchRequest(CDLesson.self))
        let child = studentID.uuidString
        for workID in workIDs {
            guard let (work, lesson) = workAndLesson(workID, context: context) else { continue }
            presentation(of: work, context: context)?.confirmStudent(studentID)
            resolveFollowUp(of: work, studentID: studentID, as: .readyForNextPresentation, context: context)
            guard let next = PlanNextLessonService.findNextLesson(after: lesson, in: allLessons),
                  let nextID = next.id else { continue }
            let record = PresentationRecordIndex(lessonIDs: [nextID.uuidString], students: [child], in: context)
            guard record.given(student: child, lesson: nextID.uuidString) == nil else { continue }
            lessonIDs.insert(nextID)
            let request = CDFetchRequest(CDLessonAssignment.self)
            request.predicate = NSPredicate(format: "lessonID == %@", nextID.uuidString)
            let existing = context.safeFetch(request).filter { !$0.isPresented && !$0.isDeleted }
            guard !existing.contains(where: { $0.resolvedStudentIDs.contains(studentID) }) else { continue }
            PlanNextLessonService.planLesson(
                next, forStudents: [studentID], allStudents: [], allLessons: allLessons,
                existingLessonAssignments: existing, context: context
            )
        }
        return lessonIDs
    }

    /// Closes her follow-up on the work's presentation the way the
    /// presentation review would for the same decision.
    private static func resolveFollowUp(
        of work: CDWorkModel, studentID: UUID, as resolution: PresentationFollowUpResolution,
        context: NSManagedObjectContext
    ) {
        guard let id = work.presentationID.flatMap(UUID.init(uuidString:)) else { return }
        let now = Date()
        for row in PresentationFollowUpService.rows(for: id, in: context) where row.studentID == studentID.uuidString {
            PresentationFollowUpService.resolve(resolution, row: row, at: now)
        }
    }

    // MARK: - Lookups

    private static func workIDs(_ strings: [String]?) -> Set<UUID> {
        Set((strings ?? []).compactMap(UUID.init(uuidString:)))
    }

    private static func workAndLesson(_ workID: UUID, context: NSManagedObjectContext) -> (CDWorkModel, CDLesson)? {
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(format: "id == %@", workID as CVarArg)
        request.fetchLimit = 1
        guard let work = context.safeFetch(request).first,
              let lesson = lesson(of: work, context: context) else { return nil }
        return (work, lesson)
    }

    private static func lesson(of work: CDWorkModel, context: NSManagedObjectContext) -> CDLesson? {
        guard let lessonID = UUID(uuidString: work.lessonID) else { return nil }
        let request = CDFetchRequest(CDLesson.self)
        request.predicate = NSPredicate(format: "id == %@", lessonID as CVarArg)
        request.fetchLimit = 1
        return context.safeFetch(request).first
    }

    /// The presentation the work came from, if it came from one.
    private static func presentation(of work: CDWorkModel, context: NSManagedObjectContext) -> CDLessonAssignment? {
        guard let id = work.presentationID.flatMap(UUID.init(uuidString:)) else { return nil }
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return context.safeFetch(request).first
    }

    /// The lesson's name for a message, else the work's title.
    static func lessonName(of work: CDWorkModel, context: NSManagedObjectContext) -> String {
        if let name = lesson(of: work, context: context)?.name.trimmed(), !name.isEmpty { return name }
        let title = work.title.trimmed()
        return title.isEmpty ? "That work" : title
    }
}
