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
        selectedArea: String?,
        selectedSequence: String?,
        allLessons: [CDLesson]? = nil
    ) -> [CDLesson] {
        let query = searchText.trimmed()
        let predicate = buildLessonPredicate(
            sourceFilter: sourceFilter, personalKindFilter: personalKindFilter,
            formatFilter: formatFilter,
            selectedArea: selectedArea, selectedSequence: selectedSequence, searchText: searchText
        )
        let descriptor = NSFetchRequest<CDLesson>(entityName: "Lesson")
        if let predicate { descriptor.predicate = predicate }
        descriptor.sortDescriptors = lessonSortDescriptors(selectedSequence: selectedSequence, selectedArea: selectedArea)

        var fetched = viewContext.safeFetch(descriptor)
        if let area = selectedArea?.trimmed(), !area.isEmpty, query.isEmpty {
            fetched = fetched.filter { $0.area.trimmed().caseInsensitiveCompare(area) == .orderedSame }
        }
        if let sequence = selectedSequence?.trimmed(), !sequence.isEmpty, query.isEmpty {
            fetched = fetched.filter { $0.sequence.trimmed().caseInsensitiveCompare(sequence) == .orderedSame }
        }
        if let formatFilter {
            fetched = fetched.filter { $0.lessonFormat == formatFilter }
        }
        if !query.isEmpty {
            fetched = fetched.filter { l in
                l.name.localizedCaseInsensitiveContains(query)
                || l.area.localizedCaseInsensitiveContains(query)
                || l.sequence.localizedCaseInsensitiveContains(query)
                || l.section.localizedCaseInsensitiveContains(query)
                || l.writeUp.localizedCaseInsensitiveContains(query)
            }
        }

        let scoped = scopedLessonsForOrdering(
            allLessons: allLessons, sourceFilter: sourceFilter,
            personalKindFilter: personalKindFilter, viewContext: viewContext
        )
        let areaIndex = areaIndexMap(from: scoped)
        let sequenceIdxCache = buildSequenceIndexCache(for: Set(fetched.map { norm($0.area) }), from: scoped)

        if !query.isEmpty || selectedSequence == nil && selectedArea == nil {
            return sortByAreaSequenceOrder(fetched, areaIndex: areaIndex, sequenceIndexCache: sequenceIdxCache)
        } else if selectedSequence != nil {
            return fetched.sorted { lhs, rhs in
                if lhs.orderInSequence == rhs.orderInSequence {
                    return Self.lessonNameOrder(lhs, rhs)
                }
                return lhs.orderInSequence < rhs.orderInSequence
            }
        } else {
            return fetched.sorted { lhs, rhs in
                if lhs.sortIndex != rhs.sortIndex { return lhs.sortIndex < rhs.sortIndex }
                if lhs.orderInSequence != rhs.orderInSequence { return lhs.orderInSequence < rhs.orderInSequence }
                return Self.lessonNameOrder(lhs, rhs)
            }
        }
    }

    // MARK: - Sort Descriptors

    func lessonSortDescriptors(selectedSequence: String?, selectedArea: String?) -> [NSSortDescriptor] {
        if selectedSequence != nil { return [NSSortDescriptor(key: "orderInSequence", ascending: true), NSSortDescriptor(key: "name", ascending: true)] }
        if selectedArea != nil { return [NSSortDescriptor(key: "sortIndex", ascending: true), NSSortDescriptor(key: "name", ascending: true)] }
        return [NSSortDescriptor(key: "area", ascending: true), NSSortDescriptor(key: "sortIndex", ascending: true), NSSortDescriptor(key: "name", ascending: true)]
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

    func buildSequenceIndexCache(for areas: Set<String>, from scoped: [CDLesson]) -> [String: [String: Int]] {
        var cache: [String: [String: Int]] = [:]
        for area in areas where cache[area] == nil {
            if let original = scoped.first(where: { norm($0.area) == area })?.area {
                cache[area] = sequenceIndex(for: original, lessons: scoped)
            }
        }
        return cache
    }

    func sortByAreaSequenceOrder(
        _ lessons: [CDLesson],
        areaIndex: [String: Int],
        sequenceIndexCache: [String: [String: Int]]
    ) -> [CDLesson] {
        let keyed = lessons.map { lesson -> (CDLesson, LessonSortKey) in
            let si = areaIndex[norm(lesson.area)] ?? Int.max
            let gi = sequenceIndexCache[norm(lesson.area)]?[norm(lesson.sequence)] ?? Int.max
            let key = LessonSortKey(
                areaIdx: si, groupIdx: gi, orderInSequence: lesson.orderInSequence,
                name: lesson.name, id: lesson.id?.uuidString ?? ""
            )
            return (lesson, key)
        }
        return keyed.sorted { lhs, rhs in
            let (_, l) = lhs; let (_, r) = rhs
            if l.areaIdx != r.areaIdx { return l.areaIdx < r.areaIdx }
            if l.groupIdx != r.groupIdx { return l.groupIdx < r.groupIdx }
            if l.orderInSequence != r.orderInSequence { return l.orderInSequence < r.orderInSequence }
            let n = l.name.localizedCaseInsensitiveCompare(r.name)
            return n == .orderedSame ? l.id < r.id : n == .orderedAscending
        }.map { $0.0 }
    }
}
