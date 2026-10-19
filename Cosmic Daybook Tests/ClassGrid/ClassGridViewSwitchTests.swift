import Foundation
import Testing
@testable import CosmicDaybook

/// The Class Grid's one screen with four views: the switch, the old destinations
/// opening it on their view, and the area, search and children filter carrying
/// across views (`ClassGridScope`).
@Suite("Class Grid view switch")
@MainActor
struct ClassGridViewSwitchTests {

    private func isolatedDefaults() throws -> UserDefaults {
        let suite = "ClassGridViewSwitchTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("Four views, named as the canvas names them, in order")
    func fourViews() {
        #expect(ClassGridViewKind.allCases.map(\.title) == ["Checklist", "Three Years", "Children", "Recall"])
        #expect(ClassGridViewKind.allCases.filter(\.allowsAllAreas) == [.threeYears, .children, .recall])
    }

    @Test("Each old destination opens the Class Grid on its view")
    func destinationsOpenTheirView() {
        #expect(ClassGridViewKind.opening(.planningChecklist) == .checklist)
        #expect(ClassGridViewKind.opening(.curriculumMap) == .threeYears)
        #expect(ClassGridViewKind.opening(.progressDashboard) == .children)
        #expect(ClassGridViewKind.opening(.lessonRecall) == .recall)
        #expect(ClassGridViewKind.opening(.today) == nil)

        #expect(ClassAreaChecklistView().initialView == .checklist)
        #expect(ClassCurriculumMapView().initialView == .threeYears)
        #expect(ProgressDashboardView().initialView == .children)
        #expect(RecallQueueView().initialView == .recall)
        #expect(ProgressDashboardView.reloadEntityNames == ClassGridChildrenView.reloadEntityNames)
        #expect(ClassGridView(initialView: .recall).initialView == .recall)
        #expect(ClassGridView().initialView == .checklist)
    }

    @Test("The Checklist keeps its remembered area; the other views open on All areas")
    func checklistKeepsItsArea() throws {
        let defaults = try isolatedDefaults()
        defaults.set("Geometry", forKey: UserDefaultsKeys.checklistSelectedArea)
        let scope = ClassGridScope(defaults: defaults)

        #expect(scope.area == nil)
        #expect(scope.menuTitle(for: .checklist) == "Geometry")
        #expect(scope.menuSelection(for: .checklist) == "Geometry")
        #expect(scope.menuTitle(for: .threeYears) == "All areas")
        #expect(scope.menuSelection(for: .children) == nil)
        #expect(scope.searchPrompt(for: .checklist) == "Search Geometry")
        #expect(scope.searchPrompt(for: .children) == "Search children")
    }

    @Test("An area picked in any view carries to the others, the Checklist included")
    func areaCarriesAcross() throws {
        let defaults = try isolatedDefaults()
        let scope = ClassGridScope(defaults: defaults)

        scope.pick(area: "Math")
        #expect(scope.menuTitle(for: .threeYears) == "Math")
        #expect(scope.menuTitle(for: .recall) == "Math")
        #expect(scope.checklistAreaToShow == "Math")
        #expect(defaults.string(forKey: UserDefaultsKeys.checklistSelectedArea) == "Math")

        // "All areas" elsewhere leaves the Checklist on the area it last showed.
        scope.pick(area: nil)
        #expect(scope.menuTitle(for: .children) == "All areas")
        #expect(scope.menuTitle(for: .checklist) == "Math")
        #expect(defaults.string(forKey: UserDefaultsKeys.checklistSelectedArea) == "Math")
    }

    @Test("The Checklist moving itself (a deep link) moves the menu with it")
    func checklistMovesTheMenu() throws {
        let defaults = try isolatedDefaults()
        let scope = ClassGridScope(defaults: defaults)

        scope.checklistDidShow(area: "Language")
        // With All areas showing elsewhere, the other views stay on All areas…
        #expect(scope.area == nil)
        #expect(scope.menuTitle(for: .checklist) == "Language")

        // …but a picked area follows the Checklist to its new one.
        scope.pick(area: "Math")
        scope.checklistDidShow(area: "Geometry")
        #expect(scope.area == "Geometry")
        #expect(defaults.string(forKey: UserDefaultsKeys.checklistSelectedArea) == "Geometry")
    }

    @Test("The children filter keeps only the children picked, or everyone")
    func childrenFilter() throws {
        let scope = ClassGridScope(defaults: try isolatedDefaults())
        let maya = UUID()
        let eli = UUID()
        #expect(scope.showsChild(maya))
        scope.childFilterIDs = [maya]
        #expect(scope.showsChild(maya))
        #expect(!scope.showsChild(eli))
    }
}
