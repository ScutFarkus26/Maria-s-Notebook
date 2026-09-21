import CoreData
import Foundation

/// The classroom roster, fetched once per workspace and kept live.
///
/// Forty-odd views used to each hold a whole-table `@FetchRequest` over
/// `CDStudent`, so every CloudKit import tick re-evaluated every one of them.
/// This store holds the one `NSFetchedResultsController` instead; views read
/// `dependencies.roster.all` / `.enrolled` / `.byID` and are invalidated
/// through observation when the controller reports a change. The rows are the
/// managed objects themselves, so a row stays bindable with `@ObservedObject`.
///
/// `all` is every student once, in the roster screen's alphabetical order
/// (first name, last name, manual order); CloudKit duplicate-ID artifacts are
/// dropped first-wins, which is what every consumer's `uniqueByID` did.
/// `enrolled` is `all` without withdrawn or transferred students. Neither
/// applies the test-student preference — pass them through
/// `testStudents.visible(_:)` or `TestStudentsFilter.filterVisible` as before.
///
/// Owned by `AppDependencies` as a lazy service, so each classroom workspace
/// (My Class, Sample Class) has its own store bound to its own view context.
@Observable
@MainActor
final class RosterStore {
    /// The view context the store is bound to.
    let context: NSManagedObjectContext

    private(set) var all: [CDStudent] = []
    private(set) var enrolled: [CDStudent] = []
    private(set) var byID: [UUID: CDStudent] = [:]

    private let table: FetchedTable<CDStudent>

    private static let canonicalSort: [NSSortDescriptor] = [
        NSSortDescriptor(key: "firstName", ascending: true),
        NSSortDescriptor(key: "lastName", ascending: true),
        NSSortDescriptor(key: "manualOrder", ascending: true)
    ]

    init(context: NSManagedObjectContext) {
        self.context = context
        table = FetchedTable(CDStudent.self, context: context, sortDescriptors: Self.canonicalSort)
        table.onChange = { [weak self] in self?.refresh() }
        refresh()
    }

    func student(id: UUID) -> CDStudent? {
        byID[id]
    }

    /// Rebuilds the cached arrays from the controller — once per change, never per read.
    private func refresh() {
        let rows = table.objects.uniqueByID
        all = rows
        enrolled = rows.filterEnrolled()
        byID = Dictionary(
            rows.compactMap { student in student.id.map { ($0, student) } },
            uniquingKeysWith: { first, _ in first }
        )
    }
}
