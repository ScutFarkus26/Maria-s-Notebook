// Maria's Notebook/Lessons/LessonsViewModel.swift

import Foundation
import OSLog
import SwiftData

/// Provides filtering and ordering utilities for Lessons screens.
/// Methods here are pure functions and do not mutate external state.
@MainActor
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
            sourceFilter: sourceFilter,
            personalKindFilter: personalKindFilter,
            selectedSubject: selectedSubject,
            selectedGroup: selectedGroup,
            searchText: searchText
        )
        
        let sortDescriptors: [SortDescriptor<Lesson>] = {
            if selectedGroup != nil {
                // When filtering by group, use orderInGroup
                return [SortDescriptor(\.orderInGroup), SortDescriptor(\.name)]
            } else if selectedSubject != nil {
                // When filtering by subject, use sortIndex (subject-level ordering)
                return [SortDescriptor(\.sortIndex), SortDescriptor(\.name)]
            } else {
                // No filter: use subject, then sortIndex within subject
                return [SortDescriptor(\.subject), SortDescriptor(\.sortIndex), SortDescriptor(\.name)]
            }
        }()
        
        var descriptor = FetchDescriptor<Lesson>()
        if let predicate = predicate {
            descriptor.predicate = predicate
        }
        descriptor.sortBy = sortDescriptors
        
        var fetched = modelContext.safeFetch(descriptor)
        
        // 1. FIX: Use trimmed comparison for subject filtering to catch "Geometry " vs "Geometry"
        if let subject = selectedSubject?.trimmed(), !subject.isEmpty, query.isEmpty {
            fetched = fetched.filter { $0.subject.trimmed().caseInsensitiveCompare(subject) == .orderedSame }
        }
        // 2. FIX: Use trimmed comparison for group filtering
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
        
        // Derive the scoped lesson set for subject/group ordering.
        // When allLessons is provided (from the @Query in the view), use in-memory
        // filtering to avoid a second database fetch.
        let scoped: [Lesson]
        if let allLessons = allLessons {
            if sourceFilter != nil || personalKindFilter != nil {
                scoped = allLessons.filter { lesson in
                    if let sf = sourceFilter, lesson.source != sf { return false }
                    if let pkf = personalKindFilter, lesson.personalKind != pkf { return false }
                    return true
                }
            } else {
                scoped = allLessons
            }
        } else {
            // Fallback: original second fetch for backward compatibility
            let scopedPredicate = buildSourceAndKindPredicate(
                sourceFilter: sourceFilter,
                personalKindFilter: personalKindFilter
            )
            var scopedDescriptor = FetchDescriptor<Lesson>()
            if let scopedPredicate = scopedPredicate {
                scopedDescriptor.predicate = scopedPredicate
            }
            scoped = modelContext.safeFetch(scopedDescriptor)
        }
        
        // PERFORMANCE: Pre-compute sort indices for all lessons to avoid repeated lookups during comparison
        let subjectIndex = subjectIndexMap(from: scoped)
        var groupIndexCache: [String: [String: Int]] = [:]
        
        // Pre-compute group indices for all unique subjects in fetched results
        let uniqueSubjects = Set(fetched.map { norm($0.subject) })
        for subject in uniqueSubjects where groupIndexCache[subject] == nil {
            // Find the original (non-normalized) subject name for lookup
            if let originalSubject = scoped.first(where: { norm($0.subject) == subject })?.subject {
                groupIndexCache[subject] = groupIndex(for: originalSubject, lessons: scoped)
            }
        }

        // Sorting logic with pre-computed indices
        if !query.isEmpty {
            let sortKeys = fetched.map { lesson -> LessonSortKey in
                let subjectIdx = subjectIndex[norm(lesson.subject)] ?? Int.max
                let groupIdx = groupIndexCache[norm(lesson.subject)]?[norm(lesson.group)] ?? Int.max
                return LessonSortKey(
                    subjectIdx: subjectIdx, groupIdx: groupIdx,
                    orderInGroup: lesson.orderInGroup,
                    name: lesson.name, id: lesson.id.uuidString
                )
            }
            
            let indexedLessons = zip(fetched, sortKeys).map { ($0, $1) }
            let sorted = indexedLessons.sorted { lhs, rhs in
                let (_, lKeys) = lhs
                let (_, rKeys) = rhs
                
                if lKeys.subjectIdx != rKeys.subjectIdx { return lKeys.subjectIdx < rKeys.subjectIdx }
                if lKeys.groupIdx != rKeys.groupIdx { return lKeys.groupIdx < rKeys.groupIdx }
                if lKeys.orderInGroup != rKeys.orderInGroup { return lKeys.orderInGroup < rKeys.orderInGroup }
                
                let nameOrder = lKeys.name.localizedCaseInsensitiveCompare(rKeys.name)
                if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
                return lKeys.id < rKeys.id
            }
            return sorted.map { $0.0 }
        } else if selectedGroup != nil {
            return fetched.sorted { lhs, rhs in
                if lhs.orderInGroup == rhs.orderInGroup {
                    let nameOrder = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                    if nameOrder == .orderedSame { return lhs.id.uuidString < rhs.id.uuidString }
                    return nameOrder == .orderedAscending
                }
                return lhs.orderInGroup < rhs.orderInGroup
            }
        } else if selectedSubject != nil {
            // Use sortIndex for subject-level ordering
            return fetched.sorted { lhs, rhs in
                if lhs.sortIndex != rhs.sortIndex {
                    return lhs.sortIndex < rhs.sortIndex
                }
                // Fallback to orderInGroup, then name for stable ordering
                if lhs.orderInGroup != rhs.orderInGroup {
                    return lhs.orderInGroup < rhs.orderInGroup
                }
                let nameOrder = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                if nameOrder == .orderedSame { return lhs.id.uuidString < rhs.id.uuidString }
                return nameOrder == .orderedAscending
            }
        } else {
            let sortKeys = fetched.map { lesson -> LessonSortKey in
                let subjectIdx = subjectIndex[norm(lesson.subject)] ?? Int.max
                let groupIdx = groupIndexCache[norm(lesson.subject)]?[norm(lesson.group)] ?? Int.max
                return LessonSortKey(
                    subjectIdx: subjectIdx, groupIdx: groupIdx,
                    orderInGroup: lesson.orderInGroup,
                    name: lesson.name, id: lesson.id.uuidString
                )
            }
            
            let indexedLessons = zip(fetched, sortKeys).map { ($0, $1) }
            let sorted = indexedLessons.sorted { lhs, rhs in
                let (_, lKeys) = lhs
                let (_, rKeys) = rhs
                
                if lKeys.subjectIdx != rKeys.subjectIdx { return lKeys.subjectIdx < rKeys.subjectIdx }
                if lKeys.groupIdx != rKeys.groupIdx { return lKeys.groupIdx < rKeys.groupIdx }
                if lKeys.orderInGroup != rKeys.orderInGroup { return lKeys.orderInGroup < rKeys.orderInGroup }
                
                let nameOrder = lKeys.name.localizedCaseInsensitiveCompare(rKeys.name)
                if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
                return lKeys.id < rKeys.id
            }
            return sorted.map { $0.0 }
        }
    }
    
    // ... [Rest of file is unchanged] ...
    
    // Ensure you keep the Data Maintenance and Lesson Status sections here as they were in your original file.
    // I am omitting them here for brevity, but they should remain in the file.
    
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

        var lastActivity: Date?
        if !activeWork.isEmpty {
            let lastTouches = activeWork.compactMap { work -> Date? in
                let checkIns = work.checkIns ?? []
                let notes = work.unifiedNotes ?? []
                return WorkAgingPolicy.lastMeaningfulTouchDate(for: work, checkIns: checkIns, notes: notes)
            }
            lastActivity = lastTouches.max()
        } else if isPresented {
            let presentationDates = lasForLesson.compactMap { $0.presentedAt ?? ($0.isPresented ? $0.createdAt : nil) }
            lastActivity = presentationDates.max()
        }
        
        var isStale = false
        var isOverdue = false
        if let work = activeWork.first {
            let checkIns = work.checkIns ?? []
            let notes = work.unifiedNotes ?? []
            isStale = WorkAgingPolicy.isStale(work, modelContext: modelContext, checkIns: checkIns, notes: notes)
            isOverdue = WorkAgingPolicy.isOverdue(work, checkIns: checkIns)
        }
        
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
            status: status,
            ageString: ageString,
            lastActivityDate: lastActivity,
            isStale: isStale,
            isOverdue: isOverdue
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
