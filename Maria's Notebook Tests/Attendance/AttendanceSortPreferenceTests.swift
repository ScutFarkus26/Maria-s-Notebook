import Foundation
import Testing
@testable import Maria_s_Notebook

// The sort picker used to live only in view state, so every relaunch dropped back to last name.
// These cover the round trip through SyncedPreferencesStore that keeps the last choice.
@MainActor
@Suite("Attendance sort preference")
struct AttendanceSortPreferenceTests {

    private static let sortKey = AttendanceViewModel.sortKeyPreferenceKey

    /// Runs `work` with the sort key unset, then puts back whatever was stored.
    private func withCleanPreference(_ work: () -> Void) {
        let store = SyncedPreferencesStore.shared
        let saved = store.get(key: Self.sortKey)
        defer { store.set(saved, forKey: Self.sortKey) }
        store.remove(key: Self.sortKey)
        work()
    }

    @Test("An unset preference still opens sorted by last name")
    func unsetPreferenceDefaultsToLastName() {
        withCleanPreference {
            #expect(AttendanceViewModel.storedSortKey() == .lastName)
            #expect(AttendanceViewModel().sortKey == .lastName)
        }
    }

    @Test("Choosing a sort survives into the next view model")
    func chosenSortSurvivesRelaunch() {
        withCleanPreference {
            AttendanceViewModel().setSortKey(.firstName)
            #expect(AttendanceViewModel.storedSortKey() == .firstName)
            // A fresh view model stands in for the next launch of the app.
            #expect(AttendanceViewModel().sortKey == .firstName)
        }
    }

    @Test("Switching back to last name is remembered too")
    func switchingBackIsStored() {
        withCleanPreference {
            let viewModel = AttendanceViewModel()
            viewModel.setSortKey(.firstName)
            viewModel.setSortKey(.lastName)
            #expect(viewModel.sortKey == .lastName)
            #expect(AttendanceViewModel.storedSortKey() == .lastName)
        }
    }

    @Test("The sort key is registered to sync across devices")
    func sortKeySyncs() {
        #expect(SyncedPreferencesStore.shared.isSynced(key: Self.sortKey))
    }
}
