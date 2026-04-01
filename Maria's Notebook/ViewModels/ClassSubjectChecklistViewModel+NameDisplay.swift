// ClassSubjectChecklistViewModel+NameDisplay.swift
// Cached duplicate-aware name formatting for ClassSubjectChecklistViewModel.

import Foundation

extension ClassSubjectChecklistViewModel {

    // MARK: - Name Display Helpers

    func normalizedFirstName(_ name: String) -> String {
        name.trimmed().lowercased()
    }

    var duplicateFirstNameKeys: Set<String> {
        // OPTIMIZATION: Cache duplicate name computation based on student list hash
        let currentHash = students.map(\.id).hashValue
        if lastStudentHashForDuplicates != currentHash {
            var counts: [String: Int] = [:]
            for s in students {
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
