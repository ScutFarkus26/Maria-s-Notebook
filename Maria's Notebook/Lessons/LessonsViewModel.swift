// Maria's Notebook/Lessons/LessonsViewModel.swift

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

    private func indexForGroup(_ group: String, inSubject subject: String, cache: inout [String: [String: Int]], lessons: [Lesson]) -> Int {
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
            (!hasPersonalKindFilter || (lesson.sourceRaw == personalRawValue && (lesson.personalKindRaw == personalKindFilterRaw || (lesson.personalKindRaw == nil && personalKindFilterRaw == personalKindPersonalRaw)))) &&
            // Note: Predicates don't support .trimmed(), so we rely on exact match here,
            // but the in-memory fallback below handles the loose matching.
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

    func filteredLessons(
        modelContext: ModelContext,
        sourceFilter: LessonSource?,
        personalKindFilter: PersonalLessonKind?,
        searchText: String,
        selectedSubject: String?,
        selectedGroup: String?
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

        // Sorting logic (Unchanged)
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
        studentLessons: [StudentLesson],
        workModels: [WorkModel],
        modelContext: ModelContext
    ) -> LessonStatusInfo {
        let lessonIDString = lesson.id.uuidString
        let slsForLesson = studentLessons.filter { $0.lessonID == lessonIDString }
        let isPresented = slsForLesson.contains { $0.isPresented || $0.givenAt != nil }
        
        let slIDs = Set(slsForLesson.map { $0.id })
        let workForLesson = workModels.filter { work in
            guard let workSLID = work.studentLessonID else { return false }
            return slIDs.contains(workSLID)
        }
        
        let activeWork = workForLesson.filter { $0.completedAt == nil }
        
        var lastActivity: Date? = nil
        if !activeWork.isEmpty {
            let lastTouches = activeWork.compactMap { work -> Date? in
                let checkIns = work.checkIns ?? []
                let notes = work.unifiedNotes ?? []
                return WorkAgingPolicy.lastMeaningfulTouchDate(for: work, checkIns: checkIns, notes: notes)
            }
            lastActivity = lastTouches.max()
        } else if isPresented {
            let presentationDates = slsForLesson.compactMap { $0.givenAt ?? ($0.isPresented ? $0.createdAt : nil) }
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
        if isStale || isOverdue { status = .stalled }
        else if !activeWork.isEmpty { status = .practicing }
        else if isPresented { status = .presented }
        else { status = .ready }
        
        let ageString = formatAgeString(from: lastActivity, modelContext: modelContext)
        
        return LessonStatusInfo(
            status: status,
            ageString: ageString,
            lastActivityDate: lastActivity,
            isStale: isStale,
            isOverdue: isOverdue
        )
    }
    
    private static func formatAgeString(from date: Date?, modelContext: ModelContext) -> String {
        guard let date = date else { return "" }
        let today = AppCalendar.startOfDay(Date())
        let startDate = AppCalendar.startOfDay(date)
        
        var days = 0
        var cursor = startDate
        while cursor < today {
            if !isNonSchoolDaySync(cursor, using: modelContext) { days += 1 }
            cursor = AppCalendar.addingDays(1, to: cursor)
            if days > 365 { break }
        }
        
        if days == 0 { return "" }
        if days < 7 { return "\(days)d" }
        if days < 30 { return "\(days / 7)w" }
        return "\(days / 30)m"
    }
    
    private static func isNonSchoolDaySync(_ date: Date, using context: ModelContext) -> Bool {
        let cal = AppCalendar.shared
        let day = AppCalendar.startOfDay(date)
        do {
            let nsDescriptor = FetchDescriptor<NonSchoolDay>(predicate: #Predicate { $0.date == day })
            let nonSchoolDays: [NonSchoolDay] = try context.fetch(nsDescriptor)
            if !nonSchoolDays.isEmpty { return true }
        } catch {}
        
        let weekday = cal.component(.weekday, from: day)
        let isWeekend = (weekday == 1 || weekday == 7)
        guard isWeekend else { return false }
        
        do {
            let ovDescriptor = FetchDescriptor<SchoolDayOverride>(predicate: #Predicate { $0.date == day })
            let overrides: [SchoolDayOverride] = try context.fetch(ovDescriptor)
            if !overrides.isEmpty { return false }
        } catch {}
        
        return true
    }
}
