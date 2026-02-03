#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

@Suite("StudentLessonMergeService Tests", .serialized)
@MainActor
struct StudentLessonMergeServiceTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Lesson.self,
            StudentLesson.self,
            Note.self,
        ])
    }

    @Test("merge moves students, merges fields, and deletes source")
    func mergeMovesStudentsAndDeletesSource() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lessonID = UUID()
        let student1 = UUID()
        let student2 = UUID()

        let target = makeTestStudentLesson(
            lessonID: lessonID,
            studentIDs: [student1],
            notes: "Target notes"
        )
        target.needsPractice = false
        target.needsAnotherPresentation = false
        target.followUpWork = "Target follow-up"

        let source = makeTestStudentLesson(
            lessonID: lessonID,
            studentIDs: [student2],
            notes: "Source notes"
        )
        source.needsPractice = true
        source.needsAnotherPresentation = true
        source.followUpWork = "Source follow-up"

        context.insert(target)
        context.insert(source)
        try context.save()

        let result = StudentLessonMergeService.merge(
            sourceID: source.id,
            targetID: target.id,
            context: context
        )

        #expect(result == true)

        let merged = (try? context.fetch(FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.id == target.id })))?.first
        #expect(merged != nil)
        if let merged {
            let mergedIDs = Set(merged.studentIDs)
            #expect(mergedIDs == Set([student1.uuidString, student2.uuidString]))
            #expect(merged.needsPractice == true)
            #expect(merged.needsAnotherPresentation == true)
            #expect(merged.notes.trimmed() == "Target notes\nSource notes")
            #expect(merged.followUpWork.trimmed() == "Target follow-up\nSource follow-up")
        }

        let deleted = (try? context.fetch(FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.id == source.id })))?.first
        #expect(deleted == nil)
    }

    @Test("merge fails when lessons differ")
    func mergeFailsWhenLessonsDiffer() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let target = makeTestStudentLesson(lessonID: UUID(), studentIDs: [UUID()])
        let source = makeTestStudentLesson(lessonID: UUID(), studentIDs: [UUID()])
        context.insert(target)
        context.insert(source)
        try context.save()

        let result = StudentLessonMergeService.merge(
            sourceID: source.id,
            targetID: target.id,
            context: context
        )

        #expect(result == false)

        let targets = (try? context.fetch(FetchDescriptor<StudentLesson>())) ?? []
        #expect(targets.count == 2)
    }

    @Test("merge fails when source is given")
    func mergeFailsWhenSourceIsGiven() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lessonID = UUID()
        let target = makeTestStudentLesson(lessonID: lessonID, studentIDs: [UUID()])
        let source = makeTestStudentLesson(lessonID: lessonID, studentIDs: [UUID()], isPresented: true)
        context.insert(target)
        context.insert(source)
        try context.save()

        let result = StudentLessonMergeService.merge(
            sourceID: source.id,
            targetID: target.id,
            context: context
        )

        #expect(result == false)

        let fetched = (try? context.fetch(FetchDescriptor<StudentLesson>())) ?? []
        #expect(fetched.count == 2)
    }
}
#endif
