import CoreData
import Foundation

/// Re-present and Ready for Next on a meeting's work cards: what filing the
/// meeting plans, and what Clear takes back. Both decisions close their work
/// the moment the card is tapped but plan their lessons only when the meeting
/// is filed, and they ride in the child's stored draft until then.
///
/// The Meetings workflow's draft model and the student record's Meetings tab
/// both come through here, so the tab's Clear and Save to History treat the
/// two decisions the way the workflow does (bug hunt 2026-10-09, #8). Clear
/// is in `+Clear`.
enum MeetingLessonDecisions {
    typealias Draft = MeetingPersistenceService.CurrentMeetingData

    // MARK: - File

    /// What filing a meeting's Re-present and Ready for Next did.
    struct Filed {
        /// The lessons planned (or found already planned), so a lesson
        /// request for one isn't filed twice.
        var planned: Set<UUID> = []
        /// Work changed after the meeting (marked Mastered, reopened, closed
        /// another way): nothing was planned for it (bug hunt 2026-10-10, #13).
        var changedSince: [CDWorkModel] = []
    }

    /// Plans each re-presented work's lesson again as a second pass, and puts
    /// each ready work's next lesson On Deck, for work still as the meeting
    /// left it. Nothing here saves; the caller files it with the meeting in
    /// one save, then names `changedSince` (`changedSinceMessage`).
    static func file(_ draft: Draft, studentID: UUID, context: NSManagedObjectContext) throws -> Filed {
        let tokens = draft.closeTokens ?? [:]
        var filed = Filed()
        try planRepresentations(
            uuids(draft.representWorkIDs), tokens: tokens, studentID: studentID, context: context, into: &filed
        )
        planNextLessons(
            uuids(draft.readyWorkIDs), tokens: tokens, studentID: studentID, context: context, into: &filed
        )
        return filed
    }

    /// The catalog lessons asked for go to the inbox for her, apart from
    /// those `file` planned already. Nothing here saves.
    static func fileRequests(
        _ lessonIDs: [UUID], skipping planned: Set<UUID>, studentID: UUID, context: NSManagedObjectContext
    ) {
        for lessonID in lessonIDs where !planned.contains(lessonID) {
            _ = PresentationFactory.makeDraft(lessonID: lessonID, studentIDs: [studentID], context: context)
        }
    }

    /// "<Lesson> was changed after the meeting, so nothing was planned for it."
    static func changedSinceMessage(_ works: [CDWorkModel], context: NSManagedObjectContext) -> String? {
        let names = works.map { lessonName(of: $0, context: context) }
        guard let first = names.first else { return nil }
        guard names.count > 1 else { return "\(first) was changed after the meeting, so nothing was planned for it." }
        let list = ListFormatter.localizedString(byJoining: names)
        return "\(list) were changed after the meeting, so nothing was planned for them."
    }

    /// The student record's Meetings tab's Save to History: the tab's fields
    /// as the history entry, with what the workflow left in the draft filed
    /// the way Complete files it: Re-present and Ready for Next, the lessons
    /// asked for, the focus checklist's changes, and the work reviewed with
    /// its notes (bug hunt 2026-10-09, #8; 2026-10-10, #10 and its review).
    /// Unlike Complete it doesn't clear today's booking. One save; false
    /// (nothing written) when there was nothing to file or the save failed.
    static func saveTabMeeting(studentID: UUID, tabData: Draft, context: NSManagedObjectContext) -> Bool {
        let stored = MeetingPersistenceService.loadCurrent(studentID: studentID)
        let requested = (stored.requestLessonIDs ?? []).compactMap(UUID.init(uuidString:))
        let checklist = FocusItemService.ChecklistChanges(
            resolvedIDs: uuids(stored.resolvedFocusIDs),
            droppedIDs: uuids(stored.droppedFocusIDs),
            newTexts: stored.pendingFocusTexts ?? []
        )
        let active = FocusItemService.fetchActive(studentID: studentID, context: context)
        var entry = tabData
        if !checklist.isEmpty {
            entry.focusText = checklist.historyText(active: active, typed: tabData.focusText.trimmed())
        }
        if !requested.isEmpty {
            let typed = tabData.requestsText
                .split(whereSeparator: \.isNewline)
                .map { String($0).trimmed() }
                .filter { !$0.isEmpty }
            entry.requestsText = (lessonNames(requested, context: context) + typed).joined(separator: "; ")
        }

        let transaction = ContextMutationTransaction(context: context)
        guard let meeting = MeetingPersistenceService.saveToHistory(
            studentID: studentID, data: entry, context: context, save: false
        ) else {
            transaction.rollback()
            return false
        }
        let meetingID = meeting.id ?? UUID()
        MeetingReviewService.persistReviews(
            meetingID: meetingID, meeting: meeting, drafts: notes(in: stored),
            reviewedIDs: uuids(stored.reviewedWorkIDs), context: context
        )
        let filed: Filed
        do {
            filed = try file(stored, studentID: studentID, context: context)
            fileRequests(requested, skipping: filed.planned, studentID: studentID, context: context)
            checklist.file(active: active, studentID: studentID, meetingID: meetingID, context: context)
            guard context.safeSave() else { throw WorkLogService.LogError.saveFailed }
        } catch {
            transaction.rollback()
            ToastService.shared.showError("Couldn't save the meeting. Try again.")
            return false
        }
        transaction.commit()
        if let message = changedSinceMessage(filed.changedSince, context: context) {
            ToastService.shared.showInfo(message, duration: 4)
        }
        return true
    }

    /// Whether `work` is still as the meeting's card left it, so filing its
    /// decision plans what the guide meant (bug hunt 2026-10-10, #13): every
    /// receipt can be taken back, or, with none to read (the work already
    /// had that status, a draft saved before receipts were kept, a store
    /// reset), it still has the status the decision gave it.
    private static func isAsTheMeetingLeftIt(
        _ work: CDWorkModel, decided status: WorkStatus, tokens: [String: [MeetingCloseToken]],
        context: NSManagedObjectContext
    ) -> Bool {
        let workReceipts = receipts(of: work, in: tokens)
        guard isReadable(workReceipts, in: context) else { return work.status == status }
        return MeetingCloseToken.canTakeBack(workReceipts, from: work)
    }

    // MARK: - Re-present

    private static func planRepresentations(
        _ workIDs: Set<UUID>, tokens: [String: [MeetingCloseToken]], studentID: UUID,
        context: NSManagedObjectContext, into filed: inout Filed
    ) throws {
        for workID in workIDs {
            guard let (work, lesson) = workAndLesson(workID, context: context),
                  let lessonID = lesson.id else { continue }
            guard isAsTheMeetingLeftIt(work, decided: .incomplete, tokens: tokens, context: context) else {
                filed.changedSince.append(work)
                continue
            }
            if let presentation = presentation(of: work, context: context) {
                try flagForAnotherPresentation(presentation, studentID: studentID, context: context)
            }
            try CaptureFollowUpPersistence.createRepresentationIfNeeded(
                studentID: studentID, lesson: lesson, context: context
            )
            filed.planned.insert(lessonID)
        }
    }

    /// Records that the presentation didn't take for her (bug hunt
    /// 2026-10-09, #12): her own follow-up row is resolved as Re-present, the
    /// way a presentation review's Re-present resolves it, starting a
    /// follow-up on a row that had none. The shared flag says the same of
    /// everyone on the presentation, so it is set only when she had it alone.
    /// A recall check's Forgotten files the same way (bug hunt 2026-10-11, #26).
    static func flagForAnotherPresentation(
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
        _ workIDs: Set<UUID>, tokens: [String: [MeetingCloseToken]], studentID: UUID,
        context: NSManagedObjectContext, into filed: inout Filed
    ) {
        guard !workIDs.isEmpty else { return }
        let allLessons = context.safeFetch(CDFetchRequest(CDLesson.self))
        let child = studentID.uuidString
        for workID in workIDs {
            guard let (work, lesson) = workAndLesson(workID, context: context) else { continue }
            guard isAsTheMeetingLeftIt(work, decided: .done, tokens: tokens, context: context) else {
                filed.changedSince.append(work)
                continue
            }
            presentation(of: work, context: context)?.confirmStudent(studentID)
            resolveFollowUp(of: work, studentID: studentID, as: .readyForNextPresentation, context: context)
            guard let next = PlanNextLessonService.findNextLesson(after: lesson, in: allLessons),
                  let nextID = next.id else { continue }
            let record = PresentationRecordIndex(lessonIDs: [nextID.uuidString], students: [child], in: context)
            guard record.given(student: child, lesson: nextID.uuidString) == nil else { continue }
            filed.planned.insert(nextID)
            let request = CDFetchRequest(CDLessonAssignment.self)
            request.predicate = NSPredicate(format: "lessonID == %@", nextID.uuidString)
            let existing = context.safeFetch(request).filter { !$0.isPresented && !$0.isDeleted }
            guard !existing.contains(where: { $0.resolvedStudentIDs.contains(studentID) }) else { continue }
            PlanNextLessonService.planLesson(
                next, forStudents: [studentID], allStudents: [], allLessons: allLessons,
                existingLessonAssignments: existing, context: context
            )
        }
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

    private static func uuids(_ strings: [String]?) -> Set<UUID> {
        Set((strings ?? []).compactMap(UUID.init(uuidString:)))
    }

    /// The draft's notes on its work cards, by work.
    private static func notes(in draft: Draft) -> [UUID: String] {
        Dictionary(
            (draft.workReviewDrafts ?? [:]).compactMap { key, value in UUID(uuidString: key).map { ($0, value) } },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// The work the draft's Re-present and Ready for Next decisions closed.
    static func pendingWork(in draft: Draft, context: NSManagedObjectContext) -> [CDWorkModel] {
        let ids = uuids(draft.representWorkIDs).union(uuids(draft.readyWorkIDs))
        guard !ids.isEmpty else { return [] }
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(format: "id IN %@", Array(ids))
        return context.safeFetch(request).filter { !$0.isDeleted }
    }

    static func receipts(of work: CDWorkModel, in tokens: [String: [MeetingCloseToken]]) -> [MeetingCloseToken] {
        work.id.flatMap { tokens[$0.uuidString] } ?? []
    }

    /// Whether there are receipts and each one still names rows on this device.
    static func isReadable(_ receipts: [MeetingCloseToken], in context: NSManagedObjectContext) -> Bool {
        !receipts.isEmpty && receipts.allSatisfy { $0.undoToken(in: context) != nil }
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
        UUID(uuidString: work.lessonID).flatMap { lesson($0, context: context) }
    }

    private static func lesson(_ id: UUID, context: NSManagedObjectContext) -> CDLesson? {
        let request = CDFetchRequest(CDLesson.self)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return context.safeFetch(request).first
    }

    /// The names of the lessons asked for, in order; one no longer in the
    /// catalog is left out.
    private static func lessonNames(_ ids: [UUID], context: NSManagedObjectContext) -> [String] {
        ids.compactMap { lesson($0, context: context)?.name.trimmed() }.filter { !$0.isEmpty }
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
