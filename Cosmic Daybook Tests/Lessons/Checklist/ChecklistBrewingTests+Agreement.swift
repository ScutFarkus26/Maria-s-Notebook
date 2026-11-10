import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Cases 7 and 8 of the Brewing mark's suite: the grid and Lessons & Work's Inbox say
/// the same thing over a varied store, and the grid's row-at-a-time update gives what a
/// full build gives.
extension ChecklistBrewingTests {

    // MARK: - 7: The Grid and the Inbox Agree

    @Test("7: the cells the grid marks brewing are exactly the children on the Inbox's Brewing lessons",
          arguments: [UInt64(7), 42, 1110])
    func gridAgreesWithTheInbox(seed: UInt64) async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        var store = VariedStore(context: context, seed: seed)
        try store.seed()

        let inbox = await Room.inbox(context)
        let grids = try ["Math", "Language"].map { try Room.grid(area: $0, context: context) }
        let roster = Set(try #require(grids.first).rosterStudents.compactMap(\.id))
        #expect(roster.count == 9)

        // What the Inbox says: every shown child on a lesson under Brewing, and who holds it.
        var expected: [Cell: Set<UUID>] = [:]
        for lesson in inbox.blockedLessons {
            let lessonID = try #require(UUID(uuidString: lesson.lessonID))
            for studentID in lesson.resolvedStudentIDs where roster.contains(studentID) {
                expected[Cell(studentID: studentID, lessonID: lessonID)] = inbox.blockingStudentIDs(of: lesson)
            }
        }

        // What the grid says.
        var marked: [Cell: Set<UUID>] = [:]
        for grid in grids {
            for (studentID, row) in grid.matrixStates {
                for (lessonID, state) in row where state.isBrewing {
                    marked[Cell(studentID: studentID, lessonID: lessonID)] = Set(state.brewingHeldBy)
                }
            }
        }

        #expect(marked == expected)
        // The seed really did put lessons under both tabs.
        #expect(!inbox.blockedLessons.isEmpty)
        #expect(!inbox.readyLessons.isEmpty)
        #expect(!marked.isEmpty)
    }

    // MARK: - 8: Incremental Rows

    @Test("8: rebuilding the rows after the lesson before is presented and confirmed matches a full build")
    func rebuildRowsMatchesFullBuild() throws {
        let room = try Room.make()
        room.plan([room.avital, room.dalia])
        try room.context.save()
        let students = [room.avital, room.dalia, room.maya]
        let avitalID = try #require(room.avital.id)
        let plannedID = try #require(room.planned.id)
        let beforeID = try #require(room.before.id)
        func fullBuild() -> ClassGridEngine.Matrix {
            ClassGridEngine.buildMatrix(students: students, lessons: room.lessons, context: room.context)
        }
        var matrix = fullBuild()
        #expect(matrix[avitalID]?[plannedID]?.isBrewing == true)

        // One of the two is given the lesson before: still brewing, now held by the other.
        try room.give([room.avital], confirming: [room.avital])
        try room.context.save()
        ClassGridEngine.rebuildRows(
            in: &matrix, touching: [beforeID], students: students, lessons: room.lessons, context: room.context
        )
        #expect(matrix == fullBuild())
        #expect(matrix[avitalID]?[plannedID]?.brewingHeldBy == [try #require(room.dalia.id)])

        // Then the other: the row is plain Planned.
        try room.give([room.dalia], confirming: [room.dalia])
        try room.context.save()
        ClassGridEngine.rebuildRows(
            in: &matrix, touching: [beforeID], students: students, lessons: room.lessons, context: room.context
        )
        #expect(matrix == fullBuild())
        #expect(matrix[avitalID]?[plannedID]?.isBrewing == false)
        #expect(matrix[avitalID]?[plannedID]?.displayStatus == .planned)
    }
}

/// A varied store over two areas, the same every run for a seed: givings with and
/// without confirmations and asked-for practice, open and closed work on them, mastery
/// marks, rule overrides, a withdrawn child, and for each lesson at most one plan
/// (dated, or undated and sometimes unlocked). One plan per lesson keeps "her plan" one
/// row, so the grid and the Inbox can be compared cell for cell.
@MainActor
private struct VariedStore {
    let context: NSManagedObjectContext
    private var state: UInt64
    private var students: [CDStudent] = []

    init(context: NSManagedObjectContext, seed: UInt64) {
        self.context = context
        state = seed
    }

    /// A small deterministic generator.
    private mutating func next(_ bound: Int) -> Int {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Int((state >> 33) % UInt64(bound))
    }

    private mutating func someStudents(oneIn bound: Int) -> [CDStudent] {
        var chosen: [CDStudent] = []
        for student in students where next(bound) == 0 { chosen.append(student) }
        return chosen
    }

    mutating func seed() throws {
        students = (0..<9).map { index in
            CoreDataTestHelpers.seedStudent(in: context, firstName: "S\(index)", lastName: "L\(index)")
        }
        students.append(CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Gone", lastName: "Away", enrollmentStatus: .withdrawn
        ))
        for (area, sequence, count) in [("Math", "Decimal", 5), ("Math", "Fractions", 4), ("Language", "Grammar", 4)] {
            for order in 0..<count {
                let lesson = CoreDataTestHelpers.seedLesson(
                    in: context, name: "\(sequence) \(order)", area: area, sequence: sequence
                )
                lesson.orderInSequence = Int64(order)
                if next(5) == 0 { lesson.practiceOverride = .no }
                if next(6) == 0 { lesson.confirmationOverride = .no }
                for _ in 0..<next(3) { try seedGiving(of: lesson) }
                seedMasteryMarks(on: lesson)
                seedPlan(of: lesson)
            }
        }
        try context.save()
    }

    /// A given presentation: some confirmed, some with work that follows it.
    private mutating func seedGiving(of lesson: CDLesson) throws {
        let members = someStudents(oneIn: 2)
        guard !members.isEmpty else { return }
        let given = PresentationFactory.makeDraft(lesson: lesson, students: members, context: context)
        given.needsPractice = next(3) == 0
        given.markPresented(
            at: Date(timeIntervalSince1970: 1_790_000_000 + Double(next(1_000_000))), snapshotLesson: false
        )
        for member in members where next(3) != 0 {
            given.confirmStudent(try #require(member.id))
        }
        for member in members where next(4) == 0 {
            let work = CoreDataTestHelpers.seedWorkModel(
                in: context, studentID: try #require(member.id), lessonID: try #require(lesson.id)
            )
            work.presentationID = given.id?.uuidString
            work.status = next(2) == 0 ? .active : .done
        }
    }

    private mutating func seedMasteryMarks(on lesson: CDLesson) {
        for student in someStudents(oneIn: 8) {
            let mark = CDLessonPresentation(context: context)
            mark.studentID = student.cloudKitKey
            mark.lessonID = lesson.id?.uuidString ?? ""
            mark.state = .proficient
            mark.masteredAt = Date(timeIntervalSince1970: 1_790_000_000)
        }
    }

    /// No plan, a dated one, or an Inbox one (now and then unlocked by the guide).
    private mutating func seedPlan(of lesson: CDLesson) {
        let kind = next(4)
        let members = someStudents(oneIn: 3)
        guard kind != 0, !members.isEmpty else { return }
        let plan = PresentationFactory.makeDraft(lesson: lesson, students: members, context: context)
        if kind == 1 {
            plan.schedule(onDay: Date(timeIntervalSince1970: 1_800_000_000))
        } else if next(6) == 0 {
            plan.manuallyUnblocked = true
        }
    }
}
