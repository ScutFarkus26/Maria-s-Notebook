// WorkPeers.swift
// Who else is doing the same work.
//
// A work item is one child's row. `assign_work` and the Quick New Work sheet
// give six children the same invitation by writing six rows, so a guide looking
// at one card cannot see the other five — the group is only recoverable from
// the rows themselves (see `WorkGrouping`).
//
// This answers the question from any single row, and it is deliberately wider
// than `WorkGrouping.group(containing:)`. That recovers the rows created
// *together*; a child given the same work a week later is still doing the same
// work, and a guide asking "who else has this?" means her too. So the test here
// is the work itself — same lesson, same title — not the batch it came from.

import CoreData
import Foundation

/// One other child doing the work that was asked about.
struct WorkPeer: Identifiable, Equatable {
    /// The child, which is also this row's identity in a menu.
    let id: UUID
    let name: String
    /// The record to reveal for her: her own copy, or the shared row she rides
    /// on. Nil only for a row with no id, which nothing can route to.
    let workID: UUID?
    /// "Practice · 6d" — what her work is and how long it has sat.
    let detail: String
    /// Whether her copy is in the workspace's Attention list. The guide asking
    /// who else has this usually wants to know whose has gone quiet.
    let needsAttention: Bool
}

/// The answer to "who else?".
struct WorkPeerList: Equatable {
    let peers: [WorkPeer]

    /// Children who have finished the same work. Counted rather than listed:
    /// the question is who is *doing* it, and a finished record cannot be
    /// revealed in a workspace that holds only open work.
    let finishedCount: Int

    static let none = WorkPeerList(peers: [], finishedCount: 0)

    var isEmpty: Bool { peers.isEmpty && finishedCount == 0 }
}

@MainActor
enum WorkPeers {

    // MARK: - The two questions

    /// Everyone else with the same work as `work`: the same lesson and the
    /// same title, whether they were given it together or separately.
    ///
    /// The row asked about is included in the scan, not skipped — on a shared
    /// project or book-club row the other children named on it are doing that
    /// very work, and they are the answer's most obvious members.
    static func others(
        doing work: CDWorkModel, in context: NSManagedObjectContext
    ) -> WorkPeerList {
        let title = WorkGrouping.normalizedTitle(work.title)
        let rows = rows(onLessonID: work.lessonID, in: context)
            .filter { WorkGrouping.normalizedTitle($0.title) == title }
        return list(
            from: rows,
            excluding: WorkGrouping.owner(of: work),
            naming: .kind,
            in: context
        )
    }

    /// Everyone with work on a lesson, whatever that work is — the question a
    /// lesson can answer, as against a single work item's.
    static func children(
        workingOn lessonID: UUID, in context: NSManagedObjectContext
    ) -> WorkPeerList {
        list(
            from: rows(onLessonID: lessonID.uuidString, in: context),
            excluding: nil,
            naming: .work,
            in: context
        )
    }

    // MARK: - Building the answer

    /// What each row says about itself in the list. Naming the kind is enough
    /// when every row is the same work; naming the work is what distinguishes
    /// them when the only thing shared is the lesson.
    private enum Detail {
        case kind
        case work
    }

    private static func list(
        from rows: [CDWorkModel],
        excluding subject: UUID?,
        naming detail: Detail,
        in context: NSManagedObjectContext
    ) -> WorkPeerList {
        let open = rows.filter { $0.status.isOpen }
        let finished = rows.filter { $0.status.isClosed }

        // Owners first, so a child who has a copy of her own is pointed at it
        // rather than at a row she is only named on.
        var claimed: Set<UUID> = subject.map { [$0] } ?? []
        var found: [(studentID: UUID, work: CDWorkModel)] = []
        for row in open {
            guard let owner = WorkGrouping.owner(of: row), claimed.insert(owner).inserted else { continue }
            found.append((owner, row))
        }
        for row in open {
            for id in WorkGrouping.studentIDs(of: row) where claimed.insert(id).inserted {
                found.append((id, row))
            }
        }

        let finishedIDs = Set(finished.flatMap(WorkGrouping.studentIDs(of:))).subtracting(claimed)
        let names = names(for: Set(found.map(\.studentID)).union(finishedIDs), in: context)
        let ages = ages(of: open, in: context)

        let peers = found.compactMap { entry -> WorkPeer? in
            // A child whose name does not resolve is left out rather than
            // listed as "Student": she is a withdrawn record, a hidden test
            // child, or a row pointing at a student who no longer exists, and
            // none of those answer the guide's question.
            guard let name = names[entry.studentID] else { return nil }
            return WorkPeer(
                id: entry.studentID,
                name: name,
                workID: entry.work.id,
                detail: describe(
                    entry.work,
                    days: entry.work.id.flatMap { ages[$0] } ?? 0,
                    naming: detail
                ),
                needsAttention: LessonsAndWorkTriage.bucket(for: entry.work, context: context) == .attention
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        return WorkPeerList(
            peers: peers,
            finishedCount: finishedIDs.count { names[$0] != nil }
        )
    }

    private static func describe(_ work: CDWorkModel, days: Int, naming detail: Detail) -> String {
        let kind = (work.kind ?? .research).displayName
        let title = work.title.trimmed()
        // Falls back to the kind rather than to the lesson name: every row in
        // a lesson's list carries the same lesson, so it distinguishes nothing.
        let lead = detail == .work && !title.isEmpty ? title : kind
        return "\(lead) · \(days)d"
    }

    // MARK: - Reading the store

    private static func rows(
        onLessonID lessonID: String, in context: NSManagedObjectContext
    ) -> [CDWorkModel] {
        guard !lessonID.isEmpty else { return [] }
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(format: "lessonID == %@", lessonID)
        return context.safeFetch(request)
    }

    private static func names(
        for ids: Set<UUID>, in context: NSManagedObjectContext
    ) -> [UUID: String] {
        guard !ids.isEmpty else { return [:] }
        let request = CDFetchRequest(CDStudent.self)
        request.predicate = NSPredicate(format: "id IN %@", Array(ids))
        let visible = TestStudentsFilter.filterVisible(context.safeFetch(request))
        return Dictionary(
            visible.compactMap { student in
                student.id.map { ($0, StudentFormatter.displayName(for: student)) }
            },
            // CloudKit sync can leave two rows with one id.
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// School days since the guide last did anything with each row — the same
    /// number by the same two steps the card itself uses, so a peer's age and
    /// her own card cannot disagree.
    private static func ages(
        of rows: [CDWorkModel], in context: NSManagedObjectContext
    ) -> [UUID: Int] {
        let calendar = SchoolCalendarService.shared
        let today = Date()
        let touched = rows.map { row in
            WorkAgingPolicy.lastMeaningfulTouchDate(
                for: row,
                checkIns: (row.checkIns?.allObjects as? [CDWorkCheckIn]) ?? [],
                notes: (row.unifiedNotes?.allObjects as? [CDNote]) ?? []
            )
        }
        // One preload for the whole range, so each count below is a cache hit
        // rather than a fetch per row.
        if let earliest = touched.min() {
            calendar.preloadNonSchoolDays(from: earliest, to: today, using: context)
        }

        var result: [UUID: Int] = [:]
        for (row, date) in zip(rows, touched) {
            guard let id = row.id else { continue }
            result[id] = calendar.schoolDaysSinceCreation(createdAt: date, asOf: today, using: context)
        }
        return result
    }
}
