// SchoolYearRolloverViewModel+CarryOver.swift
// The rollover's carried-over year-plan choice: which children have entries
// left over from the outgoing year, what the guide chose for each, and where a
// re-dated run starts.
//
// Split out of the view model so that type stays under the 350-line limit; the
// state itself lives on `RolloverPlan`, so a choice travels with the plan into
// `RolloverService.apply` rather than being re-derived at apply time.

import CoreData
import Foundation

extension SchoolYearRolloverViewModel {

    /// A row per child on the roster who has entries targeted at the outgoing
    /// year. Empty when there is nothing to decide, which hides the section.
    func carryOverSurvey(context: NSManagedObjectContext, store: SchoolYearStore) -> [YearPlanCarryOver.Survey] {
        YearPlanCarryOver.survey(continuingStudents, in: context, yearStart: incomingYear(store: store).start)
    }

    /// Only children staying or being promoted are asked about: a departing
    /// child's plan is skipped wholesale by the departure cascade.
    var continuingStudents: [CDStudent] {
        students.filter { student in
            switch outcome(for: student) {
            case .stay, .promote: return true
            case .transfer, .withdraw: return false
            }
        }
    }

    func carryOverChoice(for studentID: UUID) -> YearPlanCarryOverChoice {
        plan.carryOverChoice(for: studentID)
    }

    func setCarryOver(_ choice: YearPlanCarryOverChoice, for studentID: UUID) {
        if choice == .leave {
            plan.carryOver[studentID] = nil
        } else {
            plan.carryOver[studentID] = choice
        }
    }

    /// Applies one choice to every child in the survey.
    func bulkCarryOver(_ choice: YearPlanCarryOverChoice, in surveys: [YearPlanCarryOver.Survey]) {
        for survey in surveys {
            setCarryOver(choice, for: survey.studentID)
        }
    }

    /// Where a re-dated run starts: the guide's own date if she picked one
    /// no earlier than `earliestCarryOverLanding`, otherwise that earliest day.
    func carryOverLandingDate(
        store: SchoolYearStore, context: NSManagedObjectContext, today: Date = Date()
    ) -> Date {
        let earliest = earliestCarryOverLanding(store: store, context: context, today: today)
        guard let asked = plan.carryOverLanding, AppCalendar.startOfDay(asked) > earliest else {
            return earliest
        }
        return YearPlanPacing.schoolDay(onOrAfter: asked, in: context)
    }

    /// The first day a re-dated run may start: the first open day of the year
    /// being rolled into, or of the days after today once that year has begun.
    /// Since an autumn rollover closes out last year (10-11), the incoming
    /// year's start was weeks past, and every re-dated entry read "Behind"
    /// the moment it landed (bug hunt 2026-10-12 #52). The Settings sweep
    /// starts from tomorrow for the same reason.
    func earliestCarryOverLanding(
        store: SchoolYearStore, context: NSManagedObjectContext, today: Date = Date()
    ) -> Date {
        let tomorrow = AppCalendar.addingDays(1, to: AppCalendar.startOfDay(today))
        let start = AppCalendar.startOfDay(incomingYear(store: store, today: today).start)
        return YearPlanPacing.schoolDay(onOrAfter: max(start, tomorrow), in: context)
    }

    /// True once any child has been given a re-date choice — the landing-date
    /// picker only makes sense then.
    var hasRedateChoice: Bool {
        plan.carryOver.values.contains(.redate)
    }

    /// What the review step states before anything is written.
    func carryOverCounts(context: NSManagedObjectContext, store: SchoolYearStore) -> RolloverSummary {
        RolloverService.summary(
            for: plan, students: students, context: context, carryOverBefore: incomingYear(store: store).start
        )
    }

    /// Whether there is anything to review: a child changing, or a carried-over
    /// choice that moves or skips entries. A rollover run only to sort out
    /// last year's plans used to be stuck on the first step (bug hunt
    /// 2026-10-12 #54).
    func canReview(context: NSManagedObjectContext, store: SchoolYearStore) -> Bool {
        guard changeCount == 0 else { return true }
        let counts = carryOverCounts(context: context, store: store)
        return counts.carriedOverToRedate + counts.carriedOverToSkip > 0
    }

    /// The review step's button: the number of children changing, when any are.
    var applyButtonTitle: String {
        changeCount > 0 ? "Apply Rollover (\(changeCount))" : "Apply Rollover"
    }

    /// The Done screen's line: the children changed and, from the counts taken
    /// when Apply was pressed, what happened to last year's plans (#54).
    /// "Applied 3 changes. Re-dated 7 carried-over year-plan entries."
    var appliedSummaryText: String {
        let count = appliedChangeCount
        var sentences: [String] = []
        if count > 0 || appliedCarryOverParts.isEmpty {
            sentences.append("Applied \(count) change\(count == 1 ? "" : "s").")
        }
        if !appliedCarryOverParts.isEmpty {
            let joined = appliedCarryOverParts.joined(separator: " and ")
            sentences.append(joined.prefix(1).uppercased() + joined.dropFirst() + ".")
        }
        return sentences.joined(separator: " ")
    }

    private var appliedCarryOverParts: [String] {
        let redated = appliedCarryOver.carriedOverToRedate
        let skipped = appliedCarryOver.carriedOverToSkip
        var parts: [String] = []
        if redated > 0 {
            parts.append("re-dated \(redated) carried-over year-plan \(redated == 1 ? "entry" : "entries")")
        }
        if skipped > 0 {
            parts.append("skipped \(skipped) carried-over year-plan \(skipped == 1 ? "entry" : "entries")")
        }
        return parts
    }
}
