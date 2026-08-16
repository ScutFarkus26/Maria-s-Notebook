// SchoolYearRolloverViewModel.swift
// State for the guided school-year rollover sheet: the plan being assembled,
// the roster snapshot it applies to, and the assign → review → done phases.

import Foundation
import CoreData

@Observable
@MainActor
final class SchoolYearRolloverViewModel {

    enum Phase {
        case assign
        case review
        case done
    }

    var phase: Phase = .assign
    var plan = RolloverPlan()
    private(set) var students: [CDStudent] = []
    private(set) var appliedChangeCount = 0

    // MARK: - Loading

    /// Snapshots the enrolled roster and resets the plan. The snapshot (not a live
    /// fetch) also keeps departing students visible on the Done screen after apply.
    func load(students: [CDStudent], store: SchoolYearStore) {
        self.students = students.sorted { lhs, rhs in
            if lhs.level != rhs.level { return levelOrder(lhs.level) < levelOrder(rhs.level) }
            return lhs.fullName.localizedCaseInsensitiveCompare(rhs.fullName) == .orderedAscending
        }
        plan = RolloverPlan(effectiveDate: Self.defaultEffectiveDate(store: store))
        appliedChangeCount = 0
        phase = .assign
    }

    private func levelOrder(_ level: CDStudent.Level) -> Int {
        CDStudent.Level.allCases.firstIndex(of: level) ?? 0
    }

    /// Near a year boundary the rollover should be dated to the outgoing year's last
    /// day, so departures stay visible in that year's lens and drop out of the next.
    static func defaultEffectiveDate(today: Date = Date(), store: SchoolYearStore) -> Date {
        let calendar = AppCalendar.shared
        let current = store.current
        let lastDayOfCurrent = calendar.date(byAdding: .day, value: -1, to: current.end) ?? current.end
        // Closing stretch of the current year (within ~60 days of its end).
        if let window = calendar.date(byAdding: .day, value: 60, to: today), window >= current.end {
            return lastDayOfCurrent
        }
        // Just after a boundary: the rollover belongs to the year that just ended.
        let daysSinceStart = calendar.dateComponents([.day], from: current.start, to: today).day ?? 0
        if daysSinceStart < 30 {
            return calendar.date(byAdding: .day, value: -1, to: current.start) ?? today
        }
        return today
    }

    // MARK: - Year math

    /// The school year the effective date falls in (the year being closed out).
    func outgoingYear(store: SchoolYearStore) -> SchoolYear {
        SchoolYear.containing(
            plan.effectiveDate,
            startMonth: store.startMonth, startDay: store.startDay, calendar: AppCalendar.shared
        )
    }

    /// The school year after the effective date (the year being rolled into).
    func incomingYear(store: SchoolYearStore) -> SchoolYear {
        let outgoing = outgoingYear(store: store)
        return SchoolYear.beginning(
            in: outgoing.beginYear + 1,
            startMonth: store.startMonth, startDay: store.startDay, calendar: AppCalendar.shared
        )
    }

    /// Explains what the chosen effective date means for the school-year lens.
    func lensFootnote(store: SchoolYearStore) -> String {
        let outgoing = outgoingYear(store: store)
        let incoming = incomingYear(store: store)
        return "Departing students dated \(DateFormatters.mediumDate.string(from: plan.effectiveDate)) "
            + "stay visible when viewing \(outgoing.label) and leave the \(incoming.label) roster."
    }

    // MARK: - Outcomes

    func outcome(for student: CDStudent) -> RolloverOutcome {
        plan.outcome(for: student.id)
    }

    func setOutcome(_ outcome: RolloverOutcome, for student: CDStudent) {
        guard let id = student.id else { return }
        if case .stay = outcome {
            plan.outcomes[id] = nil
        } else {
            plan.outcomes[id] = outcome
        }
    }

    /// Assigns one outcome to every student currently at `level`.
    func bulkAssign(_ outcome: RolloverOutcome, toLevel level: CDStudent.Level) {
        for student in students where student.level == level {
            setOutcome(outcome, for: student)
        }
    }

    var summary: RolloverSummary {
        RolloverService.summary(for: plan, students: students)
    }

    var changeCount: Int { summary.changeCount }

    /// Roster grouped by current level, in ladder order, for the assign list.
    var studentsByLevel: [(level: CDStudent.Level, students: [CDStudent])] {
        CDStudent.Level.allCases.compactMap { level in
            let group = students.filter { $0.level == level }
            return group.isEmpty ? nil : (level, group)
        }
    }

    /// Students in a given outcome bucket, for the review lists.
    func students(with outcome: RolloverOutcome) -> [CDStudent] {
        students.filter { self.outcome(for: $0) == outcome }
    }

    /// Everyone leaving the class (transfer or withdraw) — the Done screen offers
    /// a PDF summary for each.
    var departingStudents: [CDStudent] {
        students.filter { student in
            switch outcome(for: student) {
            case .transfer, .withdraw: return true
            case .stay, .promote: return false
            }
        }
    }

    // MARK: - Apply

    func apply(context: NSManagedObjectContext, store: SchoolYearStore) {
        appliedChangeCount = RolloverService.apply(
            plan,
            students: students,
            incomingYearLabel: incomingYear(store: store).label,
            context: context
        )
        phase = .done
    }

    // MARK: - Report support

    /// Number of report-flagged observations visible to this student in the outgoing
    /// year — the notes a generated PDF summary would draw from. Mirrors
    /// `ReportGeneratorService.fetchReportNotes`.
    func flaggedNoteCount(
        for student: CDStudent,
        store: SchoolYearStore,
        context: NSManagedObjectContext
    ) -> Int {
        guard let studentID = student.id else { return 0 }
        let year = outgoingYear(store: store)
        let request = CDFetchRequest(CDNote.self)
        request.predicate = NSPredicate(
            format: "includeInReport == YES AND createdAt >= %@ AND createdAt < %@",
            year.start as NSDate, year.end as NSDate
        )
        let flagged = context.safeFetch(request)
        return flagged.filter { note in
            note.scopeIsAll || note.searchIndexStudentID == studentID || note.scope.applies(to: studentID)
        }.count
    }
}
