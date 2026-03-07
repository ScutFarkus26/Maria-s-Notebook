// Maria's Notebook/Lessons/LessonsViewModel.swift
// swiftlint:disable file_length

import Foundation
import OSLog
import SwiftData

/// Provides filtering and ordering utilities for Lessons screens.
/// Methods here are pure functions and do not mutate external state.
@MainActor
// swiftlint:disable:next type_body_length
struct LessonsViewModel {
    private static let logger = Logger.lessons
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
                // FIX: Trim lesson subject before comparing to ensure "Math " matches "Math"
                .filter { $0.subject.trimmed().caseInsensitiveCompare(trimmedSubject) == .orderedSame }
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

    private func indexForGroup(
        _ group: String,
        inSubject subject: String,
        cache: inout [String: [String: Int]],
        lessons: [Lesson]
    ) -> Int {
        let key = norm(subject)
        if cache[key] == nil { cache[key] = groupIndex(for: subject, lessons: lessons) }
        return cache[key]?[norm(group)] ?? Int.max
    }

    // MARK: - Predicate Building
    
    func buildLessonPredicate(
        sourceFilter: LessonSource?,
        personalKindFilter: PersonalLessonKind?,
        selectedSubject: String?,
        selectedGroup: String?,
        searchText: String
    ) -> Predicate<Lesson>? {
        let query = searchText.trimmed()
        
        guard query.isEmpty else {
            return buildSourceAndKindPredicate(sourceFilter: sourceFilter, personalKindFilter: personalKindFilter)
        }
        
        let sourceFilterRaw = sourceFilter?.rawValue
        let personalKindFilterRaw = personalKindFilter?.rawValue
        let personalRawValue = "personal"
        let personalKindPersonalRaw = "personal"
        let trimmedSubject = selectedSubject?.trimmed()
        let trimmedGroup = selectedGroup?.trimmed()
        let hasSubject = trimmedSubject.map { !$0.isEmpty } ?? false
        let hasGroup = trimmedGroup.map { !$0.isEmpty } ?? false
        let isPersonalSourceFilter = sourceFilter == .personal || sourceFilter == nil
        let hasPersonalKindFilter = personalKindFilterRaw != nil && isPersonalSourceFilter
        
        return #Predicate<Lesson> { lesson in
            (sourceFilterRaw == nil || lesson.sourceRaw == sourceFilterRaw!) &&
            (!hasPersonalKindFilter ||
                (lesson.sourceRaw == personalRawValue &&
                    (lesson.personalKindRaw == personalKindFilterRaw ||
                        (lesson.personalKindRaw == nil &&
                            personalKindFilterRaw == personalKindPersonalRaw)))) &&
            (!hasSubject || lesson.subject == trimmedSubject!) &&
            (!hasGroup || lesson.group == trimmedGroup!)
        }
    }
    
    private func buildSourceAndKindPredicate(
        sourceFilter: LessonSource?,
        personalKindFilter: PersonalLessonKind?
    ) -> Predicate<Lesson>? {
        let personalRawValue = "personal"
        let personalKindPersonalRaw = "personal"
        
        guard let sourceFilter = sourceFilter else {
            if let personalKindFilterRaw = personalKindFilter?.rawValue {
                return #Predicate<Lesson> {
                    $0.sourceRaw == personalRawValue &&
                    ($0.personalKindRaw == personalKindFilterRaw ||
                        ($0.personalKindRaw == nil &&
                            personalKindFilterRaw == personalKindPersonalRaw))
                }
            }
            return nil
        }
        
        let sourceFilterRaw = sourceFilter.rawValue
        let isPersonalSourceFilter = sourceFilter == .personal
        
        if let personalKindFilterRaw = personalKindFilter?.rawValue, isPersonalSourceFilter {
            return #Predicate<Lesson> {
                $0.sourceRaw == personalRawValue &&
                ($0.personalKindRaw == personalKindFilterRaw ||
                    ($0.personalKindRaw == nil &&
                        personalKindFilterRaw == personalKindPersonalRaw))
            }
        }
        
        return #Predicate<Lesson> { $0.sourceRaw == sourceFilterRaw }
    }

    private struct LessonSortKey {
        let subjectIdx: Int
        let groupIdx: Int
        let orderInGroup: Int
        let name: String
        let id: String
    }

    // MARK: - Sorting Pipelines

    // swiftlint:disable:next function_parameter_count
    func filteredLessons(
        modelContext: ModelContext,
        sourceFilter: LessonSource?,
        personalKindFilter: PersonalLessonKind?,
        searchText: String,
        selectedSubject: String?,
        selectedGroup: String?,
        allLessons: [Lesson]? = nil
    ) -> [Lesson] {
        let query = searchText.trimmed()
        let predicate = buildLessonPredicate(
            sourceFilter: sourceFilter, personalKindFilter: personalKindFilter,
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
                    let n = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                    return n == .orderedSame ? lhs.id.uuidString < rhs.id.uuidString : n == .orderedAscending
                }
                return lhs.orderInGroup < rhs.orderInGroup
            }
        } else {
            return fetched.sorted { lhs, rhs in
                if lhs.sortIndex != rhs.sortIndex { return lhs.sortIndex < rhs.sortIndex }
                if lhs.orderInGroup != rhs.orderInGroup { return lhs.orderInGroup < rhs.orderInGroup }
                let n = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                return n == .orderedSame ? lhs.id.uuidString < rhs.id.uuidString : n == .orderedAscending
            }
        }
    }

    private func lessonSortDescriptors(selectedGroup: String?, selectedSubject: String?) -> [SortDescriptor<Lesson>] {
        if selectedGroup != nil { return [SortDescriptor(\.orderInGroup), SortDescriptor(\.name)] }
        if selectedSubject != nil { return [SortDescriptor(\.sortIndex), SortDescriptor(\.name)] }
        return [SortDescriptor(\.subject), SortDescriptor(\.sortIndex), SortDescriptor(\.name)]
    }

    private func scopedLessonsForOrdering(
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

    private func buildGroupIndexCache(for subjects: Set<String>, from scoped: [Lesson]) -> [String: [String: Int]] {
        var cache: [String: [String: Int]] = [:]
        for subject in subjects where cache[subject] == nil {
            if let original = scoped.first(where: { norm($0.subject) == subject })?.subject {
                cache[subject] = groupIndex(for: original, lessons: scoped)
            }
        }
        return cache
    }

    private func sortBySubjectGroupOrder(
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
                for (idx, l) in sorted.enumerated() where l.orderInGroup != idx {
                    l.orderInGroup = idx; changed = true
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

// MARK: - Lesson Status

extension LessonsViewModel {
    enum LessonStatus {
        case ready, presented, practicing, stalled
    }

    struct LessonStatusInfo {
        let status: LessonStatus
        let ageString: String
        let lastActivityDate: Date?
        let isStale: Bool
        let isOverdue: Bool
    }

    static func computeLessonStatusInfo(
        lesson: Lesson,
        lessonAssignments: [LessonAssignment],
        workModels: [WorkModel],
        modelContext: ModelContext,
        schoolDayCache: SchoolDayLookupCache? = nil
    ) -> LessonStatusInfo {
        let lessonIDString = lesson.id.uuidString
        let lasForLesson = lessonAssignments.filter { $0.lessonID == lessonIDString }
        let isPresented = lasForLesson.contains { $0.isPresented }
        let laIDs = Set(lasForLesson.map { $0.id })
        let workForLesson = workModels.filter { work in
            work.lessonID == lessonIDString || laIDs.contains(work.studentLessonID ?? UUID())
        }
        let activeWork = workForLesson.filter { $0.completedAt == nil }

        let lastActivity = computeLastActivityDate(
            lasForLesson: lasForLesson, workForLesson: workForLesson, isPresented: isPresented
        )
        let (isStale, isOverdue) = computeWorkFlags(activeWork: activeWork, modelContext: modelContext)

        let status: LessonStatus
        if isStale || isOverdue {
            status = .stalled
        } else if !activeWork.isEmpty {
            status = .practicing
        } else if isPresented {
            status = .presented
        } else {
            status = .ready
        }

        let resolvedCache: SchoolDayLookupCache
        if let schoolDayCache = schoolDayCache {
            resolvedCache = schoolDayCache
        } else {
            resolvedCache = SchoolDayLookupCache()
            resolvedCache.preload(using: modelContext)
        }
        let ageString = formatAgeString(from: lastActivity, schoolDayCache: resolvedCache)

        return LessonStatusInfo(
            status: status, ageString: ageString,
            lastActivityDate: lastActivity, isStale: isStale, isOverdue: isOverdue
        )
    }

    private static func computeLastActivityDate(
        lasForLesson: [LessonAssignment],
        workForLesson: [WorkModel],
        isPresented: Bool
    ) -> Date? {
        let activeWork = workForLesson.filter { $0.completedAt == nil }
        if !activeWork.isEmpty {
            let lastTouches = activeWork.compactMap { work -> Date? in
                let checkIns = work.checkIns ?? []
                let notes = work.unifiedNotes ?? []
                return WorkAgingPolicy.lastMeaningfulTouchDate(for: work, checkIns: checkIns, notes: notes)
            }
            return lastTouches.max()
        } else if isPresented {
            let dates = lasForLesson.compactMap { $0.presentedAt ?? ($0.isPresented ? $0.createdAt : nil) }
            return dates.max()
        }
        return nil
    }

    private static func computeWorkFlags(
        activeWork: [WorkModel],
        modelContext: ModelContext
    ) -> (isStale: Bool, isOverdue: Bool) {
        guard let work = activeWork.first else { return (false, false) }
        let checkIns = work.checkIns ?? []
        let notes = work.unifiedNotes ?? []
        return (
            WorkAgingPolicy.isStale(work, modelContext: modelContext, checkIns: checkIns, notes: notes),
            WorkAgingPolicy.isOverdue(work, checkIns: checkIns)
        )
    }

    private static func formatAgeString(from date: Date?, schoolDayCache: SchoolDayLookupCache) -> String {
        guard let date = date else { return "" }
        let today = AppCalendar.startOfDay(Date())
        let startDate = AppCalendar.startOfDay(date)
        guard startDate < today else { return "" }

        let days = schoolDayCache.schoolDaysBetween(start: startDate, end: today)

        if days == 0 { return "" }
        if days < 7 { return "\(days)d" }
        if days < 30 { return "\(days / 7)w" }
        return "\(days / 30)m"
    }

    // MARK: - Status Counts

    /// Computes the number of students who need each lesson (have not been presented).
    /// Returns a dictionary mapping lesson UUID to student count.
    func computeLessonStatusCounts(
        for lessonIDs: [UUID],
        context: ModelContext
    ) -> [UUID: Int] {
        guard !lessonIDs.isEmpty else { return [:] }

        var result: [UUID: Int] = [:]
        let lessonIDStrings = Set(lessonIDs.uuidStrings)

        // Fetch only un-presented LessonAssignment records (drafts and scheduled).
        let presentedRaw = LessonAssignmentState.presented.rawValue
        let descriptor = FetchDescriptor<LessonAssignment>(
            predicate: #Predicate<LessonAssignment> { $0.stateRaw != presentedRaw }
        )
        let assignments: [LessonAssignment]
        do {
            assignments = try context.fetch(descriptor)
        } catch {
            Self.logger.warning("Failed to fetch LessonAssignment: \(error)")
            return [:]
        }

        for la in assignments {
            guard lessonIDStrings.contains(la.lessonID) else { continue }
            guard let uuid = UUID(uuidString: la.lessonID) else { continue }
            result[uuid, default: 0] += 1
        }

        return result
    }
}
