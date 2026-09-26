import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Since 2026-09-26 the whole-record index reads dictionary rows of the
/// columns it folds when the context holds no unsaved record edit, instead of
/// every presentation, assignment and year-plan entry as a managed object.
/// These pin that the two reads build the same index, rows that are easy to
/// fold wrong included, on the in-memory and the SQLite store; that a pending
/// edit still takes the object read; and that the column read, and so Today's
/// ready queue and the two MCP sweeps, register no record row in the context.
@Suite("Presentation Record Index row path")
@MainActor
struct PresentationRecordIndexRowPathTests {
    private typealias Index = PresentationRecordIndex
    private typealias Fixture = RecordIndexRowPathFixture

    enum Store {
        case inMemory, sqlite
    }

    private func makeContext(_ store: Store) throws -> (context: NSManagedObjectContext, owner: AnyObject?) {
        switch store {
        case .inMemory:
            let stack = try CoreDataTestHelpers.makeInMemoryStack()
            return (stack.viewContext, stack)
        case .sqlite:
            return (try CoreDataTestHelpers.makeSplitStoreContext(), nil)
        }
    }

    // MARK: - Comparing

    /// Every question the index answers, put to both, over every pair asked.
    private func expectSameAnswers(
        _ columns: Index, _ objects: Index, students: [String], lessons: [String]
    ) {
        #expect(columns.givenByLesson == objects.givenByLesson)
        #expect(columns.givenByStudent == objects.givenByStudent)
        #expect(columns.openPlanByLesson == objects.openPlanByLesson)
        #expect(columns.latestPresentedAssignmentByLesson == objects.latestPresentedAssignmentByLesson)
        for lesson in lessons {
            #expect(columns.givenStudents(lesson: lesson) == objects.givenStudents(lesson: lesson))
            #expect(columns.masteredStudents(lesson: lesson) == objects.masteredStudents(lesson: lesson))
            #expect(columns.confirmedStudents(lesson: lesson) == objects.confirmedStudents(lesson: lesson))
            for student in students {
                let given = columns.given(student: student, lesson: lesson)
                #expect(given == objects.given(student: student, lesson: lesson))
                let planned = columns.hasOpenPlan(student: student, lesson: lesson)
                #expect(planned == objects.hasOpenPlan(student: student, lesson: lesson))
                let standing = columns.standing(student: student, lesson: lesson)
                #expect(standing == objects.standing(student: student, lesson: lesson))
            }
        }
    }

    private func recordRows(registeredIn context: NSManagedObjectContext) -> Int {
        context.registeredObjects.count(where: { object in
            object is CDLessonPresentation || object is CDLessonAssignment || object is CDYearPlanEntry
        })
    }

    // MARK: - Equivalence

    @Test(
        "The column read returns the object read's rows, in order, and builds the same index",
        arguments: [Store.inMemory, .sqlite]
    )
    func columnReadMatchesObjectRead(store: Store) throws {
        let (context, owner) = try makeContext(store)
        defer { withExtendedLifetime(owner) {} }
        let record = try Fixture.seedOddRecord(in: context)

        let objectRows = Index.readObjects(lessonIDs: nil, in: context)
        let columnRows = try #require(Index.readColumns(in: context))
        #expect(columnRows == objectRows)
        #expect(columnRows.presentations.count == 11)
        #expect(columnRows.assignments.count == 16)
        #expect(columnRows.planEntries.count == 7)

        let scopes: [Set<String>?] = [nil, Set(record.students), [record.ada, record.cy, record.eve], [], ["nobody"]]
        for students in scopes {
            expectSameAnswers(
                Index(rows: columnRows, students: students),
                Index(rows: objectRows, students: students),
                students: record.askedStudents, lessons: record.askedLessons
            )
        }

        // The public initializer takes the column read here and agrees too.
        #expect(Index.readPath(lessonIDs: nil, in: context) == .columns)
        expectSameAnswers(
            Index(in: context), Index(rows: objectRows, students: nil),
            students: record.askedStudents, lessons: record.askedLessons
        )

        // On SQLite both reads spanned the private and the shared store.
        if store == .sqlite {
            let shared = context.safeFetch(CDFetchRequest(CDLessonPresentation.self)).filter {
                $0.objectID.persistentStore?.configurationName == CoreDataStack.sharedConfiguration
            }
            #expect(shared.count == 3)
        }
    }

    @Test("The odd rows fold the way the record reads them")
    func oddRowsFoldAsTheRecordReads() throws {
        let context = try CoreDataTestHelpers.makeSplitStoreContext()
        let record = try Fixture.seedOddRecord(in: context)
        let index = Index(in: context)

        let adaFirst = try #require(index.given(student: record.ada, lesson: record.first))
        #expect(adaFirst.days == [record.march11, record.march12])
        #expect(adaFirst.confirmed && !adaFirst.mastered)
        #expect(index.given(student: record.ada, lesson: record.second) == Index.Given(mastered: true))
        #expect(index.given(student: record.ben, lesson: record.second)?.mastered == true)
        #expect(index.given(student: record.ben, lesson: record.third)?.mastered == false)
        #expect(index.given(student: record.cy, lesson: record.first)?.days == [record.march11, record.april2])
        #expect(index.given(student: record.dee, lesson: record.third) == Index.Given())
        #expect(index.given(student: record.eve, lesson: record.third)?.confirmed == false)
        #expect(index.given(student: "", lesson: record.fourth) != nil)
        #expect(index.given(student: record.dee, lesson: "") != nil)
        #expect(index.openPlanByLesson[record.fourth] == [record.ada, record.eve, record.ben])
        #expect(index.openPlanByLesson[record.third] == [record.ben, record.ada])
        #expect(index.openPlanByLesson[record.first] == [record.dee])
        #expect(index.openPlanByLesson[record.second] == [record.eve, record.ben])
        #expect(index.latestPresentedAssignmentByLesson[record.second]?[record.cy] != nil)
        #expect(index.latestPresentedAssignmentByLesson[record.third]?[record.dee] != nil)
        #expect(index.given(student: record.ada, lesson: record.fourth) != nil)
        let roster = Index(students: Set(record.students), in: context)
        #expect(roster.given(student: "outsider", lesson: record.fourth) == nil)
    }

    // MARK: - The Gate

    @Test(
        "An unsaved record edit takes the object read, which sees it; an edit elsewhere does not",
        arguments: [Store.inMemory, .sqlite]
    )
    func pendingRecordEditsTakeTheObjectRead(store: Store) throws {
        let (context, owner) = try makeContext(store)
        defer { withExtendedLifetime(owner) {} }
        let record = try Fixture.seedOddRecord(in: context)
        #expect(Index.readPath(lessonIDs: nil, in: context) == .columns)
        #expect(Index.readPath(lessonIDs: [record.first], in: context) == .objects)

        // An unsaved draft: only the object read can see it.
        let draft = CDLessonAssignment(context: context)
        draft.lessonID = record.first
        draft.studentIDs = ["fay"]
        #expect(Index.readPath(lessonIDs: nil, in: context) == .objects)
        #expect(Index(in: context).hasOpenPlan(student: "fay", lesson: record.first))
        let storeOnly = Index(rows: try #require(Index.readColumns(in: context)), students: nil)
        #expect(!storeOnly.hasOpenPlan(student: "fay", lesson: record.first))
        context.rollback()
        #expect(Index.readPath(lessonIDs: nil, in: context) == .columns)

        // An unsaved mastery mark on a saved row.
        let rows = context.safeFetch(CDFetchRequest(CDLessonPresentation.self))
        let bensThird = try #require(rows.first { $0.studentID == record.ben && $0.lessonID == record.third })
        bensThird.masteredAt = record.april2
        #expect(Index.readPath(lessonIDs: nil, in: context) == .objects)
        #expect(Index(in: context).given(student: record.ben, lesson: record.third)?.mastered == true)
        context.rollback()

        // An unsaved delete of Dee's only plan for the first lesson.
        let entries = context.safeFetch(CDFetchRequest(CDYearPlanEntry.self))
        for entry in entries where entry.studentID == record.dee { context.delete(entry) }
        #expect(Index.readPath(lessonIDs: nil, in: context) == .objects)
        #expect(!Index(in: context).hasOpenPlan(student: record.dee, lesson: record.first))
        context.rollback()
        #expect(Index(in: context).hasOpenPlan(student: record.dee, lesson: record.first))

        // An unsaved edit to another entity leaves the column read in place.
        CoreDataTestHelpers.seedNote(in: context, body: "Unrelated")
        #expect(Index.readPath(lessonIDs: nil, in: context) == .columns)
        expectSameAnswers(
            Index(in: context), Index(rows: Index.readObjects(lessonIDs: nil, in: context), students: nil),
            students: record.askedStudents, lessons: record.askedLessons
        )
        context.rollback()

        // A child context reads through its parent, whose unsaved edits a
        // dictionary fetch would not see.
        let child = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        child.parent = context
        #expect(Index.readPath(lessonIDs: nil, in: child) == .objects)
    }

    // MARK: - What a Build Registers

    @Test(
        "At April's size the column read registers nothing; the object read registers every row",
        arguments: [Store.inMemory, .sqlite]
    )
    func columnReadRegistersNothing(store: Store) throws {
        let (context, owner) = try makeContext(store)
        defer { withExtendedLifetime(owner) {} }
        let scale = try Fixture.seedAprilScale(in: context)
        context.reset()
        // Keep whatever a read registers until it is counted; the view context
        // otherwise lets unreferenced objects go when the pool drains. (The
        // policy can only change while nothing is registered, so it stays.)
        context.retainsRegisteredObjects = true
        #expect(context.registeredObjects.isEmpty)

        #expect(Index.readPath(lessonIDs: nil, in: context) == .columns)
        let fromColumns = Index(students: Set(scale.students), in: context)
        #expect(context.registeredObjects.isEmpty)

        let objectRows = Index.readObjects(lessonIDs: nil, in: context)
        let fromObjects = Index(rows: objectRows, students: Set(scale.students))
        #expect(context.registeredObjects.count == 1_782 + 481 + 300)
        #expect(!fromColumns.givenByLesson.isEmpty)
        expectSameAnswers(fromColumns, fromObjects, students: scale.students, lessons: scale.lessons)
    }

    @Test("Today's ready queue and the MCP sweeps read the record without registering a row of it")
    func sweepsRegisterNoRecordRows() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        try Fixture.seedReadyClassroom(in: context)
        context.reset()
        context.retainsRegisteredObjects = true

        let queue = TodayViewModel.buildReadyForNext(lessons: nil, in: context)
        #expect(queue.map(\.basis) == [.confirmed])
        #expect(recordRows(registeredIn: context) == 0)

        let tools = MCPNotebookTools.makeTools(context: { context })
        let ready = try await #require(tools.first { $0.name == "students_ready" }).handler([:])
        #expect(ready.contains("Avital Beyderman:"))
        #expect(!ready.contains("Noa Cohen:"))
        let candidates = try await #require(tools.first { $0.name == "mastery_candidates" }).handler([:])
        #expect(candidates.contains("Avital Beyderman"))
        #expect(recordRows(registeredIn: context) == 0)
    }
}
