import Foundation

extension String {
    /// Everyday short words that sit within a letter or two of a child's name
    /// ("and" ~ Ana, "was" ~ Max, "the" ~ Theo). Never a fuzzy name match.
    nonisolated private static let commonShortWords: Set<String> = [
        "add", "ago", "all", "and", "any", "are", "art", "ask", "ate", "bad", "bag", "bed", "big", "box",
        "boy", "but", "can", "car", "cat", "cut", "day", "did", "dog", "end", "far", "few", "for", "fun",
        "got", "had", "has", "her", "him", "his", "hot", "how", "its", "job", "let", "lot", "man", "map",
        "may", "men", "mix", "new", "not", "now", "odd", "off", "old", "one", "our", "out", "own", "pen",
        "put", "ran", "red", "run", "sad", "sat", "saw", "say", "see", "set", "she", "sit", "six", "sun",
        "ten", "the", "too", "top", "try", "two", "use", "was", "way", "who", "why", "won", "yes", "yet",
        "you", "also", "away", "back", "been", "book", "came", "come", "does", "done", "down", "each",
        "even", "felt", "from", "gave", "give", "good", "hard", "have", "help", "here", "into", "just",
        "kind", "know", "like", "made", "make", "many", "more", "most", "much", "must", "name", "next",
        "only", "over", "read", "said", "same", "some", "such", "sure", "take", "than", "that", "them",
        "then", "they", "this", "time", "told", "very", "want", "well", "went", "were", "what", "when",
        "will", "with", "word", "work", "year", "your"
    ]

    /// Calculates the Levenshtein distance to another string.
    nonisolated func levenshteinDistance(to destination: String) -> Int {
        let sCount = self.count
        let dCount = destination.count
        if sCount == 0 { return dCount }
        if dCount == 0 { return sCount }

        var matrix = [[Int]](repeating: [Int](repeating: 0, count: dCount + 1), count: sCount + 1)
        for i in 0...sCount { matrix[i][0] = i }
        for j in 0...dCount { matrix[0][j] = j }

        for i in 1...sCount {
            for j in 1...dCount {
                let sIndex = self.index(self.startIndex, offsetBy: i - 1)
                let dIndex = destination.index(destination.startIndex, offsetBy: j - 1)
                let cost = self[sIndex] == destination[dIndex] ? 0 : 1
                matrix[i][j] = Swift.min(
                    matrix[i - 1][j] + 1,
                    matrix[i][j - 1] + 1,
                    matrix[i - 1][j - 1] + cost
                )
            }
        }
        return matrix[sCount][dCount]
    }

    /// Checks if a string is a "fuzzy match" to a target name. Case and accents
    /// don't count ("zoe" matches "Zoë").
    nonisolated func isFuzzyMatch(to target: String, tolerance: Int = 2) -> Bool {
        let foldedSelf = self.folded()
        let foldedTarget = target.folded()

        // 1. Exact match
        if foldedSelf == foldedTarget { return true }

        // 2. Abbreviation check (e.g., "D." matching "Danny"). It needs the period:
        //    a lone letter is a word ("a", "I"), not an abbreviation.
        let cleanedSelf = foldedSelf.replacingOccurrences(of: ".", with: "")
        if cleanedSelf.count == 1, cleanedSelf != foldedSelf, foldedTarget.hasPrefix(cleanedSelf) {
            return true
        }

        // 3. Length check: Don't fuzzy match very short strings unless very close
        if self.count < 3 || target.count < 3 { return false }

        // 4. Everyday short words are never a name, however close
        if Self.commonShortWords.contains(foldedSelf) { return false }

        // 5. Calculate distance. The allowance grows with the longer word: none at
        //    three letters ("fan" isn't Ian, "leg" isn't Leo), one at four or five
        //    ("Mya" ~ Maya), the full tolerance above that.
        let length = Swift.max(foldedSelf.count, foldedTarget.count)
        let allowance = length <= 3 ? 0 : (length <= 5 ? Swift.min(tolerance, 1) : tolerance)
        return foldedSelf.levenshteinDistance(to: foldedTarget) <= allowance
    }
}
