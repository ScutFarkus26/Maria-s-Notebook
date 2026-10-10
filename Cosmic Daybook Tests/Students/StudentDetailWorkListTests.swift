import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The student page's work list (`StudentDetailViewModel.fetchWorkModelsForStudent`):
/// each assignment once, through `WorkGrouping.visibleWork`, even when the
/// same work was given to the same children twice.
@Suite("Student detail work list")
@MainActor
struct StudentDetailWorkListTests {

    /// One fan-out group for `students`, made the way assign_work makes one.
    private func assign(
        _ students: [CDStudent], lessonID: UUID, in context: NSManagedObjectContext
    ) -> [CDWorkModel] {
        let works = students.map { student -> CDWorkModel in
            let work = CoreDataTestHelpers.seedWorkModel(
                in: context, title: "Checkerboard practice", studentID: student.id!, lessonID: lessonID
            )
            work.id = UUID()
            work.kind = .practiceLesson
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

    @Test("the same work given twice, weeks apart, lists her two copies and none of her classmate's")
    func repeatAssignmentListsHerOwnCopiesOnly() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Test")
        let eli = CoreDataTestHelpers.seedStudent(in: context, firstName: "Eli", lastName: "Test")
        let lessonID = UUID()
        let first = assign([maya, eli], lessonID: lessonID, in: context)
        for work in first {
            work.createdAt = AppCalendar.addingDays(-21, to: work.createdAt ?? Date())
        }
        let second = assign([maya, eli], lessonID: lessonID, in: context)
        CoreDataTestHelpers.save(context)

        let model = StudentDetailViewModel(student: maya, dependencies: AppDependencies(coreDataStack: stack))
        let listed = model.fetchWorkModelsForStudent(viewContext: context)
        let mayas = (first + second).filter { $0.studentID == maya.id!.uuidString }
        #expect(Set(listed.map(\.objectID)) == Set(mayas.map(\.objectID)))
        #expect(listed.count == 2)
    }
}
