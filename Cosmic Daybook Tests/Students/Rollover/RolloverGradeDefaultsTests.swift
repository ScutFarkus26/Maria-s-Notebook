// RolloverGradeDefaultsTests.swift
// Domain logic review 2026-11-20, A8 (rollover part): the rollover sheet
// starts each child at the level her grade next year calls for (4th grade
// is Upper, 7th is Adolescent) rather than Stay for everyone.

import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

@Suite("Rollover grade defaults (domain logic A8)")
@MainActor
struct RolloverGradeDefaultsTests {

    private func makeStore() -> SchoolYearStore {
        let store = SchoolYearStore()
        store.publish = { _, _, _ in }
        return store
    }

    /// A birthday that makes her `age` on the grade cutoff of the year the
    /// sheet rolls into, so she is in grade `age - 5` that year.
    private func birthday(ageNextYear age: Int, store: SchoolYearStore) -> Date {
        let probe = SchoolYearRolloverViewModel()
        probe.load(students: [], store: store)
        let incomingStart = probe.incomingYear(store: store).start
        let cutoff = FloridaGradeCalculator.gradeCutoff(for: incomingStart, calendar: AppCalendar.shared)
        let years = AppCalendar.shared.date(byAdding: .year, value: -age, to: cutoff) ?? cutoff
        return AppCalendar.shared.date(byAdding: .month, value: -3, to: years) ?? years
    }

    @Test("A 3rd grader in Lower defaults to Upper at rollover")
    func thirdGraderGoesUp() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let store = makeStore()
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Pardo", level: .lower)
        ora.birthday = birthday(ageNextYear: 9, store: store)  // 4th grade next year

        let viewModel = SchoolYearRolloverViewModel()
        viewModel.load(students: [ora], store: store)

        #expect(viewModel.outcome(for: ora) == .promote(to: .upper))
    }

    @Test("Each child starts at the level her grade next year calls for")
    func defaultsFollowGrade() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let store = makeStore()
        func child(_ name: String, _ level: CDStudent.Level, ageNextYear: Int?) -> CDStudent {
            let student = CoreDataTestHelpers.seedStudent(in: context, firstName: name, lastName: "Test", level: level)
            student.birthday = ageNextYear.map { birthday(ageNextYear: $0, store: store) }
            return student
        }
        let second = child("Bina", .lower, ageNextYear: 8)       // 3rd grade next year
        let sixth = child("Chana", .upper, ageNextYear: 12)      // 7th grade next year
        let fifth = child("Dina", .upper, ageNextYear: 11)       // 6th grade next year
        let noBirthday = child("Esti", .lower, ageNextYear: nil)
        let graduating = child("Fruma", .adolescent, ageNextYear: 14)
        let alreadyUp = child("Gila", .upper, ageNextYear: 8)    // never moved down

        let viewModel = SchoolYearRolloverViewModel()
        viewModel.load(students: [second, sixth, fifth, noBirthday, graduating, alreadyUp], store: store)

        #expect(viewModel.outcome(for: second) == .stay)
        #expect(viewModel.outcome(for: sixth) == .promote(to: .adolescent))
        #expect(viewModel.outcome(for: fifth) == .stay)
        #expect(viewModel.outcome(for: noBirthday) == .stay)
        #expect(viewModel.outcome(for: graduating) == .stay)
        #expect(viewModel.outcome(for: alreadyUp) == .stay)
    }
}
