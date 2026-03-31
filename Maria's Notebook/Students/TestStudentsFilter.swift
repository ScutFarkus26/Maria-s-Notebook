import Foundation

/// Centralized helper to hide configured Test Students across the app.
/// Uses the preferences General.showTestStudents (Bool) and General.testStudentNames (String)
/// to decide whether and which students to hide. Matching is case-insensitive on fullName.
enum TestStudentsFilter {
    static let showKey = "General.showTestStudents"
    static let namesKey = "General.testStudentNames"

    /// Returns a normalized set of hidden full names (lowercased, trimmed).
    /// If `show` is true, returns an empty set (no hiding). If nil, reads from UserDefaults.
    static func normalizedHiddenNames(show: Bool? = nil, namesRaw: String? = nil) -> Set<String> {
        let defaults = UserDefaults.standard
        let showValue = show ?? defaults.bool(forKey: showKey)
        guard showValue == false else { return [] }
        let raw = namesRaw ?? (defaults.string(forKey: namesKey) ?? "Danny De Berry,Lil Dan D")
        let lower = raw.lowercased()
        let parts = lower.split(whereSeparator: { ch in ch == "," || ch == ";" || ch.isNewline })
        let tokens = parts.map { String($0).trimmed() }.filter { !$0.isEmpty }
        return Set(tokens)
    }

    /// Returns true if the given student should be hidden.
    static func isHidden(_ student: Student, show: Bool? = nil, namesRaw: String? = nil) -> Bool {
        let set = normalizedHiddenNames(show: show, namesRaw: namesRaw)
        guard !set.isEmpty else { return false }
        let name = student.fullName.normalizedForComparison()
        return set.contains(name)
    }

    /// Filters out hidden students from the provided list.
    static func filterVisible(_ students: [Student], show: Bool? = nil, namesRaw: String? = nil) -> [Student] {
        let set = normalizedHiddenNames(show: show, namesRaw: namesRaw)
        guard !set.isEmpty else { return students }
        return students.filter { s in
            let name = s.fullName.normalizedForComparison()
            return !set.contains(name)
        }
    }

    /// Computes the IDs of hidden students from the provided list.
    static func hiddenIDs(from students: [Student], show: Bool? = nil, namesRaw: String? = nil) -> Set<UUID> {
        let set = normalizedHiddenNames(show: show, namesRaw: namesRaw)
        guard !set.isEmpty else { return [] }
        return Set(students.compactMap { s in
            let name = s.fullName.normalizedForComparison()
            return set.contains(name) ? s.id : nil
        })
    }

    // MARK: - Core Data Overloads

    /// Returns true if the given CD student should be hidden.
    static func isHidden(_ student: CDStudent, show: Bool? = nil, namesRaw: String? = nil) -> Bool {
        let set = normalizedHiddenNames(show: show, namesRaw: namesRaw)
        guard !set.isEmpty else { return false }
        let name = student.fullName.normalizedForComparison()
        return set.contains(name)
    }

    /// Filters out hidden students from the provided CD list.
    static func filterVisible(_ students: [CDStudent], show: Bool? = nil, namesRaw: String? = nil) -> [CDStudent] {
        let set = normalizedHiddenNames(show: show, namesRaw: namesRaw)
        guard !set.isEmpty else { return students }
        return students.filter { s in
            let name = s.fullName.normalizedForComparison()
            return !set.contains(name)
        }
    }

    /// Computes the IDs of hidden students from the provided CD list.
    static func hiddenIDs(from students: [CDStudent], show: Bool? = nil, namesRaw: String? = nil) -> Set<UUID> {
        let set = normalizedHiddenNames(show: show, namesRaw: namesRaw)
        guard !set.isEmpty else { return [] }
        return Set(students.compactMap { s in
            let name = s.fullName.normalizedForComparison()
            return set.contains(name) ? s.id : nil
        })
    }
}
