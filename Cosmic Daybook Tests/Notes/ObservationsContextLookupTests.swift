import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

/// Pins that the Observations loader's batched lesson/topic lookup labels every
/// note exactly as the per-note `lesson` / `communityTopic` accessors did.
@MainActor
struct ObservationsContextLookupTests {

    // The label as `ObservationsView.contextText(for:)` built it before 2026-09-22.
    // swiftlint:disable:next cyclomatic_complexity
    private func legacyContextText(for note: CDNote) -> String? {
        if let lesson = note.lesson { return "Lesson: \(lesson.name)" }
        if let work = note.work { return "Work: \(work.title)" }
        if note.lessonAssignment != nil { return "Presentation" }
        if note.attendanceRecordID != nil { return "Attendance" }
        if note.workCheckIn != nil { return "Check-In" }
        if note.workCompletionRecord != nil { return "Completion" }
        if note.studentMeeting != nil { return "Meeting" }
        if note.projectSession != nil { return "Session" }
        if let communityTopic = note.communityTopic { return "Topic: \(communityTopic.title)" }
        if note.reminder != nil { return "Reminder" }
        if note.schoolDayOverride != nil { return "Override" }
        return nil
    }

    @Test func loaderLabelsMatchPerNoteAccessors() throws {
        let context = try CoreDataTestHelpers.makeSplitStoreContext()
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Golden Beads")
        let topic = CDCommunityTopicEntity(context: context)
        topic.title = "Snack table"
        let work = CoreDataTestHelpers.seedWorkModel(in: context, title: "Bead frame")
        let assignment = CDLessonAssignment(context: context)

        var notes: [CDNote] = []
        func note(_ body: String, _ configure: (CDNote) -> Void) {
            let n = CoreDataTestHelpers.seedNote(in: context, body: body)
            configure(n)
            notes.append(n)
        }
        note("lesson") { $0.lessonID = lesson.id?.uuidString }
        note("lesson and work") { $0.lessonID = lesson.id?.uuidString; $0.work = work }
        note("missing lesson falls through to work") { $0.lessonID = UUID().uuidString; $0.work = work }
        note("garbage lesson id") { $0.lessonID = "not-a-uuid" }
        note("work") { $0.work = work }
        note("presentation") { $0.lessonAssignment = assignment }
        note("attendance") { $0.attendanceRecordID = UUID().uuidString }
        note("topic") { $0.communityTopicID = topic.id?.uuidString }
        note("missing topic") { $0.communityTopicID = UUID().uuidString }
        note("plain") { _ in }
        try context.save()

        let items = ObservationsDataLoader.loadAllNotes(context: context)
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.contextText) })
        #expect(items.count == notes.count)
        for n in notes {
            let id = try #require(n.id)
            #expect(byID[id] == .some(legacyContextText(for: n)), "\(n.body)")
        }
        #expect(byID[try #require(notes[0].id)] == .some("Lesson: Golden Beads"))
        #expect(byID[try #require(notes[7].id)] == .some("Topic: Snack table"))
    }
}
