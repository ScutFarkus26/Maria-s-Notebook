import Foundation
import Testing
@testable import CosmicDaybook

/// Daybook Assistant bug hunt 2026-10-20, #26: the exact tier stopped at the
/// spelling the recognizer wrote, so "Mark Sarah here" with Sara and Sarah in
/// the class marked Sarah without asking, though Siri may have heard Sara. A
/// final "h" after a vowel is folded (Sarah/Sara, Noah/Noa, not Beth/Bet):
/// names that sound the same come back together and Siri asks which. A
/// sound-alike first name alone is still never taken for the child (Leah who
/// left is never marked as Lea in the class, bug hunt 2026-10-17, #4); with
/// the last name or its initial it is.
@Suite("Student name matcher (Fix1020 SR)")
struct StudentNameMatcherFix1020SRTests {

    private static func child(_ first: String, _ last: String) -> StudentNameMatcher.Candidate {
        StudentNameMatcher.Candidate(id: UUID(), firstName: first, lastName: last, nickname: nil)
    }

    private static func match(
        _ spoken: String, current: [StudentNameMatcher.Candidate], former: [StudentNameMatcher.Candidate] = []
    ) -> [String] {
        StudentNameMatcher.matches(for: spoken, current: current, former: { former })
            .map { "\($0.firstName) \($0.lastName)" }
    }

    private let saraK = child("Sara", "Klein")
    private let sarahA = child("Sarah", "Adler")
    private let noa = child("Noa", "Levi")
    private let noah = child("Noah", "Gold")
    private let bet = child("Bet", "Ross")
    private let beth = child("Beth", "Cole")
    private let maya = child("Maya", "Stone")

    @Test("Names that sound the same come back together, whichever spelling Siri heard")
    func soundAlikesComeBackTogether() {
        let roster = [saraK, sarahA, maya]
        #expect(Self.match("Sarah", current: roster) == ["Sara Klein", "Sarah Adler"])
        #expect(Self.match("Sara", current: roster) == ["Sara Klein", "Sarah Adler"])
        #expect(Self.match("Noah", current: [noa, noah, maya]) == ["Noa Levi", "Noah Gold"])
    }

    @Test("A final h after a consonant is a different name")
    func bethIsNotBet() {
        #expect(Self.match("Beth", current: [bet, beth]) == ["Beth Cole"])
        #expect(Self.match("Bet", current: [bet, beth]) == ["Bet Ross"])
    }

    @Test("The last name or its initial tells sound-alikes apart")
    func lastNameDecides() {
        let roster = [saraK, sarahA, maya]
        #expect(Self.match("Sarah Klein", current: roster) == ["Sara Klein"])
        #expect(Self.match("Sara Adler", current: roster) == ["Sarah Adler"])
        #expect(Self.match("Sarah K", current: roster) == ["Sara Klein"])
    }

    @Test("A sound-alike first name alone is still never taken for the child")
    func loneSoundAlikeStillRefused() {
        let lea = Self.child("Lea", "Moss"), leah = Self.child("Leah", "Hart")
        #expect(Self.match("Leah", current: [lea]).isEmpty)
        #expect(Self.match("Leah", current: [lea], former: [leah]) == ["Leah Hart"])
    }

    @Test("The fold drops only a final h after a vowel")
    func fold() {
        #expect(StudentNameMatcher.soundFolded("Sarah") == "sara")
        #expect(StudentNameMatcher.soundFolded("Rivkah Stone") == "rivka stone")
        #expect(StudentNameMatcher.soundFolded("Beth") == "beth")
        #expect(StudentNameMatcher.soundFolded("Ah") == "ah")
    }
}
