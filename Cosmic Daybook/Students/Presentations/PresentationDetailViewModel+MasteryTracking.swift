// PresentationDetailViewModel+MasteryTracking.swift
// CDLessonPresentation mastery state loading and updating for PresentationDetailViewModel.

import Foundation
import OSLog
import CoreData

extension PresentationDetailViewModel {

    // MARK: - Mastery State Loading (Static)

    /// Loads the "highest" mastery state from all students' CDLessonPresentation records.
    /// If any student has mastered, returns .proficient. Otherwise returns the highest state found.
    static func loadProficiencyState(
        lessonID: String,
        studentIDs: [String],
        viewContext: NSManagedObjectContext
    ) -> LessonPresentationState {
        guard !studentIDs.isEmpty, !lessonID.isEmpty else { return .presented }

        let allLessonPresentations: [CDLessonPresentation]
        do {
            let request = presentationsRequest(lessonID: lessonID, studentIDs: studentIDs)
            allLessonPresentations = try viewContext.fetch(request)
        } catch {
            Self.logger.warning("Failed to fetch CDLessonPresentation: \(error)")
            return .presented
        }
        let matching = allLessonPresentations.filter { lp in
            lp.lessonID == lessonID && studentIDs.contains(lp.studentID)
        }

        // Return the "highest" state found (mastered > readyForAssessment > practicing > presented)
        if matching.contains(where: { $0.state == .proficient }) {
            return .proficient
        } else if matching.contains(where: { $0.state == .readyForAssessment }) {
            return .readyForAssessment
        } else if matching.contains(where: { $0.state == .practicing }) {
            return .practicing
        }
        return .presented
    }

    /// The presentation records for one lesson and these students. Both
    /// attributes are Strings, so String arguments are the right type. This
    /// used to be a whole-table fetch filtered in memory by the same test; the
    /// in-memory filters that follow still apply, and store order is kept.
    static func presentationsRequest(lessonID: String, studentIDs: [String]) -> NSFetchRequest<CDLessonPresentation> {
        let req = CDFetchRequest(CDLessonPresentation.self)
        req.predicate = NSPredicate(format: "lessonID == %@ AND studentID IN %@", lessonID, studentIDs)
        return req
    }

    // MARK: - Mastery State Updating

    /// Gives every child a CDLessonPresentation record for this lesson, and,
    /// when the guide changed the group's mastery control, sets all of them
    /// to `state`. Otherwise existing records keep each child's own state and
    /// a missing one starts at `.presented`: the control shows the group's
    /// highest state, which is one child's, not everyone's.
    ///
    /// Every record a child has for the lesson changes together (a lesson
    /// given twice has two): changing only the first in store order left the
    /// latest one, which MCP and the record index read, saying otherwise. A
    /// missing record is made for this presentation and on its day (none for
    /// an undated one), so it follows the presentation when its lesson is
    /// changed or it is deleted, rather than standing alone dated today.
    ///
    /// `childStates` are the guide's own choices for single children, made on
    /// the lesson's row of the sequence recap (`recapStateEdits`): each one
    /// counts as a change for that child alone, so the row a Save makes for
    /// her (a child added to a given presentation) carries it too (bug hunt
    /// 2026-11-03 #18).
    func updateProficiencyState(
        lessonID: String,
        studentIDs: [String],
        state guideState: LessonPresentationState,
        guideChangedState: Bool,
        childStates: [UUID: LessonPresentationState] = [:]
    ) {
        let groupState = guideChangedState ? guideState : .presented
        guard !studentIDs.isEmpty, !lessonID.isEmpty else { return }

        let allLessonPresentations = viewContext.safeFetch(
            Self.presentationsRequest(lessonID: lessonID, studentIDs: studentIDs)
        )

        for studentID in studentIDs {
            let childState = UUID(uuidString: studentID).flatMap { childStates[$0] }
            let changed = guideChangedState || childState != nil
            let state = childState ?? groupState

            let existing = allLessonPresentations.filter {
                $0.lessonID == lessonID && $0.studentID == studentID && !$0.isDeleted
            }
            if !existing.isEmpty {
                guard changed else { continue }
                for row in existing {
                    Self.apply(state, to: row)
                }
            } else {
                let lp = CDLessonPresentation(context: viewContext)
                lp.studentID = studentID
                lp.lessonID = lessonID
                lp.presentationID = lessonAssignment.id?.uuidString
                lp.state = state
                lp.presentedAt = lessonAssignment.presentedAt
                lp.lastObservedAt = Date()
                lp.masteredAt = state == .proficient ? Date() : nil
            }
        }
    }

    // MARK: - Sibling-Lesson Mastery Updates

    /// Updates the mastery state for a single (lesson, student) pair from the Sequence Recap.
    /// Used to change the status of any lesson in the group directly from the recap UI,
    /// the one this sheet is for included: its row is where one child's mastery of the
    /// lesson just given is set, since the sheet has no group-wide control. Persists
    /// immediately and recomputes the group recap so the badge + progress chip refresh.
    ///
    /// The choice is also remembered (`recapStateEdits`), so the rows a later Save or
    /// Record makes for her on this lesson carry it rather than starting at Presented.
    func updateSiblingLessonProficiencyState(
        lessonID: String,
        studentID: String,
        state: LessonPresentationState,
        lessons: [CDLesson],
        currentLesson: CDLesson?,
        students: [CDStudent]
    ) {
        guard !lessonID.isEmpty, !studentID.isEmpty else { return }
        rememberRecapStateEdit(state, lessonID: lessonID, studentID: studentID)
        // The lesson on the sheet, not yet given: the choice waits for Record,
        // which carries it onto the rows it makes. A row written now would
        // read as given today, with no presentation behind it.
        let isCurrent = currentLesson?.id != nil && currentLesson?.id == UUID(uuidString: lessonID)
        if isCurrent, !lessonAssignment.isPresented {
            recomputeSequenceRecap(currentLesson: currentLesson, students: students)
            return
        }

        let allLessonPresentations = viewContext.safeFetch(
            Self.presentationsRequest(lessonID: lessonID, studentIDs: [studentID])
        )

        // Every record she has for the lesson, as the detail view's control
        // does: a lesson given twice has two.
        let existing = allLessonPresentations.filter {
            $0.lessonID == lessonID && $0.studentID == studentID && !$0.isDeleted
        }
        if !existing.isEmpty {
            for row in existing {
                Self.apply(state, to: row)
            }
        } else {
            let lp = CDLessonPresentation(context: viewContext)
            lp.studentID = studentID
            lp.lessonID = lessonID
            // On the lesson given here, the row is this presentation's.
            lp.presentationID = isCurrent ? lessonAssignment.id?.uuidString : nil
            lp.state = state
            lp.presentedAt = isCurrent ? lessonAssignment.presentedAt : Date()
            lp.lastObservedAt = Date()
            lp.masteredAt = state == .proficient ? Date() : nil
        }

        _ = saveCoordinator.save(viewContext, reason: "Updating sibling lesson proficiency state")
        recomputeSequenceRecap(currentLesson: currentLesson, students: students)
    }

    // MARK: - The Recap's Choices

    /// Notes one child's choice on the recap, keyed by the lesson and her id
    /// as UUIDs read them, so the presentation's own spelling of either
    /// doesn't matter.
    private func rememberRecapStateEdit(_ state: LessonPresentationState, lessonID: String, studentID: String) {
        guard let lesson = UUID(uuidString: lessonID), let student = UUID(uuidString: studentID) else { return }
        recapStateEdits[SequenceRecapPairKey(lessonID: lesson.uuidString, studentID: student.uuidString)] = state
    }

    /// The children's choices made on the recap for `lessonID`, by child.
    func recapStateEdits(forLesson lessonID: String) -> [UUID: LessonPresentationState] {
        guard let lesson = UUID(uuidString: lessonID)?.uuidString else { return [:] }
        var byChild: [UUID: LessonPresentationState] = [:]
        for (key, state) in recapStateEdits where key.lessonID == lesson {
            if let student = UUID(uuidString: key.studentID) { byChild[student] = state }
        }
        return byChild
    }

    /// After Record: the rows the recording made start at Presented, so the
    /// choices made on the recap's row for this lesson before it are put on
    /// them too, and saved. Nothing to do when none were made.
    func applyRecapStateEditsAfterRecording() {
        let edits = recapStateEdits(forLesson: lessonAssignment.lessonID)
        guard !edits.isEmpty else { return }
        updateProficiencyState(
            lessonID: lessonAssignment.lessonID,
            studentIDs: lessonAssignment.studentIDs,
            state: .presented,
            guideChangedState: false,
            childStates: edits
        )
        if saveCoordinator.save(viewContext, reason: "Keeping the recap's mastery choices") {
            recapStateEdits.removeAll()
        }
    }

    /// The guide's mastery choice on one record: an existing mastered day is
    /// kept, and anything short of mastered clears it.
    static func apply(_ state: LessonPresentationState, to row: CDLessonPresentation) {
        row.state = state
        row.lastObservedAt = Date()
        if state == .proficient && row.masteredAt == nil {
            row.masteredAt = Date()
        } else if state != .proficient {
            row.masteredAt = nil
        }
    }
}
