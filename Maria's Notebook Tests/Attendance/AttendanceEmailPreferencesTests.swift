import Foundation
import Testing
@testable import Maria_s_Notebook

// AttendanceEmailBodyTests passes the formatting options in directly, so it never exercises
// the step where the report reads them back out of SyncedPreferencesStore — which is where
// both settings quietly stopped reaching the email. These cover that seam, plus the change
// counter that is the only thing telling SwiftUI to redraw a @SyncedAppStorage control.
@MainActor
@Suite("Attendance email preferences")
struct AttendanceEmailPreferencesTests {

    private static let reportFormatKeys = [
        AttendanceEmailPrefs.nameOrderKey,
        AttendanceEmailPrefs.groupByLevelKey
    ]

    private let students = [
        AttendanceEmailStudent(firstName: "Ada", lastName: "Zeller", level: .upper),
        AttendanceEmailStudent(firstName: "Bo", lastName: "Adams", level: .adolescent)
    ]

    /// Runs `work` with the report-format keys unset, then puts back whatever was stored.
    private func withCleanPreferences(_ work: () -> Void) {
        let store = SyncedPreferencesStore.shared
        let saved = Self.reportFormatKeys.map { ($0, store.get(key: $0)) }
        defer {
            for (key, value) in saved { store.set(value, forKey: key) }
        }
        for key in Self.reportFormatKeys { store.remove(key: key) }
        work()
    }

    private func bodyLines() -> [String] {
        AttendanceEmail
            .makeBody(present: students, tardy: [], absent: [], date: Date())
            .components(separatedBy: "\n")
    }

    @Test("Unset preferences leave the report the shape it has always had")
    func unsetPreferences() {
        withCleanPreferences {
            #expect(AttendanceEmail.storedNameOrder() == .firstLast)
            #expect(AttendanceEmail.storedGroupByLevel() == false)
            #expect(bodyLines().contains("    • Ada Zeller"))
        }
    }

    @Test("A stored name order reaches the report body")
    func storedNameOrderReachesBody() {
        withCleanPreferences {
            SyncedPreferencesStore.shared.set(
                AttendanceEmailNameOrder.lastFirst.rawValue,
                forKey: AttendanceEmailPrefs.nameOrderKey
            )
            #expect(AttendanceEmail.storedNameOrder() == .lastFirst)
            #expect(bodyLines().contains("    • Adams, Bo"))
        }
    }

    @Test("A stored grouping preference reaches the report body")
    func storedGroupingReachesBody() {
        withCleanPreferences {
            SyncedPreferencesStore.shared.set(true, forKey: AttendanceEmailPrefs.groupByLevelKey)
            #expect(AttendanceEmail.storedGroupByLevel())
            let lines = bodyLines()
            #expect(lines.contains("UPPER ELEMENTARY"))
            #expect(lines.contains("    • Ada Zeller"))
        }
    }

    @Test("Writing a preference advances the counter SwiftUI redraws on")
    func writesAdvanceChangeCount() {
        withCleanPreferences {
            let store = SyncedPreferencesStore.shared
            let before = store.changeCount
            store.set(true, forKey: AttendanceEmailPrefs.groupByLevelKey)
            #expect(store.changeCount > before)
        }
    }
}
