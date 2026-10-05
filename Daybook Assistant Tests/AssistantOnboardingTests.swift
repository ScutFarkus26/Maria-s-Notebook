import Foundation
import CoreData
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

    // MARK: - Her name in the classroom's list

    @Test("Saving her name sets her row in the classroom's list, and passes a new row on to go into the share")
    func nameJoinsTheList() throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        var saves: [[NSManagedObject]] = []
        let save = { (context: NSManagedObjectContext, created: [NSManagedObject]) -> Bool in
            saves.append(created)
            return context.safeSave()
        }
        try AssistantRestockTestSupport.asIdentity("_ana", named: nil) {
            #expect(AssistantNameStore.setInList("Ana", in: context, save: save))
            let first = try #require(saves.first?.first as? CDClassroomPerson)
            #expect(first.recordName == "_ana")
            #expect(first.role == .assistant)
            #expect(first.displayName == "Ana")
            #expect(!context.hasChanges)

            // A rename updates the same row; nothing new goes into the share.
            #expect(AssistantNameStore.setInList("Anna", in: context, save: save))
            #expect(saves.count == 2)
            #expect(saves[1].isEmpty)
            #expect(context.safeFetch(CDFetchRequest(CDClassroomPerson.self)).map(\.displayName) == ["Anna"])
            #expect(ClassroomNames.snapshot(in: context).name(forRecordName: "_ana") == "Anna")
            #expect(ClassroomIdentity.displayName == "Anna")

            // The same name again saves nothing.
            #expect(AssistantNameStore.setInList("Anna", in: context, save: save))
            #expect(saves.count == 2)
        }
    }

    @Test("Before her record name is known her name waits, and launch writes it to the list once it is")
    func nameWaitsForRecordName() throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        try AssistantRestockTestSupport.asIdentity(nil, named: nil) {
            var saved = false
            #expect(AssistantNameStore.setInList("Ana", in: context) { _, _ in
                saved = true
                return true
            })
            #expect(!saved)
            #expect(ClassroomIdentity.displayName == "Ana")
            #expect(ClassroomIdentity.nameWaitingAs == .assistant)
            #expect(context.safeFetch(CDFetchRequest(CDClassroomPerson.self)).isEmpty)

            // Launch: iCloud says who she is, then the waiting name is written.
            ClassroomIdentity.currentUserRecordName = "_ana"
            #expect(AssistantNameStore.writeWaitingName(in: context, container: nil))
            let rows = context.safeFetch(CDFetchRequest(CDClassroomPerson.self))
            #expect(rows.map(\.displayName) == ["Ana"])
            #expect(rows.map(\.recordName) == ["_ana"])
            #expect(!context.hasChanges)
            #expect(ClassroomIdentity.nameWaitingAs == nil)
            #expect(ClassroomIdentity.displayName == "Ana", "her own marks are still stamped with it")

            // The next launch has nothing to write.
            #expect(!AssistantNameStore.writeWaitingName(in: context, container: nil))
        }
    }

    @Test("A name she gave before the list existed joins it at launch without her typing it again")
    func olderNameJoinsAtLaunch() throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        try AssistantRestockTestSupport.asIdentity("_ana", named: "Ana") {
            #expect(AssistantNameStore.writeWaitingName(in: context, container: nil))
            #expect(ClassroomNames.snapshot(in: context).name(forRecordName: "_ana") == "Ana")
        }
    }

    @Test("The sample class's guide has a name in the sample's own list")
    func sampleGuideName() throws {
        let sample = try AssistantSampleClass.makeStack()
        let names = ClassroomNames.snapshot(in: sample.viewContext)
        #expect(names.guideName == AssistantSampleClass.guideName)
        #expect(names.name(forRecordName: AssistantSampleClass.guideRecordName) == "Ms. Rivera")
        #expect(sample.viewContext.safeFetch(CDFetchRequest(CDClassroomPerson.self)).count == 1)
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
