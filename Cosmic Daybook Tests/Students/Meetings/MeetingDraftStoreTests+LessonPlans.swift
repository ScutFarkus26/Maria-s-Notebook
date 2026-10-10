import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// What filing a meeting plans for Re-present and Ready for Next, whether
// Ready for Next is offered, and the receipts in the stored draft (bug hunt
// 2026-10-09, #11–#13). The room and helpers are in +LessonDecisions.
extension MeetingDraftStoreTests {

    // MARK: - What filing plans (#11, #12)

    @Test("Ready for Next doesn't put back On Deck a next lesson she has already had")
    @MainActor
    func readySkipsAGivenNextLesson() throws {
        let room = try makeDecisionRoom()
        defer { MeetingPersistenceService.clearCurrent(studentID: room.child) }
        _ = PresentationFactory.makePresented(lesson: room.second, students: [room.student], context: room.context)
        #expect(CoreDataTestHelpers.save(room.context))
        let draft = MeetingDraftModel(studentID: room.child)
        draft.load(context: room.context)
        draft.readyForNext(room.work, context: room.context)

        #expect(draft.complete(context: room.context, saveCoordinator: .preview) { _ in nil })
        #expect(openPlans(for: room.second, in: room.context).isEmpty)
        #expect(room.given.confirmedStudentIDs == [room.child.uuidString])
    }

    @Test("Ready for Next doesn't put back On Deck a next lesson she has mastered")
    @MainActor
    func readySkipsAMasteredNextLesson() throws {
        let room = try makeDecisionRoom()
        defer { MeetingPersistenceService.clearCurrent(studentID: room.child) }
        let mark = CDLessonPresentation(context: room.context)
        mark.studentID = room.child.uuidString
        mark.lessonID = try #require(room.second.id).uuidString
        mark.state = .proficient
        mark.masteredAt = Date()
        #expect(CoreDataTestHelpers.save(room.context))
        let draft = MeetingDraftModel(studentID: room.child)
        draft.load(context: room.context)
        draft.readyForNext(room.work, context: room.context)

        #expect(draft.complete(context: room.context, saveCoordinator: .preview) { _ in nil })
        #expect(openPlans(for: room.second, in: room.context).isEmpty)
    }

    @Test("Re-present for one child of a group flags her own row, not the whole group's presentation")
    @MainActor
    func representFlagsOnlyHer() throws {
        let room = try makeDecisionRoom()
        defer { MeetingPersistenceService.clearCurrent(studentID: room.child) }
        let ben = CoreDataTestHelpers.seedStudent(in: room.context, firstName: "Ben", lastName: "Adler")
        let benID = try #require(ben.id).uuidString
        let group = PresentationFactory.makePresented(
            lesson: room.first, students: [room.student, ben], context: room.context
        )
        let groupID = try #require(group.id).uuidString
        let rows = try [room.child.uuidString, benID].map { studentID in
            try LifecycleService.upsertLessonPresentation(
                presentationID: groupID, studentID: studentID, lessonID: group.lessonID,
                presentedAt: Date(), context: room.context
            )
        }
        room.work.presentationID = groupID
        #expect(CoreDataTestHelpers.save(room.context))

        let draft = MeetingDraftModel(studentID: room.child)
        draft.load(context: room.context)
        draft.represent(room.work, context: room.context)
        #expect(draft.complete(context: room.context, saveCoordinator: .preview) { _ in nil })

        #expect(!group.needsAnotherPresentation)
        #expect(rows[0].followUpResolution == .supportOrRepresent)
        #expect(rows[1].followUpActionRaw == nil)
        let representations = ChildRepresentations(in: room.context)
        #expect(group.needsAnotherPresentation(for: room.child.uuidString, given: representations))
        #expect(!group.needsAnotherPresentation(for: benID, given: representations))
        #expect(openPlans(for: room.first, in: room.context).map(\.resolvedStudentIDs) == [[room.child]])
    }

    @Test("A group presentation marked given without its rows gets her row for the Re-present")
    @MainActor
    func representMakesHerMissingRow() throws {
        let room = try makeDecisionRoom()
        defer { MeetingPersistenceService.clearCurrent(studentID: room.child) }
        let ben = CoreDataTestHelpers.seedStudent(in: room.context, firstName: "Ben", lastName: "Adler")
        let group = PresentationFactory.makePresented(
            lesson: room.first, students: [room.student, ben], context: room.context
        )
        let groupID = try #require(group.id).uuidString
        room.work.presentationID = groupID
        #expect(CoreDataTestHelpers.save(room.context))

        let draft = MeetingDraftModel(studentID: room.child)
        draft.load(context: room.context)
        draft.represent(room.work, context: room.context)
        #expect(draft.complete(context: room.context, saveCoordinator: .preview) { _ in nil })

        #expect(!group.needsAnotherPresentation)
        let flagged = ChildRepresentations(presentationIDs: [groupID], in: room.context).students(on: groupID)
        #expect(flagged == [room.child.uuidString])
        #expect(PresentationFollowUpService.rows(for: try #require(group.id), in: room.context).count == 1)
    }

    @Test("Re-present on an undated group presentation gives her an undated row of her own")
    @MainActor
    func representOnUndatedGroup() throws {
        let room = try makeDecisionRoom()
        defer { MeetingPersistenceService.clearCurrent(studentID: room.child) }
        let ben = CoreDataTestHelpers.seedStudent(in: room.context, firstName: "Ben", lastName: "Adler")
        let benID = try #require(ben.id)
        let group = PresentationFactory.makePreviouslyPresented(
            lessonID: try #require(room.first.id), studentIDs: [room.child, benID], context: room.context
        )
        let groupID = try #require(group.id).uuidString
        room.work.presentationID = groupID
        #expect(CoreDataTestHelpers.save(room.context))

        let draft = MeetingDraftModel(studentID: room.child)
        draft.load(context: room.context)
        draft.represent(room.work, context: room.context)
        #expect(draft.complete(context: room.context, saveCoordinator: .preview) { _ in nil })

        #expect(!group.needsAnotherPresentation)
        let rows = PresentationFollowUpService.rows(for: try #require(group.id), in: room.context)
        #expect(rows.map(\.studentID) == [room.child.uuidString])
        #expect(rows.first?.presentedAt == nil)
        let representations = ChildRepresentations(in: room.context)
        #expect(group.needsAnotherPresentation(for: room.child.uuidString, given: representations))
        #expect(!group.needsAnotherPresentation(for: benID.uuidString, given: representations))
    }

    // MARK: - Ready for Next at the end of a sequence (#13)

    @Test("Ready for Next is offered only for a lesson with a next one in its sequence")
    @MainActor
    func readyOfferedOnlyWithANextLesson() throws {
        let room = try makeDecisionRoom()
        defer { MeetingPersistenceService.clearCurrent(studentID: room.child) }
        let loose = CoreDataTestHelpers.seedLesson(in: room.context, name: "Clocks", area: "Math", sequence: "")
        let tiedA = CoreDataTestHelpers.seedLesson(in: room.context, name: "Map A", area: "Geo", sequence: "Maps")
        let tiedB = CoreDataTestHelpers.seedLesson(in: room.context, name: "Map B", area: "geo", sequence: "maps ")
        tiedA.orderInSequence = 3
        tiedB.orderInSequence = 3
        #expect(CoreDataTestHelpers.save(room.context))

        let draft = MeetingDraftModel(studentID: room.child)
        draft.load(context: room.context)
        #expect(draft.hasNextLesson(after: try #require(room.first.id).uuidString))
        #expect(!draft.hasNextLesson(after: try #require(room.second.id).uuidString))
        #expect(!draft.hasNextLesson(after: try #require(loose.id).uuidString))
        #expect(!draft.hasNextLesson(after: try #require(tiedA.id).uuidString))
        #expect(!draft.hasNextLesson(after: try #require(tiedB.id).uuidString))
        #expect(!draft.hasNextLesson(after: "not a lesson"))
    }

    // MARK: - The draft

    @Test("Close receipts ride in the draft, and the tab's saves keep them")
    func closeTokensRoundTrip() throws {
        let name = "MeetingDraftStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let child = UUID()
        let uri = try #require(URL(string: "x-coredata://STORE/WorkModel/p1"))
        let token = MeetingCloseToken(
            day: AppCalendar.startOfDay(Date()),
            rows: [.init(objectURI: uri, statusRaw: "active", completedAt: nil, lastTouchedAt: Date())],
            leftStatusRaw: "incomplete",
            leftLastTouchedAt: Date()
        )
        var workflow = MeetingPersistenceService.CurrentMeetingData()
        workflow.representWorkIDs = [UUID().uuidString]
        workflow.closeTokens = [UUID().uuidString: [token]]
        MeetingPersistenceService.saveCurrent(studentID: child, data: workflow, defaults: defaults)
        #expect(MeetingPersistenceService.loadCurrent(studentID: child, defaults: defaults) == workflow)

        var tab = MeetingPersistenceService.CurrentMeetingData()
        tab.reflectionText = "Typed in the student record"
        MeetingPersistenceService.saveCurrent(studentID: child, data: tab, defaults: defaults)
        #expect(MeetingPersistenceService.loadCurrent(studentID: child, defaults: defaults).closeTokens
            == workflow.closeTokens)

        var receiptsOnly = MeetingPersistenceService.CurrentMeetingData()
        receiptsOnly.closeTokens = workflow.closeTokens
        #expect(!receiptsOnly.isEmpty)
    }
}
