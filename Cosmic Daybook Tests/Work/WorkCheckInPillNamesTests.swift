import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The week plan's single check-in pill takes its lesson and child names from
/// its `CalendarCheckInGroup`, which resolved them in the range's batched
/// lookup, instead of fetching the work, lesson and child by id in its body.
/// These pin that the pill still shows exactly the strings it used to resolve
/// for itself, fallbacks included.
@Suite("Work check-in pill names")
@MainActor
struct WorkCheckInPillNamesTests {

    // MARK: - The pill's own lookups, as they were

    /// `WorkCheckInPill.workTitle` before the pill took the group's title.
    private func oldWorkTitle(_ checkIn: CDWorkCheckIn, in context: NSManagedObjectContext) -> String {
        guard let workID = checkIn.workID.asUUID,
              let work = context.object(CDWorkModel.self, id: workID) else { return "Work" }

        if let lessonID = work.lessonID.asUUID {
            if let lesson = context.object(CDLesson.self, id: lessonID) {
                let name = lesson.name.trimmed()
                if !name.isEmpty { return name }
            }
        }
        return "Lesson \(String(work.lessonID.prefix(6)))"
    }

    /// `WorkCheckInPill.studentName` before the pill took the group's name.
    private func oldStudentName(_ checkIn: CDWorkCheckIn, in context: NSManagedObjectContext) -> String {
        guard let workID = checkIn.workID.asUUID,
              let work = context.object(CDWorkModel.self, id: workID),
              let studentID = work.studentID.asUUID else { return "" }

        if let student = context.object(CDStudent.self, id: studentID) {
            return student.shortName
        }
        return ""
    }

    // MARK: - Fixture

    private let today = AppCalendar.startOfDay(Date())

    /// A work and one scheduled check-in on it. Each call gets its own purpose,
    /// so no two check-ins share a pill unless a test asks for it.
    @discardableResult
    private func seedCheckIn(
        in context: NSManagedObjectContext,
        lessonID: String,
        studentID: String,
        purpose: String,
        style: CheckInStyle = .flexible,
        studentInitiated: Bool = false
    ) -> CDWorkCheckIn {
        let work = CDWorkModel(context: context)
        work.lessonID = lessonID
        work.studentID = studentID
        work.checkInStyle = style
        let checkIn = CDWorkCheckIn(context: context)
        checkIn.workID = work.id?.uuidString ?? ""
        checkIn.work = work
        checkIn.date = today.addingTimeInterval(9 * 3_600)
        checkIn.purpose = purpose
        checkIn.studentInitiated = studentInitiated
        return checkIn
    }

    private func groups(
        for checkIns: [CDWorkCheckIn], in context: NSManagedObjectContext
    ) -> [CalendarCheckInGroup] {
        let lookup = CalendarCheckInGrouper.Lookup.build(for: checkIns, in: context)
        return CalendarCheckInGrouper.groups(from: checkIns, lookup: lookup)
    }

    /// The work behind one check-in, by the ids it carries.
    private struct NameCase {
        let lessonID: String
        let studentID: String
        var style: CheckInStyle = .flexible
    }

    /// One saved check-in per way a pill's names can resolve, and the id of
    /// the lesson with the blank name.
    private func seedNameCases(
        in context: NSManagedObjectContext
    ) throws -> (checkIns: [CDWorkCheckIn], blankLessonID: String) {
        let lesson = { (name: String) in
            try #require(CoreDataTestHelpers.seedLesson(in: context, name: name).id).uuidString
        }
        let child = { (first: String, last: String) in
            try #require(CoreDataTestHelpers.seedStudent(in: context, firstName: first, lastName: last).id).uuidString
        }
        let named = try lesson("Long Division")
        let blank = try lesson("   ")
        let ada = try child("Ada", "lovelace")

        let cases = [
            NameCase(lessonID: named, studentID: ada),                              // both on file
            NameCase(lessonID: try lesson("  Checkerboard  "), studentID: ada, style: .group), // needs trimming
            NameCase(lessonID: blank, studentID: ada),                              // blank name: fallback
            NameCase(lessonID: UUID().uuidString, studentID: ada),                  // lesson not on file
            NameCase(lessonID: "legacy-lesson-7", studentID: ada),                  // not a uuid
            NameCase(lessonID: "", studentID: ada),                                 // no lesson at all
            NameCase(lessonID: named, studentID: try child("Noa", "")),
            NameCase(lessonID: named, studentID: try child("", "Katz")),
            NameCase(lessonID: named, studentID: try child("  Maya ", " stern")),
            NameCase(lessonID: named, studentID: UUID().uuidString),                // child not on file
            NameCase(lessonID: named, studentID: ""),                               // offered work, no owner
            NameCase(lessonID: named, studentID: "not-a-uuid"),
            NameCase(lessonID: named, studentID: ada, style: .individual)           // opted out of grouping
        ]
        let checkIns = cases.enumerated().map { index, item in
            seedCheckIn(
                in: context, lessonID: item.lessonID, studentID: item.studentID,
                purpose: "purpose \(index)", style: item.style, studentInitiated: index.isMultiple(of: 2)
            )
        }
        #expect(CoreDataTestHelpers.save(context))
        return (checkIns, blank)
    }

    // MARK: - Tests

    @Test("Every single pill shows the names it used to fetch, fallbacks included")
    func namesMatchThePillsOwnLookups() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let (checkIns, blankID) = try seedNameCases(in: context)

        let singles = groups(for: checkIns, in: context).filter { !$0.isGrouped }
        #expect(singles.count == checkIns.count)
        for group in singles {
            let pill = WorkCheckInPill(group: group)
            #expect(pill.checkIn === group.primary)
            #expect(pill.workTitle == oldWorkTitle(group.primary, in: context))
            #expect(pill.studentName == oldStudentName(group.primary, in: context))
        }

        // The strings themselves, so the two sides cannot agree on a wrong one.
        let titles = Set(singles.map { WorkCheckInPill(group: $0).workTitle })
        let names = Set(singles.map { WorkCheckInPill(group: $0).studentName })
        let blankFallback = "Lesson " + String(blankID.prefix(6))
        #expect(titles.isSuperset(of: ["Long Division", "Checkerboard", blankFallback, "Lesson legacy", "Lesson "]))
        #expect(names == ["Ada L", "Noa", "Katz", "Maya S", ""])
    }

    @Test("A check-in whose work is gone gets no pill, so the old \"Work\" fallback never drew")
    func missingWorkDrawsNoPill() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Stamp Game")
        let lessonID = try #require(lesson.id).uuidString
        let kept = seedCheckIn(in: context, lessonID: lessonID, studentID: "", purpose: "kept")

        let orphan = CDWorkCheckIn(context: context)
        orphan.workID = UUID().uuidString
        orphan.date = today
        orphan.purpose = "orphan"
        let garbled = CDWorkCheckIn(context: context)
        garbled.workID = "not-a-uuid"
        garbled.date = today
        garbled.purpose = "garbled"
        #expect(CoreDataTestHelpers.save(context))

        // What the pill would have drawn for them on its own.
        #expect(oldWorkTitle(orphan, in: context) == "Work")
        #expect(oldWorkTitle(garbled, in: context) == "Work")

        let drawn = groups(for: [kept, orphan, garbled], in: context).flatMap(\.checkIns)
        #expect(drawn.count == 1)
        #expect(drawn.first === kept)
    }

    @Test("Check-ins sharing a lesson and purpose draw as the grouped pill, not this one")
    func sharedCheckInsAreGrouped() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Bead Frame")
        let lessonID = try #require(lesson.id).uuidString
        let first = seedCheckIn(
            in: context, lessonID: lessonID, studentID: UUID().uuidString, purpose: "progressCheck"
        )
        let second = seedCheckIn(
            in: context, lessonID: lessonID, studentID: UUID().uuidString, purpose: "progressCheck"
        )
        #expect(CoreDataTestHelpers.save(context))

        let drawn = groups(for: [first, second], in: context)
        #expect(drawn.count == 1)
        #expect(drawn.first?.isGrouped == true)
    }
}
