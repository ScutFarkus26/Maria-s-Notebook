// StudentDataWiper.swift
// Centralized helper to wipe lesson/work history for specific students by name.
// Scopes deletions to the two target students only and avoids collateral damage to other students.

import Foundation
import SwiftData

struct StudentDataWiper {
    /// Wipes lesson and work history for the two specific students by full name (case-insensitive):
    /// "Danny De Berry" and "Lil Dan D".
    ///
    /// This method:
    /// - Locates the students by name
    /// - Removes them from Presentations (deletes presentations that become empty)
    /// - Updates or deletes StudentLessons that include them
    /// - Removes them from WorkModel participants (deletes works that become orphaned)
    /// - Deletes their WorkContracts
    /// - Deletes their WorkCompletionRecords
    /// - Deletes ScopedNotes that explicitly reference these students or their related entities
    ///
    /// It does NOT delete the Student records themselves, shared Lessons/Albums, or other students' data.
    /// - Parameters:
    ///   - context: SwiftData ModelContext to operate on.
    /// - Returns: A human-readable summary string for logging/UI.
    static func wipeDannyAndLilDanD(using context: ModelContext) throws -> String {
        // 1) Resolve target students by full name (case-insensitive)
        let students = try context.fetch(FetchDescriptor<Student>())
        let targetNamesLower: Set<String> = [
            "danny de berry",
            "lil dan d"
        ]
        let targets: [Student] = students.filter { s in
            let trimmedLower = s.fullName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return targetNamesLower.contains(trimmedLower)
        }
        let targetIDs: Set<UUID> = Set(targets.map { $0.id })
        guard !targets.isEmpty else {
            let msg = "[StudentDataWiper] No matching students found for request."
            print(msg)
            return "No matching students found."
        }

        // 2) Presentations — remove target students from studentIDs; delete presentation if empty after removal
        let allPresentations = try context.fetch(FetchDescriptor<Presentation>())
        var presentationsChanged = 0
        var presentationsDeleted = 0
        for p in allPresentations {
            let uuids = p.studentUUIDs
            if targetIDs.isDisjoint(with: Set(uuids)) { continue }
            let remaining = p.studentIDs.filter { raw in
                if let id = UUID(uuidString: raw) { return !targetIDs.contains(id) }
                return true
            }
            if remaining.isEmpty {
                context.delete(p)
                presentationsDeleted += 1
            } else if remaining.count != p.studentIDs.count {
                p.studentIDs = remaining
                presentationsChanged += 1
            }
        }

        // 3) StudentLessons — remove target IDs; delete if no students remain
        let allSLs = try context.fetch(FetchDescriptor<StudentLesson>())
        var slUpdated = 0
        var slDeleted = 0
        for sl in allSLs {
            let beforeIDs = sl.studentIDs
            let afterIDs = beforeIDs.filter { !targetIDs.contains($0) }
            if afterIDs.count == beforeIDs.count { continue }
            if afterIDs.isEmpty {
                context.delete(sl)
                slDeleted += 1
            } else {
                sl.studentIDs = afterIDs
                // Also prune relationship to keep it consistent
                sl.students = sl.students.filter { !targetIDs.contains($0.id) }
                slUpdated += 1
            }
        }

        // 4) WorkModels — remove target participants; delete work if no participants remain
        let allWorks = try context.fetch(FetchDescriptor<WorkModel>())
        var worksUpdated = 0
        var worksDeleted = 0
        for w in allWorks {
            let beforeCount = (w.participants ?? []).count
            if beforeCount == 0 { continue }
            let current = w.participants ?? []
            let remaining = current.filter { !targetIDs.contains($0.studentID) }
            w.participants = remaining
            let afterCount = (w.participants ?? []).count
            if afterCount == beforeCount { continue }
            if afterCount == 0 {
                // Deleting the work will cascade to its check-ins and scoped notes per model delete rules
                context.delete(w)
                worksDeleted += 1
            } else {
                worksUpdated += 1
            }
        }

        // 5) WorkCompletionRecords — delete for target students only
        let allCompletions = try context.fetch(FetchDescriptor<WorkCompletionRecord>())
        var completionsDeleted = 0
        for rc in allCompletions where targetIDs.contains(rc.studentID) {
            context.delete(rc)
            completionsDeleted += 1
        }

        // 6) WorkContracts — delete contracts for target students only
        if let contracts = try? context.fetch(FetchDescriptor<WorkContract>()) {
            var contractsDeleted = 0
            for c in contracts {
                if let sid = UUID(uuidString: c.studentID), targetIDs.contains(sid) {
                    context.delete(c)
                    contractsDeleted += 1
                }
            }
            if contractsDeleted > 0 {
                // Continue; any scoped notes tied to these contracts will be handled below
            }
        }

        // 7) ScopedNotes — delete notes explicitly scoped to these students or tied to entities still containing them
        let allScopedNotes = try context.fetch(FetchDescriptor<ScopedNote>())
        var scopedNotesDeleted = 0
        notesLoop: for n in allScopedNotes {
            // Delete if scope explicitly includes these students
            switch n.scope {
            case .all:
                break
            case .student(let sid):
                if targetIDs.contains(sid) {
                    context.delete(n)
                    scopedNotesDeleted += 1
                    continue notesLoop
                }
            case .students(let ids):
                if !Set(ids).isDisjoint(with: targetIDs) {
                    context.delete(n)
                    scopedNotesDeleted += 1
                    continue notesLoop
                }
            }
            // Delete if attached StudentLesson still includes any target student
            if let sl = n.studentLesson {
                if !Set(sl.studentIDs).isDisjoint(with: targetIDs) {
                    context.delete(n)
                    scopedNotesDeleted += 1
                    continue notesLoop
                }
            }
            // Delete if attached WorkModel still includes any target student (participant)
            if let w = n.work {
                let ids = Set((w.participants ?? []).map { $0.studentID })
                if !ids.isDisjoint(with: targetIDs) {
                    context.delete(n)
                    scopedNotesDeleted += 1
                    continue notesLoop
                }
            }
            // Delete if attached WorkContract belongs to a target student
            if let wc = n.workContract, let sid = UUID(uuidString: wc.studentID), targetIDs.contains(sid) {
                context.delete(n)
                scopedNotesDeleted += 1
                continue notesLoop
            }
            // Notes attached to Presentations are left alone unless they were explicitly scoped to the target students above
        }

        let summary = "Presentations changed: \(presentationsChanged), deleted: \(presentationsDeleted); StudentLessons updated: \(slUpdated), deleted: \(slDeleted); Works updated: \(worksUpdated), deleted: \(worksDeleted); WorkCompletions deleted: \(completionsDeleted); ScopedNotes deleted: \(scopedNotesDeleted)"
        print("[StudentDataWiper] Wipe complete for Danny + Lil Dan D → \(summary)")
        return summary
    }
}
