import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Linked copies must have been made together: the same presentation, or —
/// when neither has one — created within `WorkGrouping.fanOutWindow`. Without
/// that, the same work given to the same children weeks later joined the
/// first assignment's group.
@Suite("Work Grouping: made together")
@MainActor
struct WorkGroupingMadeTogetherTests {

    /// One row per child, each naming every child, the way `assign_work`
    /// makes a group.
    private func seedLinkedCopies(
        in context: NSManagedObjectContext, studentIDs: [UUID], lessonID: UUID, presentationID: UUID? = nil
    ) -> [CDWorkModel] {
        let works = studentIDs.map { studentID -> CDWorkModel in
            let work = CoreDataTestHelpers.seedWorkModel(
                in: context, title: "Commutative law follow-up", studentID: studentID, lessonID: lessonID
            )
            work.id = UUID()
            work.kind = .followUpAssignment
            work.presentationID = presentationID?.uuidString
            return work
        }
        for work in works {
            for other in works {
                let participant = CDWorkParticipantEntity(context: context)
                participant.id = UUID()
                participant.studentID = other.studentID
                participant.work = work
            }
        }
        return works
    }

    /// Moves rows' creation stamps back, the way a group assigned weeks ago
    /// looks next to one assigned today.
    private func backdate(_ works: [CDWorkModel], days: Int) {
        for work in works {
            work.createdAt = AppCalendar.addingDays(-days, to: work.createdAt ?? Date())
        }
    }

    @Test("the same assignment given again weeks later is a separate group")
    func repeatAssignmentWeeksLaterStaysSeparate() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let lessonID = UUID()
        let students = [UUID(), UUID()]
        let first = seedLinkedCopies(in: context, studentIDs: students, lessonID: lessonID)
        backdate(first, days: 21)
        let second = seedLinkedCopies(in: context, studentIDs: students, lessonID: lessonID)
        CoreDataTestHelpers.save(context)

        #expect(!WorkGrouping.areLinkedCopies(first[0], second[1]))
        let firstGroup = WorkGrouping.group(containing: first[0], in: context)
        #expect(Set(firstGroup.members.map(\.objectID)) == Set(first.map(\.objectID)))
        let secondGroup = WorkGrouping.group(containing: second[0], in: context)
        #expect(Set(secondGroup.members.map(\.objectID)) == Set(second.map(\.objectID)))
        #expect(secondGroup.shape == .linkedCopies(total: 2))
    }

    @Test("copies made within the minute still group; more than a minute apart they don't")
    func fanOutWindowIsOneMinute() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let works = seedLinkedCopies(in: context, studentIDs: [UUID(), UUID()], lessonID: UUID())
        let start = Date()
        works[0].createdAt = start
        works[1].createdAt = start.addingTimeInterval(45)
        #expect(WorkGrouping.areLinkedCopies(works[0], works[1]))

        works[1].createdAt = start.addingTimeInterval(61)
        #expect(!WorkGrouping.areLinkedCopies(works[0], works[1]))
    }

    @Test("the same presentation doesn't join assignments made weeks apart")
    func sharedPresentationStillNeedsTheWindow() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let lessonID = UUID()
        let presentationID = UUID()
        let students = [UUID(), UUID()]
        // `createWork` links both assignments to the children's one
        // presentation of the lesson.
        let first = seedLinkedCopies(
            in: context, studentIDs: students, lessonID: lessonID, presentationID: presentationID
        )
        backdate(first, days: 21)
        let second = seedLinkedCopies(
            in: context, studentIDs: students, lessonID: lessonID, presentationID: presentationID
        )
        CoreDataTestHelpers.save(context)

        #expect(WorkGrouping.areLinkedCopies(first[0], first[1]))
        #expect(!WorkGrouping.areLinkedCopies(first[0], second[1]))
        let group = WorkGrouping.group(containing: second[0], in: context)
        #expect(Set(group.members.map(\.objectID)) == Set(second.map(\.objectID)))
    }

    @Test("a row with no creation date keeps the old rule, so older group work still groups")
    func missingCreatedAtKeepsOldRule() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let works = seedLinkedCopies(in: context, studentIDs: [UUID(), UUID()], lessonID: UUID())
        backdate([works[0]], days: 21)
        works[1].createdAt = nil
        CoreDataTestHelpers.save(context)

        #expect(WorkGrouping.areLinkedCopies(works[0], works[1]))
    }

    @Test("a child sees each of two assignments weeks apart once: her own copies")
    func visibleWorkWithRepeatAssignment() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let lessonID = UUID()
        let naomi = UUID()
        let ora = UUID()
        let first = seedLinkedCopies(in: context, studentIDs: [naomi, ora], lessonID: lessonID)
        backdate(first, days: 21)
        let second = seedLinkedCopies(in: context, studentIDs: [naomi, ora], lessonID: lessonID)
        CoreDataTestHelpers.save(context)

        let all = context.safeFetch(CDFetchRequest(CDWorkModel.self))
        let naomiSees = WorkGrouping.visibleWork(for: naomi, among: all, in: context)
        let naomis = (first + second).filter { $0.studentID == naomi.uuidString }
        #expect(Set(naomiSees.map(\.objectID)) == Set(naomis.map(\.objectID)))
        #expect(naomiSees.count == 2)
    }

    // MARK: - The callers

    @Test("a status for everyone reaches only the copies made together")
    func workLogTargetsStayInOneAssignment() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let lessonID = UUID()
        let students = [UUID(), UUID()]
        let first = seedLinkedCopies(in: context, studentIDs: students, lessonID: lessonID)
        backdate(first, days: 21)
        let second = seedLinkedCopies(in: context, studentIDs: students, lessonID: lessonID)
        CoreDataTestHelpers.save(context)

        let rows = try WorkLogTargets.resolve(work: second[0], in: context)
        #expect(Set(rows.map(\.objectID)) == Set(second.map(\.objectID)))
        try WorkLogService.log(rows.map { WorkLogService.Entry(work: $0, status: .mastered) }, context: context)
        #expect(second.filter { $0.isClosed }.count == 2)
        #expect(first.filter { $0.isClosed }.isEmpty)
    }

    @Test("deleting a copy strips its child from her new group only")
    func deletionStaysInOneAssignment() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let lessonID = UUID()
        let naomi = UUID()
        let ora = UUID()
        let first = seedLinkedCopies(in: context, studentIDs: [naomi, ora], lessonID: lessonID)
        backdate(first, days: 21)
        let second = seedLinkedCopies(in: context, studentIDs: [naomi, ora], lessonID: lessonID)
        CoreDataTestHelpers.save(context)
        let service = WorkDeletionService(context: context)

        let plan = try service.removalPlan(for: naomi, from: second[0])
        #expect(Set(plan.steps.map(\.work.objectID)) == Set(second.map(\.objectID)))

        try service.delete([second[0]])
        #expect(!WorkGrouping.involves(naomi, in: second[1]))
        #expect(WorkGrouping.involves(naomi, in: first[1]))
        #expect(WorkGrouping.group(containing: first[0], in: context).shape == .linkedCopies(total: 2))
    }
}
