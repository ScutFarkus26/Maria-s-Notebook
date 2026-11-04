// WorkDetailViewModel+PageActions.swift
// The work page's own actions that write at once: Unlock Next Lesson, a
// check-in's Delete, Schedule New Check-In, and the Practice Overview's
// numbers. They lived in the view; here they can be tested as the page runs
// them.

import CoreData
import Foundation

extension WorkDetailViewModel {

    // MARK: - Unlock Next Lesson

    /// The lesson and child an unlock is about: this work's.
    var unlockTarget: (lessonID: UUID, studentID: UUID)? {
        guard let lessonID = resolvedLessonID, let studentID = resolvedStudentID else { return nil }
        return (lessonID, studentID)
    }

    /// Offers to unlock the lesson after this one for her, unless it is
    /// already unlocked, on the schedule, or given. The plans are read again
    /// first, so one made since the page opened (by the last unlock, or on
    /// another device) counts.
    func offerUnlock() {
        reloadLessonAssignments()
        guard let target = unlockTarget,
              let currentLesson = relatedLessons.first(where: { $0.id == target.lessonID }),
              let nextLesson = PlanNextLessonService.findNextLesson(after: currentLesson, in: relatedLessons) else {
            return
        }

        let existingLAs = relatedLessonAssignments.filter { la in
            la.lessonIDUUID == nextLesson.id &&
            la.resolvedStudentIDs.contains(target.studentID)
        }

        // Nothing to unlock if the next lesson is already unlocked, already on the
        // schedule, or already presented for this student.
        if existingLAs.contains(where: {
            $0.manuallyUnblocked || $0.scheduledFor != nil || $0.presentedAt != nil || $0.isPresented
        }) {
            return
        }

        nextLessonToUnlock = nextLesson
        showUnlockNextLessonAlert = true
    }

    /// Unlocks the next lesson for her alone (see `UnlockNextLessonService`)
    /// and saves at once: it is an action, not an edit waiting for Save. The
    /// page's plans are read again afterwards, so it doesn't offer the same
    /// unlock twice.
    func unlockNextLesson(modelContext: NSManagedObjectContext, saveCoordinator: SaveCoordinator) {
        guard let target = unlockTarget else { return }

        let saved = saveCoordinator.saveEdit(in: modelContext, reason: "Unlocking next lesson") {
            _ = UnlockNextLessonService.unlockNextLesson(
                after: target.lessonID,
                for: target.studentID,
                context: modelContext,
                lessons: relatedLessons,
                saveImmediately: false
            )
        }
        if !saved {
            ToastService.shared.showError("Couldn't unlock the next lesson. Try again.")
        }
        reloadLessonAssignments()
    }

    // MARK: - Check-ins

    /// What the page asks before a check-in's Delete: what goes, and that a
    /// note typed on it stays.
    static func deleteMessage(for checkIn: CDWorkCheckIn) -> String {
        let day = checkIn.date.map(dayName) ?? "its day"
        if WorkCheckInService.hasNote(checkIn) {
            return "It has a note, so it stays on \(day) marked skipped, and the note stays with it."
        }
        return "The check-in on \(day) comes off the calendar."
    }

    /// A check-in's Delete takes it off the calendar the way the rest of the
    /// app does, through `WorkCheckInService.unschedule`: one carrying a note
    /// is marked skipped where it is, so the note stays; one with none is
    /// deleted. It used to be deleted outright, and the note typed on it
    /// went with it (bug hunt 2026-11-03 #35). The due date then follows the
    /// check-ins left, as Clear All's does. A failed save takes it all back.
    func deleteCheckIn(
        _ item: CDWorkCheckIn, modelContext: NSManagedObjectContext, saveCoordinator: SaveCoordinator
    ) {
        let saved = saveCoordinator.saveEdit(in: modelContext, reason: "Deleting check-in") {
            guard WorkCheckInService(context: modelContext).unschedule(item) != nil,
                  let work else { return }
            modelContext.processPendingChanges()
            let due = CalendarForwardShiftService.earliestScheduledDate(of: work, in: modelContext)
            if due != work.dueAt { work.dueAt = due }
        }
        if !saved {
            ToastService.shared.showError("Couldn't delete the check-in. Try again.")
        }
    }

    /// Schedule New Check-In, held to the rules every other way of adding
    /// one keeps (see `WorkCheckInService.addCheckIn`). A day already taken,
    /// or closed work, adds nothing and says so; the form keeps what was
    /// typed, so another day can be picked.
    func addCheckIn(modelContext: NSManagedObjectContext, saveCoordinator: SaveCoordinator) {
        guard let work else { return }
        let note = newPlanNote.trimmed()

        var outcome: WorkCheckInService.AddOutcome?
        let saved = saveCoordinator.saveEdit(in: modelContext, reason: "Adding check-in") {
            outcome = WorkCheckInService(context: modelContext).addCheckIn(
                to: work, on: newPlanDate ?? Date(), purpose: newPlanPurpose,
                note: note.isEmpty ? nil : note
            )
        }
        guard saved, let outcome else {
            ToastService.shared.showError("Couldn't add the check-in. Try again.")
            return
        }

        switch outcome {
        case .workClosed:
            ToastService.shared.showInfo("This work is closed, so it doesn't get check-ins. Set it back to Working "
                + "and save to schedule one.")
            return
        case .dayTaken(let existing):
            let day = existing.date.map(Self.dayName) ?? "that day"
            ToastService.shared.showInfo("This work already has a check-in on \(day).")
            return
        case .added(let checkIn, let askedFor):
            if let askedFor, let landed = checkIn.date {
                ToastService.shared.showInfo(
                    "\(askedFor.formatted(.dateTime.weekday(.wide))) isn't a school day, so the check-in is on "
                        + "\(Self.dayName(landed)).",
                    duration: 3
                )
            }
        }

        // Reset form fields
        newPlanDate = nil
        newPlanPurpose = "progressCheck"
        newPlanNote = ""
    }

    /// "Thursday, Nov 5".
    private static func dayName(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    // MARK: - Practice Overview

    /// The overview's numbers. "Check-ins Scheduled" counts this work's own
    /// scheduled check-ins, the ones listed under Scheduled Check-Ins below
    /// it. It counted the dates written on practice sessions, which stayed
    /// after the real check-in was done, moved or deleted (#46).
    func practiceStats(sessions: [CDPracticeSession]) -> PracticeStats {
        let scheduled = work.flatMap { work in
            work.managedObjectContext.map { WorkLogService.scheduledCheckIns(of: work, in: $0).count }
        } ?? 0
        return PracticeStatsCalculator.calculate(from: sessions, scheduledCheckIns: scheduled)
    }
}
