//
//  PresentationRecordIndex.swift
//  Maria's Notebook
//
//  What the record says about every child and every lesson, read once.
//
//  Three questions keep coming up in the same shape — has she had this
//  lesson, has she mastered it, is it already on a plan for her — and until
//  now each caller fetched and folded the rows its own way. `students_pending`
//  read "given" from the presentation record plus presented assignments;
//  `TrackProgressResolver` read "mastered" from `masteredAt` or the proficient
//  state; the Three-Year View read "confirmed" off the assignment's confirmed
//  list. This index folds all three, plus the open plans, into value types in
//  one pass so the regive guard, the mastery sweep and the ready queue answer
//  from one definition.
//
//  Scoped to a handful of lessons it is three small fetches; unscoped it reads
//  the whole record, which is what a class-wide sweep needs anyway.
//

import CoreData
import Foundation

nonisolated struct PresentationRecordIndex: Sendable {

    /// What the record holds for one child on one lesson.
    struct Given: Sendable, Equatable {
        /// The days she was given it, oldest first, one entry per day. Empty
        /// when the only record is an undated "previously presented" mark.
        var days: [Date] = []
        /// A mastery mark: `masteredAt` set, or the proficient state.
        var mastered: Bool = false
        /// The guide confirmed her ready for the next lesson at capture.
        var confirmed: Bool = false
    }

    enum Standing: Sendable, Equatable {
        /// She has had the lesson.
        case onRecord(Given)
        /// Not given, but an unpresented plan or a live year-plan entry names her.
        case planned
        /// Nothing at all.
        case noRecord
    }

    /// lessonID → studentID → what the record holds.
    let givenByLesson: [String: [String: Given]]
    /// studentID → lessonID → what the record holds. The same facts, keyed
    /// the other way for a walk across one child's lessons.
    let givenByStudent: [String: [String: Given]]
    /// lessonID → children with an unpresented assignment or a year-plan
    /// entry that is not skipped.
    let openPlanByLesson: [String: Set<String>]
    /// lessonID → studentID → her most recent presented assignment for it,
    /// for a write that needs the managed object back (flagging it for a
    /// second pass). Absent when only a `CDLessonPresentation` row exists.
    let latestPresentedAssignmentByLesson: [String: [String: NSManagedObjectID]]

    /// - Parameters:
    ///   - lessonIDs: the lessons to read; `nil` reads the whole record.
    ///   - students: the children to keep; `nil` keeps everyone.
    init(
        lessonIDs: Set<String>? = nil,
        students: Set<String>? = nil,
        in context: NSManagedObjectContext
    ) {
        var builder = Builder(students: students)
        for row in Self.fetch(CDLessonPresentation.self, lessonIDs: lessonIDs, in: context) {
            builder.fold(row)
        }
        for assignment in Self.fetch(CDLessonAssignment.self, lessonIDs: lessonIDs, in: context) {
            builder.fold(assignment)
        }
        for entry in Self.fetch(CDYearPlanEntry.self, lessonIDs: lessonIDs, in: context) {
            builder.fold(entry)
        }

        let given: [String: [String: Given]] = builder.given.mapValues { children in
            children.mapValues { detail in
                var copy = detail
                copy.days.sort()
                return copy
            }
        }
        var byStudent: [String: [String: Given]] = [:]
        for (lessonID, children) in given {
            for (studentID, detail) in children {
                byStudent[studentID, default: [:]][lessonID] = detail
            }
        }

        givenByLesson = given
        givenByStudent = byStudent
        openPlanByLesson = builder.openPlan
        latestPresentedAssignmentByLesson = builder.latest.mapValues { $0.mapValues(\.id) }
    }

    // MARK: - Questions

    func given(student studentID: String, lesson lessonID: String) -> Given? {
        givenByLesson[lessonID]?[studentID]
    }

    func hasOpenPlan(student studentID: String, lesson lessonID: String) -> Bool {
        openPlanByLesson[lessonID]?.contains(studentID) ?? false
    }

    /// The record wins over the plan, as it does everywhere else: a child
    /// who has had the lesson is on record however many entries name her.
    func standing(student studentID: String, lesson lessonID: String) -> Standing {
        if let detail = given(student: studentID, lesson: lessonID) { return .onRecord(detail) }
        if hasOpenPlan(student: studentID, lesson: lessonID) { return .planned }
        return .noRecord
    }

    /// Children the record says have had the lesson.
    func givenStudents(lesson lessonID: String) -> Set<String> {
        Set((givenByLesson[lessonID] ?? [:]).keys)
    }

    func masteredStudents(lesson lessonID: String) -> Set<String> {
        Set((givenByLesson[lessonID] ?? [:]).filter { $0.value.mastered }.keys)
    }

    func confirmedStudents(lesson lessonID: String) -> Set<String> {
        Set((givenByLesson[lessonID] ?? [:]).filter { $0.value.confirmed }.keys)
    }

    // MARK: - Folding

    /// The three record shapes, folded one row at a time.
    private struct Builder {
        let students: Set<String>?
        var given: [String: [String: Given]] = [:]
        var openPlan: [String: Set<String>] = [:]
        var latest: [String: [String: (date: Date, id: NSManagedObjectID)]] = [:]

        init(students: Set<String>?) {
            self.students = students
        }

        private func keeps(_ studentID: String) -> Bool {
            students.map { $0.contains(studentID) } ?? true
        }

        private mutating func note(_ lessonID: String, _ studentID: String, _ change: (inout Given) -> Void) {
            var detail = given[lessonID, default: [:]][studentID] ?? Given()
            change(&detail)
            given[lessonID, default: [:]][studentID] = detail
        }

        private static func addDay(_ date: Date?, to detail: inout Given) {
            guard let date else { return }
            let day = AppCalendar.startOfDay(date)
            if !detail.days.contains(day) { detail.days.append(day) }
        }

        /// A presentation record row: given on its day, mastered if marked.
        mutating func fold(_ row: CDLessonPresentation) {
            guard keeps(row.studentID) else { return }
            note(row.lessonID, row.studentID) { detail in
                Self.addDay(row.presentedAt, to: &detail)
                if row.masteredAt != nil || row.state == .proficient { detail.mastered = true }
            }
        }

        /// A presented assignment is given for everyone on it, confirmed for
        /// those the guide confirmed; an unpresented one is an open plan.
        mutating func fold(_ assignment: CDLessonAssignment) {
            let roster = assignment.studentIDs.filter(keeps)
            guard !roster.isEmpty else { return }
            guard assignment.isPresented else {
                openPlan[assignment.lessonID, default: []].formUnion(roster)
                return
            }
            let confirmed = Set(assignment.confirmedStudentIDs)
            let presented = assignment.presentedAt ?? .distantPast
            for studentID in roster {
                note(assignment.lessonID, studentID) { detail in
                    Self.addDay(assignment.presentedAt, to: &detail)
                    if confirmed.contains(studentID) { detail.confirmed = true }
                }
                let current = latest[assignment.lessonID]?[studentID]
                if current == nil || presented > (current?.date ?? .distantPast) {
                    latest[assignment.lessonID, default: [:]][studentID] = (presented, assignment.objectID)
                }
            }
        }

        /// A year-plan entry that is not skipped is an open plan.
        mutating func fold(_ entry: CDYearPlanEntry) {
            guard entry.status != .skipped, keeps(entry.studentID) else { return }
            openPlan[entry.lessonID, default: []].insert(entry.studentID)
        }
    }

    // MARK: - Fetching

    private static func fetch<T: NSManagedObject>(
        _ type: T.Type, lessonIDs: Set<String>?, in context: NSManagedObjectContext
    ) -> [T] {
        let request = CDFetchRequest(T.self)
        if let lessonIDs {
            request.predicate = NSPredicate(format: "lessonID IN %@", Array(lessonIDs))
        }
        return context.safeFetch(request).filter { !$0.isDeleted }
    }
}
