import Foundation
import Testing
@testable import CosmicDaybook

/// How a name Siri heard becomes the children it could mean: strictest form
/// first, so a full name never drags in a namesake, while a shared first name
/// returns both and Siri asks which.
@Suite("Student name matcher")
struct StudentNameMatcherTests {

    private static func child(
        _ first: String, _ last: String, nickname: String? = nil
    ) -> StudentNameMatcher.Candidate {
        StudentNameMatcher.Candidate(id: UUID(), firstName: first, lastName: last, nickname: nickname)
    }

    private let maya = child("Maya", "Stone")
    private let sarahK = child("Sarah", "Klein")
    private let sarahA = child("Sarah", "Adler")
    private let ettyR = child("Etty", "Rosen")
    private let ettyG = child("Etty", "Goldman")
    private let miriam = child("Miriam", "Vale", nickname: "Miri")
    private let talia = child("Talia", "Brook")
    private let leah = child("Léah", "Hart")

    private var roster: [StudentNameMatcher.Candidate] { [maya, sarahK, sarahA, ettyR, ettyG, miriam, talia, leah] }

    private func names(_ spoken: String) -> [String] {
        StudentNameMatcher.matches(for: spoken, in: roster).map { "\($0.firstName) \($0.lastName)" }
    }

    @Test("A first name alone finds the one child who has it")
    func uniqueFirstName() {
        #expect(names("Maya") == ["Maya Stone"])
        #expect(names("maya") == ["Maya Stone"])
    }

    @Test("A shared first name returns both, so Siri asks which")
    func sharedFirstName() {
        #expect(names("Sarah") == ["Sarah Klein", "Sarah Adler"])
    }

    @Test("A full name or the short form picks one of two namesakes")
    func fullAndShortNames() {
        #expect(names("Sarah Adler") == ["Sarah Adler"])
        #expect(names("Sarah K") == ["Sarah Klein"])
        #expect(names("Sarah K.") == ["Sarah Klein"])
        #expect(names("Etty G") == ["Etty Goldman"])
    }

    @Test("Nicknames, last names and accents")
    func otherNames() {
        #expect(names("Miri") == ["Miriam Vale"])
        #expect(names("Miri Vale") == ["Miriam Vale"])
        #expect(names("Goldman") == ["Etty Goldman"])
        #expect(names("Leah") == ["Léah Hart"])
    }

    @Test("The start of a name, three letters or more")
    func prefixes() {
        #expect(names("Tal") == ["Talia Brook"])
        #expect(names("Ma") == [])
    }

    @Test("A name Siri spelled by sound still finds the child")
    func nearMisses() {
        #expect(names("Talya") == ["Talia Brook"])
        #expect(names("Eddie") == ["Etty Rosen", "Etty Goldman"])
        #expect(names("Gideon") == [])
    }

    @Test("Exact matches win over near misses")
    func exactBeatsNear() {
        let mia = Self.child("Mia", "Lowe")
        let found = StudentNameMatcher.matches(for: "Mia", in: roster + [mia])
        #expect(found == [mia])
    }

    @Test("Sound keys merge letters that sound alike")
    func soundKeys() {
        #expect(StudentNameMatcher.soundKey("Eddie") == StudentNameMatcher.soundKey("Etty"))
        #expect(StudentNameMatcher.soundKey("Philip") == StudentNameMatcher.soundKey("Filip"))
        #expect(StudentNameMatcher.soundKey("Yael") == "yael")
    }
}
