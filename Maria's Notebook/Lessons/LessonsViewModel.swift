// Maria's Notebook/Lessons/LessonsViewModel.swift

import Foundation
import OSLog
import CoreData

/// Provides filtering and ordering utilities for Lessons screens.
/// Methods here are pure functions and do not mutate external state.
@MainActor
struct LessonsViewModel {
    private static let logger = Logger.lessons
    // MARK: - Public API

    // Compute ordered unique areas using FilterOrderStore
    func areas(from lessons: [CDLesson]) -> [String] {
        let unique = Set(lessons.map { $0.area.trimmed() }.filter { !$0.isEmpty })
        let existing = Array(unique).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return FilterOrderStore.loadAreaOrder(existing: existing)
    }

    // Compute ordered unique groups for a given area using FilterOrderStore
    func groups(for area: String, lessons: [CDLesson]) -> [String] {
        let trimmedArea = area.trimmed()
        let unique = Set(
            lessons
                // FIX: Trim lesson area before comparing to ensure "Math " matches "Math"
                .filter { $0.area.trimmed().caseInsensitiveCompare(trimmedArea) == .orderedSame }
                .map { $0.sequence.trimmed() }
                .filter { !$0.isEmpty }
        )
        let existing = Array(unique).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return FilterOrderStore.loadSequenceOrder(for: trimmedArea, existing: existing)
    }

    // MARK: - Private Helpers

    func norm(_ s: String) -> String { s.trimmed().lowercased() }

    func areaIndexMap(from lessons: [CDLesson]) -> [String: Int] {
        let list = areas(from: lessons)
        return list.enumerated().reduce(into: [:]) { $0[norm($1.element)] = $1.offset }
    }

    func sequenceIndex(for area: String, lessons: [CDLesson]) -> [String: Int] {
        let orderedSequences = groups(for: area, lessons: lessons)
        return orderedSequences.enumerated().reduce(into: [:]) { (d: inout [String: Int], p) in
            d[norm(p.element)] = p.offset
        }
    }

    // MARK: - Predicate Building
    
    func buildLessonPredicate(
        sourceFilter: LessonSource?,
        personalKindFilter: PersonalLessonKind?,
        formatFilter: LessonFormat? = nil,
        selectedArea: String?,
        selectedSequence: String?,
        searchText: String
    ) -> NSPredicate? {
        let query = searchText.trimmed()

        guard query.isEmpty else {
            return buildSourceAndKindPredicate(sourceFilter: sourceFilter, personalKindFilter: personalKindFilter)
        }

        var subpredicates: [NSPredicate] = []

        // Source filter
        if let sourceFilterRaw = sourceFilter?.rawValue {
            subpredicates.append(NSPredicate(format: "sourceRaw == %@", sourceFilterRaw))
        }

        // Personal kind filter
        let isPersonalSourceFilter = sourceFilter == .personal || sourceFilter == nil
        if let personalKindFilterRaw = personalKindFilter?.rawValue, isPersonalSourceFilter {
            subpredicates.append(NSPredicate(
                format: "sourceRaw == %@ AND (personalKindRaw == %@ OR (personalKindRaw == nil AND %@ == %@))",
                "personal", personalKindFilterRaw, personalKindFilterRaw, "personal"
            ))
        }

        // Area filter
        if let trimmedArea = selectedArea?.trimmed(), !trimmedArea.isEmpty {
            subpredicates.append(NSPredicate(format: "area == %@", trimmedArea))
        }

        // Group filter
        if let trimmedSequence = selectedSequence?.trimmed(), !trimmedSequence.isEmpty {
            subpredicates.append(NSPredicate(format: "sequence == %@", trimmedSequence))
        }

        guard !subpredicates.isEmpty else { return nil }
        return NSCompoundPredicate(andPredicateWithSubpredicates: subpredicates)
    }
    
    func buildSourceAndKindPredicate(
        sourceFilter: LessonSource?,
        personalKindFilter: PersonalLessonKind?
    ) -> NSPredicate? {
        guard let sourceFilter else {
            if let personalKindFilterRaw = personalKindFilter?.rawValue {
                return NSPredicate(
                    format: "sourceRaw == %@ AND (personalKindRaw == %@ OR (personalKindRaw == nil AND %@ == %@))",
                    "personal", personalKindFilterRaw, personalKindFilterRaw, "personal"
                )
            }
            return nil
        }

        let sourceFilterRaw = sourceFilter.rawValue

        if let personalKindFilterRaw = personalKindFilter?.rawValue, sourceFilter == .personal {
            return NSPredicate(
                format: "sourceRaw == %@ AND (personalKindRaw == %@ OR (personalKindRaw == nil AND %@ == %@))",
                "personal", personalKindFilterRaw, personalKindFilterRaw, "personal"
            )
        }

        return NSPredicate(format: "sourceRaw == %@", sourceFilterRaw as CVarArg)
    }

    struct LessonSortKey {
        let areaIdx: Int
        let groupIdx: Int
        let orderInSequence: Int64
        let name: String
        let id: String
    }

}

// MARK: - CDLesson Status

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

    private static func computeLastActivityDate(
        lasForLesson: [CDLessonAssignment],
        workForLesson: [CDWorkModel],
        isPresented: Bool
    ) -> Date? {
        let activeWork = workForLesson.filter { $0.completedAt == nil }
        if !activeWork.isEmpty {
            let lastTouches = activeWork.compactMap { work -> Date? in
                let checkIns = (work.checkIns?.allObjects as? [CDWorkCheckIn]) ?? []
                let notes = (work.unifiedNotes?.allObjects as? [CDNote]) ?? []
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
        activeWork: [CDWorkModel],
        viewContext: NSManagedObjectContext
    ) -> (isStale: Bool, isOverdue: Bool) {
        guard let work = activeWork.first else { return (false, false) }
        let checkIns = (work.checkIns?.allObjects as? [CDWorkCheckIn]) ?? []
        let notes = (work.unifiedNotes?.allObjects as? [CDNote]) ?? []
        return (
            WorkAgingPolicy.isStale(work, using: viewContext, checkIns: checkIns, notes: notes),
            WorkAgingPolicy.isOverdue(work, checkIns: checkIns)
        )
    }

    private static func formatAgeString(from date: Date?, schoolDayCache: SchoolDayLookupCache) -> String {
        guard let date else { return "" }
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
        context: NSManagedObjectContext
    ) -> [UUID: Int] {
        guard !lessonIDs.isEmpty else { return [:] }

        var result: [UUID: Int] = [:]
        let lessonIDStrings = Set(lessonIDs.uuidStrings)

        // Fetch only un-presented CDLessonAssignment records (drafts and scheduled).
        let presentedRaw = LessonAssignmentState.presented.rawValue
        let descriptor: NSFetchRequest<CDLessonAssignment> = NSFetchRequest(entityName: "LessonAssignment")
        descriptor.predicate = NSPredicate(format: "stateRaw != %@", presentedRaw as CVarArg)
        let assignments: [CDLessonAssignment]
        do {
            assignments = try context.fetch(descriptor)
        } catch {
            Self.logger.warning("Failed to fetch CDLessonAssignment: \(error)")
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
