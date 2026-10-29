import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-29, #20: Siri's name matching takes a child who has left,
/// named exactly, over a child in the class whose name only sounds alike
/// (right for attendance, bug hunt 2026-10-17 #4), so Log Observation could
/// file a note on Leah, who has left, when the guide meant Lea. A note now
/// goes to a current child whose name is hers or sounds just like it; the
/// child who left only when nobody in the class does.
@Suite("Log Observation prefers a child in the class (fix 10-29 #20)")
struct LogObservationChildFix1029Tests {

    private static func child(
        _ first: String, _ last: String, nickname: String? = nil
    ) -> StudentNameMatcher.Candidate {
        StudentNameMatcher.Candidate(id: UUID(), firstName: first, lastName: last, nickname: nickname)
    }

    private let lea = child("Lea", "Moss")
    private let leah = child("Leah", "Hart")
    private let ettyR = child("Etty", "Rosen")
    private let eddie = child("Eddie", "Cole")
    private let sara = child("Sara", "Klein")
    private let sarahA = child("Sarah", "Adler")
    private let sarahB = child("Sarah", "Bloom")
    private let maya = child("Maya", "Stone")
    private let ora = child("Ora", "Levi")

    private func stayIns(for found: StudentNameMatcher.Candidate, _ current: [StudentNameMatcher.Candidate]) -> [UUID] {
        LogObservationIntent.currentChildren(for: found, among: current).map(\.id)
    }

    @Test("A child who left gives way to one in the class whose name sounds just like hers")
    func currentSoundAlikeWins() {
        #expect(stayIns(for: leah, [maya, lea]) == [lea.id])
        #expect(stayIns(for: eddie, [ettyR, maya]) == [ettyR.id])
    }

    @Test("Several in the class who could be meant all come back, for Siri to ask which")
    func severalCurrentMatches() {
        #expect(stayIns(for: sarahB, [sara, sarahA, maya]) == [sara.id, sarahA.id])
    }

    @Test("A child who left keeps the note when nobody in the class sounds like her")
    func departedWhenNobodyCurrentMatches() {
        #expect(stayIns(for: ora, [maya, lea]).isEmpty)
        // A name only near hers is a guess, not a match.
        #expect(stayIns(for: Self.child("Avi", "Cohen"), [Self.child("Ari", "Shaw")]).isEmpty)
    }

    @Test("A child in the class is never swapped for another")
    func currentChildStays() {
        #expect(stayIns(for: lea, [lea, leah]).isEmpty)
    }

    @Test("A nickname counts as her name")
    func nicknameCounts() {
        let departed = Self.child("Rivkah", "Gold", nickname: "Riv")
        let current = Self.child("Rebecca", "Shaw", nickname: "Riv")
        #expect(stayIns(for: departed, [maya, current]) == [current.id])
    }
}
