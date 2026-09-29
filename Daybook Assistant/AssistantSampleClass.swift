#if DEBUG
import Foundation
import CoreData

/// A throwaway class for looking at the attendance screen without joining a
/// real one. Launch with `-AssistantSampleClass` and the app skips joining,
/// opens an in-memory store (no iCloud, nothing on disk) and fills it with a
/// made-up roster. Debug builds only.
enum AssistantSampleClass {
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-AssistantSampleClass")
    }

    static func makeStack() throws -> CoreDataStack {
        let stack = try CoreDataStack(enableCloudKit: false, inMemory: true)
        let context = stack.viewContext
        let calendar = Calendar.current
        for (index, (first, last)) in names.enumerated() {
            let student = CDStudent(context: context)
            student.firstName = first
            student.lastName = last
            // Nine-to-twelve-year-olds born through the year, and Maya's
            // birthday today, so the cake shows.
            let age = 9 + index % 4
            student.birthday = index == 1
                ? calendar.date(byAdding: .year, value: -age, to: Date())
                : calendar.date(from: DateComponents(year: calendar.component(.year, from: Date()) - age,
                                                     month: 1 + (index * 5) % 12, day: 1 + (index * 7) % 28))
        }
        _ = context.safeSave()
        // A fresh class starts the morning fresh.
        AssistantAttendanceViewModel.LatePhaseMemory.forget()
        return stack
    }

    /// 22 children, the real class's size, with two Ettys and two Sarahs so
    /// short names have to tell them apart.
    private static let names: [(String, String)] = [
        ("Ari", "Cedar"), ("Maya", "Stone"), ("Noah", "Linden"), ("Leah", "Hart"),
        ("Ezra", "Bloom"), ("Tamar", "Reed"), ("Miriam", "Vale"), ("Eli", "Brooks"),
        ("Rina", "Ash"), ("Etty", "Rosen"), ("Etty", "Goldman"), ("Sarah", "Klein"),
        ("Sarah", "Adler"), ("Yael", "Morrow"), ("Dina", "Fairweather"), ("Levi", "Park"),
        ("Asher", "Quinn"), ("Gideon", "Hale"), ("Micah", "Frost"), ("Noa", "Winter"),
        ("Shira", "Lowe"), ("Talia", "Brook")
    ]
}
#endif
