import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The Timeline and the Progress dashboard read a lesson's rung the way the class
/// checklist does (bug hunt 2026-10-10, P2 #34, #35, #37, #68): Mastered only from a
/// mastery mark, closed work without one as Reviewing; Plan Lesson plans the lesson
/// tapped and a draft shows as Planned; work ages count school days and stop at
/// close; a duplicated lesson row doesn't trap the sequence sheet; Insights reads
/// group observations.
@Suite("Progress status fixes 2026-10-10")
@MainActor
struct ProgressStatusFix1010GTests {

    private struct Seeded {
        let stack: CoreDataStack
        let student: CDStudent
        /// Given, marked mastered, practice still open.
        let marked: CDLesson
        /// Given, its work closed as Keep Practicing, no mark.
        let closedUnmarked: CDLesson
        /// Not given or planned yet.
        let next: CDLesson
        let last: CDLesson
        var context: NSManagedObjectContext { stack.viewContext }
    }

    private func seed() throws -> Seeded {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stone")
        let studentID = try #require(student.id)
        let lessons = (0..<4).map { index in
            let lesson = CoreDataTestHelpers.seedLesson(
                in: context, name: "Chain \(index)", area: "Math", sequence: "Chains"
            )
            lesson.orderInSequence = Int64(index)
            return lesson
        }
        for lesson in lessons.prefix(2) {
            let given = CDLessonAssignment(context: context)
            given.lessonID = try #require(lesson.id).uuidString
            given.studentIDs = [studentID.uuidString]
            given.state = .presented
            given.presentedAt = Date()
        }
        let mark = CDLessonPresentation(context: context)
        mark.studentID = studentID.uuidString
        mark.lessonID = try #require(lessons[0].id).uuidString
        mark.state = .proficient
        let markedID = try #require(lessons[0].id)
        let closedID = try #require(lessons[1].id)
        let open: CDWorkModel = CoreDataTestHelpers.seedWorkModel(
            in: context, title: "More chains", studentID: studentID, lessonID: markedID
        )
        open.status = WorkStatus.active
        let closed: CDWorkModel = CoreDataTestHelpers.seedWorkModel(
            in: context, title: "Chain work", studentID: studentID, lessonID: closedID
        )
        closed.status = WorkStatus.keepPracticing
        closed.completedAt = Date()
        #expect(CoreDataTestHelpers.save(context))
        return Seeded(
            stack: stack, student: student,
            marked: lessons[0], closedUnmarked: lessons[1], next: lessons[2], last: lessons[3]
        )
    }

    private func label(_ status: LessonNodeStatus) -> String { status.label }

    @Test("The Timeline reads Mastered from the mark and Reviewing for closed work with none")
    func timelineReadsTheMasteryMark() throws {
        let seeded = try seed()
        let timeline = StudentAreaProgressionViewModel()
        timeline.configure(for: seeded.student, area: "Math", sequence: "Chains", context: seeded.context)

        #expect(timeline.nodes.map { label($0.status) } == ["Mastered", "Reviewing", "Not Started", "Not Started"])
        #expect(timeline.completedCount == 1)
        #expect(timeline.nodes.map(\.isNext) == [false, false, true, false])
    }

    @Test("The Children view's marks agree with the Timeline")
    func dashboardReadsTheMasteryMark() throws {
        let seeded = try seed()
        let dashboard = ClassGridChildrenModel()
        dashboard.loadData(context: seeded.context)

        let card = try #require(dashboard.studentCards.first { $0.id == seeded.student.id })
        let pills = try #require(card.subjects.first?.sequences.first?.pills)
        #expect(pills.map(\.status) == [.mastered, .reviewing, .notReady, .notReady])
    }

    @Test("Plan Lesson plans the lesson tapped, shows it Planned, and works on the last lesson")
    func planLessonPlansTheLessonTapped() throws {
        let seeded = try seed()
        let studentID = try #require(seeded.student.id)
        let timeline = StudentAreaProgressionViewModel()
        timeline.configure(for: seeded.student, area: "Math", sequence: "Chains", context: seeded.context)

        timeline.planLesson(seeded.next, context: seeded.context)
        timeline.configure(for: seeded.student, area: "Math", sequence: "Chains", context: seeded.context)
        #expect(timeline.nodes.map { label($0.status) } == ["Mastered", "Reviewing", "Planned", "Not Started"])
        #expect(timeline.nodes.map(\.isNext) == [false, false, false, true])

        timeline.planLesson(seeded.last, context: seeded.context)
        let drafts = CDFetchRequest(CDLessonAssignment.self)
        drafts.predicate = NSPredicate(format: "stateRaw == %@", LessonAssignmentState.draft.rawValue)
        let planned = try seeded.context.fetch(drafts)
        #expect(Set(planned.map(\.lessonID)) == Set([seeded.next, seeded.last].compactMap { $0.id?.uuidString }))
        #expect(planned.allSatisfy { $0.resolvedStudentIDs == [studentID] })
    }

    @Test("A work's age counts school days only, and stops when it closed")
    func workAgeCountsSchoolDaysUntilClose() throws {
        let seeded = try seed()
        let context = seeded.context
        let calendar = AppCalendar.shared
        func day(_ dayOfMonth: Int) throws -> Date {
            try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: dayOfMonth, hour: 9)))
        }
        // Assigned Monday Sept 14, closed the next Monday; Wednesday was a day off.
        let work = CoreDataTestHelpers.seedWorkModel(
            in: context, title: "Chain work", studentID: try #require(seeded.student.id),
            lessonID: try #require(seeded.closedUnmarked.id)
        )
        work.assignedAt = try day(14)
        work.status = .mastered
        work.completedAt = try day(21)
        let holiday = CDNonSchoolDay(context: context)
        holiday.date = calendar.startOfDay(for: try day(16))
        #expect(CoreDataTestHelpers.save(context))

        let timeline = StudentAreaProgressionViewModel()
        timeline.configure(for: seeded.student, area: "Math", sequence: "Chains", context: context)
        let node = try #require(timeline.nodes.first { $0.lesson.objectID == seeded.closedUnmarked.objectID })
        let item = try #require(node.activeWork.first { $0.work.objectID == work.objectID })
        // Mon, Tue, Thu, Fri.
        #expect(item.ageSchoolDays == 4)
    }

    @Test("The sequence sheet keeps going when sync left two copies of a lesson")
    func sequenceSheetSurvivesDuplicateLessons() throws {
        let seeded = try seed()
        let context = seeded.context
        let lessonID = try #require(seeded.marked.id)
        let copy = CoreDataTestHelpers.seedLesson(in: context, name: "Chain 0", area: "Math", sequence: "Chains")
        copy.id = lessonID
        #expect(CoreDataTestHelpers.save(context))

        let detail = StudentSequenceDetailLoader.load(
            target: StudentSequenceDetailTarget(
                studentID: try #require(seeded.student.id), studentName: "Maya Stone",
                area: "Math", sequence: "Chains", lessonIDs: [lessonID]
            ),
            context: context
        )
        #expect(detail.work.map(\.title) == ["More chains"])
    }
}

/// Answers every analysis with the same well-formed JSON.
private struct CannedInsightsClient: MCPClientProtocol {
    static let json = """
    {"overallProgress": "Steady", "keyStrengths": ["focus"], "areasForGrowth": ["handwriting"],
     "developmentalMilestones": [], "observedPatterns": [], "behavioralTrends": [],
     "socialEmotionalInsights": [], "recommendedNextLessons": [], "suggestedPracticeFocus": [],
     "interventionSuggestions": []}
    """
    func generateText(prompt: String, temperature: Double) async throws -> String { "" }
    func generateStructuredJSON(prompt: String, temperature: Double) async throws -> String { Self.json }
    func sendConversation(
        messages: [[String: String]], systemMessage: String?, temperature: Double,
        maxTokens: Int, timeout: TimeInterval?
    ) async throws -> String { "" }
}

@Suite("Insights reads group observations 2026-10-10")
@MainActor
struct StudentInsightsGroupNotesFix1010GTests {

    @Test("An observation of a small group counts for each child in it, a class-wide one for none")
    func groupObservationsCount() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stone")
        let ezra = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ezra", lastName: "Bloom")
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Reyes")
        let mayaID = try #require(maya.id), ezraID = try #require(ezra.id), adaID = try #require(ada.id)
        CoreDataTestHelpers.seedNote(in: context, body: "Maya alone").scope = .student(mayaID)
        CoreDataTestHelpers.seedNote(in: context, body: "Maya and Ezra").scope = .students([mayaID, ezraID])
        CoreDataTestHelpers.seedNote(in: context, body: "Ezra and Ada").scope = .students([ezraID, adaID])
        CoreDataTestHelpers.seedNote(in: context, body: "Whole class").scope = .all
        #expect(CoreDataTestHelpers.save(context))

        let service = StudentAnalysisService(modelContext: context, mcpClient: CannedInsightsClient())
        let snapshot = try await service.analyzeStudent(maya, lookbackDays: 30)
        #expect(snapshot.totalNotesAnalyzed == 2)
    }
}
