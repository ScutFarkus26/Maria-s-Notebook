import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The guide sets the order of an area's sub-areas from the Class Grid (Move Up /
/// Move Down on a band) or over MCP (`reorder_lessons`' `sub_areas`), and the grid,
/// the map and `find_lessons` all draw them in it (2026-11-09). The unfiled lessons'
/// band ("Other" on the grid, "Ungrouped" in the map and the tools) keeps the place
/// it is given instead of always trailing.
///
/// The order syncs between devices through `SyncedPreferencesStore`. Every case writes
/// the real stores under an area name unique to this run, and clears what it wrote.
@Suite("Sub-area order", .serialized)
@MainActor
struct SubAreaOrderTests {

    private let area = "SubAreaTest-\(UUID().uuidString)"

    private var key: String { FilterOrderStore.sequenceOrderKeyPrefix + area.normalizedForComparison() }

    private func clearStoredOrders() {
        let store = SyncedPreferencesStore.shared
        for key in store.storedKeys(withPrefix: FilterOrderStore.sequenceOrderKeyPrefix)
        where key.contains(area.lowercased()) {
            store.remove(key: key)
        }
        FilterOrderStore.resetCache()
    }

    // MARK: - Syncing

    @Test("The order is kept where it syncs to the guide's other devices")
    func orderIsSynced() {
        defer { clearStoredOrders() }
        clearStoredOrders()
        #expect(SyncedPreferencesStore.shared.isSynced(key: key))

        SubAreaOrder.save(["B", "A"], area: area)
        #expect(SyncedPreferencesStore.shared.get(key: key) as? [String] == ["B", "A"])
        #expect(NSUbiquitousKeyValueStore.default.array(forKey: key) as? [String] == ["B", "A"])
    }

    @Test("An order saved on this device before syncing began is still read")
    func earlierLocalOrderIsRead() {
        defer { clearStoredOrders() }
        clearStoredOrders()
        UserDefaults.standard.set(["B", "A"], forKey: key)
        FilterOrderStore.resetCache()

        #expect(FilterOrderStore.loadSequenceOrder(for: area, existing: ["A", "B"]) == ["B", "A"])
    }

    @Test("Another device's change replaces the cached order")
    func externalChangeResetsTheCache() {
        defer { clearStoredOrders() }
        clearStoredOrders()
        SubAreaOrder.save(["A", "B"], area: area)
        #expect(FilterOrderStore.loadSequenceOrder(for: area, existing: ["A", "B"]) == ["A", "B"])

        // What iCloud does when another device moves a band: the value lands, then the notice.
        NSUbiquitousKeyValueStore.default.set(["B", "A"], forKey: key)
        let before = FilterOrderStore.revision
        SyncedPreferencesStore.shared.handleExternalChange(reason: 0, changedKeys: ["Other.key"])
        #expect(FilterOrderStore.revision == before, "an unrelated key leaves the cache alone")
        SyncedPreferencesStore.shared.handleExternalChange(reason: 0, changedKeys: [key])
        #expect(FilterOrderStore.revision != before)
        #expect(FilterOrderStore.loadSequenceOrder(for: area, existing: ["A", "B"]) == ["B", "A"])
    }

    // MARK: - Moving

    @Test("A band moves one place past its neighbor, and not past an edge")
    func movesOnePlace() {
        let full = ["A", "B", "C", ""]
        #expect(SubAreaOrder.moving("B", by: -1, visible: full, in: full) == ["B", "A", "C", ""])
        #expect(SubAreaOrder.moving("C", by: 1, visible: full, in: full) == ["A", "B", "", "C"])
        #expect(SubAreaOrder.moving("", by: -1, visible: full, in: full) == ["A", "B", "", "C"])
        #expect(SubAreaOrder.moving("A", by: -1, visible: full, in: full) == nil)
        #expect(SubAreaOrder.moving("", by: 1, visible: full, in: full) == nil)
        #expect(SubAreaOrder.moving("Z", by: 1, visible: full, in: full) == nil)
    }

    @Test("A move among the bands on screen leaves a hidden band in its slot")
    func hiddenBandKeepsItsSlot() {
        let full = ["A", "Hidden", "B", "C"]
        let visible = ["A", "B", "C"]
        #expect(SubAreaOrder.moving("B", by: -1, visible: visible, in: full) == ["B", "Hidden", "A", "C"])
    }

    // MARK: - The unfiled band

    @Test("The unfiled band trails until it is given a place, then keeps it")
    func ungroupedKeepsItsPlace() {
        defer { clearStoredOrders() }
        clearStoredOrders()
        #expect(SubAreaOrder.withUngrouped(["A", "B"], hasUngrouped: true, area: area) == ["A", "B", ""])
        #expect(SubAreaOrder.withUngrouped(["A", "B"], hasUngrouped: false, area: area) == ["A", "B"])

        SubAreaOrder.save(["", "B", "A"], area: area)
        FilterOrderStore.resetCache()
        #expect(SubAreaOrder.withUngrouped(["A", "B"], hasUngrouped: true, area: area) == ["", "B", "A"])
        #expect(FilterOrderStore.loadSequenceOrder(for: area, existing: ["A", "B"]) == ["B", "A"])
    }

    // MARK: - The Class Grid

    private func makeViewModel() throws -> (ClassAreaChecklistViewModel, NSManagedObjectContext) {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Test")
        for (name, sequence) in [("Cube", "Algebra"), ("Beads", "Decimal System"), ("Story", "")] {
            CoreDataTestHelpers.seedLesson(in: context, name: name, area: area, sequence: sequence)
        }
        #expect(CoreDataTestHelpers.save(context))
        return (try loadedViewModel(context), context)
    }

    private func loadedViewModel(_ context: NSManagedObjectContext) throws -> ClassAreaChecklistViewModel {
        let viewModel = ClassAreaChecklistViewModel()
        viewModel.selectedArea = area
        viewModel.loadData(context: context)
        viewModel.applyVisibilityFilter(context: context, show: true, namesRaw: "")
        return viewModel
    }

    @Test("Move Up on a Class Grid band reorders the sub-areas and is remembered")
    func checklistMoveIsSaved() throws {
        defer { clearStoredOrders() }
        clearStoredOrders()
        let (viewModel, context) = try makeViewModel()
        #expect(viewModel.visibleSequences == ["Algebra", "Decimal System", ""])
        #expect(!viewModel.canMoveSequence("Algebra", by: -1))
        #expect(viewModel.canMoveSequence("", by: -1))

        viewModel.moveSequence("Decimal System", by: -1)
        viewModel.moveSequence("", by: -1)
        #expect(viewModel.visibleSequences == ["Decimal System", "", "Algebra"])

        FilterOrderStore.resetCache()
        let reopened = try loadedViewModel(context)
        #expect(reopened.orderedSequences == ["Decimal System", "", "Algebra"])
    }

    // MARK: - MCP

    @Test("reorder_lessons' sub_areas sets the order find_lessons lists them in")
    func mcpSubAreaOrder() async throws {
        defer { clearStoredOrders() }
        clearStoredOrders()
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        for (name, sequence) in [("Cube", "Algebra"), ("Beads", "Decimal System"), ("Ratio", "Fractions")] {
            CoreDataTestHelpers.seedLesson(in: context, name: name, area: area, sequence: sequence)
        }
        CoreDataTestHelpers.seedLesson(in: context, name: "Story", area: area, sequence: "")
        #expect(CoreDataTestHelpers.save(context))
        let tools = MCPNotebookTools.makeTools(context: { context })
        let reorder = try #require(tools.first { $0.name == "reorder_lessons" })
        let find = try #require(tools.first { $0.name == "find_lessons" })

        let output = try await reorder.handler([
            "area": .string(area), "sub_areas": .array([.string("fractions"), .string("Ungrouped")])
        ])
        #expect(output.contains("1. Fractions\n2. Ungrouped\n3. Algebra\n4. Decimal System"))
        #expect(output.contains("2 unlisted sub-area(s)"))

        let listing = try await find.handler(["area": .string(area)])
        let headers = listing.split(separator: "\n").filter { $0.contains(" — ") && $0.contains("lesson(s)") }
        #expect(headers.map { $0.components(separatedBy: " › ").last?.components(separatedBy: " — ").first }
            == ["Fractions", "Ungrouped", "Algebra", "Decimal System"])
        #expect(context.registeredObjects.allSatisfy { !$0.hasChanges })

        await #expect(throws: MCPToolError.self) {
            try await reorder.handler([
                "area": .string(area), "sub_areas": .array([.string("Algebra")]), "sub_area": .string("Algebra")
            ])
        }
        await #expect(throws: MCPToolError.self) {
            try await reorder.handler(["area": .string(area), "sub_areas": .array([.string("Geometry")])])
        }
        await #expect(throws: MCPToolError.self) {
            try await reorder.handler(["area": .string(area)])
        }
    }

    @Test("find_lessons lists sections by their earliest lesson, with unsectioned lessons in place")
    func mcpSectionsFollowLessonOrder() async throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        for (index, (name, section)) in [
            ("Intro", ""), ("Stamps", "Stamp Game"), ("Story", ""),
            ("Bead Bars", "Beads"), ("More Stamps", "Stamp Game")
        ].enumerated() {
            let lesson = CoreDataTestHelpers.seedLesson(in: context, name: name, area: area, sequence: "Operations")
            lesson.section = section
            lesson.orderInSequence = Int64(index)
        }
        #expect(CoreDataTestHelpers.save(context))
        let tools = MCPNotebookTools.makeTools(context: { context })
        let find = try #require(tools.first { $0.name == "find_lessons" })

        let output = try await find.handler(["area": .string(area), "sub_area": .string("Operations")])
        let headings = output.split(separator: "\n").filter { $0 == "No section" || $0.hasPrefix("Section: ") }
        #expect(headings == ["No section", "Section: Stamp Game", "No section", "Section: Beads"])
        #expect(output.contains("Section: Stamp Game\n2. "))
        #expect(output.contains("5. [lesson id=") && output.contains("More Stamps"))
    }
}
