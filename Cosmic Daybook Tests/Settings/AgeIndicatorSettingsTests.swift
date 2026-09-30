import Foundation
import SwiftUI
import Testing
@testable import CosmicDaybook

/// Pins the one age-indicator settings view: each kind keeps the exact keys
/// the cards read (stored settings must survive the merge), and the preview's
/// sample ages land in the fresh, warning and overdue bands.
@Suite("Age indicator settings")
@MainActor
struct AgeIndicatorSettingsTests {

    @Test("Lesson and work keep their stored key strings")
    func keysAreUnchanged() {
        let lesson = AgeIndicatorKind.lesson.keys
        #expect(lesson.warningDays == "LessonAge.warningDays")
        #expect(lesson.overdueDays == "LessonAge.overdueDays")
        #expect(lesson.freshColorHex == "LessonAge.freshColorHex")
        #expect(lesson.warningColorHex == "LessonAge.warningColorHex")
        #expect(lesson.overdueColorHex == "LessonAge.overdueColorHex")

        let work = AgeIndicatorKind.work.keys
        #expect(work.warningDays == "WorkAge.warningDays")
        #expect(work.overdueDays == "WorkAge.overdueDays")
        #expect(work.freshColorHex == "WorkAge.freshColorHex")
        #expect(work.warningColorHex == "WorkAge.warningColorHex")
        #expect(work.overdueColorHex == "WorkAge.overdueColorHex")
    }

    @Test("Each kind starts from its own defaults")
    func defaults() {
        #expect(AgeIndicatorKind.lesson.warningDays == LessonAgeDefaults.warningDays)
        #expect(AgeIndicatorKind.lesson.overdueColorHex == LessonAgeDefaults.overdueColorHex)
        #expect(AgeIndicatorKind.work.overdueDays == WorkAgeDefaults.overdueDays)
        #expect(AgeIndicatorKind.work.freshColorHex == WorkAgeDefaults.freshColorHex)
    }

    @Test("The preview shows one fresh, one warning and one overdue pill")
    func previewSpansTheBands() {
        let palette = StudentAgePalette(
            warningDays: LessonAgeDefaults.warningDays,
            overdueDays: LessonAgeDefaults.overdueDays,
            fresh: .blue, warning: .orange, overdue: .red
        )
        let samples = AgeIndicatorPreview.sampleDays(
            warningDays: palette.warningDays, overdueDays: palette.overdueDays
        )
        #expect(samples.map(palette.status(forDays:)) == [.fresh, .warning, .overdue])
    }

    @Test("The overdue sample is past the warning even when the thresholds are out of order")
    func outOfOrderThresholds() {
        let samples = AgeIndicatorPreview.sampleDays(warningDays: 10, overdueDays: 5)
        #expect(samples == [5, 10, 11])
    }

    @Test("Days are counted in school days, singular and plural")
    func schoolDays() {
        #expect(AgeIndicatorSettings.schoolDays(1) == "1 school day")
        #expect(AgeIndicatorSettings.schoolDays(6) == "6 school days")
    }
}
