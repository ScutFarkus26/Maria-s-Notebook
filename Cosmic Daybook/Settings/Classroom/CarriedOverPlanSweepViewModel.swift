// CarriedOverPlanSweepViewModel.swift
// State for the one-time sweep of year-plan entries left over from a school
// year that has ended.
//
// The rollover asks the same question at the boundary, but the boundary has
// already passed for this notebook: children opened the year carrying targets
// from last April. This is the same choice, offered any time from Settings →
// School Calendar, over the whole roster at once.
//
// Nothing is written until Apply, and Apply is a single `safeSave` so the
// whole sweep is one atomic change.

import CoreData
import Foundation

@Observable
@MainActor
final class CarriedOverPlanSweepViewModel {

    enum Phase {
        case choose
        case done
    }

    private(set) var surveys: [YearPlanCarryOver.Survey] = []
    var choices: [UUID: YearPlanCarryOverChoice] = [:]
    var landing: Date = Date()
    private(set) var phase: Phase = .choose
    private(set) var redatedEntries = 0
    private(set) var skippedEntries = 0
    private(set) var childrenTouched = 0
    /// Re-dated targets that now fall past the end of this school year. Stated,
    /// never fixed: compressing the spacing to make them fit would rewrite the
    /// guide's pacing behind her back.
    private(set) var pastYearEnd = 0

    /// The boundary the whole sheet is measured against, fixed at load so a
    /// midnight rollover cannot change it under an open sheet.
    private(set) var yearStart: Date = YearPlanStaleness.currentYearStart()

    // MARK: - Loading

    func load(
        context: NSManagedObjectContext,
        showTestStudents: Bool,
        testStudentNames: String
    ) {
        yearStart = YearPlanStaleness.currentYearStart()
        let request = CDFetchRequest(CDStudent.self)
        request.predicate = CDStudent.enrolledPredicate
        request.sortDescriptors = CDStudent.sortByName
        let roster = context.safeFetch(request)
            .visibleRoster(showTest: showTestStudents, testNames: testStudentNames)
        surveys = YearPlanCarryOver.survey(roster, in: context, yearStart: yearStart)
        choices = [:]
        landing = YearPlanPacing.schoolDay(
            onOrAfter: AppCalendar.addingDays(1, to: AppCalendar.startOfDay(Date())), in: context
        )
        phase = .choose
        redatedEntries = 0
        skippedEntries = 0
        childrenTouched = 0
        pastYearEnd = 0
    }

    // MARK: - Choices

    func choice(for studentID: UUID) -> YearPlanCarryOverChoice {
        choices[studentID] ?? .leave
    }

    func setChoice(_ choice: YearPlanCarryOverChoice, for studentID: UUID) {
        if choice == .leave {
            choices[studentID] = nil
        } else {
            choices[studentID] = choice
        }
    }

    func setAll(_ choice: YearPlanCarryOverChoice) {
        for survey in surveys {
            setChoice(choice, for: survey.studentID)
        }
    }

    var hasRedateChoice: Bool { choices.values.contains(.redate) }

    var totalEntries: Int { surveys.reduce(0) { $0 + $1.count } }

    /// How many entries the current choices would move or retire — the number
    /// on the Apply button, and the reason it is disabled at zero.
    var affectedEntries: Int {
        surveys.reduce(0) { total, survey in
            choice(for: survey.studentID) == .leave ? total : total + survey.count
        }
    }

    // MARK: - Applying

    func apply(context: NSManagedObjectContext) {
        var redated = 0
        var skipped = 0
        var children = 0
        var overshot = 0
        let yearEnd = YearPlanStaleness.schoolYear(containing: Date()).end
        for survey in surveys {
            let decision = choice(for: survey.studentID)
            guard decision != .leave else { continue }
            let entries = YearPlanCarryOver.entries(
                for: survey.studentID, in: context, yearStart: yearStart
            )
            guard !entries.isEmpty else { continue }
            children += 1
            switch decision {
            case .leave:
                continue
            case .redate:
                redated += YearPlanCarryOver.redate(entries, landingOn: landing, in: context)
                overshot += YearPlanCarryOver.landingAfterYearEnd(entries, yearEnd: yearEnd)
            case .skip:
                skipped += YearPlanCarryOver.skip(entries)
            }
        }
        if redated > 0 || skipped > 0 {
            context.safeSave()
        }
        redatedEntries = redated
        skippedEntries = skipped
        childrenTouched = children
        pastYearEnd = overshot
        stampSweptYear()
        phase = .done
    }

    /// "Re-dated 7 entries for 2 children. Skipped 3 for 1 child."
    var receipt: String {
        var parts: [String] = []
        if redatedEntries > 0 {
            parts.append("Re-dated \(redatedEntries) \(redatedEntries == 1 ? "entry" : "entries") "
                + "from \(DateFormatters.mediumDate.string(from: landing))")
        }
        if skippedEntries > 0 {
            parts.append("Skipped \(skippedEntries) \(skippedEntries == 1 ? "entry" : "entries")")
        }
        guard !parts.isEmpty else { return "Nothing was changed." }
        let children = "\(childrenTouched) \(childrenTouched == 1 ? "child" : "children")"
        var text = parts.joined(separator: " · ") + " for \(children). Nothing was deleted."
        if pastYearEnd > 0 {
            let end = DateFormatters.mediumDate.string(
                from: AppCalendar.addingDays(-1, to: YearPlanStaleness.schoolYear(containing: Date()).end)
            )
            text += " \(pastYearEnd) of the re-dated "
                + (pastYearEnd == 1 ? "target lands" : "targets land")
                + " after \(end), the last day of this school year — "
                + "run it again from an earlier day, or shorten the plan."
        }
        return text
    }

    /// Records that this school year's sweep has been run, which drops the
    /// count badge in Settings. The button itself always stays.
    private func stampSweptYear() {
        let year = YearPlanStaleness.schoolYear(containing: Date()).beginYear
        UserDefaults.standard.set(year, forKey: UserDefaultsKeys.yearPlanCarryOverSweepYear)
    }

    /// How many carried-over entries the whole roster holds, for the Settings
    /// badge. Nil once this year's sweep has been run.
    static func badgeCount(
        context: NSManagedObjectContext,
        showTestStudents: Bool,
        testStudentNames: String
    ) -> Int? {
        let year = YearPlanStaleness.schoolYear(containing: Date())
        let swept = UserDefaults.standard.object(forKey: UserDefaultsKeys.yearPlanCarryOverSweepYear) as? Int
        guard swept != year.beginYear else { return nil }
        let request = CDFetchRequest(CDStudent.self)
        request.predicate = CDStudent.enrolledPredicate
        let roster = context.safeFetch(request)
            .visibleRoster(showTest: showTestStudents, testNames: testStudentNames)
        let total = YearPlanCarryOver
            .survey(roster, in: context, yearStart: year.start)
            .reduce(0) { $0 + $1.count }
        return total > 0 ? total : nil
    }
}
