import Foundation
import Testing
@testable import CosmicDaybook

// One fold feeds every "do these two names match" comparison in the app, so
// the MCP tools and the screens can never disagree about whether "École" is
// "ecole". These pin the fold itself and the lesson-name key that the
// uniqueness rule and the same-name merge build on top of it.
@Suite("String folding")
struct StringFoldingTests {

    @Test("folded() trims, lowercases, and drops diacritics")
    func foldedTrimsLowercasesAndStripsAccents() {
        #expect("  Café ".folded() == "cafe")
    }

    @Test("Accented and plain spellings fold equal")
    func accentedAndPlainSpellingsFoldEqual() {
        #expect("École".folded() == "ecole".folded())
        #expect("École".folded() == "ecole")
    }

    @Test("foldedKey() collapses internal whitespace and newlines to one space")
    func foldedKeyCollapsesInternalWhitespace() {
        #expect("Great  Lesson\n Two".foldedKey() == "great lesson two")
    }

    @Test("The lesson-name key is built from folded(), so MCP and UI agree")
    func lessonNameKeyIsBuiltFromFolded() {
        let name = " Rôle-play "
        let area = "Language"
        let sequence = "Écriture"
        let key = LessonRepository.nameKey(name: name, area: area, sequence: sequence)
        #expect(key == [area, sequence, name].map { $0.folded() }.joined(separator: "|"))
        #expect(key == "language|ecriture|role-play")
    }
}
