import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// #59 from the 2026-10-05 data-model hunt: a presentation with no usable
// lesson id answered a new random UUID on every read, so lists that group or
// diff by lesson saw it change identity each time.

@Suite("Resolved lesson id")
@MainActor
struct ResolvedLessonIDTests {

    @Test("A lessonless presentation answers the same lesson id on every read")
    func lessonlessIsStable() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let assignment = CDLessonAssignment(context: context)
        assignment.lessonID = ""

        #expect(assignment.resolvedLessonID == assignment.resolvedLessonID)
    }

    @Test("Two lessonless presentations don't share a lesson id")
    func lessonlessRowsDiffer() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let first = CDLessonAssignment(context: context)
        first.lessonID = "not a uuid"
        let second = CDLessonAssignment(context: context)
        second.lessonID = ""

        #expect(first.resolvedLessonID != second.resolvedLessonID)
    }

    @Test("A stored lesson id is answered whether or not the lesson is on this device")
    func storedIDWithoutLesson() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let lessonID = UUID()
        let assignment = CDLessonAssignment(context: context)
        assignment.lessonID = lessonID.uuidString

        #expect(assignment.resolvedLessonID == lessonID)

        let lesson = CoreDataTestHelpers.seedLesson(in: context)
        assignment.lesson = lesson
        #expect(assignment.resolvedLessonID == lesson.id)
    }
}
