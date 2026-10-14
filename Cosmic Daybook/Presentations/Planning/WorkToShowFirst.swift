//
//  WorkToShowFirst.swift
//  Cosmic Daybook
//
//  Before a lesson: which of its children still have work open from an
//  earlier lesson in the same sequence, to look at before going on.
//
//  Danny's definition (2026-10-13): a child's open work whose lesson comes
//  earlier in the same sub-area than the lesson being given. "Earlier" is
//  `LessonSequenceOrder`'s order, the ready queue's; "open" is
//  `WorkStatus.isOpen`; "the child's" is the Work column's rule
//  (`QuietStudentsOrder.openStudentIDs` through `WorkVisibility`): her own
//  copy of linked work, or a shared row she hasn't finished her part of. A
//  classmate's open copy that names her is not hers.
//
//  Three surfaces read it: the Scheduled strip's cards (a mark on the chip),
//  the present-a-lesson sheet ("Before you start") and the Work tab's
//  "Before a Lesson" pill. Each asks for many lessons at once, and the answer
//  for all of them is one fetch: every row on the earlier lessons that a
//  child owns, plus the open rows that name one. The owned closed rows are
//  read too because they are what tells a classmate's copy from a shared row.
//

import CoreData
import Foundation

enum WorkToShowFirst {

    /// One lesson and the children it is planned for.
    struct Request: Hashable, Sendable {
        /// The lesson being given, as a UUID string.
        let lessonID: String
        let studentIDs: Set<UUID>
    }

    /// One piece of open work a child has on an earlier lesson.
    struct Item: Identifiable {
        let work: CDWorkModel
        let studentID: UUID
        /// The earlier lesson the work is on, as a UUID string.
        let lessonID: String
        /// That lesson's name, or the work's own title when the lesson has none.
        let lessonName: String
        /// The lesson's place in its sub-area, 1-based.
        let step: Int

        /// A shared row can be open work of two children on one lesson, so
        /// the child is part of the identity.
        var id: ItemID { ItemID(studentID: studentID, work: work.objectID) }

        /// The work's own title, when it says something the lesson name doesn't.
        var workTitle: String? {
            let title = work.title.trimmed()
            guard !title.isEmpty, title.caseInsensitiveCompare(lessonName) != .orderedSame else { return nil }
            return title
        }

        /// "Golden Bead Addition, Working".
        var summary: String {
            [lessonName, workTitle, work.status.displayName].compactMap { $0 }.joined(separator: ", ")
        }
    }

    /// An item's identity: the child and the row.
    struct ItemID: Hashable {
        let studentID: UUID
        let work: NSManagedObjectID
    }

    /// Each child's open earlier work, in sequence order. A child with none is absent.
    typealias ByChild = [UUID: [Item]]

    // MARK: - Earlier lessons

    /// The lessons before `lessonID` in its sub-area, first first. Empty for
    /// the first lesson, and for one with no area or sequence.
    static func earlierLessonIDs(before lessonID: String, in order: LessonSequenceOrder) -> [String] {
        guard let position = order.position(of: lessonID) else { return [] }
        let ids = order.lessonIDs(area: position.area, sequence: position.sequence)
        return Array(ids.prefix(position.step - 1))
    }

    // MARK: - Finding it

    /// The open earlier work for one lesson's children.
    static func find(
        lessonID: String,
        studentIDs: Set<UUID>,
        order: LessonSequenceOrder,
        in context: NSManagedObjectContext
    ) -> ByChild {
        let request = Request(lessonID: lessonID, studentIDs: studentIDs)
        return find([0: request], order: order, in: context)[0] ?? [:]
    }

    /// The open earlier work for many lessons at once, keyed as the caller
    /// keys its requests (a presentation's id, say). One fetch for all of
    /// them; a key with nothing to show is absent.
    static func find<Key: Hashable>(
        _ requests: [Key: Request],
        order: LessonSequenceOrder,
        in context: NSManagedObjectContext
    ) -> [Key: ByChild] {
        var earlierByLesson: [String: [String]] = [:]
        for request in requests.values where earlierByLesson[request.lessonID] == nil {
            earlierByLesson[request.lessonID] = earlierLessonIDs(before: request.lessonID, in: order)
        }
        let asked = requests.values.filter { !$0.studentIDs.isEmpty && !(earlierByLesson[$0.lessonID] ?? []).isEmpty }
        let lessonIDs = Set(asked.flatMap { earlierByLesson[$0.lessonID] ?? [] })
        let children = Set(asked.flatMap(\.studentIDs))
        guard !lessonIDs.isEmpty, !children.isEmpty else { return [:] }

        let open = openWork(
            in: context.safeFetch(fetchRequest(lessonIDs: lessonIDs, studentIDs: children)),
            for: children
        )
        var result: [Key: ByChild] = [:]
        for (key, request) in requests {
            let byChild = items(
                for: request.studentIDs, on: earlierByLesson[request.lessonID] ?? [], open: open, order: order
            )
            if !byChild.isEmpty { result[key] = byChild }
        }
        return result
    }

    /// Each open row among `rows`, by lesson and then by each of `children`
    /// it is open work of.
    private static func openWork(
        in rows: [CDWorkModel], for children: Set<UUID>
    ) -> [String: [UUID: [CDWorkModel]]] {
        let rows = rows.filter { !$0.isDeleted }
        let visibility = WorkVisibility(rows: rows)
        var open: [String: [UUID: [CDWorkModel]]] = [:]
        for row in rows where row.status.isOpen {
            for child in QuietStudentsOrder.openStudentIDs(of: row, visibility: visibility)
            where children.contains(child) {
                open[row.lessonID, default: [:]][child, default: []].append(row)
            }
        }
        return open
    }

    /// One request's answer, out of the open rows already sorted by lesson.
    private static func items(
        for children: Set<UUID>,
        on earlier: [String],
        open: [String: [UUID: [CDWorkModel]]],
        order: LessonSequenceOrder
    ) -> ByChild {
        var byChild: ByChild = [:]
        for lessonID in earlier {
            guard let byStudent = open[lessonID], let position = order.position(of: lessonID) else { continue }
            for child in children {
                for work in byStudent[child] ?? [] {
                    byChild[child, default: []].append(Item(
                        work: work,
                        studentID: child,
                        lessonID: lessonID,
                        lessonName: LessonFormatter.lessonName(
                            position.name, orRowTitle: work.title, missing: LessonFormatter.untitledWork
                        ),
                        step: position.step
                    ))
                }
            }
        }
        return byChild.mapValues { $0.sorted(by: isOrderedBefore) }
    }

    /// Every row on `lessonIDs` a child owns, open or closed, and every open
    /// row naming one of them. Participants are prefetched: who a row is
    /// open for is read from them.
    static func fetchRequest(lessonIDs: Set<String>, studentIDs: Set<UUID>) -> NSFetchRequest<CDWorkModel> {
        let ids = studentIDs.map(\.uuidString)
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "lessonID IN %@", Array(lessonIDs)),
            NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "studentID IN %@", ids),
                NSCompoundPredicate(andPredicateWithSubpredicates: [
                    WorkStatus.openPredicate,
                    NSPredicate(format: "ANY participants.studentID IN %@", ids)
                ])
            ])
        ])
        request.relationshipKeyPathsForPrefetching = ["participants"]
        return request
    }

    /// Earlier in the sequence first; on one lesson, the older work first.
    private static func isOrderedBefore(_ lhs: Item, _ rhs: Item) -> Bool {
        if lhs.step != rhs.step { return lhs.step < rhs.step }
        let lhsMade = lhs.work.createdAt ?? .distantPast
        let rhsMade = rhs.work.createdAt ?? .distantPast
        if lhsMade != rhsMade { return lhsMade < rhsMade }
        return (lhs.work.id?.uuidString ?? "") < (rhs.work.id?.uuidString ?? "")
    }
}

// MARK: - Words

extension WorkToShowFirst {
    /// The mark on a strip chip, the card's line, the sheet's rows and the
    /// Work half's pill.
    nonisolated static let glyph = "arrow.uturn.backward.circle.fill"

    /// "2 to check first", for a card or a section header.
    static func countLine(_ count: Int) -> String {
        "\(count) to check first"
    }

    /// A chip's tooltip on the Mac: what the child has open, without her
    /// name (the chip says it). Kept near the 60–75 characters Apple advises.
    static func helpText(for items: [Item]) -> String {
        guard let first = items.first else { return "" }
        if items.count == 1 { return "Still open from earlier: \(first.lessonName)" }
        return "Still open from earlier: \(first.lessonName) and \(items.count - 1) more"
    }
}
