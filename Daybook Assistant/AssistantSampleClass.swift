import Foundation
import CoreData

/// A made-up class for looking at the attendance screen without joining a
/// real one: an in-memory store (no iCloud, nothing on disk) filled with a
/// roster of invented names.
///
/// Two ways in. The join screen's **Try a Sample Class** opens it for this
/// session, which is how App Review (and anyone curious before their guide's
/// invitation arrives) sees the app; Leave Sample Class or a relaunch goes
/// back to joining. And in Debug builds, launching with `-AssistantSampleClass`
/// skips joining altogether.
///
/// Its marks go nowhere: no share attach, no reminders, no Siri, and the Late
/// phase is kept in its own defaults suite so it can't touch the real class's.
enum AssistantSampleClass {
    /// Launched with `-AssistantSampleClass`. Always false in Release, so
    /// callers need no `#if` of their own (a Release-only branch is one no
    /// Debug build compiles). `AssistantStack` builds the sample then, so
    /// Siri reads it too.
    static var isRequested: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-AssistantSampleClass")
        #else
        false
        #endif
    }

    /// Opened from the join screen for this session. The real stack stays
    /// open underneath, untouched, for Siri and for joining.
    static var isChosen = false

    /// The sample is on screen, however it was opened.
    static var isActive: Bool { isRequested || isChosen }

    /// Where the sample's Late phase is remembered, apart from the real
    /// class's (`.standard`).
    static let defaults = UserDefaults(suiteName: "Assistant.sampleClass") ?? .standard

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
        AssistantLatePhase.forget(defaults: defaults)
        return stack
    }

    /// 22 children, the real class's size, with two Ettys and two Sarahs so
    /// short names have to tell them apart.
    static let names: [(String, String)] = [
        ("Ari", "Cedar"), ("Maya", "Stone"), ("Noah", "Linden"), ("Leah", "Hart"),
        ("Ezra", "Bloom"), ("Tamar", "Reed"), ("Miriam", "Vale"), ("Eli", "Brooks"),
        ("Rina", "Ash"), ("Etty", "Rosen"), ("Etty", "Goldman"), ("Sarah", "Klein"),
        ("Sarah", "Adler"), ("Yael", "Morrow"), ("Dina", "Fairweather"), ("Levi", "Park"),
        ("Asher", "Quinn"), ("Gideon", "Hale"), ("Micah", "Frost"), ("Noa", "Winter"),
        ("Shira", "Lowe"), ("Talia", "Brook")
    ]
}
