import CoreData
import SwiftUI
import Testing
@testable import CosmicDaybook

/// The report that started the Brewing mark, replayed in the Sample Class: Add to Inbox
/// from the Checklist on a lesson the children aren't ready for. With `BREWING_SHOT_DIR`
/// set (see `+Mark`) the grid's own cells, key and card are saved there, light and dark.
extension ChecklistBrewingTests {

    private static let decimalFractions = [
        "Formation and Reading of Quantities",
        "Addition with Decimals",
        "Subtraction with Decimals",
        "Multiplication with Decimals",
        "Division with Decimals by a Unit Divisor",
        "Converting a Fraction with the Instrument"
    ]

    /// The Sample Class over a small Math › Decimal Fractions, with three children added
    /// to the Inbox for one lesson from the grid; the first of them has mastered the
    /// lesson before, the other two haven't had it.
    @MainActor
    private struct SampleClass {
        let stack: CoreDataStack
        let grid: ClassAreaChecklistViewModel
        let before: CDLesson
        let lesson: CDLesson
        let ready: CDStudent
        let waiting: [CDStudent]
        /// The first columns of the roster, the three children among them.
        let columns: [CDStudent]

        var context: NSManagedObjectContext { stack.viewContext }

        func cell(_ student: CDStudent) throws -> CellIdentifier {
            CellIdentifier(studentID: try #require(student.id), lessonID: try #require(lesson.id))
        }
    }

    private func makeSampleClass() throws -> SampleClass {
        let myClass = try CoreDataTestHelpers.makeInMemoryStack()
        for (order, name) in Self.decimalFractions.enumerated() {
            let lesson = CoreDataTestHelpers.seedLesson(
                in: myClass.viewContext, name: name, area: "Math", sequence: "Decimal Fractions"
            )
            lesson.orderInSequence = Int64(order)
        }
        try myClass.viewContext.save()
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        try SampleClassroomSeeder.prepare(lessonsFrom: myClass.viewContext, sampleContext: context)

        let grid = try Room.grid(area: "Math", context: context)
        let columns = Array(grid.rosterStudents.prefix(8))
        let ordered = grid.lessons.sorted { $0.orderInSequence < $1.orderInSequence }
        // The latest lesson that three of those children aren't ready for and aren't planned for.
        func notYet(_ lesson: CDLesson) -> [CDStudent] {
            columns.filter { grid.state(for: $0, lesson: lesson)?.displayStatus == .notReady }
        }
        let index = try #require(ordered.indices.dropFirst().last { notYet(ordered[$0]).count >= 3 })
        let lesson = ordered[index], before = ordered[index - 1]
        let children = Array(notYet(lesson).prefix(3))

        // One of them masters the lesson before; then all three go to the Inbox, as the
        // card's Add to Inbox does it.
        grid.markComplete(student: children[0], lesson: before, context: context)
        for child in children {
            grid.toggleScheduled(student: child, lesson: lesson, context: context)
        }
        return SampleClass(
            stack: stack, grid: grid, before: before, lesson: lesson,
            ready: children[0], waiting: Array(children.dropFirst()), columns: columns
        )
    }

    @Test("In the Sample Class, Add to Inbox on a lesson the children aren't ready for turns their cells Brewing")
    func sampleClassAddToInbox() async throws {
        let sample = try makeSampleClass()
        let grid = sample.grid
        let waitingIDs = sample.waiting.compactMap(\.id)

        // All three are on one Inbox lesson, and it is under Brewing in Lessons & Work.
        let inbox = await Room.inbox(sample.context)
        let lessonID = try #require(sample.lesson.id).uuidString
        let row = try #require(inbox.blockedLessons.first { $0.lessonID == lessonID })
        #expect(Set(row.resolvedStudentIDs) == Set(([sample.ready] + sample.waiting).compactMap(\.id)))
        #expect(!inbox.readyLessons.contains { $0.lessonID == lessonID })

        // The grid says so on each of their cells, and names the two it is waiting on.
        for child in [sample.ready] + sample.waiting {
            let state = try #require(grid.state(for: child, lesson: sample.lesson))
            #expect(state.showsBrewing)
            #expect(Set(state.brewingHeldBy) == Set(waitingIDs))
        }
        #expect(grid.statusCounts.brewing >= 3)

        // The card of the child who is ready herself names who holds the group.
        let names = sample.waiting.map(\.shortName)
        let readyState = try #require(grid.state(for: sample.ready, lesson: sample.lesson))
        let holders = readyState.brewingHeldBy.compactMap { id in
            grid.rosterStudents.first { $0.id == id }?.shortName
        }
        #expect(Set(holders) == Set(names))
        let text = ChecklistCellCardText.status(
            state: readyState, record: .init(), precedingLessonName: sample.before.name, brewingHeldByOthers: holders
        )
        #expect(text.title == "Brewing.")
        #expect(text.detail
            == "In the Inbox under Brewing, waiting on \(holders[0]) and 1 other for \(sample.before.name).")

        try savePictures(of: sample)
    }

    // MARK: - Pictures

    /// The two rows as the Checklist draws them on an iPad or Mac: the grid's own cells.
    private struct Rows: View {
        let sample: SampleClass
        private let metrics = ChecklistGridMetrics.regular

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Color.clear.frame(width: metrics.lessonColumnWidth, height: 20)
                    ForEach(sample.columns, id: \.objectID) { student in
                        Text(student.firstName)
                            .font(.caption2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .frame(width: metrics.studentColumnWidth)
                    }
                }
                ForEach([sample.before, sample.lesson], id: \.objectID) { lesson in
                    ChecklistGridMetrics.hairline.frame(height: 1)
                    HStack(spacing: 0) {
                        Text(lesson.name)
                            .font(.callout)
                            .lineLimit(1)
                            .padding(.leading, 10)
                            .frame(width: metrics.lessonColumnWidth, alignment: .leading)
                        ForEach(sample.columns, id: \.objectID) { student in
                            cell(student, lesson)
                        }
                    }
                }
            }
            .padding(12)
        }

        private func cell(_ student: CDStudent, _ lesson: CDLesson) -> some View {
            ClassChecklistSmartCell(
                cell: CellIdentifier(studentID: student.id ?? UUID(), lessonID: lesson.id ?? UUID()),
                state: sample.grid.state(for: student, lesson: lesson),
                isSelected: false,
                isSelectionMode: false,
                isRegular: true,
                studentName: student.shortName,
                lessonName: lesson.name,
                onAction: ChecklistCellActionHandler { _, _ in }
            )
            .frame(width: metrics.studentColumnWidth, height: metrics.rowHeight)
        }
    }

    private func savePictures(of sample: SampleClass) throws {
        guard let dir = ProcessInfo.processInfo.environment["BREWING_SHOT_DIR"] else { return }
        let grid = sample.grid
        let handler = ChecklistCellActionHandler { _, _ in }
        for scheme in [ColorScheme.light, .dark] {
            func save(_ view: some View, _ name: String) throws {
                let framed = view
                    .background(ChecklistGridMetrics.surface)
                    .environment(grid)
                    .environment(\.colorScheme, scheme)
                let file = "sample-class-\(name)-\(scheme == .dark ? "dark" : "light").png"
                try png(framed)?.write(to: URL(fileURLWithPath: dir).appendingPathComponent(file))
            }
            try save(Rows(sample: sample), "rows")
            try save(
                ChecklistStatusBar(
                    counts: grid.statusCounts, lessonCount: grid.visibleLessons.count, studentCount: grid.students.count
                ).keyItems,
                "key"
            )
            for (child, name) in [(sample.waiting[0], "card-held-by-her"), (sample.ready, "card-held-by-others")] {
                let cell = try sample.cell(child)
                grid.openCard(cell, context: sample.context)
                try save(ChecklistCellCard(cell: cell, isRegular: true, onAction: handler), name)
            }
            grid.closeCard()
        }
    }
}
