//
//  WorkToShowFirst.swift
//  Cosmic Daybook
//
//  Before a lesson: which of its children still have work open from an
//  earlier lesson in the same sequence, to look at before going on.
//
//  Danny's definition (2026-10-13): a child's open work whose lesson comes
//  earlier in the same sub-area than the lesson being given. "Earlier" is a
//  strictly lower `orderInSequence`: the ready queue breaks ties by name, but
//  a lesson that only sorts first by name isn't one the child had to finish
//  first, so a sequence left all at 0 has nothing earlier. "Open" is
//  `WorkStatus.isOpen`; "the child's" is the Work column's rule
//  (`QuietStudentsOrder.openStudentIDs` through `WorkVisibility`): her own
//  copy of linked work, or a shared row she hasn't finished her part of. A
//  classmate's open copy that names her is not hers.
//
//  Three surfaces read it: the Scheduled strip's cards (a mark on the chip),
//  the present-a-lesson sheet ("Before you start") and the Work tab's
//  "Before a Lesson" pill. Each asks for many lessons at once, and the answer
//  for all of them is one fetch of the open rows on the earlier lessons that
//  name one of the children, plus, only where one of those names more than
//  one child, a second of every row on those lessons: a child's closed copy is
//  what tells a classmate's open copy from a row she shares
//  (`WorkVisibility(covering:)`'s rule).
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

    /// The library's sequences as this reads them: each lesson's place in its
    /// sub-area (`LessonSequenceOrder`, the ready queue's order and names)
    /// and the `orderInSequence` that alone decides what is earlier.
    nonisolated struct Sequences: Sendable, Equatable {
        let order: LessonSequenceOrder
        /// lessonID → `orderInSequence`.
        let ranks: [String: Int64]

        init(lessons: [CDLesson]) {
            order = LessonSequenceOrder(lessons: lessons)
            var ranks: [String: Int64] = [:]
            for lesson in lessons {
                guard let id = lesson.id?.uuidString, ranks[id] == nil else { continue }
                ranks[id] = lesson.orderInSequence
            }
            self.ranks = ranks
        }
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
        /// Whether logging the row closes it for this child alone: her own
        /// copy, or a row naming nobody else. A shared row (project or book-club
        /// work) closes for everyone on it (`WorkLogService.studentsLogged`), so
        /// the lists only open it.
        let isHersAlone: Bool

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

    /// The lessons in `lessonID`'s sub-area with a lower `orderInSequence`,
    /// first first. Empty for the first lesson, for one tied with every lesson
    /// before it, and for one with no area or sequence.
    static func earlierLessonIDs(before lessonID: String, in sequences: Sequences) -> [String] {
        guard let position = sequences.order.position(of: lessonID),
              let rank = sequences.ranks[lessonID] else { return [] }
        return sequences.order.lessonIDs(area: position.area, sequence: position.sequence).filter { id in
            sequences.ranks[id].map { $0 < rank } ?? false
        }
    }

    // MARK: - Finding it

    /// The open earlier work for one lesson's children.
    static func find(
        lessonID: String,
        studentIDs: Set<UUID>,
        sequences: Sequences,
        in context: NSManagedObjectContext
    ) -> ByChild {
        let request = Request(lessonID: lessonID, studentIDs: studentIDs)
        return find([0: request], sequences: sequences, in: context)[0] ?? [:]
    }

    /// The open earlier work for many lessons at once, keyed as the caller
    /// keys its requests (a presentation's id, say). One fetch for all of
    /// them, two when a row names more than one child; a key with nothing to
    /// show is absent.
    static func find<Key: Hashable>(
        _ requests: [Key: Request],
        sequences: Sequences,
        in context: NSManagedObjectContext
    ) -> [Key: ByChild] {
        var earlierByLesson: [String: [String]] = [:]
        for request in requests.values where earlierByLesson[request.lessonID] == nil {
            earlierByLesson[request.lessonID] = earlierLessonIDs(before: request.lessonID, in: sequences)
        }
        let asked = requests.values.filter { !$0.studentIDs.isEmpty && !(earlierByLesson[$0.lessonID] ?? []).isEmpty }
        let lessonIDs = Set(asked.flatMap { earlierByLesson[$0.lessonID] ?? [] })
        let children = Set(asked.flatMap(\.studentIDs))
        guard !lessonIDs.isEmpty, !children.isEmpty else { return [:] }

        let openRows = context.safeFetch(openRowsRequest(lessonIDs: lessonIDs, studentIDs: children))
            .filter { !$0.isDeleted && $0.status.isOpen }
        guard !openRows.isEmpty else { return [:] }
        let open = openWork(openRows, for: children, in: context)
        var result: [Key: ByChild] = [:]
        for (key, request) in requests {
            let byChild = items(
                for: request.studentIDs, on: earlierByLesson[request.lessonID] ?? [], open: open,
                order: sequences.order
            )
            if !byChild.isEmpty { result[key] = byChild }
        }
        return result
    }

    /// One open row as one child's: the row, and whether logging it closes it
    /// for her alone.
    private struct OpenRow {
        let work: CDWorkModel
        let isHersAlone: Bool
    }

    /// Each of `openRows`, by lesson and then by each of `children` it is
    /// open work of. A row naming one child is hers whatever else is on its
    /// lesson; only the lessons where a row names more are read whole, in one
    /// more fetch, to tell linked copies from a shared row.
    private static func openWork(
        _ openRows: [CDWorkModel], for children: Set<UUID>, in context: NSManagedObjectContext
    ) -> [String: [UUID: [OpenRow]]] {
        let rows = rowsToTellApart(openRows, in: context)
        let visibility = WorkVisibility(rows: rows)
        var rowsByLesson: [String: [CDWorkModel]] = [:]
        for row in rows { rowsByLesson[row.lessonID, default: []].append(row) }

        var open: [String: [UUID: [OpenRow]]] = [:]
        for row in openRows {
            let named = WorkGrouping.studentIDs(of: row)
            let owner = WorkGrouping.owner(of: row)
            // More than one child named: hers alone only as one of a set of
            // linked copies, never as a shared row.
            let isLinkedCopy = named.count > 1 && !WorkGrouping.closure(
                from: row, among: (rowsByLesson[row.lessonID] ?? []).filter { $0 !== row }
            ).filter { $0 !== row }.isEmpty
            for child in QuietStudentsOrder.openStudentIDs(of: row, visibility: visibility)
            where children.contains(child) {
                let hersAlone = owner == child && (named.count <= 1 || isLinkedCopy)
                open[row.lessonID, default: [:]][child, default: []].append(
                    OpenRow(work: row, isHersAlone: hersAlone)
                )
            }
        }
        return open
    }

    /// `openRows`, plus every row on the lessons where one of them names more
    /// than one child (`WorkVisibility(covering:)`'s fetch, kept in hand here
    /// for the linked-copy test).
    private static func rowsToTellApart(
        _ openRows: [CDWorkModel], in context: NSManagedObjectContext
    ) -> [CDWorkModel] {
        let lessonIDs = Set(openRows.filter { WorkGrouping.studentIDs(of: $0).count > 1 }.map(\.lessonID))
        guard !lessonIDs.isEmpty else { return openRows }
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(format: "lessonID IN %@", Array(lessonIDs))
        request.relationshipKeyPathsForPrefetching = ["participants"]
        var seen = Set<ObjectIdentifier>()
        return (openRows + context.safeFetch(request)).filter {
            !$0.isDeleted && seen.insert(ObjectIdentifier($0)).inserted
        }
    }

    /// One request's answer, out of the open rows already sorted by lesson.
    private static func items(
        for children: Set<UUID>,
        on earlier: [String],
        open: [String: [UUID: [OpenRow]]],
        order: LessonSequenceOrder
    ) -> ByChild {
        var byChild: ByChild = [:]
        for lessonID in earlier {
            guard let byStudent = open[lessonID], let position = order.position(of: lessonID) else { continue }
            for child in children {
                for row in byStudent[child] ?? [] {
                    byChild[child, default: []].append(Item(
                        work: row.work,
                        studentID: child,
                        lessonID: lessonID,
                        lessonName: LessonFormatter.lessonName(
                            position.name, orRowTitle: row.work.title, missing: LessonFormatter.untitledWork
                        ),
                        step: position.step,
                        isHersAlone: row.isHersAlone
                    ))
                }
            }
        }
        return byChild.mapValues { $0.sorted(by: isOrderedBefore) }
    }

    /// The open rows on `lessonIDs` that name one of the children, as owner
    /// or participant. Participants are prefetched: who a row is open for is
    /// read from them.
    static func openRowsRequest(lessonIDs: Set<String>, studentIDs: Set<UUID>) -> NSFetchRequest<CDWorkModel> {
        let ids = studentIDs.map(\.uuidString)
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "lessonID IN %@", Array(lessonIDs)),
            WorkStatus.openPredicate,
            NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "studentID IN %@", ids),
                NSPredicate(format: "ANY participants.studentID IN %@", ids)
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
