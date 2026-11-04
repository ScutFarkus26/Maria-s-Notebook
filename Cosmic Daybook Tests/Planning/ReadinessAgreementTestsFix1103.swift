import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-11-03, D2: the same record run through both readiness rules.
/// Presentations' `BlockingAlgorithmEngine` and the Checklist's and Today's
/// `ReadyForNextEngine` were fixed by different agents; they must agree on
/// whether a child is past the previous lesson's confirmation gate. (Open
/// work is a hard hold in one and a "check first" in the other by design, so
/// these records have none open.)
@Suite("Both readiness rules agree (11-03 D2)")
@MainActor
struct ReadinessAgreementFix1103Tests {

    typealias Fixture = ChecklistFix1103CFixture

    enum Record: String, CaseIterable, CustomTestStringConvertible {
        /// Given Decimal 0 and confirmed.
        case confirmed
        /// Given it, not confirmed, every gate on.
        case unconfirmed
        /// Given it, not confirmed, the lesson set to Requires Confirmation: No.
        case unconfirmedNotRequired
        /// Given it, not confirmed, the sequence set not to require confirmation.
        case unconfirmedSequenceNotRequired
        /// Given it, not confirmed, but marked Mastered.
        case mastered
        /// Never given it, but marked Mastered.
        case masteredNeverGiven
        /// Given it and confirmed, every gate on, her practice on it done.
        case confirmedPracticeDone

        var testDescription: String { rawValue }

        var passesConfirmation: Bool { self != .unconfirmed }
    }

    /// Her record on Decimal 0 for `record`.
    private func seed(_ record: Record, in fixture: Fixture) throws {
        let maya = fixture.maya
        switch record {
        case .confirmed:
            // Practice isn't what's being compared; without this the blocking
            // rule holds a given lesson that has no work yet.
            fixture.first.practiceOverride = .no
            try fixture.give([maya], on: "2026-10-20", confirming: [maya])
        case .unconfirmed:
            fixture.first.practiceOverride = .no
            try fixture.give([maya], on: "2026-10-20")
        case .unconfirmedNotRequired:
            fixture.first.practiceOverride = .no
            fixture.first.confirmationOverride = .no
            try fixture.give([maya], on: "2026-10-20")
        case .unconfirmedSequenceNotRequired:
            let settings = CDLessonSequenceSettings(context: fixture.context)
            settings.area = "Math"
            settings.sequence = "Decimal"
            settings.requiresPractice = false
            settings.requiresTeacherConfirmation = false
            try fixture.give([maya], on: "2026-10-20")
        case .mastered:
            fixture.first.practiceOverride = .no
            let given = try fixture.give([maya], on: "2026-10-20")
            let row = fixture.historyRow(maya, for: given)
            row.state = .proficient
            row.masteredAt = given.presentedAt
        case .masteredNeverGiven:
            let row = CDLessonPresentation(context: fixture.context)
            row.studentID = maya.cloudKitKey
            row.lessonID = fixture.firstID
            row.state = .proficient
            row.masteredAt = try CoreDataTestHelpers.day("2026-10-20")
        case .confirmedPracticeDone:
            let given = try fixture.give([maya], on: "2026-10-20", confirming: [maya])
            let work = CoreDataTestHelpers.seedWorkModel(
                in: fixture.context, title: "Decimal practice",
                studentID: try #require(maya.id), lessonID: try #require(fixture.first.id)
            )
            work.presentationID = given.id?.uuidString
            work.status = .done
        }
    }

    @Test("Presentations and the ready queue agree on the confirmation gate", arguments: Record.allCases)
    func bothRulesAgree(_ record: Record) throws {
        let fixture = try Fixture.make()
        let maya = fixture.maya
        let mayaID = try #require(maya.id)
        try seed(record, in: fixture)
        try fixture.context.save()

        // The ready queue, read before Decimal 1 is planned for her (a plan
        // takes her out of the queue).
        let index = PresentationRecordIndex(students: [mayaID.uuidString], in: fixture.context)
        let items = ReadyForNextEngine.items(
            studentIDs: [mayaID.uuidString], lessons: [fixture.first, fixture.second],
            index: index, in: fixture.context
        )
        let secondID = try #require(fixture.second.id).uuidString
        let queued = items.first { $0.nextLessonID == secondID }
        let queuePasses = queued.map { $0.tier != .notReady } ?? false

        // Presentations, on a plan of Decimal 1 for her.
        let plan = PresentationFactory.makeDraft(lesson: fixture.second, students: [maya], context: fixture.context)
        try fixture.context.save()
        let planID = try #require(plan.id)
        let results = BlockingAlgorithmEngine.checkBlocking(
            forBatch: [plan],
            lessons: [fixture.first, fixture.second],
            allLessonAssignments: fixture.context.safeFetch(CDFetchRequest(CDLessonAssignment.self)),
            workModels: fixture.context.safeFetch(CDFetchRequest(CDWorkModel.self))
        )
        let readiness = try #require(results[planID]?.perStudentReadiness[mayaID])

        #expect(readiness.teacherConfirmed == record.passesConfirmation)
        #expect(queuePasses == record.passesConfirmation)
        #expect(readiness.isReady == queuePasses)
    }

    @Test("A lesson needing no confirmation: the picker lists its children, no card offers to confirm them")
    func groupsFollowTheConfirmationSetting() throws {
        let fixture = try Fixture.make()
        fixture.first.practiceOverride = .no
        fixture.first.confirmationOverride = .no
        try fixture.give([fixture.maya, fixture.eli], on: "2026-10-20")
        try fixture.context.save()
        let lessons = [fixture.first, fixture.second]
        let secondID = try #require(fixture.second.id).uuidString
        let children = Set([fixture.maya, fixture.eli].compactMap { $0.id?.uuidString })

        let picker = ReadyGroups.readyStudentIDs(
            for: secondID, among: children, lessons: lessons, in: fixture.context
        )
        #expect(picker == children)

        let index = PresentationRecordIndex(students: children, in: fixture.context)
        let snapshot = ReadyQueueSnapshot(
            students: [fixture.maya, fixture.eli], lessons: lessons, index: index, in: fixture.context
        )
        let card = try #require(ReadyGroups.build(from: snapshot) { _ in 0 }.lessons.first {
            $0.position.lessonID == secondID
        })
        #expect(Set(card.ready.map(\.child.id)) == children)
        #expect(card.unconfirmed.isEmpty)
    }

    @Test("With every gate on, the unconfirmed children are still offered for confirming")
    func groupsStillOfferConfirmingByDefault() throws {
        let fixture = try Fixture.make()
        let lessons = [fixture.first, fixture.second]
        try fixture.give([fixture.maya, fixture.eli], on: "2026-10-20", confirming: [fixture.maya])
        // Eli is unconfirmed; Maya and Noa, confirmed, make the card a group.
        let noa = CoreDataTestHelpers.seedStudent(in: fixture.context, firstName: "Noa", lastName: "Gold")
        try fixture.give([noa], on: "2026-10-21", confirming: [noa])
        try fixture.context.save()
        let students = [fixture.maya, fixture.eli, noa]
        let ids = Set(students.compactMap { $0.id?.uuidString })
        let secondID = try #require(fixture.second.id).uuidString

        let index = PresentationRecordIndex(students: ids, in: fixture.context)
        let snapshot = ReadyQueueSnapshot(students: students, lessons: lessons, index: index, in: fixture.context)
        let card = try #require(ReadyGroups.build(from: snapshot) { _ in 0 }.lessons.first {
            $0.position.lessonID == secondID
        })
        #expect(card.unconfirmed.map(\.child.id) == [fixture.eli.id?.uuidString])
        #expect(ReadyGroups.readyStudentIDs(
            for: secondID, among: ids, lessons: lessons, in: fixture.context
        ) == ids.subtracting([fixture.eli.id?.uuidString ?? ""]))
    }
}
