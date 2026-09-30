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
        // A made-up front desk, so the email shows once everyone's marked.
        // Nothing can go there: `example.org` takes no mail.
        let email = CDAttendanceEmailSettings(context: context)
        email.toAddresses = "frontdesk@example.org"
        #if DEBUG
        // `-AssistantSampleDeadline 75` (minutes after midnight) moves the
        // due time, to see the due and late states at any hour.
        // A launch argument arrives as text; `integer(forKey:)` reads it.
        if UserDefaults.standard.object(forKey: "AssistantSampleDeadline") != nil {
            email.deadlineMinutes = Int32(UserDefaults.standard.integer(forKey: "AssistantSampleDeadline"))
        }
        #endif
        _ = context.safeSave()
        seedHistory(in: context)
        _ = context.safeSave()
        // A fresh class starts the morning fresh.
        AttendanceLatePhase.forget(defaults: defaults)
        return stack
    }

    /// Past marks, so the school-day count and a welcome back show: everyone
    /// here on a first day that makes today "Day 37" (in Debug, or the day
    /// given with `-AssistantSampleDayNumber 100`), and Noah absent the four
    /// school days before today.
    private static func seedHistory(in context: NSManagedObjectContext) {
        #if DEBUG
        let given = UserDefaults.standard.integer(forKey: "AssistantSampleDayNumber")
        #else
        let given = 0
        #endif
        let dayNumber = given > 0 ? given : 37
        let students = context.safeFetch(CDFetchRequest(CDStudent.self))
        let today = Calendar.current.startOfDay(for: Date())

        var firstDay = today
        for _ in 1..<dayNumber {
            guard let earlier = SchoolDayChecker.schoolDay(from: firstDay, forward: false, using: context)
            else { break }
            firstDay = earlier
        }
        for student in students {
            mark(student, .present, on: firstDay, in: context)
        }
        #if DEBUG
        if given > 0 { AssistantSchoolDayCount.yearStartOverride = firstDay }
        #endif

        guard let noah = students.first(where: { $0.firstName == "Noah" }) else { return }
        var day = today
        for _ in 0..<4 {
            guard let earlier = SchoolDayChecker.schoolDay(from: day, forward: false, using: context) else { break }
            day = earlier
            mark(noah, .absent, on: day, in: context)
        }
    }

    private static func mark(
        _ student: CDStudent,
        _ status: AttendanceStatus,
        on day: Date,
        in context: NSManagedObjectContext
    ) {
        let record = CDAttendanceRecord(context: context)
        record.studentID = student.id?.uuidString ?? ""
        record.date = day
        record.status = status
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
