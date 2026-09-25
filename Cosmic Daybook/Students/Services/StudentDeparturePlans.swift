//
//  StudentDeparturePlans.swift
//  Cosmic Daybook
//
//  The lessons a departing child is still planned for.
//
//  Withdrawing or transferring a child changes her enrollment and nothing
//  else. Every lesson planned but not yet given keeps naming her, and when
//  that lesson is finally presented the follow-up work is generated from the
//  plan's list — with her on it. The guide then edits the presentation by
//  hand, and the work rows and the presentation disagree from that moment on.
//
//  This is the missing rule: at the point of departure, name every plan she
//  is on and offer to take her off them. Presented lessons are history and
//  are never touched.
//
//  The year plan is the same rule one step earlier. A `CDYearPlanEntry` is an
//  intention with a target date, not yet a lesson on the calendar; left alone
//  it keeps claiming a future the child no longer has here, and every target
//  date that passes counts as another lesson behind pace. Those entries move
//  to `skipped` at the same moment, and are never deleted — a girl who
//  re-enrols should find her year plan where she left it.
//

import CoreData
import Foundation

enum StudentDeparturePlans {

    struct Retraction: Equatable {
        /// Plans she was removed from that still have other children on them.
        var plansEdited = 0
        /// Plans that named only her, deleted rather than left with nobody on them.
        var plansDeleted = 0

        /// Plans touched. Year-plan entries are counted separately because they
        /// are a different kind of record and the guide is told about them apart.
        var total: Int { plansEdited + plansDeleted }
    }

    /// Lessons planned for `studentID` that have not been given, soonest first.
    static func futurePlans(
        for studentID: UUID, in context: NSManagedObjectContext
    ) -> [CDLessonAssignment] {
        let idString = studentID.uuidString
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(
            format: "stateRaw != %@", LessonAssignmentState.presented.rawValue
        )
        return context.safeFetch(request)
            .filter { !$0.isPresented && $0.studentIDs.contains(idString) }
            .sorted { lhs, rhs in
                let lhsDate = lhs.scheduledFor ?? .distantFuture
                let rhsDate = rhs.scheduledFor ?? .distantFuture
                if lhsDate != rhsDate { return lhsDate < rhsDate }
                return (lhs.createdAt ?? .distantPast) < (rhs.createdAt ?? .distantPast)
            }
    }

    /// Plans for every child in `studentIDs`, each plan once.
    static func futurePlans(
        for studentIDs: [UUID], in context: NSManagedObjectContext
    ) -> [CDLessonAssignment] {
        var seen = Set<NSManagedObjectID>()
        return studentIDs.flatMap { futurePlans(for: $0, in: context) }
            .filter { seen.insert($0.objectID).inserted }
    }

    /// "Fundamental Needs — Fri, Sep 12" or "Fundamental Needs — not yet scheduled".
    static func describe(_ plan: CDLessonAssignment, in context: NSManagedObjectContext) -> String {
        let name = plan.lesson?.name ?? plan.lessonTitleSnapshot ?? "Untitled lesson"
        if let date = plan.scheduledFor {
            return "\(name) — \(DateFormatters.mediumDate.string(from: date))"
        }
        return "\(name) — not yet scheduled"
    }

    // MARK: - Year Plan

    /// Year-plan entries still pencilled in for `studentID`, soonest first.
    ///
    /// Only `planned` ones. A promoted entry has already become a real
    /// assignment on the calendar, and that assignment — reached through
    /// `futurePlans` above — is where a departing child comes off; touching
    /// the entry as well would desync it from the lesson it was promoted into.
    static func plannedEntries(
        for studentID: UUID, in context: NSManagedObjectContext
    ) -> [CDYearPlanEntry] {
        let request = CDFetchRequest(CDYearPlanEntry.self)
        request.predicate = NSPredicate(
            format: "studentID == %@ AND statusRaw == %@",
            studentID.uuidString, YearPlanEntryStatus.planned.rawValue
        )
        return context.safeFetch(request).sorted { lhs, rhs in
            let lhsDate = lhs.plannedDate ?? .distantFuture
            let rhsDate = rhs.plannedDate ?? .distantFuture
            if lhsDate != rhsDate { return lhsDate < rhsDate }
            return (lhs.createdAt ?? .distantPast) < (rhs.createdAt ?? .distantPast)
        }
    }

    /// Entries for every child in `studentIDs`, each entry once.
    static func plannedEntries(
        for studentIDs: [UUID], in context: NSManagedObjectContext
    ) -> [CDYearPlanEntry] {
        var seen = Set<NSManagedObjectID>()
        return studentIDs.flatMap { plannedEntries(for: $0, in: context) }
            .filter { seen.insert($0.objectID).inserted }
    }

    /// Marks each entry skipped, returning how many changed. Never deletes: the
    /// entries stay readable through `year_plan(status: "skipped")` and come
    /// back if she re-enrols. Does not save.
    @discardableResult
    static func skip(entries: [CDYearPlanEntry]) -> Int {
        var skipped = 0
        for entry in entries where !entry.isDeleted && entry.isPlanned {
            entry.status = .skipped
            skipped += 1
        }
        return skipped
    }

    // MARK: - Retracting

    /// Takes `studentID` off each of `plans`. A plan left with nobody on it is
    /// deleted, since the app never keeps a zero-child lesson. Does not save.
    @discardableResult
    static func retract(
        studentID: UUID, from plans: [CDLessonAssignment], in context: NSManagedObjectContext
    ) -> Retraction {
        let idString = studentID.uuidString
        var result = Retraction()
        for plan in plans where !plan.isDeleted && plan.studentIDs.contains(idString) {
            var ids = plan.studentIDs
            ids.removeAll { $0 == idString }
            if ids.isEmpty {
                context.delete(plan)
                result.plansDeleted += 1
            } else {
                plan.studentIDs = ids
                plan.modifiedAt = Date()
                result.plansEdited += 1
            }
        }
        return result
    }
}
