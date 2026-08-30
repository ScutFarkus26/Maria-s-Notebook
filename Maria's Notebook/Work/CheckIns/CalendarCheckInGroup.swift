// CalendarCheckInGroup.swift
// Collapses a day's work check-ins into the pills the calendar draws.
//
// A lesson presented to six children produces six check-ins. Drawn one per row
// they bury everything else in the column, so check-ins that share a lesson and
// a purpose collapse into a single pill that opens a per-child sheet. Work
// marked `.individual` opts out — those children are meant to be seen one at a
// time.
//
// Grouping used to run inside the day column, which meant three Core Data
// fetches per check-in per column. It resolves in three fetches total now,
// because the calendar hands it a whole range at once.

import CoreData
import Foundation

/// One pill in the calendar's check-in band: either a single check-in or
/// several that share a lesson and a purpose.
struct CalendarCheckInGroup: Identifiable {
    let id: UUID
    /// Every check-in in this pill, in the order they were resolved.
    let checkIns: [CDWorkCheckIn]
    let lessonTitle: String
    let studentNames: [String]
    let purpose: String
    let sortDate: Date

    /// Representative check-in, used for tap and drag.
    var primary: CDWorkCheckIn { checkIns[0] }
    var isGrouped: Bool { checkIns.count > 1 }
}

enum CalendarCheckInGrouper {

    /// Resolves and groups check-ins for one day.
    ///
    /// Pass `lookup` built once for the whole visible range — see
    /// `Lookup.build(for:in:)`. Grouping without one still works but falls back
    /// to per-record fetches.
    @MainActor
    static func groups(
        from checkIns: [CDWorkCheckIn],
        lookup: Lookup
    ) -> [CalendarCheckInGroup] {
        let resolved = checkIns.compactMap { checkIn -> Resolved? in
            guard let workID = checkIn.workID.asUUID, let work = lookup.works[workID] else { return nil }
            return Resolved(
                checkIn: checkIn,
                lessonTitle: lookup.lessonTitle(for: work),
                studentName: lookup.studentName(for: work),
                sequenceKey: "\(work.lessonID)|\(checkIn.purpose)",
                isIndividual: work.checkInStyle == .individual
            )
        }

        // Group by lesson + purpose, preserving first-appearance order so the
        // column does not reshuffle between redraws.
        var order: [String] = []
        var buckets: [String: [Resolved]] = [:]
        for item in resolved where !item.isIndividual {
            if buckets[item.sequenceKey] == nil { order.append(item.sequenceKey) }
            buckets[item.sequenceKey, default: []].append(item)
        }

        var result: [CalendarCheckInGroup] = order.compactMap { key in
            guard let items = buckets[key], let first = items.first else { return nil }
            return CalendarCheckInGroup(
                id: first.checkIn.id ?? UUID(),
                checkIns: items.map(\.checkIn),
                lessonTitle: first.lessonTitle,
                studentNames: items.map(\.studentName).filter { !$0.isEmpty },
                purpose: first.checkIn.purpose,
                sortDate: first.checkIn.date ?? Date()
            )
        }

        result.append(contentsOf: resolved.filter(\.isIndividual).map { item in
            CalendarCheckInGroup(
                id: item.checkIn.id ?? UUID(),
                checkIns: [item.checkIn],
                lessonTitle: item.lessonTitle,
                studentNames: item.studentName.isEmpty ? [] : [item.studentName],
                purpose: item.checkIn.purpose,
                sortDate: item.checkIn.date ?? Date()
            )
        })

        return result.sorted { $0.sortDate < $1.sortDate }
    }

    private struct Resolved {
        let checkIn: CDWorkCheckIn
        let lessonTitle: String
        let studentName: String
        let sequenceKey: String
        let isIndividual: Bool
    }

    /// The work, lesson and student records a range of check-ins refers to,
    /// fetched in three queries instead of three per check-in.
    struct Lookup {
        var works: [UUID: CDWorkModel] = [:]
        var lessons: [UUID: CDLesson] = [:]
        var students: [UUID: CDStudent] = [:]

        func lessonTitle(for work: CDWorkModel) -> String {
            let name = work.lessonID.asUUID.flatMap { lessons[$0]?.name }?.trimmed() ?? ""
            return name.isEmpty ? "Lesson \(String(work.lessonID.prefix(6)))" : name
        }

        func studentName(for work: CDWorkModel) -> String {
            work.studentID.asUUID
                .flatMap { students[$0] }
                .map(StudentFormatter.displayName(for:)) ?? ""
        }

        @MainActor
        static func build(
            for checkIns: [CDWorkCheckIn],
            in context: NSManagedObjectContext
        ) -> Lookup {
            var lookup = Lookup()
            let workIDs = Set(checkIns.compactMap { $0.workID.asUUID })
            guard !workIDs.isEmpty else { return lookup }

            lookup.works = byID(fetch(CDWorkModel.self, entity: "WorkModel", ids: workIDs, in: context))

            let works = Array(lookup.works.values)
            let lessonIDs = Set(works.compactMap { $0.lessonID.asUUID })
            let studentIDs = Set(works.compactMap { $0.studentID.asUUID })

            if !lessonIDs.isEmpty {
                lookup.lessons = byID(fetch(CDLesson.self, entity: "Lesson", ids: lessonIDs, in: context))
            }
            if !studentIDs.isEmpty {
                lookup.students = byID(fetch(CDStudent.self, entity: "Student", ids: studentIDs, in: context))
            }
            return lookup
        }

        @MainActor
        private static func fetch<T: NSManagedObject>(
            _ type: T.Type,
            entity: String,
            ids: Set<UUID>,
            in context: NSManagedObjectContext
        ) -> [T] {
            let request = NSFetchRequest<T>(entityName: entity)
            request.predicate = NSPredicate(format: "id IN %@", ids as NSSet)
            return context.safeFetch(request)
        }

        /// CloudKit sync can leave duplicate rows sharing an id; first wins,
        /// matching every other lookup table in the app.
        private static func byID<T: NSManagedObject>(_ records: [T]) -> [UUID: T] {
            Dictionary(
                records.compactMap { record -> (UUID, T)? in
                    guard let id = record.value(forKey: "id") as? UUID else { return nil }
                    return (id, record)
                },
                uniquingKeysWith: { first, _ in first }
            )
        }
    }
}
