// SchoolYearRolloverViewModel.swift
// State for the guided school-year rollover sheet: the plan being assembled,
// the roster snapshot it applies to, and the assign → review → done phases.

import Foundation
import CoreData

@Observable
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
    /// Set when Apply's save failed; the sheet shows it and stays on Review.
    var applyErrorMessage: String?
    /// The carry-over counts as they stood when Apply was pressed — after the
    /// entries move, re-deriving them would report zero.
    private(set) var appliedCarryOver = RolloverSummary()

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
    ///
    /// From the middle of the year on (spring, when school lets out, and the summer
    /// before the next start) that is this year's last day. In its first half the
    /// year to close out is the one that has already ended, so the default is the
    /// day before this year's first day. It used to be today once the year was more
    /// than 30 days old, which in autumn closed out the year still under way
    /// (2026-10-11 hunt, #35); a closing stretch of only 60 days then sent a June
    /// rollover back a year (review 2026-10-11 (c) #1).
    static func defaultEffectiveDate(today: Date = Date(), store: SchoolYearStore) -> Date {
        let calendar = AppCalendar.shared
        let current = currentYear(today: today, store: store)
        if isInSecondHalf(today, of: current) {
            return calendar.date(byAdding: .day, value: -1, to: current.end) ?? current.end
        }
        return calendar.date(byAdding: .day, value: -1, to: current.start) ?? today
    }

    /// The school year under way on `today`, by the store's start.
    private static func currentYear(today: Date, store: SchoolYearStore) -> SchoolYear {
        SchoolYear.containing(
            today, startMonth: store.startMonth, startDay: store.startDay, calendar: AppCalendar.shared
        )
    }

    /// On or after the year's midpoint: the half in which the year to close out
    /// is this one (its last 60 days, the usual time to roll over, included).
    private static func isInSecondHalf(_ date: Date, of year: SchoolYear) -> Bool {
        let midpoint = year.start.addingTimeInterval(year.end.timeIntervalSince(year.start) / 2)
        return date >= midpoint
    }

    // MARK: - Year math

    /// The school year the effective date falls in (the year being closed out).
    func outgoingYear(store: SchoolYearStore) -> SchoolYear {
        SchoolYear.containing(
            plan.effectiveDate,
            startMonth: store.startMonth, startDay: store.startDay, calendar: AppCalendar.shared
        )
    }

    /// The school year being rolled into. Closing out a year that has already
    /// ended rolls into the year under way, the store's current one; closing out
    /// the current year (its closing stretch) rolls into the next.
    func incomingYear(store: SchoolYearStore, today: Date = Date()) -> SchoolYear {
        let outgoing = outgoingYear(store: store)
        let current = Self.currentYear(today: today, store: store)
        if outgoing.beginYear < current.beginYear { return current }
        return SchoolYear.beginning(
            in: outgoing.beginYear + 1,
            startMonth: store.startMonth, startDay: store.startDay, calendar: AppCalendar.shared
        )
    }

    /// True when the effective date falls in the first half of the year still
    /// under way: the rollover would close out a year barely begun and roll
    /// into one that hasn't, so the sheet asks first.
    func closesYearInProgress(store: SchoolYearStore, today: Date = Date()) -> Bool {
        let current = Self.currentYear(today: today, store: store)
        return current.range.contains(plan.effectiveDate)
            && !Self.isInSecondHalf(plan.effectiveDate, of: current)
    }

    /// What the sheet says when `closesYearInProgress`; nil otherwise.
    func yearInProgressWarning(store: SchoolYearStore, today: Date = Date()) -> String? {
        guard closesYearInProgress(store: store, today: today) else { return nil }
        let current = Self.currentYear(today: today, store: store)
        let lastYearEnd = AppCalendar.shared.date(byAdding: .day, value: -1, to: current.start) ?? current.start
        return "This date is in the school year still under way, so the rollover will close out "
            + "\(outgoingYear(store: store).label) and roll into \(incomingYear(store: store, today: today).label). "
            + "To close out last year instead, set the date to "
            + "\(DateFormatters.mediumDate.string(from: lastYearEnd)) or earlier."
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

    /// Planned, not-yet-given lessons that name a child being transferred or
    /// withdrawn; `apply` takes those children off them.
    func futurePlansForDeparting(context: NSManagedObjectContext) -> Int {
        RolloverService.summary(for: plan, students: students, context: context).futurePlansForDeparting
    }

    /// Year-plan entries still pencilled in for a departing child; `apply`
    /// marks them skipped so they stop counting as behind pace.
    func yearPlanEntriesForDeparting(context: NSManagedObjectContext) -> Int {
        RolloverService.summary(for: plan, students: students, context: context).yearPlanEntriesForDeparting
    }

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
        let carryOver = carryOverCounts(context: context, store: store)
        do {
            appliedChangeCount = try RolloverService.apply(
                plan,
                students: students,
                incomingYearLabel: incomingYear(store: store).label,
                carryOverLanding: carryOverLandingDate(store: store, context: context),
                carryOverBefore: incomingYear(store: store).start,
                context: context
            )
        } catch {
            // Stay on Review so the guide can try again; nothing was changed.
            applyErrorMessage = (error as? RolloverService.ApplyError)?.errorDescription
                ?? RolloverService.ApplyError.saveFailed.errorDescription
            return
        }
        appliedCarryOver = carryOver
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
