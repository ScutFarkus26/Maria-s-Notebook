import CoreData
import Foundation

// MARK: - Matching rows to children

extension StudentCSVImporter {
    /// What a row is to the class: a child it updates, a new child, or one
    /// it can't be told apart from, which is left out.
    enum RowMatch {
        case existing(CDStudent)
        case new
        case possibleDuplicate
    }

    /// Fills in what `existing` is missing from row `r` (birthday, start
    /// date) and takes its level. Returns whether anything changed.
    static func apply(_ r: Row, to existing: CDStudent) -> Bool {
        var didChange = false
        if existing.birthday == nil, let b = r.birthday {
            existing.birthday = b; didChange = true
        }
        if existing.dateStarted == nil, let ds = r.dateStarted {
            existing.dateStarted = ds; didChange = true
        }
        if let lvl = r.level, existing.level != lvl {
            existing.level = lvl; didChange = true
        }
        if didChange { existing.modifiedAt = Date() }
        return didChange
    }

    /// The children a row can match: the class as it was before the import,
    /// and the ones this import has added so far.
    struct MatchIndex {
        private var byFullKey: [String: CDStudent] = [:]
        private var existingByName: [String: [CDStudent]] = [:]
        private var addedByName: [String: [CDStudent]] = [:]

        init(existing: [CDStudent]) {
            for student in existing {
                let full = StudentCSVImporter.duplicateKey(for: student)
                if byFullKey[full] == nil { byFullKey[full] = student }
                existingByName[StudentCSVImporter.nameKey(student.firstName, student.lastName), default: []]
                    .append(student)
            }
        }

        mutating func add(_ student: CDStudent) {
            let full = StudentCSVImporter.duplicateKey(for: student)
            if byFullKey[full] == nil { byFullKey[full] = student }
            addedByName[StudentCSVImporter.nameKey(student.firstName, student.lastName), default: []]
                .append(student)
        }

        func match(for row: Row) -> RowMatch {
            if row.birthday != nil,
               let student = byFullKey[StudentCSVImporter.duplicateKey(
                   first: row.firstName, last: row.lastName, birthday: row.birthday
               )] {
                return .existing(student)
            }
            let name = StudentCSVImporter.nameKey(row.firstName, row.lastName)
            // A child already in the class: the name decides only when it is
            // hers alone and no birthday disagrees; otherwise the row waits
            // for the guide rather than guessing.
            if let sameName = existingByName[name], !sameName.isEmpty {
                guard sameName.count == 1, let only = sameName.first else { return .possibleDuplicate }
                return row.birthday == nil || only.birthday == nil ? .existing(only) : .possibleDuplicate
            }
            // A child this file added: two rows with different birthdays are
            // two children (the two Sarahs), so only a missing birthday merges.
            if let sameName = addedByName[name], !sameName.isEmpty {
                if row.birthday == nil {
                    return sameName.count == 1 ? .existing(sameName[0]) : .possibleDuplicate
                }
                let undated = sameName.filter { $0.birthday == nil }
                return undated.count == 1 ? .existing(undated[0]) : .new
            }
            return .new
        }
    }
}
