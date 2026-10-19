import Foundation
import Testing
@testable import CosmicDaybook

/// The Class Grid's search (Phase 12 review, 2026-10-19): a view with no field
/// ignores it and keeps it for the way back, and a field that looks through
/// something else starts empty, so a child's name never becomes a lesson search.
@Suite("Class Grid search scope")
@MainActor
struct ClassGridSearchScopeTests {

    private func scope(openingOn view: ClassGridViewKind, isRegular: Bool = true) throws -> ClassGridScope {
        let suite = "ClassGridSearchScopeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let scope = ClassGridScope(defaults: defaults)
        scope.viewDidChange(to: view, isRegular: isRegular)
        return scope
    }

    @Test("Three Years has no field, so it ignores a lesson search and the Checklist gets it back")
    func threeYearsIgnoresAndKeeps() throws {
        let scope = try scope(openingOn: .checklist)
        scope.searchText = "Stamp"
        scope.viewDidChange(to: .threeYears, isRegular: true)
        #expect(scope.query(for: .threeYears, isRegular: true).isEmpty)
        #expect(scope.searchText == "Stamp")
        scope.viewDidChange(to: .checklist, isRegular: true)
        #expect(scope.query(for: .checklist, isRegular: true) == "Stamp")
    }

    @Test("A child's name typed in Children doesn't become a lesson search on the Checklist")
    func childSearchClearsOnChecklist() throws {
        let scope = try scope(openingOn: .children)
        scope.searchText = "Maya"
        scope.viewDidChange(to: .checklist, isRegular: true)
        #expect(scope.searchText.isEmpty)
    }

    @Test("Through Three Years and back to Children, a child search still clears on the Checklist")
    func targetSurvivesAFieldlessView() throws {
        let scope = try scope(openingOn: .children)
        scope.searchText = "Maya"
        scope.viewDidChange(to: .threeYears, isRegular: true)
        #expect(scope.searchText == "Maya")
        scope.viewDidChange(to: .checklist, isRegular: true)
        #expect(scope.searchText.isEmpty)
    }

    @Test("Recall searches on the Mac and iPad, but not on the iPhone, which shows no field")
    func recallFieldOnlyWhenRegular() throws {
        let regular = try scope(openingOn: .recall, isRegular: true)
        regular.searchText = "Maya"
        #expect(regular.query(for: .recall, isRegular: true) == "Maya")

        let phone = try scope(openingOn: .children, isRegular: false)
        phone.searchText = "Maya"
        phone.viewDidChange(to: .recall, isRegular: false)
        #expect(phone.query(for: .recall, isRegular: false).isEmpty)
        #expect(phone.searchText == "Maya")
    }

    @Test("Only views that show a field have a search target")
    func searchTargets() {
        #expect(ClassGridViewKind.checklist.searchTarget(isRegular: false) == .lessons)
        #expect(ClassGridViewKind.threeYears.searchTarget(isRegular: true) == nil)
        #expect(ClassGridViewKind.children.searchTarget(isRegular: false) == .children)
        #expect(ClassGridViewKind.recall.searchTarget(isRegular: true) == .lessonsAndChildren)
        #expect(ClassGridViewKind.recall.searchTarget(isRegular: false) == nil)
    }

    @Test("The grid opens on All marks, and the Checklist's lens is kept while another view shows")
    func lensKept() throws {
        let scope = try scope(openingOn: .checklist)
        #expect(scope.checklistLens == .allMarks)
        scope.checklistLens = .ready
        scope.viewDidChange(to: .children, isRegular: true)
        #expect(scope.checklistLens == .ready)
    }
}
