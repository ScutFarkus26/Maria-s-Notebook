// LessonsViewModel.swift
// Helpers for ordering and filtering lessons by subject/group. No behavior changes.

import Foundation

/// Provides filtering and ordering utilities for Lessons screens.
/// Methods here are pure functions and do not mutate external state.
struct LessonsViewModel {
    // MARK: - Public API

    // Compute ordered unique subjects using FilterOrderStore
    func subjects(from lessons: [Lesson]) -> [String] {
        let unique = Set(lessons.map { $0.subject.trimmed() }.filter { !$0.isEmpty })
        let existing = Array(unique).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return FilterOrderStore.loadSubjectOrder(existing: existing)
    }

    // Compute ordered unique groups for a given subject using FilterOrderStore
    func groups(for subject: String, lessons: [Lesson]) -> [String] {
        let trimmedSubject = subject.trimmed()
        let unique = Set(
            lessons
                .filter { $0.subject.caseInsensitiveCompare(trimmedSubject) == .orderedSame }
                .map { $0.group.trimmed() }
                .filter { !$0.isEmpty }
        )
        let existing = Array(unique).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return FilterOrderStore.loadGroupOrder(for: trimmedSubject, existing: existing)
    }

    // MARK: - Private Helpers

    private func norm(_ s: String) -> String { s.trimmed().lowercased() }

    private func subjectIndexMap(from lessons: [Lesson]) -> [String: Int] {
        let list = subjects(from: lessons)
        return list.enumerated().reduce(into: [:]) { $0[norm($1.element)] = $1.offset }
    }

    private func groupIndex(for subject: String, lessons: [Lesson]) -> [String: Int] {
        let orderedGroups = groups(for: subject, lessons: lessons)
        return orderedGroups.enumerated().reduce(into: [:]) { (d: inout [String: Int], p) in
            d[norm(p.element)] = p.offset
        }
    }

    private func indexForGroup(_ group: String, inSubject subject: String, cache: inout [String: [String: Int]], lessons: [Lesson]) -> Int {
        let key = norm(subject)
        if cache[key] == nil { cache[key] = groupIndex(for: subject, lessons: lessons) }
        return cache[key]?[norm(group)] ?? Int.max
    }

    // MARK: - Sorting Pipelines

    // Main filter/sort pipeline extracted from LessonsRootView
    func filteredLessons(lessons: [Lesson], sourceFilter: LessonSource?, personalKindFilter: PersonalLessonKind?, searchText: String, selectedSubject: String?, selectedGroup: String?) -> [Lesson] {
        let query = searchText.trimmed()
        var scoped = lessons
        
        // Only apply scope filters if NOT searching. Search should be global ("Search all lessons").
        if query.isEmpty {
            if let sourceFilter {
                scoped = scoped.filter { $0.source == sourceFilter }
            }
            if (sourceFilter == .personal) || (sourceFilter == nil) {
                if let kind = personalKindFilter {
                    scoped = scoped.filter { $0.source == .personal && $0.personalKind == kind }
                }
            }
        }

        var base: [Lesson]
        if !query.isEmpty {
            base = scoped.filter { l in
                l.name.localizedCaseInsensitiveContains(query)
                || l.subject.localizedCaseInsensitiveContains(query)
                || l.group.localizedCaseInsensitiveContains(query)
                || l.subheading.localizedCaseInsensitiveContains(query)
                || l.writeUp.localizedCaseInsensitiveContains(query)
            }
        } else {
            base = scoped
            if let subject = selectedSubject {
                base = base.filter { $0.subject.caseInsensitiveCompare(subject) == .orderedSame }
            }
            if let group = selectedGroup {
                base = base.filter { $0.group.caseInsensitiveCompare(group) == .orderedSame }
            }
        }

        let subjectIndex = subjectIndexMap(from: scoped)
        var groupIndexCache: [String: [String: Int]] = [:]

        if !query.isEmpty {
            return base.sorted { lhs, rhs in
                let ls = subjectIndex[norm(lhs.subject)] ?? Int.max
                let rs = subjectIndex[norm(rhs.subject)] ?? Int.max
                if ls == rs {
                    let lg = indexForGroup(lhs.group, inSubject: lhs.subject, cache: &groupIndexCache, lessons: scoped)
                    let rg = indexForGroup(rhs.group, inSubject: rhs.subject, cache: &groupIndexCache, lessons: scoped)
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
                let lg = indexForGroup(lhs.group, inSubject: subject, cache: &groupIndexCache, lessons: scoped)
                let rg = indexForGroup(rhs.group, inSubject: subject, cache: &groupIndexCache, lessons: scoped)
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
                    let lg = indexForGroup(lhs.group, inSubject: lhs.subject, cache: &groupIndexCache, lessons: scoped)
                    let rg = indexForGroup(rhs.group, inSubject: rhs.subject, cache: &groupIndexCache, lessons: scoped)
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

    // MARK: - Data Maintenance

    // Ensure per-(subject, group) orderInGroup uniqueness, return true if any changes were made
    func ensureInitialOrderInGroupIfNeeded(_ lessons: [Lesson]) -> Bool {
        var changed = false
        func norm(_ s: String) -> String { s.trimmed().lowercased() }
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
