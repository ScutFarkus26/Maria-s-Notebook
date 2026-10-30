// ReportBoard.swift
// Every child's report at once, for the Reports view in Lessons & Work
// (2026-10-30): one row per report however many children write it, grouped
// by stage, with who presents soon above and what was presented this school
// year below.

import CoreData
import Foundation

struct ReportBoard {

    /// One report: its linked copies folded into the one row.
    struct Report: Identifiable {
        /// The copy the row reads and acts on: the first still open, or else
        /// the first presented.
        let anchor: CDWorkModel
        /// Everyone still writing it (or who presented it), in copy order.
        let studentIDs: [UUID]
        let stageName: String
        let presentDay: Date?
        let isResting: Bool
        let presentedOn: Date?

        var id: NSManagedObjectID { anchor.objectID }
    }

    struct StageGroup: Identifiable {
        let name: String
        let reports: [Report]
        var id: String { name }
    }

    /// Open reports with a day to present within two weeks, soonest first.
    let presentingSoon: [Report]
    /// Open reports not resting, by stage in the five stages' order (a
    /// report's own stage names after them).
    let stages: [StageGroup]
    let resting: [Report]
    /// Presented since `yearStart`, newest first.
    let presented: [Report]

    var isEmpty: Bool { stages.isEmpty && resting.isEmpty && presented.isEmpty }

    static func make(
        from rows: [CDWorkModel], yearStart: Date, context: NSManagedObjectContext, now: Date = Date()
    ) -> ReportBoard {
        let reports = fold(rows, context: context, now: now)
        let open = reports.filter { $0.anchor.status.isOpen }
        let soonEnd = AppCalendar.addingDays(14, to: AppCalendar.startOfDay(now))
        let presentingSoon = open
            .filter { report in report.presentDay.map { $0 < soonEnd } ?? false }
            .sorted { ($0.presentDay ?? .distantFuture) < ($1.presentDay ?? .distantFuture) }

        let working = open.filter { !$0.isResting }
        let names = Dictionary(grouping: working, by: \.stageName)
        let ownNames = names.keys.filter { !ReportStages.standardTitles.contains($0) }.sorted()
        let order = ReportStages.standardTitles + ownNames
        let stages = order.compactMap { name in
            names[name].map { StageGroup(name: name, reports: $0) }
        }

        let presented = reports
            .filter { ReportStages.hasBeenPresented($0.anchor) && ($0.presentedOn ?? .distantPast) >= yearStart }
            .sorted { ($0.presentedOn ?? .distantPast) > ($1.presentedOn ?? .distantPast) }

        return ReportBoard(
            presentingSoon: presentingSoon,
            stages: stages,
            resting: open.filter(\.isResting),
            presented: presented
        )
    }

    /// One `Report` per group of linked copies. A group whose copies were
    /// all closed some other way (dropped) isn't listed.
    private static func fold(_ rows: [CDWorkModel], context: NSManagedObjectContext, now: Date) -> [Report] {
        var seen: Set<NSManagedObjectID> = []
        var reports: [Report] = []
        for row in rows where ReportStages.isReport(row) && !seen.contains(row.objectID) {
            let members = WorkGrouping.group(containing: row, in: context).members
            members.forEach { seen.insert($0.objectID) }
            let live = members.filter { $0.status.isOpen || ReportStages.hasBeenPresented($0) }
            guard let anchor = live.first(where: { $0.status.isOpen }) ?? live.first,
                  let stageName = ReportStages.stageName(of: anchor) else { continue }
            reports.append(Report(
                anchor: anchor,
                studentIDs: live.compactMap(WorkGrouping.owner(of:)),
                stageName: stageName,
                presentDay: ReportStages.presentDay(of: anchor),
                isResting: anchor.isResting(asOf: now),
                presentedOn: ReportStages.hasBeenPresented(anchor) ? anchor.completedAt : nil
            ))
        }
        return reports
    }
}
