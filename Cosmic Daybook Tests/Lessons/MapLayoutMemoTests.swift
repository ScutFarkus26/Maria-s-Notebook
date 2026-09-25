import CoreData
import Foundation
import SwiftUI
import Testing
@testable import CosmicDaybook

/// Pins the scope-and-sequence map's layout memo.
///
/// The map used to run `MapSectionBuilder` over the whole catalog on every body
/// pass — every frame of a detail-divider drag, every hover — and to work out
/// each row's drag eligibility and section count as it drew it. The memo keeps
/// one build until an input moves. These hold the two things that makes safe:
/// what it hands the map is exactly a fresh build (with the per-row facts the
/// map used to derive), and it builds again whenever an input the builder reads
/// has moved, and only then.
///
/// Every area here is unique to the test, so no saved area or sequence order
/// exists for it and every order falls back to alphabetical.
@Suite("Lessons map layout memo")
@MainActor
struct MapLayoutMemoTests {

    private let math = "MapMath-\(UUID().uuidString.prefix(8))"
    private let geometry = "MapGeometry-\(UUID().uuidString.prefix(8))"

    // MARK: - Seed

    private func makeContext() throws -> NSManagedObjectContext {
        try CoreDataTestHelpers.makeInMemoryStack().viewContext
    }

    @discardableResult
    private func lesson(
        _ context: NSManagedObjectContext,
        _ name: String,
        area: String,
        sequence: String,
        order: Int64,
        section: String = "",
        greatLesson: GreatLesson? = nil
    ) -> CDLesson {
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: name, area: area, sequence: sequence)
        lesson.orderInSequence = order
        lesson.section = section
        lesson.greatLesson = greatLesson
        return lesson
    }

    /// Named sequences (one padded with spaces, one with two sections), an area
    /// with a single named sequence, ungrouped rows, a padded area, arealess
    /// lessons, and ties on order in sequence.
    ///
    /// No name differs from another only in case: the builder picks between
    /// case variants through `Set` iteration, which Swift seeds per instance,
    /// so two builds of such a catalog can legitimately spell a row differently.
    private func seed(_ context: NSManagedObjectContext) throws -> [CDLesson] {
        lesson(context, "Short Chain", area: math, sequence: "Chains", order: 1, section: "Short")
        lesson(context, "Long Chain", area: math, sequence: "Chains ", order: 0, section: "Long",
               greatLesson: .storyOfNumbers)
        lesson(context, "Stamp Game", area: math, sequence: "Operations", order: 0,
               greatLesson: .storyOfNumbers)
        lesson(context, "Checkerboard", area: math, sequence: "Operations", order: 0, section: "Board")
        lesson(context, "Bead Frame", area: math, sequence: "Operations", order: 0, section: "board")
        lesson(context, "Fraction Circles", area: math, sequence: "Fractions", order: 2)
        lesson(context, "Loose", area: math, sequence: "", order: 0)
        lesson(context, "Loose Too", area: math, sequence: "  ", order: 1, greatLesson: .comingOfLife)
        lesson(context, "Triangles", area: geometry, sequence: "Shapes", order: 0, section: "Plane",
               greatLesson: .comingOfUniverse)
        lesson(context, "Solids", area: geometry, sequence: "Shapes", order: 1, section: "Solid")
        lesson(context, "Geo Loose", area: geometry, sequence: "", order: 0)
        lesson(context, "Padded Area", area: " \(math) ", sequence: "Chains", order: 3)
        lesson(context, "Orphan", area: "", sequence: "", order: 0, greatLesson: .comingOfHumans)
        lesson(context, "Orphan Two", area: "  ", sequence: "Stray", order: 0)
        try context.save()
        let request = CDFetchRequest(CDLesson.self)
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        return try context.fetch(request)
    }

    // MARK: - Equivalence

    /// The map's pre-memo test for "more than one named section on this row".
    private func legacyHasMultipleSections(_ row: ThreadRowData) -> Bool {
        Set(row.lessons.map { $0.section.trimmed() }.filter { !$0.isEmpty }).count > 1
    }

    /// `layout` is exactly what a fresh builder run gives for the same inputs,
    /// and each row's derived facts are what the map used to compute per pass.
    private func expectMatchesFreshBuild(
        _ layout: MapLayout,
        lessons: [CDLesson],
        selectedArea: String?,
        spine: MapSpine
    ) {
        let fresh: [MapSection] = MapSectionBuilder(lessons: lessons, selectedArea: selectedArea).sections(for: spine)
        let builtSectionIDs: [String] = layout.sections.map(\.id)
        let freshSectionIDs: [String] = fresh.map(\.id)
        #expect(builtSectionIDs == freshSectionIDs)
        for (built, expected) in zip(layout.sections, fresh) {
            #expect(built.section.title == expected.title)
            #expect(built.section.icon == expected.icon)
            #expect(built.section.color == expected.color)
            let builtKeys: [ThreadKey] = built.rows.map(\.data.key)
            let freshKeys: [ThreadKey] = expected.rows.map(\.key)
            #expect(builtKeys == freshKeys)
            for (row, expectedRow) in zip(built.rows, expected.rows) {
                expectRow(row, matches: expectedRow, in: expected)
            }
        }
    }

    private func expectRow(_ row: MapLayout.Row, matches expected: ThreadRowData, in section: MapSection) {
        let builtLessons: [NSManagedObjectID] = row.data.lessons.map(\.objectID)
        let freshLessons: [NSManagedObjectID] = expected.lessons.map(\.objectID)
        #expect(builtLessons == freshLessons)
        #expect(row.id == expected.id)
        let expectedRowID: String = section.rowID(for: expected)
        #expect(row.rowID == expectedRowID)
        let expectedMovable: Bool = section.canMove(expected)
        #expect(row.isMovable == expectedMovable)
        let expectedSections: Bool = legacyHasMultipleSections(expected)
        #expect(row.hasSections == expectedSections)
        let expectedColor: Color = AppColors.color(forArea: expected.key.area)
        #expect(row.color == expectedColor)
    }

    @Test("The memo's layout equals a fresh build, per-row facts included, for every spine and area filter")
    func layoutMatchesFreshBuild() throws {
        let context = try makeContext()
        let lessons = try seed(context)
        let memo = MapLayoutMemo()

        var sawMovable = false, sawFixed = false, sawSections = false, sawSingle = false
        for spine in MapSpine.allCases {
            for area: String? in [nil, math, " \(math.lowercased()) ", geometry, ""] {
                let layout = memo.layout(for: lessons, selectedArea: area, spine: spine, in: context)
                expectMatchesFreshBuild(layout, lessons: lessons, selectedArea: area, spine: spine)
                let rows = layout.sections.flatMap(\.rows)
                sawMovable = sawMovable || rows.contains { $0.isMovable }
                sawFixed = sawFixed || rows.contains { !$0.isMovable }
                sawSections = sawSections || rows.contains { $0.hasSections }
                sawSingle = sawSingle || rows.contains { !$0.hasSections }
            }
        }
        // The seed exercises both answers of each derived fact.
        #expect(sawMovable && sawFixed && sawSections && sawSingle)
    }

    // MARK: - When it builds

    @Test("Unchanged inputs reuse one build however often the map is drawn")
    func reusesLayoutWhileInputsHold() throws {
        let context = try makeContext()
        let lessons = try seed(context)
        let memo = MapLayoutMemo()

        for _ in 0..<50 {
            _ = memo.layout(for: lessons, selectedArea: nil, spine: .area, in: context)
        }
        #expect(memo.buildCount == 1)

        // A save that touches no lesson leaves it alone too.
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Lovelace")
        try context.save()
        _ = memo.layout(for: lessons, selectedArea: nil, spine: .area, in: context)
        #expect(memo.buildCount == 1)
    }

    @Test("A lesson edit rebuilds, saved or still pending, and the rebuild is current")
    func lessonEditRebuilds() throws {
        let context = try makeContext()
        let lessons = try seed(context)
        let memo = MapLayoutMemo()
        _ = memo.layout(for: lessons, selectedArea: nil, spine: .area, in: context)

        // Pending: moved to another sequence, not yet saved or announced.
        let moved = try #require(lessons.first { $0.name == "Fraction Circles" })
        moved.sequence = "Operations"
        let pending = memo.layout(for: lessons, selectedArea: nil, spine: .area, in: context)
        #expect(memo.buildCount == 2)
        expectMatchesFreshBuild(pending, lessons: lessons, selectedArea: nil, spine: .area)

        try context.save()
        let saved = memo.layout(for: lessons, selectedArea: nil, spine: .area, in: context)
        expectMatchesFreshBuild(saved, lessons: lessons, selectedArea: nil, spine: .area)
        let settled = memo.buildCount
        _ = memo.layout(for: lessons, selectedArea: nil, spine: .area, in: context)
        #expect(memo.buildCount == settled)

        // A section edit changes only a derived fact, and still rebuilds.
        let shapes = try #require(lessons.first { $0.name == "Solids" })
        shapes.section = "Plane"
        try context.save()
        let resectioned = memo.layout(for: lessons, selectedArea: nil, spine: .area, in: context)
        #expect(memo.buildCount == settled + 1)
        expectMatchesFreshBuild(resectioned, lessons: lessons, selectedArea: nil, spine: .area)
    }

    @Test("A different lesson list, area filter or spine rebuilds")
    func otherInputsRebuild() throws {
        let context = try makeContext()
        let lessons = try seed(context)
        let memo = MapLayoutMemo()
        _ = memo.layout(for: lessons, selectedArea: nil, spine: .area, in: context)

        let narrowed = lessons.filter { $0.name != "Solids" }
        let filtered = memo.layout(for: narrowed, selectedArea: nil, spine: .area, in: context)
        #expect(memo.buildCount == 2)
        expectMatchesFreshBuild(filtered, lessons: narrowed, selectedArea: nil, spine: .area)

        _ = memo.layout(for: narrowed, selectedArea: math, spine: .area, in: context)
        #expect(memo.buildCount == 3)
        _ = memo.layout(for: narrowed, selectedArea: math, spine: .greatLesson, in: context)
        #expect(memo.buildCount == 4)
        _ = memo.layout(for: narrowed, selectedArea: math, spine: .greatLesson, in: context)
        #expect(memo.buildCount == 4)
    }

    @Test("A saved sequence order rebuilds, and the rebuild shows the new order")
    func savedOrderRebuilds() throws {
        let context = try makeContext()
        lesson(context, "Chain", area: math, sequence: "Chains", order: 0)
        lesson(context, "Circle", area: math, sequence: "Fractions", order: 0)
        lesson(context, "Stamp", area: math, sequence: "Operations", order: 0)
        lesson(context, "Loose", area: math, sequence: "", order: 0)
        try context.save()
        let lessons = try context.fetch(CDFetchRequest(CDLesson.self))
        let memo = MapLayoutMemo()

        let before = memo.layout(for: lessons, selectedArea: nil, spine: .area, in: context)
        let mathSection = try #require(before.sections.first { $0.id == "area:\(math)" })
        #expect(mathSection.rows.map(\.data.key.sequence) == ["Chains", "Fractions", "Operations", ""])

        let key = "Lessons.SequenceOrder." + math.normalizedForComparison()
        defer {
            UserDefaults.standard.removeObject(forKey: key)
            FilterOrderStore.resetCache()
        }
        FilterOrderStore.saveSequenceOrder(["Operations", "Chains", "Fractions"], for: math)

        let after = memo.layout(for: lessons, selectedArea: nil, spine: .area, in: context)
        #expect(memo.buildCount == 2)
        let reordered = try #require(after.sections.first { $0.id == "area:\(math)" })
        #expect(reordered.rows.map(\.data.key.sequence) == ["Operations", "Chains", "Fractions", ""])
        expectMatchesFreshBuild(after, lessons: lessons, selectedArea: nil, spine: .area)
    }

    @Test("A different context starts over")
    func newContextRebuilds() throws {
        let context = try makeContext()
        let lessons = try seed(context)
        let memo = MapLayoutMemo()
        _ = memo.layout(for: lessons, selectedArea: nil, spine: .area, in: context)

        let other = try makeContext()
        _ = memo.layout(for: lessons, selectedArea: nil, spine: .area, in: other)
        #expect(memo.buildCount == 2)
    }
}

/// Pins how the map picks the row a lifted one would land on, now that the rule
/// lives on the layout's section rather than in the view.
@Suite("Lessons map hover target")
@MainActor
struct MapHoverTargetTests {

    private let area = "MapHover-\(UUID().uuidString.prefix(8))"

    /// One area: three named sequences, which can be dragged, and an ungrouped
    /// row, which cannot.
    private func seed() throws -> (context: NSManagedObjectContext, lessons: [CDLesson]) {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        for (name, sequence) in [("A", "Alpha"), ("B", "Beta"), ("C", "Gamma"), ("Loose", "")] {
            CoreDataTestHelpers.seedLesson(in: context, name: name, area: area, sequence: sequence)
        }
        try context.save()
        return (context, try context.fetch(CDFetchRequest(CDLesson.self)))
    }

    private func areaSection(in layout: MapLayout) throws -> MapLayout.Section {
        let section = try #require(layout.sections.first { $0.id == "area:\(area)" })
        let sequences: [String] = section.rows.map(\.data.key.sequence)
        #expect(sequences == ["Alpha", "Beta", "Gamma", ""])
        return section
    }

    @Test("Hover picks the nearest draggable row of the same area, within one row height")
    func hoverTargetRule() throws {
        let (context, lessons) = try seed()
        let layout = MapLayoutMemo().layout(for: lessons, selectedArea: nil, spine: .area, in: context)
        let section = try areaSection(in: layout)
        let alpha: MapLayout.Row = section.rows[0]
        let beta: String? = section.rows[1].rowID
        let gamma: String? = section.rows[2].rowID

        // Rows 40 pt tall, 44 pt apart: midYs 20, 64, 108, 152.
        var frames: [String: CGRect] = [:]
        for (index, row) in section.rows.enumerated() {
            let top: CGFloat = CGFloat(index) * 44
            frames[row.rowID] = CGRect(x: 0, y: top, width: 300, height: 40)
        }
        func target(_ y: CGFloat, canReorder: Bool = true) -> String? {
            section.nearestRowID(to: y, from: alpha, frames: frames, canReorder: canReorder)
        }
        let none: String? = nil
        #expect(target(64) == beta)
        #expect(target(130) == gamma)
        // Over the lifted row itself, and over the undraggable row: nothing close enough.
        #expect(target(20) == none)
        #expect(target(152) == none)
        #expect(target(64, canReorder: false) == none)
        // Only rows that reported a frame can be targets.
        frames[section.rows[2].rowID] = nil
        #expect(target(108) == none)
    }
}
