import Foundation
import Testing
@testable import Maria_s_Notebook

/// "Set Aside Until" is the first thing in the app outside a student meeting
/// that writes `restingUntil`, and the triage rule reads that field before
/// every reason to nag. So the boundary matters: a preset that resolves to
/// today would set the work aside and wake it in the same breath.
@Suite("Work rest presets")
struct WorkRestPresetTests {

    private let calendar = AppCalendar.shared

    @Test("Every preset wakes the work strictly after today")
    func everyPresetIsInTheFuture() {
        let now = Date()
        let today = AppCalendar.startOfDay(now)

        for preset in WorkRestPreset.allCases {
            let wake = preset.wakeDate(from: now, calendar: calendar)
            #expect(wake > today, "\(preset.title) does not outlast today")
            #expect(wake == AppCalendar.startOfDay(wake), "\(preset.title) is not a whole day")
        }
    }

    @Test("Resting work reads as scheduled until its date, and needs the guide after")
    func triageHonorsThePresets() {
        let now = Date()

        for preset in WorkRestPreset.allCases {
            let wake = preset.wakeDate(from: now, calendar: calendar)
            // Stale enough to be nagging, were it not resting.
            let input = WorkTriageInput(
                status: .active,
                restingUntil: wake,
                schoolDaysSinceLastTouch: LessonsAndWorkTriage.staleSchoolDays + 5
            )

            #expect(
                LessonsAndWorkTriage.bucket(for: input, asOf: now) == .scheduled,
                "\(preset.title) did not quiet the card"
            )

            // The day it comes back, it asks for the guide again.
            let afterWaking = calendar.date(byAdding: .day, value: 1, to: wake) ?? wake
            #expect(
                LessonsAndWorkTriage.bucket(for: input, asOf: afterWaking) == .attention,
                "\(preset.title) stayed asleep past its date"
            )
        }
    }

    @Test("The presets are ordered nearest-first, and none collide")
    func presetsAreDistinctAndOrdered() {
        let now = Date()
        let dates = WorkRestPreset.allCases.map { $0.wakeDate(from: now, calendar: calendar) }

        #expect(Set(dates).count == dates.count, "two presets resolve to the same day")
        #expect(dates == dates.sorted(), "the menu would read out of order")
    }
}
