import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

/// The single declaration of the "test students" preferences. Thirty-one views
/// now read it instead of declaring the pair themselves, so two things have to
/// hold: an untouched store yields the shared default name list, and the
/// wrapper hides exactly the students `visibleRoster` hides.
///
/// Each test reads its own `UserDefaults(suiteName:)` so nothing leaks between
/// tests or in from the test host's standard defaults.
@Suite("Test student visibility")
@MainActor
struct TestStudentVisibilityTests {

    private func makeStore() throws -> (store: UserDefaults, name: String) {
        let name = "TestStudentVisibilityTests.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: name)), name)
    }

    @Test("An empty store yields the shared default names")
    func emptyStoreUsesSharedDefault() throws {
        let (store, name) = try makeStore()
        defer { store.removePersistentDomain(forName: name) }

        let settings = TestStudentVisibility(store: store).wrappedValue
        #expect(settings.show == false)
        #expect(settings.namesRaw == TestStudentsFilter.defaultNames)
        #expect(settings.hiddenNames == ["danny de berry", "lil dan d"])
    }

    @Test("visible(_:) hides the named students until Show Test Students is on")
    func visibleHonorsTheToggle() throws {
        let (store, name) = try makeStore()
        defer { store.removePersistentDomain(forName: name) }

        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let danny = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Danny", lastName: "De Berry"
        )
        let maya = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Maya", lastName: "Stern"
        )
        // `visible(_:)` drops duplicate IDs, and a freshly inserted CDStudent
        // has none, so give each row the ID production would have.
        danny.id = UUID()
        maya.id = UUID()
        let roster = [danny, maya]

        let hidden = TestStudentVisibility(store: store).wrappedValue.visible(roster)
        #expect(hidden.map(\.fullName) == ["Maya Stern"])

        store.set(true, forKey: UserDefaultsKeys.generalShowTestStudents)
        let shown = TestStudentVisibility(store: store).wrappedValue.visible(roster)
        #expect(shown.map(\.fullName) == ["Danny De Berry", "Maya Stern"])
    }
}
