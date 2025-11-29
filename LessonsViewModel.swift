import Foundation

struct LessonsViewModel {
    // Compute ordered unique subjects using FilterOrderStore
    func subjects(from lessons: [Lesson]) -> [String] {
        let unique = Set(lessons.map { $0.subject.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        let existing = Array(unique).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return FilterOrderStore.loadSubjectOrder(existing: existing)
    }

    // Compute ordered unique groups for a given subject using FilterOrderStore
    func groups(for subject: String, lessons: [Lesson]) -> [String] {
        let trimmedSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let unique = Set(
            lessons
                .filter { $0.subject.caseInsensitiveCompare(trimmedSubject) == .orderedSame }
                .map { $0.group.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        let existing = Array(unique).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return FilterOrderStore.loadGroupOrder(for: trimmedSubject, existing: existing)
    }

    // Main filter/sort pipeline extracted from LessonsRootView
    func filteredLessons(lessons: [Lesson], searchText: String, selectedSubject: String?, selectedGroup: String?) -> [Lesson] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var base: [Lesson]
        if !query.isEmpty {
            base = lessons.filter { l in
                l.name.localizedCaseInsensitiveContains(query)
                || l.subject.localizedCaseInsensitiveContains(query)
                || l.group.localizedCaseInsensitiveContains(query)
                || l.subheading.localizedCaseInsensitiveContains(query)
                || l.writeUp.localizedCaseInsensitiveContains(query)
            }
        } else {
            base = lessons
            if let subject = selectedSubject {
                base = base.filter { $0.subject.caseInsensitiveCompare(subject) == .orderedSame }
            }
            if let group = selectedGroup {
                base = base.filter { $0.group.caseInsensitiveCompare(group) == .orderedSame }
            }
        }

        func norm(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

        // Subject index map from ordered subjects
        let subjectOrderList = subjects(from: lessons)
        let subjectIndex: [String: Int] = subjectOrderList.enumerated().reduce(into: [:]) { dict, pair in
            dict[norm(pair.element)] = pair.offset
        }

        // Cache group index maps per subject to avoid recomputing
        var groupIndexCache: [String: [String: Int]] = [:]
        func indexForGroup(_ group: String, inSubject subject: String) -> Int {
            let sKey = norm(subject)
            if groupIndexCache[sKey] == nil {
                let orderedGroups = groups(for: subject, lessons: lessons)
                let map = orderedGroups.enumerated().reduce(into: [:]) { (d: inout [String: Int], p) in
                    d[norm(p.element)] = p.offset
                }
                groupIndexCache[sKey] = map
            }
            return groupIndexCache[sKey]?[norm(group)] ?? Int.max
        }

        if !query.isEmpty {
            return base.sorted { lhs, rhs in
                let ls = subjectIndex[norm(lhs.subject)] ?? Int.max
                let rs = subjectIndex[norm(rhs.subject)] ?? Int.max
                if ls == rs {
                    let lg = indexForGroup(lhs.group, inSubject: lhs.subject)
                    let rg = indexForGroup(rhs.group, inSubject: rhs.subject)
                    if lg == rg {
                        if lhs.orderInGroup == rhs.orderInGroup {
                            let nameOrder = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                            if nameOrder == .orderedSame { return lhs.id.uuidString < rhs.id.uuidString }
                            return nameOrder == .orderedAscending
                        }
                        return lhs.orderInGroup < rhs.orderInGroup
                    }
                    return lg < rg
                }
                return ls < rs
            }
        } else if selectedGroup != nil {
            return base.sorted { lhs, rhs in
                if lhs.orderInGroup == rhs.orderInGroup {
                    let nameOrder = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                    if nameOrder == .orderedSame { return lhs.id.uuidString < rhs.id.uuidString }
                    return nameOrder == .orderedAscending
                }
                return lhs.orderInGroup < rhs.orderInGroup
            }
        } else if let subject = selectedSubject {
            return base.sorted { lhs, rhs in
                let lg = indexForGroup(lhs.group, inSubject: subject)
                let rg = indexForGroup(rhs.group, inSubject: subject)
                if lg == rg {
                    if lhs.orderInGroup == rhs.orderInGroup {
                        let nameOrder = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                        if nameOrder == .orderedSame { return lhs.id.uuidString < rhs.id.uuidString }
                        return nameOrder == .orderedAscending
                    }
                    return lhs.orderInGroup < rhs.orderInGroup
                }
                return lg < rg
            }
        } else {
            return base.sorted { lhs, rhs in
                let ls = subjectIndex[norm(lhs.subject)] ?? Int.max
                let rs = subjectIndex[norm(rhs.subject)] ?? Int.max
                if ls == rs {
                    let lg = indexForGroup(lhs.group, inSubject: lhs.subject)
                    let rg = indexForGroup(rhs.group, inSubject: rhs.subject)
                    if lg == rg {
                        if lhs.orderInGroup == rhs.orderInGroup {
                            let nameOrder = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                            if nameOrder == .orderedSame { return lhs.id.uuidString < rhs.id.uuidString }
                            return nameOrder == .orderedAscending
                        }
                        return lhs.orderInGroup < rhs.orderInGroup
                    }
                    return lg < rg
                }
                return ls < rs
            }
        }
    }

    // Ensure per-(subject, group) orderInGroup uniqueness, return true if any changes were made
    func ensureInitialOrderInGroupIfNeeded(_ lessons: [Lesson]) -> Bool {
        var changed = false
        func norm(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        var buckets: [String: [Lesson]] = [:]
        for l in lessons {
            let key = norm(l.subject) + "|" + norm(l.group)
            buckets[key, default: []].append(l)
        }

        for (_, arr) in buckets {
            guard !arr.isEmpty else { continue }
            let allZero = arr.allSatisfy { $0.orderInGroup == 0 }
            if allZero {
                let sorted = arr.sorted { lhs, rhs in
                    lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                for (idx, l) in sorted.enumerated() {
                    if l.orderInGroup != idx { l.orderInGroup = idx; changed = true }
                }
                continue
            }
            var seen = Set<Int>()
            var duplicates: [Lesson] = []
            for l in arr.sorted(by: { $0.orderInGroup < $1.orderInGroup }) {
                if seen.contains(l.orderInGroup) {
                    duplicates.append(l)
                } else {
                    seen.insert(l.orderInGroup)
                }
            }
            if !duplicates.isEmpty {
                var maxOrder = seen.max() ?? -1
                for l in duplicates {
                    maxOrder += 1
                    if l.orderInGroup != maxOrder { l.orderInGroup = maxOrder; changed = true }
                }
            }
        }

        return changed
    }
}
