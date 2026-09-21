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
/// lesson-picking sheets list the catalog in.
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
    private(set) var sortedByAreaAndSortIndex: [CDLesson] = []

    // Observed, not ignored: a view whose body reads only `lessons(area:sequence:)`
    // must still be invalidated when the controller reports a change.
    private var bySequence: [SequenceKey: [CDLesson]] = [:]

    private let table: FetchedTable<CDLesson>

    private struct SequenceKey: Hashable {
        let area: String
        let sequence: String

        init(area: String, sequence: String) {
            self.area = area.trimmed().lowercased()
            self.sequence = sequence.trimmed().lowercased()
        }
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

    /// Rebuilds the cached arrays from the controller — once per change, never per read.
    private func refresh() {
        let rows = table.objects
        all = rows
        byID = Dictionary(
            rows.compactMap { lesson in lesson.id.map { ($0, lesson) } },
            uniquingKeysWith: { first, _ in first }
        )
        sortedByAreaAndSortIndex = (rows as NSArray).sortedArray(using: Self.areaAndSortIndex) as? [CDLesson] ?? rows
        bySequence = Dictionary(grouping: rows) { SequenceKey(area: $0.area, sequence: $0.sequence) }
            .mapValues { $0.sorted { $0.orderInSequence < $1.orderInSequence } }
    }
}
