import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-17, #4: Siri took a sound-alike child in the class over
/// an exact match on one who had left ("Mark Leah here" marked Lea), and a
/// lone near miss as the child ("Ari" for Avi, with no question asked).
/// Exact and prefix matches over the class and then former children come
/// before any sound-alike, a short name must sound exactly alike, and a near
/// miss never comes back alone.
@Suite("Student name matcher (Fix1017 At)")
struct StudentNameMatcherFix1017AtTests {

    private static func child(_ first: String, _ last: String) -> StudentNameMatcher.Candidate {
        StudentNameMatcher.Candidate(id: UUID(), firstName: first, lastName: last, nickname: nil)
    }

    private static func names(_ found: [StudentNameMatcher.Candidate]) -> [String] {
        found.map { "\($0.firstName) \($0.lastName)" }
    }

    private static func match(
        _ spoken: String, current: [StudentNameMatcher.Candidate], former: [StudentNameMatcher.Candidate] = []
    ) -> [String] {
        names(StudentNameMatcher.matches(for: spoken, current: current, former: { former }))
    }

    private let lea = child("Lea", "Moss")
    private let leah = child("Leah", "Hart")
    private let avi = child("Avi", "Cohen")
    private let ettyR = child("Etty", "Rosen")
    private let ettyG = child("Etty", "Goldman")
    private let meir = child("Meir", "Katz")
    private let miriam = child("Miriam", "Vale")

    @Test("A child who left, named exactly, comes before a sound-alike in the class")
    func formerExactBeatsCurrentSoundAlike() {
        #expect(Self.match("Leah", current: [lea], former: [leah]) == ["Leah Hart"])
        // The start of a name counts as exact.
        #expect(Self.match("Mir", current: [meir], former: [miriam]) == ["Miriam Vale"])
    }

    @Test("A child in the class named exactly still comes before one who left")
    func currentExactBeatsFormerExact() {
        let leahNow = Self.child("Leah", "Stone")
        #expect(Self.match("Leah", current: [leahNow, lea], former: [leah]) == ["Leah Stone"])
    }

    @Test("A lone near miss is never taken as the child")
    func loneNearMissIsRefused() {
        // On a locked iPhone there are no former children to look through.
        #expect(Self.match("Leah", current: [lea]).isEmpty)
        #expect(Self.match("Ari", current: [avi]).isEmpty)
        #expect(Self.names(StudentNameMatcher.matches(for: "Ari", in: [avi])).isEmpty)
        #expect(Self.match("Tahlia", current: [Self.child("Talia", "Brook")]).isEmpty)
    }

    @Test("Names that sound exactly alike still match, and two near misses come back for Siri to ask")
    func soundAlikesThatStillMatch() {
        #expect(Self.match("Eddie", current: [ettyR, ettyG, lea]) == ["Etty Rosen", "Etty Goldman"])
        #expect(Self.match("Talya", current: [Self.child("Talia", "Brook"), lea]) == ["Talia Brook"])
        let milo = Self.child("Milo", "Park"), mira = Self.child("Mira", "Fox")
        #expect(Self.match("Mila", current: [milo, mira, lea]) == ["Milo Park", "Mira Fox"])
    }

    @Test("Former children are read only when no one in the class has the name")
    func formerReadOnlyWhenNeeded() {
        var reads = 0
        let found = StudentNameMatcher.matches(for: "Lea", current: [lea], former: {
            reads += 1
            return [leah]
        })
        #expect(Self.names(found) == ["Lea Moss"])
        #expect(reads == 0)
    }
}
