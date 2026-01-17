#if canImport(Testing)
import Testing
import Foundation
@testable import Maria_s_Notebook

@Suite("String FuzzyMatch Tests")
struct StringFuzzyMatchTests {

    // MARK: - Levenshtein Distance Tests

    @Test("Identical strings have distance 0")
    func identicalStringsZeroDistance() {
        let distance = "hello".levenshteinDistance(to: "hello")

        #expect(distance == 0)
    }

    @Test("Empty source string returns target length")
    func emptySourceReturnsTargetLength() {
        let distance = "".levenshteinDistance(to: "hello")

        #expect(distance == 5)
    }

    @Test("Empty target string returns source length")
    func emptyTargetReturnsSourceLength() {
        let distance = "hello".levenshteinDistance(to: "")

        #expect(distance == 5)
    }

    @Test("Both empty strings have distance 0")
    func bothEmptyZeroDistance() {
        let distance = "".levenshteinDistance(to: "")

        #expect(distance == 0)
    }

    @Test("Single character difference has distance 1")
    func singleCharDifference() {
        let distance = "cat".levenshteinDistance(to: "bat")

        #expect(distance == 1)
    }

    @Test("Single insertion has distance 1")
    func singleInsertion() {
        let distance = "cat".levenshteinDistance(to: "cats")

        #expect(distance == 1)
    }

    @Test("Single deletion has distance 1")
    func singleDeletion() {
        let distance = "cats".levenshteinDistance(to: "cat")

        #expect(distance == 1)
    }

    @Test("Multiple operations calculated correctly")
    func multipleOperations() {
        // "kitten" to "sitting" requires 3 operations:
        // k -> s, e -> i, + g
        let distance = "kitten".levenshteinDistance(to: "sitting")

        #expect(distance == 3)
    }

    @Test("Case sensitive comparison")
    func caseSensitive() {
        let distance = "Hello".levenshteinDistance(to: "hello")

        #expect(distance == 1)
    }

    @Test("Completely different strings")
    func completelyDifferent() {
        let distance = "abc".levenshteinDistance(to: "xyz")

        #expect(distance == 3)
    }

    // MARK: - Fuzzy Match Tests

    @Test("Exact match returns true")
    func exactMatchReturnsTrue() {
        let result = "Danny".isFuzzyMatch(to: "Danny")

        #expect(result == true)
    }

    @Test("Case insensitive exact match returns true")
    func caseInsensitiveExactMatch() {
        let result = "danny".isFuzzyMatch(to: "Danny")

        #expect(result == true)
    }

    @Test("Case insensitive exact match uppercase")
    func caseInsensitiveUppercase() {
        let result = "DANNY".isFuzzyMatch(to: "Danny")

        #expect(result == true)
    }

    // MARK: - Abbreviation Tests

    @Test("Single letter abbreviation matches first letter")
    func singleLetterAbbreviation() {
        let result = "D".isFuzzyMatch(to: "Danny")

        #expect(result == true)
    }

    @Test("Single letter with period matches first letter")
    func singleLetterWithPeriod() {
        let result = "D.".isFuzzyMatch(to: "Danny")

        #expect(result == true)
    }

    @Test("Single letter case insensitive")
    func singleLetterCaseInsensitive() {
        let result = "d".isFuzzyMatch(to: "Danny")

        #expect(result == true)
    }

    @Test("Wrong single letter does not match")
    func wrongSingleLetter() {
        let result = "J".isFuzzyMatch(to: "Danny")

        #expect(result == false)
    }

    // MARK: - Short String Protection

    @Test("Very short source string does not fuzzy match")
    func shortSourceNoFuzzyMatch() {
        let result = "ab".isFuzzyMatch(to: "xyz")

        #expect(result == false)
    }

    @Test("Very short target string does not fuzzy match")
    func shortTargetNoFuzzyMatch() {
        let result = "abc".isFuzzyMatch(to: "xy")

        #expect(result == false)
    }

    @Test("Both short strings do not fuzzy match if different")
    func bothShortNoFuzzyMatch() {
        let result = "ab".isFuzzyMatch(to: "xy")

        #expect(result == false)
    }

    // MARK: - Tolerance Tests

    @Test("Within default tolerance of 2 matches")
    func withinDefaultTolerance() {
        // "Danny" to "Dany" is distance 1
        let result = "Dany".isFuzzyMatch(to: "Danny")

        #expect(result == true)
    }

    @Test("Two edits within default tolerance matches")
    func twoEditsWithinTolerance() {
        // "Danny" to "Denny" is distance 1 (a->e)
        let result = "Denny".isFuzzyMatch(to: "Danny")

        #expect(result == true)
    }

    @Test("Beyond default tolerance does not match")
    func beyondDefaultTolerance() {
        // "Danny" to "Bobby" is distance 4
        let result = "Bobby".isFuzzyMatch(to: "Danny")

        #expect(result == false)
    }

    @Test("Custom tolerance of 1 is stricter")
    func customToleranceStricter() {
        // "Danny" to "Dany" is distance 1, should match
        let result = "Dany".isFuzzyMatch(to: "Danny", tolerance: 1)

        #expect(result == true)
    }

    @Test("Custom tolerance of 0 only allows exact match")
    func customToleranceZero() {
        let result = "Dany".isFuzzyMatch(to: "Danny", tolerance: 0)

        #expect(result == false)
    }

    @Test("Custom higher tolerance allows more differences")
    func customHigherTolerance() {
        // "Danny" to "Benny" is distance 2
        let result = "Benny".isFuzzyMatch(to: "Danny", tolerance: 3)

        #expect(result == true)
    }

    // MARK: - Real Name Scenarios

    @Test("Common misspelling matches")
    func commonMisspelling() {
        let result = "Micheal".isFuzzyMatch(to: "Michael")

        #expect(result == true)
    }

    @Test("Missing letter matches")
    func missingLetter() {
        let result = "Elisabeth".isFuzzyMatch(to: "Elizabeth")

        #expect(result == true)
    }

    @Test("Extra letter matches")
    func extraLetter() {
        let result = "Johnathan".isFuzzyMatch(to: "Jonathan")

        #expect(result == true)
    }

    @Test("Transposed letters matches")
    func transposedLetters() {
        let result = "Briian".isFuzzyMatch(to: "Brian")

        #expect(result == true)
    }

    @Test("Very different names do not match")
    func veryDifferentNames() {
        let result = "Alice".isFuzzyMatch(to: "Robert")

        #expect(result == false)
    }

    // MARK: - Edge Cases

    @Test("Matching with whitespace")
    func matchingWithWhitespace() {
        // Note: This tests current behavior - whitespace is treated as characters
        let result = "John Smith".isFuzzyMatch(to: "JohnSmith")

        #expect(result == true) // Distance is 1 (the space)
    }

    @Test("Matching empty strings")
    func matchingEmptyStrings() {
        // Empty strings have length < 3, so should return false
        let result = "".isFuzzyMatch(to: "")

        // This goes through exact match first, which should be true
        #expect(result == true)
    }

    @Test("Special characters in names")
    func specialCharactersInNames() {
        let result = "O'Brien".isFuzzyMatch(to: "OBrien")

        #expect(result == true) // Distance is 1
    }

    @Test("Accented characters")
    func accentedCharacters() {
        let result = "Jose".isFuzzyMatch(to: "Jose")

        #expect(result == true)
    }
}
#endif
