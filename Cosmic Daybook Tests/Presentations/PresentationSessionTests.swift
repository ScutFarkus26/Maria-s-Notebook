import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

@Suite("Presentation Session")
@MainActor
struct PresentationSessionTests {
    private let ada = UUID()
    private let ben = UUID()
    private let cy = UUID()

    @Test("Attendance unticks an absent child; a hand-made tick survives a new day")
    func rosterFollowsAttendance() {
        let session = PresentationSession(presentationID: UUID())
        session.syncRoster(planned: [ada, ben, cy], absent: [cy])
        #expect(session.presentIDs == [ada, ben])

        session.togglePresent(cy)
        session.syncRoster(planned: [ada, ben, cy], absent: [cy])
        #expect(session.presentIDs.contains(cy))

        session.togglePresent(ada)
        session.syncRoster(planned: [ada, ben, cy], absent: [])
        #expect(!session.presentIDs.contains(ada))
        #expect(session.presentIDs.contains(ben))
    }

    @Test("A child left off the plan drops out of the ticks")
    func rosterDropsRemovedChild() {
        let session = PresentationSession(presentationID: UUID())
        session.syncRoster(planned: [ada, ben], absent: [])
        session.syncRoster(planned: [ada], absent: [])
        #expect(session.presentIDs == [ada])
    }

    @Test("Everyone sets the default; a child's own choice overrides only her")
    func everyoneAndOverrides() {
        let session = PresentationSession(presentationID: UUID())
        session.setEveryone(.practice)
        session.setDecision(.represent, for: ben)
        #expect(session.decision(for: ada) == .practice)
        #expect(session.decision(for: ben) == .represent)
        #expect(session.isOverridden(ben))
        #expect(!session.isOverridden(ada))

        // Choosing the same as everyone is not an override.
        session.setDecision(.practice, for: ben)
        #expect(!session.isOverridden(ben))

        // A new default swallows overrides that now agree with it.
        session.setDecision(.represent, for: ben)
        session.setEveryone(.represent)
        #expect(!session.isOverridden(ben))
    }

    @Test("Only decisions that differ from the record are pending")
    func pendingAgainstApplied() {
        let session = PresentationSession(presentationID: UUID())
        session.setEveryone(.continueObserving)
        session.setDecision(.practice, for: ada)
        #expect(session.pendingDecisions(for: [ada, ben]) == [ada: .practice])
        #expect(session.hasChanges(for: [ada, ben]))

        session.setDecision(.continueObserving, for: ada)
        #expect(!session.hasChanges(for: [ada, ben]))
        session.groupNote = "Both concentrated."
        #expect(session.hasChanges(for: [ada, ben]))
    }

    @Test("A Later draft round-trips the decisions and the check-in day")
    func draftRoundTrip() throws {
        let defaults = try #require(UserDefaults(suiteName: "PresentationSessionTests.\(UUID().uuidString)"))
        let presentationID = UUID()
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let monday = AppCalendar.startOfDay(Date(timeIntervalSinceReferenceDate: 812_000_000))

        let first = PresentationSession(presentationID: presentationID)
        first.setEveryone(.practice)
        first.setDecision(.represent, for: ben)
        first.checkIn = .on(monday)
        PresentationSessionDraftStore.save(first.draft, presentationID: presentationID, defaults: defaults)

        let second = PresentationSession(presentationID: presentationID)
        second.loadDecisions(
            studentIDs: [ada, ben], defaultDecision: .continueObserving, context: context, defaults: defaults
        )
        #expect(second.decision(for: ada) == .practice)
        #expect(second.decision(for: ben) == .represent)
        #expect(second.checkIn == .on(monday))

        PresentationSessionDraftStore.clear(presentationID: presentationID, defaults: defaults)
        #expect(PresentationSessionDraftStore.load(presentationID: presentationID, defaults: defaults) == nil)
    }

    @Test("The summary says what Done will write, in plain words")
    func summaryLines() {
        let lines = PresentationSessionSummary.lines(.init(
            children: [.init(id: ada, name: "Ada L"), .init(id: ben, name: "Ben K"), .init(id: cy, name: "Cy M")],
            pending: [ada: .practice, ben: .practice, cy: .represent],
            decisions: [ada: .practice, ben: .practice, cy: .represent],
            checkIn: .nextWorkCycle,
            checkInChanged: false,
            noteCount: 2,
            lessonName: "Golden Beads",
            nextLessonName: nil
        ))
        #expect(lines.contains("Practice work for Ada L and Ben K in Children Working — “Practice: Golden Beads”"))
        #expect(lines.contains("Cy M will see it again: a re-presentation goes On Deck"))
        #expect(lines.contains("2 notes, filed on this presentation"))
        #expect(PresentationSessionSummary.list(["A", "B", "C"]) == "A, B and C")
    }
}
