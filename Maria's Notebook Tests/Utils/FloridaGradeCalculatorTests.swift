import Foundation
import Testing
@testable import Maria_s_Notebook

struct FloridaGradeCalculatorTests {

    /// Reference date after the (default Sept 1) school-year start, so ages are as-of Sept 1, 2026.
    private func reference() throws -> Date {
        try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 1)))
    }

    /// A birthday making the student exactly `age` on Sept 1, 2026 (born in March).
    private func birthday(age: Int) throws -> Date {
        try #require(Calendar.current.date(from: DateComponents(year: 2026 - age, month: 3, day: 1)))
    }

    @Test("Grade boundaries around the adolescent ages: 11→6th, 12→7th, 13→8th, 14→Graduated")
    func adolescentBoundaries() throws {
        let ref = try reference()
        #expect(FloridaGradeCalculator.grade(for: try birthday(age: 11), referenceDate: ref) == .grade(6))
        #expect(FloridaGradeCalculator.grade(for: try birthday(age: 12), referenceDate: ref) == .grade(7))
        #expect(FloridaGradeCalculator.grade(for: try birthday(age: 13), referenceDate: ref) == .grade(8))
        #expect(FloridaGradeCalculator.grade(for: try birthday(age: 14), referenceDate: ref) == .graduated)
    }

    @Test("7th and 8th grade display strings")
    func middleGradeDisplay() throws {
        let ref = try reference()
        #expect(FloridaGradeCalculator.grade(for: try birthday(age: 12), referenceDate: ref).displayString == "7th Grade")
        #expect(FloridaGradeCalculator.grade(for: try birthday(age: 13), referenceDate: ref).displayString == "8th Grade")
    }

    @Test("Younger boundaries are unchanged: under 6 → Kindergarten, 6 → 1st Grade")
    func youngBoundaries() throws {
        let ref = try reference()
        #expect(FloridaGradeCalculator.grade(for: try birthday(age: 5), referenceDate: ref) == .kindergarten)
        #expect(FloridaGradeCalculator.grade(for: try birthday(age: 6), referenceDate: ref) == .grade(1))
    }
}
