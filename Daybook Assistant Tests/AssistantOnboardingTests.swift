import Foundation
import SwiftUI
import Testing
@testable import Daybook_Assistant

// Onboarding: what this iPhone remembers about the intro and setup, the
// practice grid's marks, and the reminder time the setup page edits.
@Suite("Assistant onboarding")
@MainActor
struct AssistantOnboardingTests {

    // MARK: - Remembered

    @Test("A new iPhone hasn't seen the intro; reaching the invitation page remembers it")
    func introSeen() {
        let defaults = AssistantTestSupport.makeDefaults()
        #expect(!AssistantOnboarding.introSeen(defaults))
        AssistantOnboarding.markIntroSeen(defaults)
        #expect(AssistantOnboarding.introSeen(defaults))
    }

    @Test("Setup shows until it's finished")
    func setupUntilDone() {
        let defaults = AssistantTestSupport.makeDefaults()
        #expect(AssistantOnboarding.needsSetup(isSample: false, defaults: defaults))
        AssistantOnboarding.markSetupDone(defaults)
        #expect(!AssistantOnboarding.needsSetup(isSample: false, defaults: defaults))
    }

    @Test("The sample class never shows setup")
    func noSetupOverSample() {
        let defaults = AssistantTestSupport.makeDefaults()
        #expect(!AssistantOnboarding.needsSetup(isSample: true, defaults: defaults))
    }

    @Test("A name restored from iCloud fills an empty name field, never over what she's typed")
    func restoredNameFills() {
        #expect(AssistantNameSheet.restoredName(typed: "", stored: "Rivka") == "Rivka")
        #expect(AssistantNameSheet.restoredName(typed: "  ", stored: " Rivka ") == "Rivka")
        #expect(AssistantNameSheet.restoredName(typed: "Chana", stored: "Rivka") == nil)
        #expect(AssistantNameSheet.restoredName(typed: "", stored: nil) == nil)
        #expect(AssistantNameSheet.restoredName(typed: "", stored: "   ") == nil)
    }

    // MARK: - Practice grid

    @Test("During arrival a tap marks here and a second tap takes it back")
    func arrivalTaps() {
        var roll = AssistantPracticeRoll()
        roll.tap("Maya")
        #expect(roll.status(of: "Maya") == .present)
        #expect(roll.hereCount == 1)
        #expect(roll.unmarkedCount == AssistantPracticeRoll.names.count - 1)
        roll.tap("Maya")
        #expect(roll.status(of: "Maya") == .unmarked)
        #expect(roll.hereCount == 0)
    }

    @Test("Close Arrival marks everyone left absent, and the marks already made stay")
    func closeArrival() {
        var roll = AssistantPracticeRoll()
        roll.tap("Ari")
        roll.tap("Noah")
        roll.closeArrival()
        #expect(roll.phase == .late)
        #expect(roll.status(of: "Ari") == .present)
        #expect(roll.status(of: "Leah") == .absent)
        #expect(roll.hereCount == 2)
        #expect(roll.absentCount == AssistantPracticeRoll.names.count - 2)
        #expect(roll.unmarkedCount == 0)
    }

    @Test("After arrival a tap marks an absent child late, and a second tap takes it back")
    func lateTaps() {
        var roll = AssistantPracticeRoll()
        roll.tap("Ari")
        roll.closeArrival()
        roll.tap("Leah")
        #expect(roll.status(of: "Leah") == .tardy)
        #expect(roll.hereCount == 2)
        roll.tap("Leah")
        #expect(roll.status(of: "Leah") == .absent)
        // A child already here is left alone, as on the real grid.
        roll.tap("Ari")
        #expect(roll.status(of: "Ari") == .present)
    }

    @Test("Start Over clears the marks and reopens arrival")
    func startOver() {
        var roll = AssistantPracticeRoll()
        roll.tap("Ari")
        roll.closeArrival()
        roll.reset()
        #expect(roll == AssistantPracticeRoll())
        #expect(roll.phase == .arrival)
    }

    // MARK: - Reminder time

    @Test("The reminder picker reads and writes minutes after midnight")
    func reminderTime() throws {
        let stored = StoredMinutes()
        let binding = Binding(get: { stored.value }, set: { stored.value = $0 })
        let time = ArrivalReminder.timeOfDay(binding)
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time.wrappedValue)
        #expect(parts.hour == 8)
        #expect(parts.minute == 15)

        let midnight = Calendar.current.startOfDay(for: Date())
        time.wrappedValue = try #require(Calendar.current.date(byAdding: .minute, value: 7 * 60 + 40, to: midnight))
        #expect(stored.value == 7 * 60 + 40)
    }
}

/// The setting a binding writes through, as `@AppStorage` would hold it.
private final class StoredMinutes: @unchecked Sendable {
    var value = ArrivalReminder.defaultMinutes
}
