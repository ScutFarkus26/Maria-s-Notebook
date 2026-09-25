import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Returning to Today used to rebuild the ready queue and recompute the
/// needs-lesson count every time. Both are now kept until something they read
/// moves. These pin that a return with nothing changed rebuilds neither, that
/// an input change (or, for the count, a new day, a school-calendar change or
/// the one-year window moving) still does, and that the kept values always
/// equal what the old unconditional path computes.
@Suite("Today appearance gates")
@MainActor
struct TodayAppearanceGateTests {

    private struct Fixture {
        let first: CDLesson
        let third: CDLesson
        let noa: CDStudent
    }

    /// Two children confirmed on a lesson with a successor (the ready queue),
    /// and children at every age the count distinguishes: presented recently,
    /// a month ago, only on a Parsha lesson, never, and one withdrawn.
    private func seed(in context: NSManagedObjectContext) throws -> Fixture {
        let first = CoreDataTestHelpers.seedLesson(in: context, name: "Commutative", area: "Math", sequence: "Laws")
        first.orderInSequence = 10
        let second = CoreDataTestHelpers.seedLesson(in: context, name: "Distributive", area: "Math", sequence: "Laws")
        second.orderInSequence = 20
        let third = CoreDataTestHelpers.seedLesson(in: context, name: "Associative", area: "Math", sequence: "Laws")
        third.orderInSequence = 30
        let parsha = CoreDataTestHelpers.seedLesson(in: context, name: "Bereshit", area: "Parsha", sequence: "Parsha")
        let avital = CoreDataTestHelpers.seedStudent(in: context, firstName: "Avital", lastName: "B")
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "S")
        let liat = CoreDataTestHelpers.seedStudent(in: context, firstName: "Liat", lastName: "K")
        let noa = CoreDataTestHelpers.seedStudent(in: context, firstName: "Noa", lastName: "C")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Wendy", lastName: "W", enrollmentStatus: .withdrawn)

        let now = Date()
        let given = PresentationFactory.makePresented(
            lesson: first, students: [avital], presentedAt: now.addingTimeInterval(-86_400), context: context
        )
        given.confirmStudent(try #require(avital.id))
        let monthAgo = now.addingTimeInterval(-30 * 86_400)
        let old = PresentationFactory.makePresented(
            lesson: first, students: [maya], presentedAt: monthAgo, createdAt: monthAgo, context: context
        )
        old.confirmStudent(try #require(maya.id))
        _ = PresentationFactory.makePresented(lesson: parsha, students: [liat], presentedAt: now, context: context)
        #expect(CoreDataTestHelpers.save(context))
        return Fixture(first: first, third: third, noa: noa)
    }

    /// The count exactly as TodayView computed it on every appearance before.
    private func oldNeedsLessonCount(in context: NSManagedObjectContext) -> Int {
        let request = CDFetchRequest(CDStudent.self)
        request.predicate = CDStudent.enrolledPredicate
        let students = TestStudentsFilter.filterVisible(context.safeFetch(request)).uniqueByID
        guard !students.isEmpty else { return 0 }
        let viewModel = StudentsViewModel()
        let daysMap = viewModel.computeDaysSinceLastLessonCache(
            for: students, using: context, calendar: AppCalendar.shared
        )
        return daysMap.values.filter { $0 == -1 || $0 >= 7 }.count
    }

    private func freshQueue(_ context: NSManagedObjectContext) -> [ReadyForNextItem] {
        TodayViewModel.buildReadyForNext(lessons: nil, in: context)
    }

    /// What one appearance does to the model: the old path invalidated the
    /// queue first and recomputed the count unconditionally.
    private func appear(_ viewModel: TodayViewModel, old: Bool = false) {
        if old { viewModel.invalidateReadyForNext() }
        viewModel.reload()
        viewModel.reloadDerivedCountsIfNeeded(calendar: AppCalendar.shared, force: old)
    }

    @Test("Five returns with nothing changed build each value once, not five times")
    func repeatedAppearancesBuildOnce() throws {
        let context = try CoreDataTestHelpers.makeContext()
        _ = try seed(in: context)
        let before = TodayViewModel(context: context)
        let after = TodayViewModel(context: context)

        for _ in 0..<5 {
            appear(before, old: true)
            appear(after)
        }

        #expect(before.readyForNextBuildCount == 5)
        #expect(before.derivedCountsBuildCount == 5)
        #expect(after.readyForNextBuildCount == 1)
        #expect(after.derivedCountsBuildCount == 1)
        #expect(after.readyForNext == before.readyForNext)
        #expect(after.readyForNext == freshQueue(context))
        #expect(after.needsLessonCount == before.needsLessonCount)
        #expect(after.needsLessonCount == oldNeedsLessonCount(in: context))
        // At least Noa (never) and Liat (only a Parsha lesson); Maya's month
        // depends on the counter epoch the host has set.
        #expect(after.needsLessonCount >= 2)
    }

    @Test("An input change rebuilds on the next return; unrelated edits do not")
    func inputChangesRebuild() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let fixture = try seed(in: context)
        let viewModel = TodayViewModel(context: context)
        appear(viewModel)
        #expect(viewModel.readyForNextBuildCount == 1)
        #expect(viewModel.derivedCountsBuildCount == 1)

        // Attendance is read by neither.
        CoreDataTestHelpers.seedAttendance(in: context, studentID: try #require(fixture.noa.id), date: Date())
        #expect(CoreDataTestHelpers.save(context))
        appear(viewModel)
        #expect(viewModel.readyForNextBuildCount == 1)
        #expect(viewModel.derivedCountsBuildCount == 1)

        // A lesson reorder moves the queue (and the count's lesson input).
        fixture.third.orderInSequence = 15
        #expect(CoreDataTestHelpers.save(context))
        appear(viewModel)
        #expect(viewModel.readyForNextBuildCount == 2)
        #expect(viewModel.derivedCountsBuildCount == 2)
        #expect(viewModel.readyForNext == freshQueue(context))

        // Presenting Noa a lesson moves the count.
        let countBefore = viewModel.needsLessonCount
        _ = PresentationFactory.makePresented(lesson: fixture.first, students: [fixture.noa], context: context)
        #expect(CoreDataTestHelpers.save(context))
        appear(viewModel)
        #expect(viewModel.derivedCountsBuildCount == 3)
        #expect(viewModel.needsLessonCount == countBefore - 1)
        #expect(viewModel.needsLessonCount == oldNeedsLessonCount(in: context))
        #expect(viewModel.readyForNext == freshQueue(context))

        // An unsaved edit in the same turn is seen too.
        fixture.noa.enrollmentStatus = .withdrawn
        appear(viewModel)
        #expect(viewModel.derivedCountsBuildCount == 4)
        #expect(viewModel.needsLessonCount == oldNeedsLessonCount(in: context))
        #expect(viewModel.readyForNext == freshQueue(context))
    }

    @Test("A new day, a school-calendar change and a non-school day recompute the count")
    func dayAndCalendarChangesRecomputeTheCount() throws {
        let context = try CoreDataTestHelpers.makeContext()
        _ = try seed(in: context)
        let viewModel = TodayViewModel(context: context)
        let calendar = AppCalendar.shared
        let now = Date()
        viewModel.reloadDerivedCountsIfNeeded(calendar: calendar, now: now)
        viewModel.reloadDerivedCountsIfNeeded(calendar: calendar, now: now)
        #expect(viewModel.derivedCountsBuildCount == 1)

        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: now))
        viewModel.reloadDerivedCountsIfNeeded(calendar: calendar, now: tomorrow)
        #expect(viewModel.derivedCountsBuildCount == 2)
        viewModel.reloadDerivedCountsIfNeeded(calendar: calendar, now: tomorrow)
        #expect(viewModel.derivedCountsBuildCount == 2)

        SchoolDayDataVersion.bump()
        viewModel.reloadDerivedCountsIfNeeded(calendar: calendar, now: tomorrow)
        #expect(viewModel.derivedCountsBuildCount == 3)

        let closure = CDNonSchoolDay(context: context)
        closure.date = AppCalendar.startOfDay(now)
        #expect(CoreDataTestHelpers.save(context))
        viewModel.reloadDerivedCountsIfNeeded(calendar: calendar, now: tomorrow)
        #expect(viewModel.derivedCountsBuildCount == 4)
        #expect(viewModel.needsLessonCount == oldNeedsLessonCount(in: context))

        // The ready queue reads no date: a new day keeps it, and it still
        // equals a fresh build.
        viewModel.reload()
        let built = viewModel.readyForNextBuildCount
        viewModel.date = tomorrow
        viewModel.reload()
        #expect(viewModel.readyForNextBuildCount == built)
        #expect(viewModel.readyForNext == freshQueue(context))
    }

    @Test("The count is recomputed once the one-year window passes an assignment it read")
    func windowMovingRecomputes() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let calendar = AppCalendar.shared
        // Early in a day, so the checks below stay on the same day.
        let base = AppCalendar.startOfDay(Date()).addingTimeInterval(3600)
        let lesson = CoreDataTestHelpers.seedLesson(in: context)
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Tamar", lastName: "L")
        let yearAgo = try #require(calendar.date(byAdding: .year, value: -1, to: base))
        let created = yearAgo.addingTimeInterval(3600)
        _ = PresentationFactory.makePresented(
            lesson: lesson, students: [student], presentedAt: created, createdAt: created, context: context
        )
        #expect(CoreDataTestHelpers.save(context))
        #expect(TodayViewModel.presentedWindowFloor(calendar: calendar, now: base, in: context) == created)

        let viewModel = TodayViewModel(context: context)
        viewModel.reloadDerivedCountsIfNeeded(calendar: calendar, now: base)
        viewModel.reloadDerivedCountsIfNeeded(calendar: calendar, now: base.addingTimeInterval(1800))
        #expect(viewModel.derivedCountsBuildCount == 1)
        viewModel.reloadDerivedCountsIfNeeded(calendar: calendar, now: base.addingTimeInterval(7200))
        #expect(viewModel.derivedCountsBuildCount == 2)
    }

    @Test("Pull to refresh forces the count")
    func forceRecomputes() throws {
        let context = try CoreDataTestHelpers.makeContext()
        _ = try seed(in: context)
        let viewModel = TodayViewModel(context: context)
        viewModel.reloadDerivedCountsIfNeeded(calendar: AppCalendar.shared)
        viewModel.reloadDerivedCountsIfNeeded(calendar: AppCalendar.shared, force: true)
        #expect(viewModel.derivedCountsBuildCount == 2)
        #expect(viewModel.needsLessonCount == oldNeedsLessonCount(in: context))
    }
}
