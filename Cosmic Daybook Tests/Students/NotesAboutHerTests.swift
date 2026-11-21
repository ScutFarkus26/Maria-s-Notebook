// NotesAboutHerTests.swift
// Domain logic review 2026-11-20, R9 and A11: which notes are about a child.
// A one-child lesson note counts in her sequence card; whole-class context
// notes (a community meeting's lines, a calendar day's note) stay off her
// Notes tab; "last observed" is when a note was written, and a note the app
// writes itself isn't an observation.

import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

@Suite("Notes about her (domain logic R9, A11)")
@MainActor
struct NotesAboutHerTests {

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        AppCalendar.shared.date(from: DateComponents(year: year, month: month, day: dayOfMonth, hour: 10)) ?? Date()
    }

    @Test("A one-child lesson note counts in her sequence card")
    func oneChildLessonNote() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Sela")
        let leo = CoreDataTestHelpers.seedStudent(in: context, firstName: "Leo", lastName: "Katz")
        let lesson = CoreDataTestHelpers.seedLesson(in: context)
        let lessonID = try #require(lesson.id).uuidString
        let mayaID = try #require(maya.id)

        let hers = CoreDataTestHelpers.seedNote(in: context, body: "Carried the bead bars with care.")
        hers.scope = .student(mayaID)
        hers.lessonID = lessonID
        let group = CoreDataTestHelpers.seedNote(in: context, body: "Worked the stamp game together.")
        group.scope = .students([mayaID, try #require(leo.id)])
        group.lessonID = lessonID
        group.syncStudentLinks(in: context)
        let leos = CoreDataTestHelpers.seedNote(in: context, body: "Leo alone.")
        leos.scope = .student(try #require(leo.id))
        leos.lessonID = lessonID
        #expect(CoreDataTestHelpers.save(context))

        let found = SequenceActivityFetches.notes(studentID: mayaID.uuidString, lessonIDs: [lessonID], in: context)
        #expect(Set(found.compactMap(\.id)) == Set([hers.id, group.id].compactMap { $0 }))
    }

    @Test("A typo fix doesn't move \"last observed\"")
    func typoFixKeepsLastObserved() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Sela")
        let mayaID = try #require(maya.id)
        let note = CoreDataTestHelpers.seedNote(in: context, body: "Chose the long chain.")
        note.scope = .student(mayaID)
        note.createdAt = day(2026, 9, 3)
        note.updatedAt = Date()  // the typo fixed today
        #expect(CoreDataTestHelpers.save(context))

        #expect(StudentsViewModel.latestObservationDates(for: [mayaID], in: context)[mayaID] == day(2026, 9, 3))
        // The object path, used while the context holds unsaved changes, agrees.
        CoreDataTestHelpers.seedNote(in: context, body: "Unsaved, whole class.")
        #expect(context.hasChanges)
        #expect(StudentsViewModel.latestObservationDates(for: [mayaID], in: context)[mayaID] == day(2026, 9, 3))
    }

    @Test("The rollover's own note isn't an observation")
    func rolloverNoteIsNotObserved() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Sela", level: .lower)
        let mayaID = try #require(maya.id)
        #expect(CoreDataTestHelpers.save(context))

        var plan = RolloverPlan(effectiveDate: day(2026, 6, 10), writeNotes: true)
        plan.outcomes[mayaID] = .promote(to: .upper)
        try RolloverService.apply(plan, students: [maya], incomingYearLabel: "2026–2027", context: context)
        let notes = context.safeFetch(CDFetchRequest(CDNote.self))
        #expect(notes.count == 1, "the rollover wrote its note")

        #expect(StudentsViewModel.latestObservationDates(for: [mayaID], in: context)[mayaID] == nil)
    }

    @Test("A community meeting's line isn't on every child's Notes tab")
    func communityNoteStaysOffNotesTab() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Sela")
        let topic = CDCommunityTopicEntity(context: context)
        topic.id = UUID()
        topic.title = "Snack table"
        let line = CoreDataTestHelpers.seedNote(in: context, body: "We could take turns wiping it.")
        line.scope = .all
        line.communityTopic = topic
        let classNote = CoreDataTestHelpers.seedNote(in: context, body: "The class planted bulbs.")
        classNote.scope = .all
        #expect(CoreDataTestHelpers.save(context))

        let tab = StudentNotesViewModel(student: maya, viewContext: context, saveCoordinator: .preview)
        let ids = Set(tab.items.map(\.id))
        #expect(!ids.contains(try #require(line.id)))
        #expect(ids.contains(try #require(classNote.id)), "a whole-class note still shows")
    }
}
