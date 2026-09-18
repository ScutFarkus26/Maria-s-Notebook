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
    func carryOverSurvey(context: NSManagedObjectContext) -> [YearPlanCarryOver.Survey] {
        YearPlanCarryOver.survey(
            continuingStudents, in: context, yearStart: YearPlanStaleness.currentYearStart()
        )
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

    /// Where a re-dated run starts: the guide's own date if she picked one,
    /// otherwise the first open day of the year being rolled into.
    func carryOverLandingDate(store: SchoolYearStore, context: NSManagedObjectContext) -> Date {
        let asked = plan.carryOverLanding ?? incomingYear(store: store).start
        return YearPlanPacing.schoolDay(onOrAfter: asked, in: context)
    }

    /// True once any child has been given a re-date choice — the landing-date
    /// picker only makes sense then.
    var hasRedateChoice: Bool {
        plan.carryOver.values.contains(.redate)
    }

    /// What the review step states before anything is written.
    func carryOverCounts(context: NSManagedObjectContext) -> RolloverSummary {
        RolloverService.summary(for: plan, students: students, context: context)
    }
}
