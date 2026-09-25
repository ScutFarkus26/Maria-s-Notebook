import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The work grid reads each work's age from its item, worked out once per pass,
/// where it used to work the age out inside the sort comparators (twice per
/// comparison), the Age bucket keys and an unused metadata string. These pin
/// that every sort mode still orders and buckets the grid exactly as before.
@Suite("Open work grid sort")
@MainActor
struct OpenWorkGridSortTests {

    // MARK: - Fixture

    private struct Fixture {
        /// Held so the works keep their values: an object does not retain
        /// its context.
        let context: NSManagedObjectContext
        let works: [CDWorkModel]
        let lessonsByID: [UUID: CDLesson]
        let studentsByID: [UUID: CDStudent]
        let attentionWorkIDs: Set<UUID>
    }

    /// Eighty works with plenty of ties in every key: lesson names equal but
    /// for case, blank and missing lessons, children sharing a short name,
    /// missing children, many works created the same day, and some with no
    /// creation date or no id at all. Eighty is past the length Swift's sort
    /// finishes with insertion sort, so its merge path runs too.
    private func makeFixture() throws -> Fixture {
        let context = try CoreDataTestHelpers.makeContext()
        let lessons = ["Long Division", "long division", "Checkerboard", "   ", "Stamp Game"].map {
            CoreDataTestHelpers.seedLesson(in: context, name: $0)
        }
        let students = [("Ada", "Lovelace"), ("Ada", "Lamb"), ("Noam", ""), ("", "Katz"), ("Maya", "Stern")].map {
            CoreDataTestHelpers.seedStudent(in: context, firstName: $0.0, lastName: $0.1)
        }
        let lessonIDs = lessons.compactMap { $0.id?.uuidString } + [UUID().uuidString, "legacy-lesson", ""]
        let studentIDs = students.compactMap { $0.id?.uuidString } + [UUID().uuidString, ""]
        let dayOffsets: [Int?] = [0, 0, 1, 3, 3, 4, 7, 8, 14, 15, 30, 31, 45, 200, nil, 2, 7, 0]
        let today = AppCalendar.startOfDay(Date())

        var works: [CDWorkModel] = []
        for index in 0..<80 {
            let work = CDWorkModel(context: context)
            work.lessonID = lessonIDs[index % lessonIDs.count]
            work.studentID = studentIDs[(index * 3) % studentIDs.count]
            work.createdAt = dayOffsets[index % dayOffsets.count].map { offset in
                AppCalendar.addingDays(-offset, to: today).addingTimeInterval(Double(index % 5) * 3_600)
            }
            if index % 29 == 5 { work.id = nil }
            works.append(work)
        }
        let attention = Set(works.enumerated().compactMap { $0.offset % 3 == 0 ? $0.element.id : nil })
        let lessonPairs = lessons.compactMap { lesson in lesson.id.map { ($0, lesson) } }
        let studentPairs = students.compactMap { child in child.id.map { ($0, child) } }
        return Fixture(
            context: context,
            works: works,
            lessonsByID: Dictionary(uniqueKeysWithValues: lessonPairs),
            studentsByID: Dictionary(uniqueKeysWithValues: studentPairs),
            attentionWorkIDs: attention
        )
    }

    // MARK: - Tests

    @Test("Every sort mode orders and buckets the grid exactly as the comparator-side age did")
    func matchesTheOldSortInEveryMode() throws {
        let fixture = try makeFixture()
        for mode in WorkAgendaSortMode.allCases {
            let grid = OpenWorkGrid(
                works: fixture.works,
                lessonsByID: fixture.lessonsByID,
                studentsByID: fixture.studentsByID,
                attentionWorkIDs: fixture.attentionWorkIDs,
                sortMode: mode,
                onOpen: { _ in },
                onLog: { _, _ in },
                onSchedule: { _, _ in }
            )
            let legacy = LegacyOpenWorkGridSort(
                works: fixture.works,
                lessonsByID: fixture.lessonsByID,
                studentsByID: fixture.studentsByID,
                attentionWorkIDs: fixture.attentionWorkIDs,
                sortMode: mode
            )
            let sections = grid.groupedSections
            let legacySections = legacy.groupedSections

            #expect(sections.count > 1, "\(mode.rawValue): more than one section, got \(sections.map(\.key))")
            #expect(sections.flatMap(\.items).count == fixture.works.count, "\(mode.rawValue): every work drawn")
            #expect(sections.map(\.key) == legacySections.map(\.key), "\(mode.rawValue): section keys")
            #expect(
                sections.map { $0.items.map(\.id) } == legacySections.map { $0.items.map(\.id) },
                "\(mode.rawValue): order within sections"
            )
            #expect(
                sections.flatMap(\.items).map(\.title) == legacySections.flatMap(\.items).map(\.title),
                "\(mode.rawValue): titles"
            )
            #expect(
                sections.flatMap(\.items).map(\.student) == legacySections.flatMap(\.items).map(\.student),
                "\(mode.rawValue): children"
            )
        }
    }

    @Test("The old Age sort worked the age out far more than once per work")
    func oldAgeSortRecomputedTheAge() throws {
        let fixture = try makeFixture()
        let legacy = LegacyOpenWorkGridSort(
            works: fixture.works,
            lessonsByID: fixture.lessonsByID,
            studentsByID: fixture.studentsByID,
            attentionWorkIDs: fixture.attentionWorkIDs,
            sortMode: .age
        )
        _ = legacy.groupedSections
        // Once per work for the metadata string, twice per comparison, once
        // per work for the bucket key. The grid now reads it once per work.
        #expect(legacy.ageReads > 3 * fixture.works.count)
    }
}

/// `OpenWorkGrid`'s sections exactly as they were computed before the age was
/// stored on the item, counting each time the age is worked out.
@MainActor
private final class LegacyOpenWorkGridSort {
    let works: [CDWorkModel]
    let lessonsByID: [UUID: CDLesson]
    let studentsByID: [UUID: CDStudent]
    let attentionWorkIDs: Set<UUID>
    let sortMode: WorkAgendaSortMode
    private(set) var ageReads = 0

    init(
        works: [CDWorkModel],
        lessonsByID: [UUID: CDLesson],
        studentsByID: [UUID: CDStudent],
        attentionWorkIDs: Set<UUID>,
        sortMode: WorkAgendaSortMode
    ) {
        self.works = works
        self.lessonsByID = lessonsByID
        self.studentsByID = studentsByID
        self.attentionWorkIDs = attentionWorkIDs
        self.sortMode = sortMode
    }

    struct WorkGridItem: Identifiable {
        let id: NSManagedObjectID
        let workID: UUID
        let work: CDWorkModel
        let title: String
        let student: String
        let needsAttention: Bool
        let metadata: String
    }

    var groupedSections: [(key: String, items: [WorkGridItem])] {
        let items = sortedWorks
        var order: [String] = []
        var buckets: [String: [WorkGridItem]] = [:]
        for it in items {
            let key = sequenceKey(for: it)
            if buckets[key] == nil { order.append(key); buckets[key] = [] }
            buckets[key]?.append(it)
        }
        return order.map { key in (key: key, items: buckets[key] ?? []) }
    }

    private func sequenceKey(for item: WorkGridItem) -> String {
        switch sortMode {
        case .lesson:
            return item.title
        case .student:
            return item.student
        case .age:
            let days = ageDays(for: item.work)
            return ageBucketLabel(forDays: days)
        case .needsAttention:
            return item.needsAttention ? "Needs Attention" : "Other"
        }
    }

    private func ageBucketLabel(forDays days: Int) -> String {
        if days <= 0 {
            return "Today"
        } else if days <= 3 {
            return "1–3 days"
        } else if days <= 7 {
            return "4–7 days"
        } else if days <= 14 {
            return "8–14 days"
        } else if days <= 30 {
            return "15–30 days"
        } else {
            return "30+ days"
        }
    }

    private var sortedWorks: [WorkGridItem] {
        let mapped: [WorkGridItem] = works.map { w in
            let title = lessonTitle(forLessonID: w.lessonID)
            let student = studentName(for: w)
            let meta = metadata(for: w)
            let attention = needsAttention(for: w)
            return WorkGridItem(
                id: w.objectID, workID: w.id ?? UUID(), work: w, title: title,
                student: student, needsAttention: attention, metadata: meta
            )
        }
        switch sortMode {
        case .lesson:
            return mapped.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .student:
            return mapped.sorted { $0.student.localizedCaseInsensitiveCompare($1.student) == .orderedAscending }
        case .age:
            return mapped.sorted { ageDays(for: $0.work) > ageDays(for: $1.work) }
        case .needsAttention:
            return mapped.sorted { lhs, rhs in
                if lhs.needsAttention != rhs.needsAttention { return lhs.needsAttention && !rhs.needsAttention }
                // If both same attention, older first
                return ageDays(for: lhs.work) > ageDays(for: rhs.work)
            }
        }
    }

    private func lessonTitle(forLessonID lessonID: String) -> String {
        let name = lessonsByID[uuidString: lessonID]?.name ?? ""
        return LessonFormatter.titleOrFallback(name, fallback: "Lesson \(String(lessonID.prefix(6)))")
    }

    private func studentName(for w: CDWorkModel) -> String {
        if let s = studentsByID[uuidString: w.studentID] {
            return s.shortName
        }
        return "Student"
    }

    private func metadata(for w: CDWorkModel) -> String {
        var parts: [String] = []
        parts.append((w.kind ?? .research).displayName)
        let age = ageDays(for: w)
        parts.append("\(age)d")
        return parts.joined(separator: " • ")
    }

    private func ageDays(for w: CDWorkModel) -> Int {
        ageReads += 1
        // Clamped to the school-year counter epoch (see `SchoolYearCounters`).
        let start = AppCalendar.startOfDay(SchoolYearCounters.countFrom(w.createdAt ?? .distantPast))
        let now = AppCalendar.startOfDay(Date())
        let comps = AppCalendar.shared.dateComponents([.day], from: start, to: now)
        return comps.day ?? 0
    }

    private func needsAttention(for w: CDWorkModel) -> Bool {
        w.id.map(attentionWorkIDs.contains) ?? false
    }
}
