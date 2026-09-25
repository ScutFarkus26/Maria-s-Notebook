import CoreData
import Foundation

/// The lesson catalog, fetched once per workspace and kept live.
///
/// Thirty-odd views used to each hold a whole-table `@FetchRequest` over
/// `CDLesson`, most of them only to look a lesson up by ID. This store holds
/// the one `NSFetchedResultsController` instead; views read
/// `dependencies.lessonCatalog.all` / `.byID` / `.lesson(id:)` and are
/// invalidated through observation when the controller reports a change. The
/// rows are the managed objects themselves.
///
/// `all` is every row in curriculum order (area, sequence, order in sequence,
/// name). Rows are not de-duplicated: no lesson view did, and `byID` keeps the
/// first row per ID the way each view's `uniquingKeysWith: { first, _ in first }`
/// dictionary did. `lessons(area:sequence:)` matches the way the presentation
/// views did — trimmed, case-insensitive — and returns the sequence in
/// `orderInSequence` order. `sortedByAreaAndSortIndex` is the order the
/// lesson-picking sheets list the catalog in, and `sortedByAreaSortIndexAndOrder`
/// the order the Lessons screen does.
///
/// `all` and `byID` are rebuilt on every change. The other orders are read far
/// less often, so each is derived from `all` on its first read after a change
/// and kept until the next one.
///
/// Owned by `AppDependencies` as a lazy service, so each classroom workspace
/// (My Class, Sample Class) has its own catalog bound to its own view context.
@Observable
@MainActor
final class LessonCatalog {
    /// The view context the catalog is bound to.
    let context: NSManagedObjectContext

    private(set) var all: [CDLesson] = []
    private(set) var byID: [UUID: CDLesson] = [:]

    /// Bumped once per controller change. Every derived order reads it, so a
    /// view whose body reads only a derived order — or only
    /// `lessons(area:sequence:)` — is still invalidated by every change, as it
    /// was when those orders were stored properties rebuilt on each one.
    private(set) var version = 0

    /// `all` in area, sort-index order: how the lesson-picking sheets list it.
    var sortedByAreaAndSortIndex: [CDLesson] {
        derived(&areaAndSortIndexCache) { rows in
            (rows as NSArray).sortedArray(using: Self.areaAndSortIndex) as? [CDLesson] ?? rows
        }
    }

    /// `all` in area, sort-index, order-in-sequence order: how the Lessons screen
    /// lists it (it used to hold a second live fetch sorted on those three keys).
    /// Lessons tied on all three keep `all`'s order — sequence, then name — where
    /// that fetch left them in whatever order the store returned.
    var sortedByAreaSortIndexAndOrder: [CDLesson] {
        derived(&areaSortIndexAndOrderCache, build: Self.areaSortIndexAndOrder)
    }

    private var bySequence: [SequenceKey: [CDLesson]] {
        derived(&bySequenceCache) { rows in
            Dictionary(grouping: rows) { SequenceKey(area: $0.area, sequence: $0.sequence) }
                .mapValues { $0.sorted { $0.orderInSequence < $1.orderInSequence } }
        }
    }

    @ObservationIgnored private var areaAndSortIndexCache: Derived<[CDLesson]>?
    @ObservationIgnored private var areaSortIndexAndOrderCache: Derived<[CDLesson]>?
    @ObservationIgnored private var bySequenceCache: Derived<[SequenceKey: [CDLesson]]>?

    private let table: FetchedTable<CDLesson>

    /// A derived value and the `version` it was built at.
    private struct Derived<Value> {
        let version: Int
        let value: Value
    }

    private struct SequenceKey: Hashable {
        let area: String
        let sequence: String

        init(area: String, sequence: String) {
            self.area = area.trimmed().lowercased()
            self.sequence = sequence.trimmed().lowercased()
        }
    }

    /// One lesson's place in `areaSortIndexAndOrder(_:)`.
    private struct ScreenOrderKey {
        let lesson: CDLesson
        let sortIndex: Int64
        let orderInSequence: Int64
        let position: Int
    }

    private static let canonicalSort: [NSSortDescriptor] = [
        NSSortDescriptor(key: "area", ascending: true),
        NSSortDescriptor(key: "sequence", ascending: true),
        NSSortDescriptor(key: "orderInSequence", ascending: true),
        NSSortDescriptor(key: "name", ascending: true)
    ]

    private static let areaAndSortIndex: [NSSortDescriptor] = [
        NSSortDescriptor(key: "area", ascending: true),
        NSSortDescriptor(key: "sortIndex", ascending: true)
    ]

    init(context: NSManagedObjectContext) {
        self.context = context
        table = FetchedTable(CDLesson.self, context: context, sortDescriptors: Self.canonicalSort)
        table.onChange = { [weak self] in self?.refresh() }
        refresh()
    }

    func lesson(id: UUID) -> CDLesson? {
        byID[id]
    }

    /// The lessons of one sequence, in `orderInSequence` order. Area and
    /// sequence are matched trimmed and case-insensitively.
    func lessons(area: String, sequence: String) -> [CDLesson] {
        bySequence[SequenceKey(area: area, sequence: sequence)] ?? []
    }

    /// Rebuilds `all` and `byID` from the controller — once per change, never
    /// per read — and moves `version` on, so the derived orders rebuild on
    /// their next read.
    private func refresh() {
        let rows = table.objects
        all = rows
        byID = Dictionary(
            rows.compactMap { lesson in lesson.id.map { ($0, lesson) } },
            uniquingKeysWith: { first, _ in first }
        )
        version += 1
    }

    /// The value in `cache` if it was built at the current `version`,
    /// otherwise `build(all)`, kept in `cache` until the next change.
    private func derived<Value>(_ cache: inout Derived<Value>?, build: ([CDLesson]) -> Value) -> Value {
        let current = version
        if let cache, cache.version == current { return cache.value }
        let value = build(all)
        cache = Derived(version: current, value: value)
        return value
    }

    /// `rows` in area, sort-index, order-in-sequence order, ties kept in their
    /// order in `rows`.
    ///
    /// `rows` must already run area by area in the order a fetch sorts areas —
    /// as `all` does, area being its first sort key — so the areas keep that
    /// order and are only checked for equality; each area's run is sorted on
    /// the two numbers.
    static func areaSortIndexAndOrder(_ rows: [CDLesson]) -> [CDLesson] {
        var result: [CDLesson] = []
        result.reserveCapacity(rows.count)
        var runStart = rows.startIndex
        while runStart < rows.endIndex {
            let area = rows[runStart].area
            var runEnd = runStart + 1
            while runEnd < rows.endIndex, rows[runEnd].area == area { runEnd += 1 }
            let run = rows[runStart..<runEnd].enumerated().map { position, lesson in
                ScreenOrderKey(
                    lesson: lesson,
                    sortIndex: lesson.sortIndex,
                    orderInSequence: lesson.orderInSequence,
                    position: position
                )
            }
            result.append(contentsOf: run.sorted { lhs, rhs in
                if lhs.sortIndex != rhs.sortIndex { return lhs.sortIndex < rhs.sortIndex }
                if lhs.orderInSequence != rhs.orderInSequence { return lhs.orderInSequence < rhs.orderInSequence }
                return lhs.position < rhs.position
            }.map(\.lesson))
            runStart = runEnd
        }
        return result
    }
}
