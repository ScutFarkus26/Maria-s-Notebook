// ClassAreaChecklistViewModel+NameDisplay.swift
// Cached duplicate-aware name formatting for ClassAreaChecklistViewModel.

import Foundation

extension ClassAreaChecklistViewModel {

    // MARK: - Name Display Helpers

    func normalizedFirstName(_ name: String) -> String {
        name.trimmed().lowercased()
    }

    /// Keyed off the whole roster rather than the filtered columns, so a column keeps the
    /// same "Sarah B." label whether or not the other Sarah is currently filtered out.
    var duplicateFirstNameKeys: Set<String> {
        // OPTIMIZATION: Cache duplicate name computation based on student list hash
        let currentHash = rosterStudents.map(\.id).hashValue
        if lastStudentHashForDuplicates != currentHash {
            var counts: [String: Int] = [:]
            for s in rosterStudents {
                let key = normalizedFirstName(s.firstName)
                counts[key, default: 0] += 1
            }
            cachedDuplicateFirstNameKeys = Set(counts.filter { $0.value >= 2 }.map(\.key))
            lastStudentHashForDuplicates = currentHash
        }
        return cachedDuplicateFirstNameKeys
    }

    func displayName(for student: CDStudent) -> String {
        let firstTrimmed = student.firstName.trimmed()
        let key = normalizedFirstName(student.firstName)
        if duplicateFirstNameKeys.contains(key) {
            let lastInitial = student.lastName.trimmed().first.map { String($0) } ?? ""
            if lastInitial.isEmpty { return firstTrimmed }
            return "\(firstTrimmed) \(lastInitial)."
        } else {
            return firstTrimmed
        }
    }
}
