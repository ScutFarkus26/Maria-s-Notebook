import Foundation
import CoreData

/// A made-up class for looking at the attendance screen without joining a
/// real one: a local store (no iCloud) filled with a roster of invented names.
///
/// Two ways in. The join screen's **Try a Sample Class** opens it, which is
/// how App Review (and anyone curious before their guide's invitation
/// arrives) sees the app. That sample is kept on this iPhone for the day:
/// closing the app and coming back, or leaving and trying it again, finds the
/// marks where she left them, and a relaunch reopens it if it was open. The
/// next day it starts fresh. Leave Sample Class goes back to joining. And in
/// Debug builds, launching with `-AssistantSampleClass` skips joining
/// altogether, with a fresh sample in memory each launch.
///
/// Its marks go nowhere: no share attach, no Siri, no reminders but the early
/// pickup one (trying Leaving Early… should ring), and the Late phase is kept
/// in its own defaults suite so it can't touch the real class's.
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

    /// The day the saved sample was filled, as `AppCalendar.dayID`.
    static let seededDayKey = "Assistant.sampleClass.seededDay"
    /// The sample was open when the app last closed, so a relaunch reopens it.
    private static let wasOpenKey = "Assistant.sampleClass.wasOpen"

    /// Whether a relaunch should reopen the join screen's sample.
    static var wasOpen: Bool {
        get { defaults.bool(forKey: wasOpenKey) }
        set { defaults.set(newValue, forKey: wasOpenKey) }
    }

    /// Whether the real class, open underneath the sample, has a membership
    /// row: a classroom arrived while she was looking at the sample.
    static func realClassHasMembership() -> Bool {
        guard AssistantStack.isOpen, let stack = try? AssistantStack.shared() else { return false }
        let request = CDClassroomMembership.ownRowsRequest()
        request.fetchLimit = 1
        return stack.viewContext.safeFetchFirst(request) != nil
    }

    /// The join screen's sample, open for as long as the app runs, so leaving
    /// it and trying it again finds the same store.
    private static var saved: (stack: CoreDataStack, day: String)?

    /// The join screen's sample: today's saved one, or a fresh one filled now
    /// if there's none from today.
    static func savedStack() throws -> CoreDataStack {
        let today = AppCalendar.dayID(Date())
        if let saved, saved.day == today { return saved.stack }
        if let old = saved?.stack {
            // Yesterday's, still open: let go of its file before replacing it.
            close(old)
            saved = nil
        }
        let stack = try openSaved(at: CoreDataStack.sampleClassroomStoreURL(), today: today, defaults: defaults)
        saved = (stack, today)
        return stack
    }

    /// Opens the sample at `url` if it was filled `today`; otherwise (another
    /// day, no file, or a file that won't open) replaces it with a fresh one.
    static func openSaved(at url: URL, today: String, defaults: UserDefaults) throws -> CoreDataStack {
        if defaults.string(forKey: seededDayKey) == today,
           FileManager.default.fileExists(atPath: url.path),
           let stack = try? CoreDataStack(enableCloudKit: false, localStoreURL: url) {
            if stack.viewContext.safeFetchFirst(CDFetchRequest(CDStudent.self)) != nil { return stack }
            close(stack)
        }
        try destroyStore(at: url)
        let stack = try CoreDataStack(enableCloudKit: false, localStoreURL: url)
        fill(stack.viewContext, defaults: defaults)
        defaults.set(today, forKey: seededDayKey)
        return stack
    }

    private static func close(_ stack: CoreDataStack) {
        let coordinator = stack.container.persistentStoreCoordinator
        for store in coordinator.persistentStores { try? coordinator.remove(store) }
    }

    private static func destroyStore(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: try CoreDataStack.sharedModel())
        try coordinator.destroyPersistentStore(at: url, type: .sqlite)
    }

    /// A fresh sample in memory: the Debug launch argument's, and the tests'.
    static func makeStack() throws -> CoreDataStack {
        let stack = try CoreDataStack(enableCloudKit: false, inMemory: true)
        fill(stack.viewContext, defaults: defaults)
        return stack
    }

    /// The roster, the front desk, the past marks and the Restock shelf, into an
    /// empty store.
    private static func fill(_ context: NSManagedObjectContext, defaults: UserDefaults) {
        let calendar = Calendar.current
        for (index, (first, last)) in names.enumerated() {
            let student = CDStudent(context: context)
            student.firstName = first
            student.lastName = last
            // Upper Elementary and Adolescent, like the real class, so Group
            // by Level has two blocks to show.
            student.level = index % 3 == 2 ? .adolescent : .upper
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
        seedGuideName(in: context)
        seedRestock(in: context)
        _ = context.safeSave()
        // A fresh class starts the morning fresh.
        AttendanceLatePhase.forget(defaults: defaults)
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
        if given > 0 { AttendanceSchoolDayCount.yearStartOverride = firstDay }
        #endif

        guard let noah = students.first(where: { $0.firstName == "Noah" }) else { return }
        var day = today
        for _ in 0..<4 {
            guard let earlier = SchoolDayChecker.schoolDay(from: day, forward: false, using: context) else { break }
            day = earlier
            mark(noah, .absent, on: day, in: context)
        }
    }

    /// The sample guide's record name, on his Restock changes and his name.
    static let guideRecordName = "_sampleGuide"
    /// The name the sample guide set, so Restock reads "Ms. Rivera is
    /// ordering" and "Marked Out by Ms. Rivera" as a real class would.
    static let guideName = "Ms. Rivera"

    /// The sample guide's row in the classroom's list of names, in the
    /// sample's own store (it has no other): never the real class's list.
    static func seedGuideName(in context: NSManagedObjectContext, now: Date = Date()) {
        let guide = CDClassroomPerson(context: context)
        guide.recordName = guideRecordName
        guide.role = .leadGuide
        guide.displayName = guideName
        guide.createdAt = now
        guide.modifiedAt = now
    }

    /// The Restock shelf: two places, five staples, Toilet Paper out (this
    /// morning) and Paper Towels low (yesterday), both marked by the guide;
    /// glue sticks on the office run, and two things the guide is ordering,
    /// one asked for three days ago.
    static func seedRestock(in context: NSManagedObjectContext, now: Date = Date()) {
        let guide = RestockAuthor(role: .leadGuide, recordName: guideRecordName)
        let calendar = Calendar.current
        let morning = calendar.date(bySettingHour: 8, minute: 12, second: 0, of: now) ?? now
        let yesterday = calendar.date(byAdding: .day, value: -1, to: morning) ?? morning
        let bathrooms = [("Toilet Paper", RestockLevel.out), ("Hand Soap", .stocked), ("Tissues", .stocked)]
        let sink = [("Paper Towels", RestockLevel.low), ("Sponges", .stocked)]
        for (place, staples) in [("Bathrooms", bathrooms), ("Sink", sink)] {
            for (name, level) in staples {
                let at = name == "Toilet Paper" ? min(morning, now) : yesterday
                let details = RestockService.StapleDetails(name: name, place: place)
                _ = RestockService.addStaple(details, level: level, by: guide, at: at, in: context)
            }
        }
        _ = RestockService.addOneOff(
            title: "Glue sticks", quantity: 12, source: .office, by: guide,
            at: yesterday.addingTimeInterval(3_600), in: context
        )
        let asked = calendar.date(byAdding: .day, value: -3, to: morning) ?? morning
        if let paper = RestockService.addOneOff(
            title: "Watercolor Paper", source: .order, by: guide, at: asked, in: context
        )?.object {
            RestockService.markRequested([paper], from: "the office", at: asked)
        }
        _ = RestockService.addOneOff(
            title: "USB-C Charger", quantity: 2, source: .order, by: guide, at: yesterday, in: context
        )
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
