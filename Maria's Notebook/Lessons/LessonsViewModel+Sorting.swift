// Maria's Notebook/Lessons/LessonsViewModel+Sorting.swift

import Foundation
import CoreData

// MARK: - Sorting Pipelines

extension LessonsViewModel {

    /// Canonical name-then-id tiebreaker used across all lesson sort paths.
    static func lessonNameOrder(_ lhs: CDLesson, _ rhs: CDLesson) -> Bool {
        let cmp = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        return cmp == .orderedSame ? (lhs.id?.uuidString ?? "") < (rhs.id?.uuidString ?? "") : cmp == .orderedAscending
    }

    // swiftlint:disable:next function_parameter_count
    func filteredLessons(
        viewContext: NSManagedObjectContext,
        sourceFilter: LessonSource?,
        personalKindFilter: PersonalLessonKind?,
        formatFilter: LessonFormat? = nil,
        searchText: String,
        selectedSubject: String?,
        selectedGroup: String?,
        allLessons: [CDLesson]? = nil
    ) -> [CDLesson] {
        let query = searchText.trimmed()
        let predicate = buildLessonPredicate(
            sourceFilter: sourceFilter, personalKindFilter: personalKindFilter,
            formatFilter: formatFilter,
            selectedSubject: selectedSubject, selectedGroup: selectedGroup, searchText: searchText
        )
        let descriptor = NSFetchRequest<CDLesson>(entityName: "Lesson")
        if let predicate { descriptor.predicate = predicate }
        descriptor.sortDescriptors = lessonSortDescriptors(selectedGroup: selectedGroup, selectedSubject: selectedSubject)

        var fetched = viewContext.safeFetch(descriptor)
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
            personalKindFilter: personalKindFilter, viewContext: viewContext
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

    func lessonSortDescriptors(selectedGroup: String?, selectedSubject: String?) -> [NSSortDescriptor] {
        if selectedGroup != nil { return [NSSortDescriptor(key: "orderInGroup", ascending: true), NSSortDescriptor(key: "name", ascending: true)] }
        if selectedSubject != nil { return [NSSortDescriptor(key: "sortIndex", ascending: true), NSSortDescriptor(key: "name", ascending: true)] }
        return [NSSortDescriptor(key: "subject", ascending: true), NSSortDescriptor(key: "sortIndex", ascending: true), NSSortDescriptor(key: "name", ascending: true)]
    }

    // MARK: - Scoping & Caching

    func scopedLessonsForOrdering(
        allLessons: [CDLesson]?,
        sourceFilter: LessonSource?,
        personalKindFilter: PersonalLessonKind?,
        viewContext: NSManagedObjectContext
    ) -> [CDLesson] {
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
        let scopedDescriptor = NSFetchRequest<CDLesson>(entityName: "Lesson")
        if let scopedPredicate { scopedDescriptor.predicate = scopedPredicate }
        return viewContext.safeFetch(scopedDescriptor)
    }

    func buildGroupIndexCache(for subjects: Set<String>, from scoped: [CDLesson]) -> [String: [String: Int]] {
        var cache: [String: [String: Int]] = [:]
        for subject in subjects where cache[subject] == nil {
            if let original = scoped.first(where: { norm($0.subject) == subject })?.subject {
                cache[subject] = groupIndex(for: original, lessons: scoped)
            }
        }
        return cache
    }

    func sortBySubjectGroupOrder(
        _ lessons: [CDLesson],
        subjectIndex: [String: Int],
        groupIndexCache: [String: [String: Int]]
    ) -> [CDLesson] {
        let keyed = lessons.map { lesson -> (CDLesson, LessonSortKey) in
            let si = subjectIndex[norm(lesson.subject)] ?? Int.max
            let gi = groupIndexCache[norm(lesson.subject)]?[norm(lesson.group)] ?? Int.max
            let key = LessonSortKey(
                subjectIdx: si, groupIdx: gi, orderInGroup: lesson.orderInGroup,
                name: lesson.name, id: lesson.id?.uuidString ?? ""
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
