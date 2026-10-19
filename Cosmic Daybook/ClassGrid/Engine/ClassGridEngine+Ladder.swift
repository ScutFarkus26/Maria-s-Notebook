// ClassGridEngine+Ladder.swift
// The rung a Three Years cell climbs to, by the one ladder every Class Grid view
// reads (`ChecklistDisplayStatus.resolve`).

import Foundation

nonisolated extension ClassGridEngine {

    /// The one ladder (`ChecklistDisplayStatus.resolve`) from a cell's records.
    /// Three Years has no plans or readiness to read, so a lesson with nothing
    /// recorded is Not yet (the faint dot), never Ready.
    static func ladderRung(
        isMastered: Bool, workStatuses: [WorkStatus], practiceSessions: Int, isPresented: Bool
    ) -> ChecklistDisplayStatus {
        let rung = ChecklistDisplayStatus.resolve(
            isMastered: isMastered,
            workStatuses: workStatuses,
            practiceSessions: practiceSessions,
            isPresented: isPresented,
            isPlanned: false
        )
        return rung == .ready ? .notReady : rung
    }
}
