import Foundation
import Testing
@testable import Maria_s_Notebook

/// The workspace's top-level axis is now kind, and state is a pill row inside
/// each half. These lock down the two things that restructure can silently get
/// wrong: a state with no pill to reach it, and a saved selection from the old
/// state-first picker that resolves to nothing.
@Suite("Lessons & Work kind and pills")
@MainActor
struct LessonsAndWorkKindTests {

    // MARK: - Pills cover the buckets

    @Test("Every workspace bucket has a Work pill that shows it")
    func everyBucketHasAPill() {
        for bucket in TriageBucket.workspaceCases {
            let chip = WorkFilterChip.showing(bucket)
            #expect(chip.bucket == bucket, "\(bucket) has no pill of its own")
        }
    }

    @Test("Done is history, so no pill claims it")
    func donePillFallsBackToAll() {
        #expect(WorkFilterChip.showing(.done) == .all)
        #expect(WorkFilterChip.allCases.allSatisfy { $0.bucket != .done })
    }

    @Test("All is exactly the union of the other pills, with nothing doubled")
    func allIsTheUnionOfTheRest() {
        let split = TriageSplit([1, 2, 3, 4, 5, 6, 7]) { value in
            switch value % 4 {
            case 0: return .attention
            case 1: return .scheduled
            case 2: return .toSchedule
            default: return .done
            }
        }

        let all = WorkFilterChip.all.slice(of: split)
        let named = WorkFilterChip.allCases
            .filter { $0 != .all }
            .flatMap { $0.slice(of: split) }

        #expect(Set(all) == Set(named))
        #expect(all.count == named.count, "a record appears under two pills")
        #expect(!all.contains(where: split.done.contains), "finished work leaked into All")
    }

    // MARK: - A saved selection still resolves

    @Test(
        "A scene saved under the old state-first picker opens the matching half",
        arguments: [
            (TriageBucket.attention.rawValue, WorkspaceKind.work),
            (TriageBucket.toSchedule.rawValue, WorkspaceKind.presentations),
            (TriageBucket.scheduled.rawValue, WorkspaceKind.presentations),
            (TriageBucket.done.rawValue, WorkspaceKind.presentations),
            ("nonsense", WorkspaceKind.presentations)
        ]
    )
    func savedScopeMigratesToAKind(rawValue: String, expected: WorkspaceKind) {
        #expect(WorkspaceKind.resolved(rawValue: rawValue) == expected)
    }

    @Test("Its own raw values round-trip, and a missing one lands somewhere real")
    func kindRoundTrips() {
        for kind in WorkspaceKind.allCases {
            #expect(WorkspaceKind.resolved(rawValue: kind.rawValue) == kind)
        }
        #expect(WorkspaceKind.resolved(rawValue: nil) == .presentations)
        #expect(WorkFilterChip.resolved(rawValue: nil) == .all)
        #expect(WorkFilterChip.resolved(rawValue: "gone") == .all)
    }

    @Test("A route naming a record opens the half that holds that kind")
    func routedRecordChoosesItsHalf() {
        #expect(WorkspaceKind.holding(presentationID: nil, workID: UUID()) == .work)
        #expect(WorkspaceKind.holding(presentationID: UUID(), workID: nil) == .presentations)
        // Both: the work is what the guide asked to open.
        #expect(WorkspaceKind.holding(presentationID: UUID(), workID: UUID()) == .work)
    }

    @Test("The follow-up route says which half it means, since it names no record")
    func followUpRouteCarriesItsKind() throws {
        let router = AppRouter()
        router.navigateToPresentationFollowUps()

        let request = try #require(router.consumeLessonsAndWorkRequest())
        #expect(request.scope == .attention)
        #expect(request.preferredKind == .presentations)
    }

    // MARK: - Which presentation pill can reveal a deep-linked record

    @Test("A given presentation is revealed by Follow Up, not the planning inbox")
    func presentedRecordRevealsUnderFollowUp() {
        #expect(
            PresentationsView.chipRevealing(isPresented: true, scheduledFor: nil) == .followUp
        )
        #expect(
            PresentationsView.chipRevealing(isPresented: true, scheduledFor: Date()) == .followUp
        )
    }

    @Test("An unscheduled presentation is revealed by All; a scheduled one by no pill")
    func unscheduledRevealsUnderAll() {
        #expect(
            PresentationsView.chipRevealing(isPresented: false, scheduledFor: nil) == .all
        )
        // It is on the calendar pinned below, so no pill in this half holds it.
        #expect(
            PresentationsView.chipRevealing(isPresented: false, scheduledFor: Date()) == nil
        )
    }
}
