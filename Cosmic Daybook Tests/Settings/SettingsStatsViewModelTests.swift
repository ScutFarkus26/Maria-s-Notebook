import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

/// Pins Notebook at a glance: each record is counted in one section only, and
/// the total is the sum of the sections.
@Suite("Settings notebook stats")
@MainActor
struct SettingsStatsViewModelTests {

    @Test("Every kind of record sits in exactly one section")
    func everyKindHasOneSection() {
        let listed = NotebookRecordSection.allCases.flatMap(\.kinds)
        #expect(listed.count == NotebookRecordKind.allCases.count)
        #expect(Set(listed) == Set(NotebookRecordKind.allCases))
    }

    @Test("Section totals count each record once, and the total is their sum")
    func totalsAddUp() throws {
        let context = try CoreDataTestHelpers.makeContext()

        // Teaching: 2 students, 1 lesson, 3 presentations (2 planned, 1 given), 2 per-child records.
        _ = CDStudent(context: context)
        _ = CDStudent(context: context)
        _ = CDLesson(context: context)
        _ = CDLessonAssignment(context: context)
        _ = CDLessonAssignment(context: context)
        let given = CDLessonAssignment(context: context)
        given.presentedAt = Date()
        _ = CDLessonPresentation(context: context)
        _ = CDLessonPresentation(context: context)

        // Planning: 2 to-dos (1 done), 1 track enrollment, 1 going-out.
        _ = CDTodoItem(context: context)
        let done = CDTodoItem(context: context)
        done.isCompleted = true
        _ = CDStudentTrackEnrollmentEntity(context: context)
        _ = CDGoingOut(context: context)

        // Classroom: 1 order, 2 supply history rows.
        _ = CDOrderItem(context: context)
        _ = CDSupplyTransaction(context: context)
        _ = CDSupplyTransaction(context: context)

        // Library: 1 story, 3 album marks across bookmarks, notes and highlights.
        _ = CDStory(context: context)
        _ = CDAlbumBookmark(context: context)
        _ = CDAlbumPageNote(context: context)
        _ = CDAlbumHighlight(context: context)

        let stats = SettingsStatsViewModel()
        stats.loadCounts(context: context)

        #expect(stats.count(of: .presentationsPlanned) == 2)
        #expect(stats.count(of: .presentationsGiven) == 1)
        #expect(stats.count(of: .childPresentations) == 2)
        #expect(stats.total(of: .teaching) == 2 + 1 + 3 + 2)

        #expect(stats.count(of: .todos) == 2)
        #expect(stats.todoCompletedCount == 1)
        #expect(stats.detail(for: .todos) == "1 done")
        #expect(stats.total(of: .planning) == 2 + 1 + 1)

        #expect(stats.count(of: .orders) == 1)
        #expect(stats.count(of: .supplyHistory) == 2)
        #expect(stats.total(of: .classroom) == 1 + 2)

        #expect(stats.count(of: .albumMarks) == 3)
        #expect(stats.total(of: .library) == 1 + 3)

        let sectionSum = NotebookRecordSection.allCases.reduce(0) { $0 + stats.total(of: $1) }
        #expect(stats.totalRecordsCount == sectionSum)
        #expect(stats.totalRecordsCount == 8 + 4 + 3 + 4)
    }

    @Test("Loading again counts again: there is no cache to go stale")
    func reloadIsFresh() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let stats = SettingsStatsViewModel()
        stats.loadCounts(context: context)
        #expect(stats.count(of: .students) == 0)

        _ = CDStudent(context: context)
        stats.loadCounts(context: context)
        #expect(stats.count(of: .students) == 1)
    }

    @Test("A save reloads the counts on its own")
    func saveReloads() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        let stats = SettingsStatsViewModel(reloadDelay: .milliseconds(20))
        stats.loadCounts(context: context)

        _ = CDOrderItem(context: context)
        #expect(CoreDataTestHelpers.save(context))

        // Generous: in the full parallel suite, heavy synchronous @MainActor tests
        // can hold the main actor (and so the reload) for well over 10 s.
        let deadline = ContinuousClock.now + .seconds(60)
        while stats.count(of: .orders) == 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(stats.count(of: .orders) == 1)
    }

    @Test("The Overview and Templates panes read the template counts")
    func templateCounts() throws {
        let context = try CoreDataTestHelpers.makeContext()
        _ = CDNoteTemplate(context: context)
        _ = CDNoteTemplate(context: context)
        _ = CDMeetingTemplate(context: context)
        _ = CDTodoTemplateEntity(context: context)

        let stats = SettingsStatsViewModel()
        stats.loadCounts(context: context)

        #expect(stats.noteTemplatesCount == 2)
        #expect(stats.meetingTemplatesCount == 1)
        #expect(stats.todoTemplatesCount == 1)
        #expect(stats.total(of: .library) == 4)
    }

    /// A class the model names differently (`@objc(TodoItemEntity)`), or a name
    /// that resolves to nothing, would count 0 without a word.
    @Test("Every counted kind resolves to an entity in the model")
    func everyKindResolves() throws {
        let context = try CoreDataTestHelpers.makeContext()
        for kind in NotebookRecordKind.allCases {
            for entity in kind.entities {
                #expect(
                    BackupFetchHelper.entityName(for: entity, in: context) != nil,
                    "\(kind): \(entity) has no entity in the model"
                )
            }
        }
    }
}
