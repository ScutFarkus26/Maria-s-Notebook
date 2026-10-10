import Foundation
import Testing
@testable import CosmicDaybook

/// The name tagger's first tests: tables of sentences and what the tagger should
/// make of them. "Tags" are the children Quick Note and the command bar add
/// (`exact ∪ autoSelect`); "tidied" is the text after Quick Note applies the
/// tagger's replacements through its real tidy (`QuickNoteAutoTidy.apply`).
/// Rows marked "keep" pinned behavior the 2026-10-10 fixes must not change; the
/// rest are the bug hunt's failing cases (Part 2 #3–7, #15, #16).
@Suite("Student tagger")
struct StudentTaggerTests {

    // MARK: - Rosters

    nonisolated private static func student(_ first: String, _ last: String, nickname: String? = nil) -> StudentData {
        StudentData(id: UUID(), firstName: first, lastName: last, nickname: nickname)
    }

    /// A class with the real hard cases: two Ettys, two Sarahs, two Zoës, and
    /// children whose initials spell ordinary words ("is", "to", "at", "me", "OK", "PE").
    nonisolated static let classRoster: [StudentData] = [
        student("Etty", "Brown"), student("Etty", "Klein"),
        student("Sarah", "Miller"), student("Sarah", "Klein"),
        student("Zoë", "Smith"), student("Zoë", "Klein"),
        student("Maya", "Smith"), student("Leo", "Abrams"), student("Jonah", "Davis"),
        student("Isaac", "Stone"), student("Ava", "Miller"), student("Sam", "Abrams"),
        student("Paul", "Evans"), student("Olivia", "King"), student("Tia", "Vance"),
        student("Alexandra", "Stone", nickname: "Sunny"), student("Ana", "Lopez"),
        student("Max", "Turner"), student("Tom", "Owens"), student("Ian", "Norris"),
        student("Ezra", "Green"), student("Isla", "Edwards"), student("Peter", "Moss"),
        student("Mia", "Evans"), student("Aria", "Thomas")
    ]

    nonisolated static let twoLeos: [StudentData] = [student("Leo", "Abrams"), student("Leo", "Brown")]
    nonisolated static let oneSarahI: [StudentData] = [student("Sarah", "Isaacs"), student("Maya", "Smith")]
    nonisolated static let twoSarahsOneI: [StudentData] = [student("Sarah", "Isaacs"), student("Sarah", "Miller")]
    nonisolated static let lettersAndTran: [StudentData] = [
        student("Aaron", "Baker"), student("Maya", "Smith"), student("Sid", "Tran"), student("Jonah", "Davis")
    ]

    // MARK: - Tagging

    nonisolated struct TagCase: CustomTestStringConvertible, Sendable {
        let text: String
        let roster: [StudentData]
        /// Short names of the children tagged.
        let tags: Set<String>
        /// The text after the tagger's replacements, when the row checks it.
        let tidied: String?
        /// Short names that must be suggested (ambiguous names).
        let suggests: Set<String>
        /// Short names that must not even be suggested.
        let neverSuggests: Set<String>

        init(
            _ text: String, roster: [StudentData] = StudentTaggerTests.classRoster,
            tags: Set<String>, tidied: String? = nil,
            suggests: Set<String> = [], neverSuggests: Set<String> = []
        ) {
            self.text = text
            self.roster = roster
            self.tags = tags
            self.tidied = tidied
            self.suggests = suggests
            self.neverSuggests = neverSuggests
        }

        var testDescription: String { "\"\(text)\"" }
    }

    nonisolated static let tagCases: [TagCase] = [
        // Keep: the two Ettys and two Sarahs written the canonical way.
        TagCase("Etty B helped Etty K", tags: ["Etty B", "Etty K"], tidied: "Etty B helped Etty K"),
        TagCase("Etty B worked on the bead frame", tags: ["Etty B"], tidied: "Etty B worked on the bead frame"),
        TagCase("Sarah M finished her map", tags: ["Sarah M"], tidied: "Sarah M finished her map"),
        TagCase("etty b read", tags: ["Etty B"], tidied: "etty b read"),
        // Keep: possessives.
        TagCase("Sarah M's map looks done", tags: ["Sarah M"], tidied: "Sarah M's map looks done"),
        TagCase("Maya's work looks careful", tags: ["Maya S"], tidied: "Maya's work looks careful"),
        TagCase("maya finished", tags: ["Maya S"], tidied: "maya finished"),
        // Keep: names inside other words are not names.
        TagCase("We read about the Mayan calendar", tags: [], tidied: "We read about the Mayan calendar"),
        TagCase("Leonardo drew a horse", tags: [], tidied: "Leonardo drew a horse"),
        // Keep: a lone shared first name suggests both and selects neither.
        TagCase("Sarah went out", tags: [], tidied: "Sarah went out", suggests: ["Sarah M", "Sarah K"]),
        // Keep: clear initials.
        TagCase("JD read aloud", tags: ["Jonah D"]),

        // P2 #3: ordinary words read as initials.
        TagCase("she is reading", tags: [], tidied: "she is reading"),
        TagCase("Sarah went to the library", tags: [], suggests: ["Sarah M", "Sarah K"]),
        TagCase("Give it to me", tags: [], tidied: "Give it to me"),
        TagCase("We went out at 10 a.m. and came back at 1 p.m.", tags: [],
                tidied: "We went out at 10 a.m. and came back at 1 p.m."),
        TagCase("Use a map, e.g. the big one, i.e. the wall map", tags: [],
                tidied: "Use a map, e.g. the big one, i.e. the wall map"),
        TagCase("Maya S a bead frame", tags: ["Maya S"], tidied: "Maya S a bead frame"),
        TagCase("OK, time for PE and TV", tags: [], tidied: "OK, time for PE and TV"),
        // P2 #4: the word after a name.
        TagCase("gave Leo a pencil", tags: ["Leo A"], tidied: "gave Leo a pencil"),
        TagCase("gave Leo a pencil", roster: twoLeos, tags: [], tidied: "gave Leo a pencil",
                suggests: ["Leo A", "Leo B"]),
        TagCase("gave Leo A pencil", roster: twoLeos, tags: ["Leo A"], tidied: "gave Leo A pencil"),
        TagCase("Sarah I think is ready", roster: oneSarahI, tags: ["Sarah I"], tidied: "Sarah I think is ready"),
        TagCase("Sarah I think is ready", roster: twoSarahsOneI, tags: [], tidied: "Sarah I think is ready"),
        TagCase("Sarah I. is ready", roster: twoSarahsOneI, tags: ["Sarah I"], tidied: "Sarah I. is ready"),
        // Review 2026-10-10: spaced capitals with an "A" or "I", or right after a short name.
        TagCase("Maya S A great day", tags: ["Maya S"], tidied: "Maya S A great day"),
        TagCase("We traced A B and C", roster: lettersAndTran, tags: [], tidied: "We traced A B and C"),
        TagCase("Maya S T came in", roster: lettersAndTran, tags: ["Maya S"], tidied: "Maya S T came in"),
        TagCase("Today J D came in", roster: lettersAndTran, tags: ["Jonah D"], tidied: "Today Jonah D came in"),
        // Tidy goes only where the initials are, same case: not into "She's a".
        TagCase("SA helped. She's a fast reader", tags: ["Sam A"],
                tidied: "Sam A helped. She's a fast reader"),
        // Never replace with text that drops what she typed.
        TagCase("Maya S read", tags: ["Maya S"], tidied: "Maya S read"),
        TagCase("maya s. read", tags: ["Maya S"], tidied: "maya s. read"),
        TagCase("Maya Smith read", tags: ["Maya S"], tidied: "Maya Smith read"),
        TagCase("Sarah Miller read", tags: ["Sarah M"], tidied: "Sarah Miller read"),
        TagCase("Great job 👍 JD", tags: ["Jonah D"], tidied: "Great job 👍 Jonah D"),
        // P2 #7: accents folded on both sides.
        TagCase("Zoë S painted", tags: ["Zoë S"], tidied: "Zoë S painted"),
        TagCase("Zoe S painted", tags: ["Zoë S"]),
        TagCase("Zoë painted", tags: [], suggests: ["Zoë S", "Zoë K"]),
        // P2 #15: a nickname tags but is never rewritten.
        TagCase("a sunny day", tags: ["Alexandra S"], tidied: "a sunny day"),
        TagCase("Sunny read", tags: ["Alexandra S"], tidied: "Sunny read"),
        // P2 #16: one-letter and short common words don't suggest children.
        TagCase("a book and a pencil was on the desk", tags: [],
                neverSuggests: ["Alexandra S", "Ana L", "Ava M", "Aria T", "Max T", "Isaac S", "Ian N"]),
        TagCase("I think it was hard", tags: [], neverSuggests: ["Isaac S", "Isla E", "Ian N", "Max T"])
    ]

    @Test("Tags and tidied text", arguments: tagCases)
    @MainActor
    func tagging(_ row: TagCase) async {
        let tagger = StudentTagger()
        let result = await tagger.findStudentMatches(in: row.text, studentData: row.roster)
        let names = Self.shortNames(row.roster)

        let tagged = Set(result.exact.union(result.autoSelect).compactMap { names[$0] })
        #expect(tagged == row.tags)

        let suggested = Set(result.fuzzy.compactMap { names[$0] })
        #expect(row.suggests.isSubset(of: suggested), "suggested \(suggested.sorted())")
        #expect(row.neverSuggests.isDisjoint(with: suggested), "suggested \(suggested.sorted())")

        if let tidied = row.tidied {
            let applied = QuickNoteAutoTidy.apply(result.replacements, to: row.text, cursor: nil)
            #expect((applied?.text ?? row.text) == tidied)
        }
    }

    @Test("Initials shared by two children suggest both and select neither")
    func sharedInitials() async {
        let roster = [Self.student("Jonah", "Davis"), Self.student("Jade", "Dunn")]
        let result = await StudentTagger().findStudentMatches(in: "JD read", studentData: roster)
        #expect(result.exact.union(result.autoSelect).isEmpty)
        #expect(result.fuzzy == Set(roster.map(\.id)))
    }

    @Test("Quick Note's tidy changes only the place the tagger found, same case")
    @MainActor
    func tidyOnlyAtFoundRange() throws {
        let text = "JD read. Then jd and JD again"
        let second = (text as NSString).range(of: "JD again")
        let replacement = TextReplacement(
            originalText: "JD", replacement: "Jonah D", range: NSRange(location: second.location, length: 2)
        )
        let result = try #require(QuickNoteAutoTidy.apply([replacement], to: text, cursor: nil))
        #expect(result.text == "JD read. Then jd and Jonah D again")

        // She typed before it since the tagger looked: the text there no longer reads "JD".
        #expect(QuickNoteAutoTidy.apply([replacement], to: "Then " + text, cursor: nil) == nil)
    }

    // MARK: - Format Names

    nonisolated static let formatCases: [(String, String)] = [
        // Keep
        ("maya finished", "Maya S finished"),
        ("Maya's work", "Maya S's work"),
        ("gave Leo a pencil", "gave Leo A a pencil"),
        // P2 #6: one pass, short names left alone, ambiguous names left alone.
        ("Maya Smith read with Ava Miller", "Maya S read with Ava M"),
        ("Maya Smith read with Sarah Miller", "Maya S read with Sarah M"),
        ("Maya S and Etty B", "Maya S and Etty B"),
        ("Sarah helped Etty", "Sarah helped Etty"),
        ("Sarah Klein and Sarah M", "Sarah K and Sarah M"),
        // P2 #15 and #7
        ("a sunny day", "a sunny day"),
        ("Zoe Smith painted", "Zoë S painted")
    ]

    @Test("Format Names", arguments: formatCases)
    func formatNames(_ row: (String, String)) async {
        let tagger = StudentTagger()
        let once = await tagger.formatStudentNames(in: row.0, studentData: Self.classRoster)
        #expect(once == row.1)
        let twice = await tagger.formatStudentNames(in: once, studentData: Self.classRoster)
        #expect(twice == once)
    }

    // MARK: - Expand Initials

    nonisolated static let expandCases: [(String, String)] = [
        // Keep
        ("JD read aloud", "Jonah D read aloud"),
        ("J.D. read aloud", "Jonah D. read aloud"),
        // P2 #5: UTF-16 ranges, clear initials only.
        ("👍 JD and PE today", "👍 Jonah D and PE today"),
        ("Great job 👍 JD", "Great job 👍 Jonah D"),
        ("OK, TV time", "OK, TV time"),
        ("👍 JD and SA", "👍 Jonah D and Sam A")
    ]

    @Test("Expand Initials", arguments: expandCases)
    func expandInitials(_ row: (String, String)) {
        #expect(NoteInitialsExpander.expanding(row.0, students: Self.classRoster) == row.1)
    }

    // MARK: - Fuzzy suggestions

    nonisolated static let fuzzyMatches: [(String, String)] = [
        ("Mya", "Maya"), ("D.", "Danny"), ("maya", "Maya"), ("Sofia", "Sophia")
    ]

    nonisolated static let fuzzyNonMatches: [(String, String)] = [
        ("a", "Alexandra"), ("I", "Isaac"), ("and", "Ana"), ("was", "Max"), ("the", "Theo"), ("him", "Kim"),
        ("fan", "Ian"), ("pan", "Ian"), ("leg", "Leo"), ("mat", "Max")
    ]

    @Test("Fuzzy name match", arguments: fuzzyMatches)
    func fuzzyMatch(_ row: (String, String)) {
        #expect(row.0.isFuzzyMatch(to: row.1))
    }

    @Test("Short common words are never a fuzzy name match", arguments: fuzzyNonMatches)
    func fuzzyNonMatch(_ row: (String, String)) {
        #expect(!row.0.isFuzzyMatch(to: row.1))
    }

    // MARK: - Helpers

    private static func shortNames(_ roster: [StudentData]) -> [UUID: String] {
        Dictionary(roster.map {
            ($0.id, StudentFormatter.displayName(firstName: $0.firstName, lastName: $0.lastName))
        }, uniquingKeysWith: { first, _ in first })
    }
}
