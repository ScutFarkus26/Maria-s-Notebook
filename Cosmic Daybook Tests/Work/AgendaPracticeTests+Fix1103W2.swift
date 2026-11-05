import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The agenda, practice and Quick New Work bugs of the 2026-11-03 hunt
/// (#38, #41, #43, #44, #47 and Work's smaller items). #42, #46 and the
/// practice sheet's wording fixed screens round-two Simplify retired with
/// practice sessions, so their tests went with them.
@MainActor
struct Fix1103W2AgendaPractice {
    let context: NSManagedObjectContext
    let lesson: CDLesson
    let maya: CDStudent
    /// A test student the default setting hides.
    let danny: CDStudent

    var lessonID: UUID { lesson.id ?? UUID() }
    var mayaID: UUID { maya.id ?? UUID() }
    var dannyID: UUID { danny.id ?? UUID() }

    /// The setting as shipped: test students hidden.
    static let hidingTestStudents = TestStudentVisibility.Value(show: false, namesRaw: "Danny De Berry")

    init() throws {
        context = try CoreDataTestHelpers.makeContext()
        lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Stamp Game", area: "Math", sequence: "Decimal")
        maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stone")
        danny = CoreDataTestHelpers.seedStudent(in: context, firstName: "Danny", lastName: "De Berry")
        #expect(CoreDataTestHelpers.save(context))
    }

    func work(for studentID: UUID, kind: WorkKind? = .practiceLesson) -> CDWorkModel {
        let work = CoreDataTestHelpers.seedWorkModel(
            in: context, title: "Stamp Game", studentID: studentID, lessonID: lessonID
        )
        work.id = UUID()
        work.kind = kind
        work.status = .active
        work.createdAt = Date()
        return work
    }

    // MARK: - #38 Hidden test students

    @Test("The practice sheets' roster leaves out hidden test students (#38)")
    func practiceRosterHidesTestStudents() {
        let roster = WorkSheetRoster.students(enrolled: [maya, danny], testStudents: Self.hidingTestStudents)
        #expect(roster.map(\.id) == [maya.id])
    }

    @Test("Work History leaves out a hidden test student's rows (#38)")
    func worksLogHidesTestStudentRows() {
        let hers = work(for: mayaID)
        let his = work(for: dannyID)
        #expect(WorksLogRows.isShown(hers, hiddenStudentIDs: [dannyID]))
        #expect(!WorksLogRows.isShown(his, hiddenStudentIDs: [dannyID]))
    }

    // MARK: - #41 Pre-filled children not on the roster

    @Test("A sheet opened with a hidden or departed child drops her (#41)")
    func prefilledHiddenChildrenDropped() {
        let left = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Ivy", lastName: "Hart", enrollmentStatus: .withdrawn
        )
        let leftID = left.id ?? UUID()
        let roster = WorkSheetRoster.students(enrolled: [maya, danny], testStudents: Self.hidingTestStudents)
        let kept = WorkSheetRoster.keptPrefill([mayaID, dannyID, leftID], roster: roster)
        #expect(kept == [mayaID])
    }

    // MARK: - #43 Untagged practice work

    @Test("Record Practice counts untagged open work as practice (#43)")
    func recordPracticeIncludesUntaggedWork() {
        let untagged = work(for: mayaID, kind: nil)
        let followUp = work(for: dannyID, kind: .followUpAssignment)
        let found = RecordPracticeSheet.openPracticeWork(in: [untagged, followUp], lessonID: lessonID)
        #expect(found.map(\.id) == [untagged.id])
    }

    // MARK: - #44 The printed sheet's Age groups

    @Test("The printed sheet sorts and groups by the grid's age, under the grid's headings (#44)")
    func printedSheetGroupsByGridAge() {
        func item(_ name: String, schoolDaysQuiet: Int, made: Int) -> WorkPrintSheet.Item {
            WorkPrintSheet.Item(
                id: UUID(), lessonTitle: "Stamp Game", studentName: name, statusLabel: "Working",
                ageDays: schoolDaysQuiet, createdDaysAgo: made, dueAt: nil, needsAttention: false
            )
        }
        // Old work touched yesterday, and new work nobody has looked at.
        let old = item("Maya S", schoolDaysQuiet: 1, made: 20)
        let new = item("Eli P", schoolDaysQuiet: 5, made: 2)

        let grouped = WorkPrintSheet.group([new, old], by: .age)

        #expect(grouped.sorted.map(\.studentName) == ["Maya S", "Eli P"])
        #expect(grouped.groupOrder == ["15–30 days", "1–3 days"])
    }

    // MARK: - #47 Load more

    @Test("Load More names the page it will load (#47)")
    func loadMoreNamesItsPage() {
        #expect(LoadMoreButton.title(remaining: 80, pageSize: 50) == "Load 50 more")
        #expect(LoadMoreButton.title(remaining: 12, pageSize: 50) == "Load 12 more")
    }

    // MARK: - Smaller: sample-work numbering

    @Test("Deleting a sample work or a sample step closes the gap in the numbering")
    func sampleWorkDeleteRenumbers() {
        let service = SampleWorkService(context: context)
        let first = service.createSampleWork(for: lesson, title: "Addition")
        let second = service.createSampleWork(for: lesson, title: "Subtraction")
        let third = service.createSampleWork(for: lesson, title: "Multiplication")
        let stepA = service.createStep(for: first, title: "Lay out")
        let stepB = service.createStep(for: first, title: "Exchange")
        let stepC = service.createStep(for: first, title: "Read")
        #expect(CoreDataTestHelpers.save(context))

        service.delete(second)
        service.deleteStep(stepB)

        #expect(lesson.orderedSampleWorks.map(\.title) == ["Addition", "Multiplication"])
        #expect(first.orderIndex == 0)
        #expect(third.orderIndex == 1)
        #expect(first.orderedSteps.map(\.title) == ["Lay out", "Read"])
        #expect(stepA.orderIndex == 0)
        #expect(stepC.orderIndex == 1)
    }

    // MARK: - Smaller: id normalization

    @Test("Quick New Work links to a presentation that names her in lower case")
    func newWorkLinksLowercasedPresentation() throws {
        let given = PresentationFactory.makeDraft(lessonID: lessonID, studentIDs: [mayaID], context: context)
        given.studentIDs = [" " + mayaID.uuidString.lowercased()]
        given.markPresented(at: try CoreDataTestHelpers.day("2026-09-14"))
        #expect(CoreDataTestHelpers.save(context))

        let made = try WorkRepository(context: context).createWork(
            studentID: mayaID, lessonID: lessonID, kind: .practiceLesson, saveImmediately: false
        )
        #expect(made.presentationID == given.id?.uuidString)
    }

    @Test("Next Presentation finds a scheduled presentation that names her in lower case")
    func nextPresentationFindsLowercasedID() throws {
        let hers = work(for: mayaID)
        let planned = PresentationFactory.makeDraft(lessonID: lessonID, studentIDs: [mayaID], context: context)
        planned.studentIDs = [mayaID.uuidString.lowercased()]
        planned.schedule(for: try CoreDataTestHelpers.day("2026-11-10"))
        #expect(CoreDataTestHelpers.save(context))

        let status = WorkPresentationStatusService.findNextPresentationStatus(for: hers, context: context)
        guard case .scheduled = status else {
            Issue.record("Expected the scheduled presentation, got \(status.displayText)")
            return
        }
    }
}
