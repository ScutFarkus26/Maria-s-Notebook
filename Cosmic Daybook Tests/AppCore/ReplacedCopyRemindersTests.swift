import Testing
@testable import CosmicDaybook

// MARK: - Reminders when a copy is replaced, and after imports
//
// The install script opens the copy it is about to replace with
// `-CosmicDaybookClearReminders YES`; that launch removes its reminders and
// quits before the notebook opens, so the parse must never turn on for an
// ordinary launch. And the notebook rebuilds its attendance reminder after an
// import only when the import can move it.

@Suite("Replaced copy's reminders")
struct ReplacedCopyRemindersTests {
    private static let executable = "/Applications/Cosmic Daybook.app/Contents/MacOS/Cosmic Daybook"

    @Test("The install script's arguments ask for the hand-off", arguments: ["YES", "yes", "true", "1"])
    func scriptArgumentsAsk(value: String) {
        #expect(ReplacedCopyReminders.isRequested(arguments: [Self.executable, "-CosmicDaybookClearReminders", value]))
    }

    @Test("Ordinary launches never clear reminders", arguments: [
        [],
        ["-CosmicDaybookClearReminders"],
        ["-CosmicDaybookClearReminders", "NO"],
        ["-CosmicDaybookMCPAutolaunch", "YES"],
        ["-NSDocumentRevisionsDebugMode", "YES"]
    ])
    func ordinaryLaunches(extra: [String]) {
        #expect(!ReplacedCopyReminders.isRequested(arguments: [Self.executable] + extra))
        #expect(!ReplacedCopyReminders.isRequested(arguments: extra))
    }

    @Test("A send or the guide's settings arriving moves the reminder")
    func sendsAndSettingsMoveIt() {
        #expect(AppBootstrapper.importMovesFrontDeskReminder(["AttendanceRecord", "AttendanceEmailSend"]))
        #expect(AppBootstrapper.importMovesFrontDeskReminder(["AttendanceEmailSettings"]))
    }

    @Test("Other imports leave it alone")
    func otherImportsDont() {
        #expect(!AppBootstrapper.importMovesFrontDeskReminder(["AttendanceRecord", "Lesson", "Student"]))
        #expect(!AppBootstrapper.importMovesFrontDeskReminder([]))
    }

    @Test("The reminder's entities are ones the history processor reports")
    func entitiesAreReported() {
        let reported = PersistentHistoryProcessor.presentationEntityNames
        #expect(AppBootstrapper.frontDeskReminderEntities.isSubset(of: reported))
    }
}
