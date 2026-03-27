// Maria's Notebook/Lessons/LessonsViewModel+Sorting.swift

import Foundation
import SwiftData

// MARK: - Sorting Pipelines

extension LessonsViewModel {

    /// Canonical name-then-id tiebreaker used across all lesson sort paths.
    static func lessonNameOrder(_ lhs: Lesson, _ rhs: Lesson) -> Bool {
        let cmp = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        return cmp == .orderedSame ? lhs.id.uuidString < rhs.id.uuidString : cmp == .orderedAscending
    }

    // swiftlint:disable:next function_parameter_count
    func filteredLessons(
        modelContext: ModelContext,
        sourceFilter: LessonSource?,
        personalKindFilter: PersonalLessonKind?,
        formatFilter: LessonFormat? = nil,
        searchText: String,
        selectedSubject: String?,
        selectedGroup: String?,
        allLessons: [Lesson]? = nil
    ) -> [Lesson] {
        let query = searchText.trimmed()
        let predicate = buildLessonPredicate(
            sourceFilter: sourceFilter, personalKindFilter: personalKindFilter,
            formatFilter: formatFilter,
            selectedSubject: selectedSubject, selectedGroup: selectedGroup, searchText: searchText
        )
        var descriptor = FetchDescriptor<Lesson>()
        if let predicate { descriptor.predicate = predicate }
        descriptor.sortBy = lessonSortDescriptors(selectedGroup: selectedGroup, selectedSubject: selectedSubject)

        var fetched = modelContext.safeFetch(descriptor)
        if let subject = selectedSubject?.trimmed(), !subject.isEmpty, query.isEmpty {
            fetched = fetched.filter { $0.subject.trimmed().caseInsensitiveCompare(subject) == .orderedSame }
        }
        if let group = selectedGroup?.trimmed(), !group.isEmpty, query.isEmpty {
            fetched = fetched.filter { $0.group.trimmed().caseInsensitiveCompare(group) == .orderedSame }
        }
        if let formatFilter {
            fetched = fetched.filter { $0.lessonFormat == formatFilter }
        }
        if !query.isEmpty {
            fetched = fetched.filter { l in
                l.name.localizedCaseInsensitiveContains(query)
                || l.subject.localizedCaseInsensitiveContains(query)
                || l.group.localizedCaseInsensitiveContains(query)
                || l.subheading.localizedCaseInsensitiveContains(query)
                || l.writeUp.localizedCaseInsensitiveContains(query)
            }
        }

        let scoped = scopedLessonsForOrdering(
            allLessons: allLessons, sourceFilter: sourceFilter,
            personalKindFilter: personalKindFilter, modelContext: modelContext
        )
        let subjectIndex = subjectIndexMap(from: scoped)
        let groupIdxCache = buildGroupIndexCache(for: Set(fetched.map { norm($0.subject) }), from: scoped)

        if !query.isEmpty || selectedGroup == nil && selectedSubject == nil {
            return sortBySubjectGroupOrder(fetched, subjectIndex: subjectIndex, groupIndexCache: groupIdxCache)
        } else if selectedGroup != nil {
            return fetched.sorted { lhs, rhs in
                if lhs.orderInGroup == rhs.orderInGroup {
                    return Self.lessonNameOrder(lhs, rhs)
                }
                return lhs.orderInGroup < rhs.orderInGroup
            }
        } else {
            return fetched.sorted { lhs, rhs in
                if lhs.sortIndex != rhs.sortIndex { return lhs.sortIndex < rhs.sortIndex }
                if lhs.orderInGroup != rhs.orderInGroup { return lhs.orderInGroup < rhs.orderInGroup }
                return Self.lessonNameOrder(lhs, rhs)
            }
        }
    }

    // MARK: - Sort Descriptors

    func lessonSortDescriptors(selectedGroup: String?, selectedSubject: String?) -> [SortDescriptor<Lesson>] {
        if selectedGroup != nil { return [SortDescriptor(\.orderInGroup), SortDescriptor(\.name)] }
        if selectedSubject != nil { return [SortDescriptor(\.sortIndex), SortDescriptor(\.name)] }
        return [SortDescriptor(\.subject), SortDescriptor(\.sortIndex), SortDescriptor(\.name)]
    }

    // MARK: - Scoping & Caching

    func scopedLessonsForOrdering(
        allLessons: [Lesson]?,
        sourceFilter: LessonSource?,
        personalKindFilter: PersonalLessonKind?,
        modelContext: ModelContext
    ) -> [Lesson] {
        if let allLessons {
            guard sourceFilter != nil || personalKindFilter != nil else { return allLessons }
            return allLessons.filter { lesson in
                if let sf = sourceFilter, lesson.source != sf { return false }
                if let pkf = personalKindFilter, lesson.personalKind != pkf { return false }
                return true
            }
        }
        let scopedPredicate = buildSourceAndKindPredicate(
            sourceFilter: sourceFilter, personalKindFilter: personalKindFilter
        )
        var scopedDescriptor = FetchDescriptor<Lesson>()
        if let scopedPredicate { scopedDescriptor.predicate = scopedPredicate }
        return modelContext.safeFetch(scopedDescriptor)
    }

    func buildGroupIndexCache(for subjects: Set<String>, from scoped: [Lesson]) -> [String: [String: Int]] {
        var cache: [String: [String: Int]] = [:]
        for subject in subjects where cache[subject] == nil {
            if let original = scoped.first(where: { norm($0.subject) == subject })?.subject {
                cache[subject] = groupIndex(for: original, lessons: scoped)
            }
        }
        return cache
    }

    func sortBySubjectGroupOrder(
        _ lessons: [Lesson],
        subjectIndex: [String: Int],
        groupIndexCache: [String: [String: Int]]
    ) -> [Lesson] {
        let keyed = lessons.map { lesson -> (Lesson, LessonSortKey) in
            let si = subjectIndex[norm(lesson.subject)] ?? Int.max
            let gi = groupIndexCache[norm(lesson.subject)]?[norm(lesson.group)] ?? Int.max
            let key = LessonSortKey(
                subjectIdx: si, groupIdx: gi, orderInGroup: lesson.orderInGroup,
                name: lesson.name, id: lesson.id.uuidString
            )
            return (lesson, key)
        }
        return keyed.sorted { lhs, rhs in
            let (_, l) = lhs; let (_, r) = rhs
            if l.subjectIdx != r.subjectIdx { return l.subjectIdx < r.subjectIdx }
            if l.groupIdx != r.groupIdx { return l.groupIdx < r.groupIdx }
            if l.orderInGroup != r.orderInGroup { return l.orderInGroup < r.orderInGroup }
            let n = l.name.localizedCaseInsensitiveCompare(r.name)
            return n == .orderedSame ? l.id < r.id : n == .orderedAscending
        }.map { $0.0 }
    }
}
