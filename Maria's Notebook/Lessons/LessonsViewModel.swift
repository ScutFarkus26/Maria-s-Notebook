// LessonsViewModel.swift
// Helpers for ordering and filtering lessons by subject/group. No behavior changes.

import Foundation
import SwiftData

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

    // MARK: - Predicate Building
    
    /// Builds a SwiftData predicate for filtering lessons based on source, personalKind, subject, and group.
    /// Note: Search text filtering is done in-memory as SwiftData predicates don't support string contains operations well.
    func buildLessonPredicate(
        sourceFilter: LessonSource?,
        personalKindFilter: PersonalLessonKind?,
        selectedSubject: String?,
        selectedGroup: String?,
        searchText: String
    ) -> Predicate<Lesson>? {
        let query = searchText.trimmed()
        
        // If searching, don't apply scope filters (search is global)
        // We'll filter by search text in-memory after fetch
        guard query.isEmpty else {
            // For search, we can still apply source/personalKind filters if they exist
            // But subject/group filters are ignored during search
            return buildSourceAndKindPredicate(sourceFilter: sourceFilter, personalKindFilter: personalKindFilter)
        }
        
        // Extract raw values before creating predicate (predicates can't access enum cases directly)
        let sourceFilterRaw = sourceFilter?.rawValue
        let personalKindFilterRaw = personalKindFilter?.rawValue
        let personalRawValue = "personal" // LessonSource.personal.rawValue
        let personalKindPersonalRaw = "personal" // PersonalLessonKind.personal.rawValue
        let trimmedSubject = selectedSubject?.trimmed()
        let trimmedGroup = selectedGroup?.trimmed()
        let hasSubject = trimmedSubject.map { !$0.isEmpty } ?? false
        let hasGroup = trimmedGroup.map { !$0.isEmpty } ?? false
        let isPersonalSourceFilter = sourceFilter == .personal || sourceFilter == nil
        let hasPersonalKindFilter = personalKindFilterRaw != nil && isPersonalSourceFilter
        
        // Build combined predicate for non-search case
        // Combine all conditions in a single expression using && operators
        return #Predicate<Lesson> { lesson in
            // Source filter: if sourceFilterRaw is nil, match all; otherwise match the raw value
            (sourceFilterRaw == nil || lesson.sourceRaw == sourceFilterRaw!) &&
            // PersonalKind filter: if no filter or not personal source, always match; otherwise check personal kind
            (!hasPersonalKindFilter || (lesson.sourceRaw == personalRawValue && (lesson.personalKindRaw == personalKindFilterRaw || (lesson.personalKindRaw == nil && personalKindFilterRaw == personalKindPersonalRaw)))) &&
            // Subject filter: if no subject filter, match all; otherwise match the subject
            (!hasSubject || lesson.subject == trimmedSubject!) &&
            // Group filter: if no group filter, match all; otherwise match the group
            (!hasGroup || lesson.group == trimmedGroup!)
        }
    }
    
    /// Builds a predicate for source and personalKind only (used during search)
    private func buildSourceAndKindPredicate(
        sourceFilter: LessonSource?,
        personalKindFilter: PersonalLessonKind?
    ) -> Predicate<Lesson>? {
        // Extract raw values before creating predicate (predicates can't access enum cases directly)
        let personalRawValue = "personal" // LessonSource.personal.rawValue
        let personalKindPersonalRaw = "personal" // PersonalLessonKind.personal.rawValue
        
        guard let sourceFilter = sourceFilter else {
            if let personalKindFilterRaw = personalKindFilter?.rawValue {
                return #Predicate<Lesson> {
                    $0.sourceRaw == personalRawValue &&
                    ($0.personalKindRaw == personalKindFilterRaw || ($0.personalKindRaw == nil && personalKindFilterRaw == personalKindPersonalRaw))
                }
            }
            return nil
        }
        
        let sourceFilterRaw = sourceFilter.rawValue
        let isPersonalSourceFilter = sourceFilter == .personal
        
        if let personalKindFilterRaw = personalKindFilter?.rawValue, isPersonalSourceFilter {
            return #Predicate<Lesson> {
                $0.sourceRaw == personalRawValue &&
                ($0.personalKindRaw == personalKindFilterRaw || ($0.personalKindRaw == nil && personalKindFilterRaw == personalKindPersonalRaw))
            }
        }
        
        return #Predicate<Lesson> { $0.sourceRaw == sourceFilterRaw }
    }

    // MARK: - Sorting Pipelines

    // Main filter/sort pipeline using SwiftData predicates for database-level filtering
    func filteredLessons(
        modelContext: ModelContext,
        sourceFilter: LessonSource?,
        personalKindFilter: PersonalLessonKind?,
        searchText: String,
        selectedSubject: String?,
        selectedGroup: String?
    ) -> [Lesson] {
        let query = searchText.trimmed()
        
        // Build predicate for database-level filtering
        let predicate = buildLessonPredicate(
            sourceFilter: sourceFilter,
            personalKindFilter: personalKindFilter,
            selectedSubject: selectedSubject,
            selectedGroup: selectedGroup,
            searchText: searchText
        )
        
        // Build sort descriptors for database-level sorting
        // Note: Complex custom ordering (subject/group indices) still requires in-memory sorting
        let sortDescriptors: [SortDescriptor<Lesson>] = {
            if selectedGroup != nil {
                // When a group is selected, sort by orderInGroup, then name
                return [
                    SortDescriptor(\.orderInGroup),
                    SortDescriptor(\.name)
                ]
            } else {
                // Default: sort by subject, group, orderInGroup, then name
                // This provides a basic database-level sort, but we'll refine with custom ordering in-memory
                return [
                    SortDescriptor(\.subject),
                    SortDescriptor(\.group),
                    SortDescriptor(\.orderInGroup),
                    SortDescriptor(\.name)
                ]
            }
        }()
        
        // Execute fetch with predicate and sort descriptors
        var descriptor = FetchDescriptor<Lesson>()
        if let predicate = predicate {
            descriptor.predicate = predicate
        }
        descriptor.sortBy = sortDescriptors
        
        var fetched = modelContext.safeFetch(descriptor)
        
        // Apply in-memory filters that can't be done in predicates:
        // 1. Case-insensitive subject/group matching (predicates are case-sensitive)
        if let subject = selectedSubject?.trimmed(), !subject.isEmpty, query.isEmpty {
            fetched = fetched.filter { $0.subject.caseInsensitiveCompare(subject) == .orderedSame }
        }
        if let group = selectedGroup?.trimmed(), !group.isEmpty, query.isEmpty {
            fetched = fetched.filter { $0.group.caseInsensitiveCompare(group) == .orderedSame }
        }
        
        // 2. Search text filtering (SwiftData predicates don't support string contains well)
        if !query.isEmpty {
            fetched = fetched.filter { l in
                l.name.localizedCaseInsensitiveContains(query)
                || l.subject.localizedCaseInsensitiveContains(query)
                || l.group.localizedCaseInsensitiveContains(query)
                || l.subheading.localizedCaseInsensitiveContains(query)
                || l.writeUp.localizedCaseInsensitiveContains(query)
            }
        }
        
        // Get scoped lessons for custom ordering (needed for subject/group index maps)
        // We need all lessons matching the source/personalKind filters for ordering context
        let scopedPredicate = buildSourceAndKindPredicate(
            sourceFilter: sourceFilter,
            personalKindFilter: personalKindFilter
        )
        var scopedDescriptor = FetchDescriptor<Lesson>()
        if let scopedPredicate = scopedPredicate {
            scopedDescriptor.predicate = scopedPredicate
        }
        let scoped = modelContext.safeFetch(scopedDescriptor)
        
        let subjectIndex = subjectIndexMap(from: scoped)
        var groupIndexCache: [String: [String: Int]] = [:]

        // Apply in-memory sorting with custom ordering logic
        if !query.isEmpty {
            return fetched.sorted { lhs, rhs in
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
            // Already sorted by database (orderInGroup, name), but refine with custom name comparison
            return fetched.sorted { lhs, rhs in
                if lhs.orderInGroup == rhs.orderInGroup {
                    let nameOrder = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                    if nameOrder == .orderedSame { return lhs.id.uuidString < rhs.id.uuidString }
                    return nameOrder == .orderedAscending
                }
                return lhs.orderInGroup < rhs.orderInGroup
            }
        } else if let subject = selectedSubject {
            return fetched.sorted { lhs, rhs in
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
            return fetched.sorted { lhs, rhs in
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
