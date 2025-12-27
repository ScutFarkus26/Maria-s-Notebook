// WorkDataMaintenance.swift
// Best-effort data maintenance helpers for WorkModel.
// Behavior-preserving cleanup: comments and MARKs only.

import Foundation
import SwiftData

/// Non-critical maintenance utilities for keeping WorkModel data consistent.
/// These functions are idempotent and safe to call multiple times.
enum WorkDataMaintenance {
    // MARK: - Helpers
    /// Builds participant entities for the given student IDs and work item.
    /// Kept simple to help the compiler with type-checking.
    private static func makeParticipants(from studentIDs: [UUID], for work: WorkModel) -> [WorkParticipantEntity] {
        var result: [WorkParticipantEntity] = []
        result.reserveCapacity(studentIDs.count)
        for sid in studentIDs {
            let participant = WorkParticipantEntity(
                studentID: sid,
                completedAt: nil,
                work: work
            )
            result.append(participant)
        }
        return result
    }

    // MARK: - Backfill
    /// Backfill participants for any WorkModel that is missing them.
    /// If a WorkModel links to a StudentLesson, mirror its studentIDs into participants.
    /// Safe to call multiple times; it is idempotent.
    static func backfillParticipantsIfNeeded(using context: ModelContext) {
        do {
            // Fetch all WorkModel objects first
            let workFetch = FetchDescriptor<WorkModel>()
            let works: [WorkModel] = try context.fetch(workFetch)

            let lessonFetch: FetchDescriptor<StudentLesson> = FetchDescriptor<StudentLesson>()
            let allLessons: [StudentLesson] = try context.fetch(lessonFetch)
            var lessonsByID: [UUID: StudentLesson] = [:]
            lessonsByID.reserveCapacity(allLessons.count)
            for lesson in allLessons {
                lessonsByID[lesson.id] = lesson
            }

            var changed = false

            // Iterate and handle only those missing participants
            for w in works {
                let participantsOptional: [WorkParticipantEntity]? = w.participants
                var hasNoParticipants: Bool = true
                if let existing = participantsOptional {
                    hasNoParticipants = existing.isEmpty
                }
                guard hasNoParticipants else { continue }

                // If there's a linked StudentLesson, mirror its studentIDs
                guard let slID = w.studentLessonID else { continue }

                guard let sl = lessonsByID[slID] else { continue }

                // Build participants in simple, explicit steps
                let studentIDs: [UUID] = sl.studentIDs
                if studentIDs.isEmpty { continue }

                let newParticipants: [WorkParticipantEntity] = makeParticipants(from: studentIDs, for: w)
                if !newParticipants.isEmpty {
                    w.participants = newParticipants
                    changed = true
                }
            }

            if changed {
                try context.save()
            }
        } catch {
            // Non-fatal; maintenance best-effort
        }
    }

    // MARK: - Migration
    /// Migrate WorkModel data to WorkContract structure.
    /// Runs once, guarded by UserDefaults flag.
    static func migrateWorksToContractsIfNeeded(using context: ModelContext) {
        let flagKey = "Migration.workToContracts.v1"
        if UserDefaults.standard.bool(forKey: flagKey) { return }

        // Ensure participants exist on legacy works before migrating
        backfillParticipantsIfNeeded(using: context)

        do {
            let works = try context.fetch(FetchDescriptor<WorkModel>())
            guard !works.isEmpty else {
                UserDefaults.standard.set(true, forKey: flagKey)
                return
            }
            let studentLessons = try context.fetch(FetchDescriptor<StudentLesson>())
            let slByID = Dictionary(uniqueKeysWithValues: studentLessons.map { ($0.id, $0) })

            let existingContracts = try context.fetch(FetchDescriptor<WorkContract>())
            // Keyed by studentID|lessonID
            var contractByKey: [String: WorkContract] = [:]
            for c in existingContracts {
                let key = c.studentID + "|" + c.lessonID
                contractByKey[key] = c
            }

            // Group check-ins by workID for quick access
            let allCheckIns = try context.fetch(FetchDescriptor<WorkCheckIn>())
            var checkInsByWork: [UUID: [WorkCheckIn]] = [:]
            for ci in allCheckIns { checkInsByWork[ci.workID, default: []].append(ci) }

            var didChange = false

            for w in works {
                guard let slID = w.studentLessonID, let sl = slByID[slID] else { continue }
                let lessonID = sl.lessonID

                let participants = w.participants ?? []
                if participants.isEmpty { continue }

                for p in participants {
                    let sidStr = p.studentID.uuidString
                    let lidStr = lessonID.uuidString
                    let key = sidStr + "|" + lidStr

                    let contract: WorkContract
                    if let existing = contractByKey[key] {
                        contract = existing
                    } else {
                        // Map WorkModel.WorkType to WorkKind
                        let mappedKind: WorkKind? = {
                            switch w.workType {
                            case .practice: return .practiceLesson
                            case .followUp: return .followUpAssignment
                            case .research: return .research
                            }
                        }()

                        let c = WorkContract(studentID: sidStr, lessonID: lidStr, presentationID: nil, status: .active)
                        c.createdAt = w.createdAt
                        c.kind = mappedKind
                        context.insert(c)
                        contractByKey[key] = c
                        contract = c
                        didChange = true
                    }

                    // Completion mapping (participant wins; fall back to work completion)
                    if let pc = p.completedAt {
                        contract.status = .complete
                        contract.completedAt = pc
                        didChange = true
                    } else if let wc = w.completedAt {
                        contract.status = .complete
                        contract.completedAt = wc
                        didChange = true
                    }

                    // Translate WorkCheckIns -> WorkPlanItems
                    if let cis = checkInsByWork[w.id] {
                        for ci in cis {
                            // Build a compact note from purpose/note
                            let purpose = ci.purpose.trimmingCharacters(in: .whitespacesAndNewlines)
                            let note = ci.note.trimmingCharacters(in: .whitespacesAndNewlines)
                            var combined = ""
                            if !purpose.isEmpty { combined = "Purpose: \(purpose)" }
                            if !note.isEmpty { combined = combined.isEmpty ? note : combined + "\n" + note }
                            let item = WorkPlanItem(workID: contract.id, scheduledDate: ci.date, reason: .progressCheck, note: combined.isEmpty ? nil : combined)
                            context.insert(item)
                            didChange = true
                        }
                    }

                    // Copy standard Note items to ScopedNotes scoped to this student & contract
                    for n in (w.noteItems) {
                        let body = n.body
                        let created = n.createdAt
                        let updated = n.updatedAt
                        // Scope to the specific student
                        let scoped = ScopedNote(createdAt: created, updatedAt: updated, body: body, scope: .student(p.studentID), legacyFingerprint: nil, migrationKey: "migratedFromWorkModel:\(w.id.uuidString)", studentLesson: nil, work: nil, presentation: nil, workContract: contract)
                        context.insert(scoped)
                        didChange = true
                    }

                    // Copy scoped notes on the work when appropriate for this student
                    for sn in (w.scopedNotes) {
                        let include: Bool = {
                            switch sn.scope {
                            case .all: return true
                            case .student(let sid): return sid == p.studentID
                            case .students(let ids): return ids.contains(p.studentID)
                            }
                        }()
                        guard include else { continue }
                        let dup = ScopedNote(createdAt: sn.createdAt, updatedAt: sn.updatedAt, body: sn.body, scope: sn.scope, legacyFingerprint: sn.legacyFingerprint, migrationKey: "migratedFromWorkModelScoped:\(w.id.uuidString)", studentLesson: nil, work: nil, presentation: nil, workContract: contract)
                        context.insert(dup)
                        didChange = true
                    }
                }
            }

            if didChange { try context.save() }
            UserDefaults.standard.set(true, forKey: flagKey)
        } catch {
            // Best-effort; do not set the flag so we can retry later
        }
    }
}

