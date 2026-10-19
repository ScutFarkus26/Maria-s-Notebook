import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The Class Grid's one engine and one status (Simplify the app, Phase 5): the old
/// Three-Year View ladder (not presented, presented, chosen, repeated, mastered) now
/// climbs the Checklist's rungs, by the Checklist's rule, and the Checklist and Three
/// Years read the same rung off the same records.
@Suite("Class Grid engine")
@MainActor
struct ClassGridEngineTests {

    // MARK: - Status mapping (pure)

    private let child = UUID()

    private func lessonRef(order: Int = 0) -> CurriculumLessonRef {
        CurriculumLessonRef(
            id: UUID(), name: "Lesson \(order)", area: "Math", sequence: "Laws", section: "",
            orderInSequence: order, sortIndex: order, greatLessonRaw: nil, isStory: false, isKeyLesson: false
        )
    }

    private func workRef(_ lesson: CurriculumLessonRef, _ status: WorkStatus) -> CurriculumWorkRef {
        CurriculumWorkRef(
            id: UUID(), lessonID: lesson.id, studentIDs: [child], statusRaw: status.rawValue,
            assignedAt: Date(timeIntervalSince1970: 1_780_000_000), completedAt: nil, lastTouchedAt: nil,
            ownerID: child
        )
    }

    private func givenRef(_ lesson: CurriculumLessonRef, confirmed: Bool = false) -> CurriculumPresentationRef {
        CurriculumPresentationRef(
            id: UUID(), lessonID: lesson.id, studentIDs: [child],
            presentedAt: Date(timeIntervalSince1970: 1_779_000_000), confirmedStudentIDs: confirmed ? [child] : []
        )
    }

    private func state(_ input: CurriculumMapInput, _ lesson: CurriculumLessonRef) -> ChecklistDisplayStatus {
        ClassGridEngine.cells(for: child, input: input)[lesson.id]?.state ?? .notReady
    }

    @Test("Nothing recorded is Not yet on Three Years, never Ready")
    func nothingIsNotYet() {
        let lesson = lessonRef()
        let input = CurriculumMapInput(lessons: [lesson])
        #expect(state(input, lesson) == .notReady)
        #expect(ClassGridEngine.ladderRung(
            isMastered: false, workStatuses: [], practiceSessions: 0, isPresented: false
        ) == .notReady)
    }

    @Test("The old map's rungs land on the Checklist's: chosen is Practicing, repeated is Reviewing")
    func oldRungsMapToTheLadder() {
        let lesson = lessonRef()
        var input = CurriculumMapInput(lessons: [lesson])
        input.presentations = [givenRef(lesson)]
        #expect(state(input, lesson) == .presented)

        input.work = [workRef(lesson, .active)]
        #expect(state(input, lesson) == .practicing)

        input.work = [workRef(lesson, .review)]
        #expect(state(input, lesson) == .reviewing)

        input.work = [workRef(lesson, .keepPracticing)]
        #expect(state(input, lesson) == .reviewing)
    }

    @Test("Open work beside closed work is Practicing, as the Checklist reads it")
    func openBesideClosedIsPracticing() {
        let lesson = lessonRef()
        var input = CurriculumMapInput(lessons: [lesson])
        input.presentations = [givenRef(lesson)]
        input.work = [workRef(lesson, .active), workRef(lesson, .done)]
        #expect(state(input, lesson) == .practicing)
    }

    @Test("Practice sessions still count on Three Years: one is Practicing, three are Reviewing")
    func practiceSessionsCount() {
        #expect(ClassGridEngine.ladderRung(
            isMastered: false, workStatuses: [], practiceSessions: 1, isPresented: true
        ) == .practicing)
        #expect(ClassGridEngine.ladderRung(
            isMastered: false, workStatuses: [.active], practiceSessions: 3, isPresented: true
        ) == .reviewing)
        #expect(ChecklistDisplayStatus.resolve(
            isMastered: false, workStatuses: [.active], isPresented: true, isPlanned: false
        ) == .practicing)
    }

    @Test("Only a mastery mark is Mastered; the guide's confirmation is not one")
    func onlyAMarkIsMastered() {
        let lesson = lessonRef()
        var input = CurriculumMapInput(lessons: [lesson])
        input.presentations = [givenRef(lesson, confirmed: true)]
        input.work = [workRef(lesson, .mastered)]
        #expect(state(input, lesson) == .reviewing)

        input.masteries = [CurriculumMasteryRef(
            id: UUID(), studentID: child, lessonID: lesson.id, isMastered: true,
            presentedAt: nil, masteredAt: Date(timeIntervalSince1970: 1_781_000_000), lastObservedAt: nil
        )]
        #expect(state(input, lesson) == .mastered)
    }

    @Test("The ladder's order: a row's furthest mark is the largest")
    func ladderOrder() {
        let order: [ChecklistDisplayStatus] = [
            .notReady, .ready, .planned, .presented, .practicing, .reviewing, .mastered
        ]
        #expect(order == order.sorted())
        #expect(ChecklistDisplayStatus.allCases == order)
        let aggregate = ClassGridEngine.aggregate(
            [CurriculumCell(studentID: child, lessonID: UUID()), {
                var cell = CurriculumCell(studentID: child, lessonID: UUID())
                cell.state = .practicing
                return cell
            }()],
            lessonCount: 2
        )
        #expect(aggregate.state == .practicing)
        #expect(aggregate.presentedCount == 1)
    }

    // MARK: - The Checklist and Three Years agree (store)

    private struct Seeded {
        let context: NSManagedObjectContext
        let lesson: CDLesson
        let students: [String: CDStudent]
    }

    /// One lesson and seven children, each with a different record on it.
    private func seed() throws -> Seeded {
        let context = try CoreDataTestHelpers.makeContext()
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Laws A", area: "Math", sequence: "Laws")
        lesson.orderInSequence = 0
        var students: [String: CDStudent] = [:]
        for name in ["Given", "Working", "Review", "Closed", "Both", "Marked", "Nothing"] {
            students[name] = CoreDataTestHelpers.seedStudent(in: context, firstName: name, lastName: "Test")
        }
        try context.save()
        let lessonID = try #require(lesson.id)

        let given = CDLessonAssignment(context: context)
        given.lessonID = lessonID.uuidString
        given.studentIDs = ["Given", "Working", "Review", "Closed", "Both", "Marked"]
            .compactMap { students[$0]?.cloudKitKey }
        given.markPresented(at: try CoreDataTestHelpers.day("2026-09-08"), snapshotLesson: false)
        given.confirmStudent(try #require(students["Marked"]?.id))

        let repository = WorkRepository(context: context)
        func work(_ name: String, _ status: WorkStatus) throws {
            let row = try repository.createWork(
                studentID: try #require(students[name]?.id), lessonID: lessonID, saveImmediately: false
            )
            row.status = status
            if status.isClosed { row.completedAt = try CoreDataTestHelpers.day("2026-09-20") }
        }
        try work("Working", .active)
        try work("Review", .review)
        try work("Closed", .keepPracticing)
        try work("Both", .active)
        try work("Both", .done)

        let mark = CDLessonPresentation(context: context)
        mark.studentID = try #require(students["Marked"]?.id).uuidString
        mark.lessonID = lessonID.uuidString
        mark.state = .proficient
        try context.save()
        return Seeded(context: context, lesson: lesson, students: students)
    }

    @Test("The Checklist and Three Years read the same rung off the same records")
    func checklistAndThreeYearsAgree() throws {
        let seeded = try seed()
        let lessonID = try #require(seeded.lesson.id)
        let students = Array(seeded.students.values)
        let matrix = ClassGridEngine.buildMatrix(students: students, lessons: [seeded.lesson], context: seeded.context)
        let cells = ClassGridEngine.cells(input: CurriculumMapLoader.snapshot(in: seeded.context))

        func checklist(_ name: String) throws -> ChecklistDisplayStatus {
            let id = try #require(seeded.students[name]?.id)
            return try #require(matrix[id]?[lessonID]).displayStatus
        }
        func threeYears(_ name: String) throws -> ChecklistDisplayStatus {
            let id = try #require(seeded.students[name]?.id)
            return cells[id]?[lessonID]?.state ?? .notReady
        }

        let expected: [(String, ChecklistDisplayStatus)] = [
            ("Given", .presented), ("Working", .practicing), ("Review", .reviewing),
            ("Closed", .reviewing), ("Both", .practicing), ("Marked", .mastered)
        ]
        for (name, status) in expected {
            #expect(try checklist(name) == status, "Checklist, \(name)")
            #expect(try threeYears(name) == status, "Three Years, \(name)")
        }
        // An untouched first lesson: the Checklist can say Ready (it reads readiness);
        // Three Years has none to read and says Not yet.
        #expect(try checklist("Nothing") == .ready)
        #expect(try threeYears("Nothing") == .notReady)
    }
}
