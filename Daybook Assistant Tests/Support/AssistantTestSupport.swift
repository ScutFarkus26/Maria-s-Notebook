import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

/// In-memory stacks, students and days for the Assistant's tests. Nothing here
/// touches iCloud or the simulator's real store: the hosted app skips its own
/// bootstrap under tests (`AssistantBootstrapper.isRunningUnitTests`).
@MainActor
enum AssistantTestSupport {

    static func makeStack() throws -> CoreDataStack {
        try CoreDataStack(enableCloudKit: false, inMemory: true)
    }

    /// A throwaway defaults suite, so remembered phases never leak between
    /// tests or into the host app.
    static func makeDefaults() -> UserDefaults {
        let name = "AssistantTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @discardableResult
    static func student(
        _ first: String,
        _ last: String,
        in context: NSManagedObjectContext
    ) -> CDStudent {
        let student = CDStudent(context: context)
        student.id = UUID()
        student.firstName = first
        student.lastName = last
        return student
    }

    /// Start of "yyyy-MM-dd" in the current calendar.
    static func day(_ iso: String) throws -> Date {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        return try #require(Calendar.current.date(from: components))
    }

    static func viewModel(
        _ stack: CoreDataStack,
        on date: Date = Date(),
        defaults: UserDefaults? = nil
    ) -> AssistantAttendanceViewModel {
        let model = AssistantAttendanceViewModel(
            context: stack.viewContext,
            container: nil,
            date: date,
            defaults: defaults ?? makeDefaults()
        )
        model.load()
        return model
    }
}
