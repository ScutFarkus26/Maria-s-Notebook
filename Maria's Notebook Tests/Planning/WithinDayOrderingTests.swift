import CoreData
import CoreGraphics
import Foundation
import Testing
@testable import Maria_s_Notebook

/// Covers how a lesson's position *within* a day is stored and recovered.
///
/// None of this had any coverage, which is how the reorder gesture came to be
/// silently neutralized: the drop path carefully computed second-spaced times
/// and `schedule(for:)` snapped every one of them to midnight, so the sort had
/// nothing to sort by and no test noticed.
@Suite("Within-day ordering")
@MainActor
struct WithinDayOrderingTests {

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        let components = DateComponents(year: year, month: month, day: dayOfMonth)
        return AppCalendar.startOfDay(AppCalendar.shared.date(from: components)!)
    }

    /// Monday 8 June 2026.
    private var monday: Date { day(2026, 6, 8) }

    private func time(_ hour: Int, _ minute: Int = 0, _ second: Int = 0, on base: Date) -> Date {
        AppCalendar.shared.date(bySettingHour: hour, minute: minute, second: second, of: base)!
    }

    // MARK: - The write gate

    @Test("Scheduling keeps the time it was given, and mirrors the day")
    func scheduleKeepsTime() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let assignment = CDLessonAssignment(context: stack.viewContext)

        let at0903 = time(9, 0, 3, on: monday)
        assignment.schedule(for: at0903)

        #expect(assignment.scheduledFor == at0903)
        #expect(assignment.scheduledForDay == monday)
        #expect(assignment.state == .scheduled)
    }

    @Test("Scheduling a bare day lands at the start of the morning, not at whatever o'clock it is")
    func scheduleOnDayIgnoresWallClock() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let assignment = CDLessonAssignment(context: stack.viewContext)

        // A caller that means "Monday" hands over a moment with a time on it.
        assignment.schedule(onDay: time(16, 42, 17, on: monday))

        #expect(assignment.scheduledForDay == monday)
        #expect(assignment.scheduledFor == time(UIConstants.morningHour, on: monday))
    }

    // MARK: - The repair pass

    @Test("The launch repair fixes the day mirror and never touches the time")
    func mirrorRepairIsNonDestructive() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext

        // An ordered lesson whose mirror has drifted — the case the repair exists for.
        let ordered = CDLessonAssignment(context: context)
        let at0901 = time(9, 0, 1, on: monday)
        ordered.scheduledFor = at0901
        ordered.scheduledForDay = .distantPast

        // An unscheduled one, whose mirror should read as "no day".
        let unscheduled = CDLessonAssignment(context: context)
        unscheduled.scheduledFor = nil
        unscheduled.scheduledForDay = monday

        #expect(CoreDataTestHelpers.save(context))
        await DataMigrations.repairScheduledForDayMirror(using: context)

        // The regression this guards: the pass used to write `scheduledFor = day`,
        // erasing every guide's within-day order on a random tenth of launches.
        #expect(ordered.scheduledFor == at0901)
        #expect(ordered.scheduledForDay == monday)
        #expect(unscheduled.scheduledForDay == Date.distantPast)
    }

    // MARK: - Order survives a round trip

    @Test("A dragged order survives being written and read back")
    func draggedOrderSurvivesRefetch() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext

        let ids = [UUID(), UUID(), UUID()]
        for id in ids {
            let assignment = CDLessonAssignment(context: context)
            assignment.id = id
            assignment.createdAt = monday
        }
        #expect(CoreDataTestHelpers.save(context))

        // Write the third item first, as a drag to the top would.
        let reordered = [ids[2], ids[0], ids[1]]
        let times = PlanningDropUtils.assignSequentialTimes(
            ids: reordered,
            base: time(UIConstants.morningHour, on: monday),
            calendar: AppCalendar.shared,
            spacingSeconds: UIConstants.scheduleSpacingSeconds
        )
        let request: NSFetchRequest<CDLessonAssignment> = NSFetchRequest(entityName: "LessonAssignment")
        let all = context.safeFetch(request)
        for assignment in all {
            if let id = assignment.id, let when = times[id] {
                assignment.schedule(for: when)
            }
        }
        #expect(CoreDataTestHelpers.save(context))

        let readBack = context.safeFetch(request)
            .sorted(by: LessonAssignmentOrdering.isOrderedBefore)
            .compactMap(\.id)
        #expect(readBack == reordered)
    }

    @Test("Legacy rows that all sit at midnight still get one stable order")
    func midnightTiesResolveDeterministically() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext

        // Every row written before ordering existed is midnight, so a whole day
        // is one tie — and Swift's sort is not stable.
        let earlier = CDLessonAssignment(context: context)
        earlier.id = UUID()
        earlier.scheduledFor = monday
        earlier.createdAt = time(8, on: monday)

        let later = CDLessonAssignment(context: context)
        later.id = UUID()
        later.scheduledFor = monday
        later.createdAt = time(11, on: monday)

        #expect(LessonAssignmentOrdering.isOrderedBefore(earlier, later))
        #expect(!LessonAssignmentOrdering.isOrderedBefore(later, earlier))
    }

    // MARK: - Where the drop lands

    @Test("Dropping between two cards inserts between them")
    func insertionBetweenCards() {
        let ids = [UUID(), UUID(), UUID()]
        let frames: [UUID: CGRect] = [
            ids[0]: CGRect(x: 0, y: 0, width: 300, height: 60),
            ids[1]: CGRect(x: 0, y: 60, width: 300, height: 60),
            ids[2]: CGRect(x: 0, y: 120, width: 300, height: 60)
        ]
        // Above the midpoint of the second card = between the first and second.
        let result = PlanningDropUtils.reordered(
            ids: ids, moving: ids[2], toLocationY: 70, frames: frames
        )
        #expect(result == [ids[0], ids[2], ids[1]])
    }

    @Test("Dragging downward lands where the indicator promised, not one slot lower")
    func downwardDragIsNotOffByOne() {
        // The dragged card is still in `frames` while it is being dragged, so a
        // raw index would count a row that is about to be removed.
        let ids = [UUID(), UUID(), UUID()]
        let frames: [UUID: CGRect] = [
            ids[0]: CGRect(x: 0, y: 0, width: 300, height: 60),
            ids[1]: CGRect(x: 0, y: 60, width: 300, height: 60),
            ids[2]: CGRect(x: 0, y: 120, width: 300, height: 60)
        ]

        // y=130 is inside the last card but above its midpoint, so the drop
        // belongs *before* it — landing after it would be the off-by-one.
        #expect(
            PlanningDropUtils.reordered(
                ids: ids, moving: ids[0], toLocationY: 130, frames: frames
            ) == [ids[1], ids[0], ids[2]]
        )

        // Below the last midpoint is the only way to reach the end of the day.
        #expect(
            PlanningDropUtils.reordered(
                ids: ids, moving: ids[0], toLocationY: 170, frames: frames
            ) == [ids[1], ids[2], ids[0]]
        )
    }

    @Test("Cards scrolled out of view do not shift the target slot")
    func scrolledOutCardsDoNotShiftTheDrop() {
        // A LazyVStack never runs the geometry reader for off-screen rows, so
        // the frame set covers only part of the day.
        let ids = [UUID(), UUID(), UUID(), UUID()]
        let visibleOnly: [UUID: CGRect] = [
            ids[2]: CGRect(x: 0, y: 0, width: 300, height: 60),
            ids[3]: CGRect(x: 0, y: 60, width: 300, height: 60)
        ]
        // Dropped above the first *visible* card, which is third in the day.
        let result = PlanningDropUtils.reordered(
            ids: ids, moving: ids[0], toLocationY: 10, frames: visibleOnly
        )
        #expect(result == [ids[1], ids[0], ids[2], ids[3]])
    }

    // MARK: - Moving the week

    @Test("Moving the week forward carries each lesson's place in its day")
    func bulkMoveKeepsTimeOfDay() {
        let tuesday = day(2026, 6, 9)
        let moved = WeekPlanSection.preservingTimeOfDay(
            from: time(9, 0, 2, on: monday),
            onto: tuesday,
            using: AppCalendar.shared
        )
        #expect(moved == time(9, 0, 2, on: tuesday))
    }
}
