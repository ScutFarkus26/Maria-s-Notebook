//
//  UnlockNextLessonService.swift
//  Cosmic Daybook
//
//  Service for unlocking the next lesson in a sequence for one child.
//  Handles finding the next lesson and marking her plan of it as manually unblocked.
//

import Foundation
import CoreData

/// Service for manually unlocking next lessons when a child is ready to progress
struct UnlockNextLessonService {
    // MARK: - Result Type

    enum UnlockResult {
        case success(CDLessonAssignment)
        case noNextLesson
        case alreadyUnlocked
        case noCurrentLesson
    }

    // MARK: - Core Data Unlock Logic

    /// Unlocks the lesson after `currentLessonID` for one child.
    ///
    /// Only a plan that is hers alone is unlocked. `manuallyUnblocked` belongs
    /// to the plan, shared by everyone on it, so flagging a group plan that
    /// merely included her unlocked the whole group: Presentations stopped
    /// holding it back, and a classmate who hadn't finished practice on the
    /// lesson before read Ready on the Checklist (bug hunt 2026-11-03 #19).
    /// When the only plans naming her are group plans, she gets an unlocked
    /// draft of her own and the group's plan is left as it was.
    ///
    /// The plans are fetched here rather than taken from the caller: the work
    /// page handed in the list it read when it opened, so a second unlock
    /// didn't see the draft the first had made and made another (#34).
    /// - Parameters:
    ///   - currentLessonID: The lesson she just finished
    ///   - studentID: The child ready to go on
    ///   - context: Core Data managed object context
    ///   - lessons: The lessons of her sequence (the next one is found among them)
    /// - Returns: UnlockResult indicating success or reason for failure
    static func unlockNextLesson(
        after currentLessonID: UUID,
        for studentID: UUID,
        context: NSManagedObjectContext,
        lessons: [CDLesson],
        saveImmediately: Bool = true
    ) -> UnlockResult {
        guard let currentLesson = lessons.first(where: { $0.id == currentLessonID }) else {
            return .noCurrentLesson
        }
        guard let nextLesson = PlanNextLessonService.findNextLesson(after: currentLesson, in: lessons),
              let nextLessonID = nextLesson.id else {
            return .noNextLesson
        }

        // Her own plan of the next lesson, if she has one; her unscheduled
        // draft first, so a solo unlock keeps its inbox draft when she also
        // has a dated plan.
        let herOwn = plansNotYetGiven(of: nextLessonID, in: context).filter {
            Set($0.resolvedStudentIDs) == [studentID]
        }
        if let existing = herOwn.first(where: { $0.scheduledFor == nil }) ?? herOwn.first {
            if existing.manuallyUnblocked {
                return .alreadyUnlocked
            }
            existing.manuallyUnblocked = true
            if saveImmediately {
                context.safeSave()
            }
            return .success(existing)
        }

        let draft = PresentationFactory.makeDraft(
            lessonID: nextLessonID,
            studentIDs: [studentID],
            context: context
        )
        draft.manuallyUnblocked = true
        if saveImmediately {
            context.safeSave()
        }
        return .success(draft)
    }

    /// Every plan of the lesson not given yet, read from the context now,
    /// unsaved ones included.
    private static func plansNotYetGiven(
        of lessonID: UUID, in context: NSManagedObjectContext
    ) -> [CDLessonAssignment] {
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "lessonID ==[c] %@", lessonID.uuidString)
        return context.safeFetch(request).filter { plan in
            !plan.isDeleted && !plan.isPresented && plan.presentedAt == nil
        }
    }
}
