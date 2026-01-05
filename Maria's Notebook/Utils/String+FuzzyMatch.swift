import Foundation

extension String {
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
    
    /// Checks if a string is a "fuzzy match" to a target name.
    nonisolated func isFuzzyMatch(to target: String, tolerance: Int = 2) -> Bool {
        // 1. Exact match
        if self.localizedCaseInsensitiveCompare(target) == .orderedSame { return true }
        
        // 2. Abbreviation check (e.g., "D." matching "Danny")
        let cleanedSelf = self.replacingOccurrences(of: ".", with: "")
        if cleanedSelf.count == 1, target.lowercased().hasPrefix(cleanedSelf.lowercased()) {
            return true
        }

        // 3. Length check: Don't fuzzy match very short strings unless very close
        if self.count < 3 || target.count < 3 { return false }
        
        // 4. Calculate distance
        return self.lowercased().levenshteinDistance(to: target.lowercased()) <= tolerance
    }
}


