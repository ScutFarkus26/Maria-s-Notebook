import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Pins the Presentations overview's cheaper paths to the ones they replaced:
/// the view model's assignment-refetch gate, the one-fetch attendance lookup
/// behind Recently Missed, the Suggested Next count, and the week strip's
/// per-day grouping.
@MainActor
@Suite("Presentations energy pass")
struct PresentationsEnergyPassTests {

    // MARK: - View model gate

    private func run(
        _ vm: PresentationsViewModel,
        _ context: NSManagedObjectContext
    ) async {
        let lessons: [CDLesson] = context.safeFetch(CDFetchRequest(CDLesson.self))
        let students: [CDStudent] = context.safeFetch(CDFetchRequest(CDStudent.self))
        vm.update(
            viewContext: context,
            calendar: AppCalendar.shared,
            inboxOrderRaw: "",
            missWindow: .all,
            showTestStudents: true,
            testStudentNamesRaw: "",
            lessons: lessons,
            students: students
        )
        await vm.pendingUpdateTask?.value
    }

    /// Runs an update that no assignment change preceded. Other suites share
    /// the process and post global save notifications (a torn-down stack's
    /// save fails open), so first settle any bump that already landed, and
    /// apply the no-refetch check only when nothing bumped the generation
    /// during the run; returns whether it did apply.
    @discardableResult
    private func runExpectingNoRefetch(
        _ vm: PresentationsViewModel, _ context: NSManagedObjectContext
    ) async -> Bool {
        if vm.cachedAssignmentsGeneration != vm.assignmentsGeneration { await run(vm, context) }
        let generation = vm.assignmentsGeneration
        let fetches = vm.assignmentFetchCount
        await run(vm, context)
        guard vm.assignmentsGeneration == generation else { return false }
        #expect(vm.assignmentFetchCount == fetches, "refetched with no assignment change")
        return true
    }

    private func inboxIDs(_ vm: PresentationsViewModel) -> Set<UUID> {
        Set((vm.readyLessons + vm.blockedLessons).compactMap(\.id))
    }

    /// What the old path (a fresh model, which always refetches) shows.
    private func freshInboxIDs(_ context: NSManagedObjectContext) async -> Set<UUID> {
        let fresh = PresentationsViewModel()
        await run(fresh, context)
        return inboxIDs(fresh)
    }

    private func seedDraft(
        in context: NSManagedObjectContext, lesson: CDLesson, student: CDStudent
    ) -> CDLessonAssignment {
        let assignment = CDLessonAssignment(context: context)
        assignment.lessonID = lesson.id?.uuidString ?? ""
        assignment.studentIDs = [student.id?.uuidString ?? ""]
        return assignment
    }

    @Test("Assignments are refetched only after an assignment changed, and the lists match a fresh load")
    func assignmentRefetchGate() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Golden Beads")
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada")
        let first = seedDraft(in: context, lesson: lesson, student: student)
        #expect(CoreDataTestHelpers.save(context))

        let vm = PresentationsViewModel()
        await run(vm, context)
        #expect(vm.assignmentFetchCount == 1)
        #expect(inboxIDs(vm) == Set([first.id].compactMap { $0 }))

        // A student edit does not count as an assignment change. Checked
        // synchronously: the view context's own notifications are delivered
        // inline, and nothing else can run on the main actor in between.
        let generationBeforeEdit = vm.assignmentsGeneration
        student.lastName = "Byron"
        #expect(CoreDataTestHelpers.save(context))
        context.processPendingChanges()
        #expect(vm.assignmentsGeneration == generationBeforeEdit)
        // ...and re-runs with no assignment change do not read the table.
        await runExpectingNoRefetch(vm, context)
        await runExpectingNoRefetch(vm, context)
        #expect(inboxIDs(vm) == (await freshInboxIDs(context)))

        // An unsaved insert on the view context is an assignment change.
        let generationBeforeInsert = vm.assignmentsGeneration
        let second = seedDraft(in: context, lesson: lesson, student: student)
        context.processPendingChanges()
        #expect(vm.assignmentsGeneration != generationBeforeInsert)
        let fetchesBeforeInsert = vm.assignmentFetchCount
        await run(vm, context)
        #expect(vm.assignmentFetchCount > fetchesBeforeInsert)
        #expect(inboxIDs(vm).contains(try #require(second.id)))
        #expect(inboxIDs(vm) == (await freshInboxIDs(context)))

        // An edit to an existing assignment (scheduling it takes it out of the inbox).
        #expect(CoreDataTestHelpers.save(context))
        first.scheduledFor = Date()
        context.processPendingChanges()
        await run(vm, context)
        #expect(!inboxIDs(vm).contains(try #require(first.id)))
        #expect(inboxIDs(vm) == (await freshInboxIDs(context)))

        // A save on another context reaches the gate asynchronously; poll.
        let background = stack.newBackgroundContext()
        let lessonID = try #require(lesson.id)
        let studentID = try #require(student.id)
        let thirdID: UUID = await background.perform {
            let third = CDLessonAssignment(context: background)
            third.lessonID = lessonID.uuidString
            third.studentIDs = [studentID.uuidString]
            try? background.save()
            return third.id ?? UUID()
        }
        let deadline = Date().addingTimeInterval(10)
        while !inboxIDs(vm).contains(thirdID), Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
            await run(vm, context)
        }
        #expect(inboxIDs(vm).contains(thirdID))
        #expect(inboxIDs(vm) == (await freshInboxIDs(context)))
    }

    @Test("clearCaches forces the next update to refetch")
    func clearCachesRefetches() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        let lesson = CoreDataTestHelpers.seedLesson(in: context)
        let student = CoreDataTestHelpers.seedStudent(in: context)
        _ = seedDraft(in: context, lesson: lesson, student: student)
        #expect(CoreDataTestHelpers.save(context))

        let vm = PresentationsViewModel()
        await run(vm, context)
        let fetches = vm.assignmentFetchCount
        vm.clearCaches()
        await run(vm, context)
        #expect(vm.assignmentFetchCount == fetches + 1)
        #expect(inboxIDs(vm) == (await freshInboxIDs(context)))
    }

    @Test("Only saves of this coordinator's assignments invalidate the cache")
    func saveFilterIsScopedToTheCoordinator() throws {
        let mine = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let other = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let myAssignment = CDLessonAssignment(context: mine)
        let otherAssignment = CDLessonAssignment(context: other)
        let student = CoreDataTestHelpers.seedStudent(in: mine)
        #expect(CoreDataTestHelpers.save(mine))
        #expect(CoreDataTestHelpers.save(other))
        let coordinator: ObjectIdentifier? = ObjectIdentifier(try #require(mine.persistentStoreCoordinator))

        func saved(_ objects: [NSManagedObject]) -> Bool {
            PresentationsViewModel.savedAssignment(
                in: [NSUpdatedObjectsKey: Set(objects)], coordinator: coordinator
            )
        }
        #expect(saved([myAssignment]) == true)
        #expect(saved([otherAssignment]) == false)
        #expect(saved([student]) == false)
        #expect(saved([student, myAssignment]) == true)
        #expect(PresentationsViewModel.savedAssignment(
            in: [NSInvalidatedAllObjectsKey: [NSManagedObjectID]()], coordinator: coordinator
        ) == true)
        // An assignment whose id names no store yet is counted, never dropped.
        let unsaved = CDLessonAssignment(context: mine)
        #expect(saved([unsaved]) == true)
    }

    // MARK: - Attendance

    @Test("One attendance fetch for several days matches one fetch per day")
    func batchedAttendanceMatchesPerDay() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let days = (0..<4).compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        let students = (0..<4).map { _ in UUID() }

        for (dayIndex, day) in days.enumerated() {
            for (studentIndex, student) in students.enumerated() where (dayIndex + studentIndex) % 3 != 0 {
                let record = CoreDataTestHelpers.seedAttendance(in: context, studentID: student, date: day)
                record.status = (dayIndex + studentIndex).isMultiple(of: 2) ? .absent : .present
            }
        }
        // A CloudKit duplicate for one child-day, resolved by the shared winner rule.
        let duplicate = CoreDataTestHelpers.seedAttendance(in: context, studentID: students[1], date: days[0])
        duplicate.status = .absent
        #expect(CoreDataTestHelpers.save(context))

        // Each day asks about a different set of children, as the grouped
        // presentations do.
        let asked: [Date: [UUID]] = [
            days[0]: students,
            days[1]: [students[0], students[2]],
            days[2]: [students[3]],
            days[3]: []
        ]
        let batched = context.attendanceStatuses(forStudentsByDay: asked)
        for (day, ids) in asked {
            let single = context.attendanceStatuses(for: ids, on: day)
            #expect((batched[day.normalizedDay()] ?? [:]) == single, "day \(day) differs")
        }
    }

    // MARK: - Suggested Next count

    @Test("The Suggested Next pill count equals the ranked list's length")
    func suggestedCountMatchesRanking() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let vm = PresentationsViewModel()
        for size in [0, 1, 3, 5, 6, 12] {
            let candidates = (0..<size).map { _ in CDLessonAssignment(context: context) }
            let slices = ReadyToPresentSlices(
                ready: candidates, blocked: [], overdue: [], recentlyMissed: [], followUpCount: 0
            )
            let ranked = vm.rankedSuggestions(among: candidates, allLessonAssignments: candidates)
            #expect(slices.count(.suggestedNext) == ranked.count, "size \(size)")
        }
    }

    // MARK: - Week strip grouping

    @Test("Grouping by day once matches each column filtering the whole table")
    func weekStripGroupingMatchesPerColumnFilter() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let calendar = AppCalendar.shared
        let today = calendar.startOfDay(for: Date())
        let days = (0..<5).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
        let base = Date(timeIntervalSince1970: 1_800_000_000)

        var all: [CDLessonAssignment] = []
        for index in 0..<40 {
            let assignment = CDLessonAssignment(context: context)
            let day = calendar.date(byAdding: .day, value: index % 7 - 1, to: today) ?? today
            // Several legacy midnight rows per day (ties broken by createdAt), some timed.
            let offset = index.isMultiple(of: 3) ? 0 : Double(index * 600)
            assignment.scheduledFor = index % 9 == 4 ? nil : day.addingTimeInterval(offset)
            assignment.createdAt = base.addingTimeInterval(Double((index * 37) % 40))
            if index % 5 == 0 { assignment.stateRaw = LessonAssignmentState.presented.rawValue }
            all.append(assignment)
        }

        let grouped = WeekPlanSection.scheduledByDay(all, days: days, calendar: calendar)
        for day in days {
            let old = all.filter { la in
                guard let scheduled = la.scheduledFor, !la.isGiven else { return false }
                return calendar.isDate(scheduled, inSameDayAs: day)
            }
            .sorted(by: LessonAssignmentOrdering.isOrderedBefore)
            let new = grouped[calendar.startOfDay(for: day)] ?? []
            #expect(new.map(\.objectID) == old.map(\.objectID))
        }
    }
}
