// NotesBackfillService.swift
// Adds manual, idempotent backfill from legacy notes to new lifecycle models.

import Foundation
import SwiftData

struct NotesBackfillService {
    struct Report {
        var presentationsTouched: Int = 0
        var workContractsTouched: Int = 0
        var presentationNotesCreated: Int = 0
        var presentationNotesSkipped: Int = 0
        var notesCreated: Int = 0
        var notesSkippedAsDuplicates: Int = 0
        var unmatched: Int = 0
        var errors: [String] = []

        var errorCount: Int { errors.count }

        func summaryString(elapsed: TimeInterval) -> String {
            let base = [
                String(format: "Completed in %.2fs", elapsed),
                "Presentations touched: \(presentationsTouched)",
                "WorkContracts touched: \(workContractsTouched)",
                "Presentation notes created: \(presentationNotesCreated)",
                "Presentation notes skipped: \(presentationNotesSkipped)",
                "Notes created: \(notesCreated)",
                "Notes skipped as duplicates: \(notesSkippedAsDuplicates)",
                "Unmatched legacy notes: \(unmatched)",
                errors.isEmpty ? "Errors: 0" : "Errors: \(errors.count)\n\(errors.joined(separator: "\n"))"
            ]
            return base.joined(separator: "\n")
        }
    }

    /// Entry point. Runs synchronously; callers may wrap in a Task if needed.
    static func run(modelContext: ModelContext) throws -> Report {
        let start = Date()
        var report = Report()

        // Build quick lookup maps for Presentations and WorkContracts
        let presentations = try modelContext.fetch(FetchDescriptor<Presentation>())
        let presentationsByLegacySL: [UUID: Presentation] = Dictionary(
            presentations.compactMap { p in
                guard let raw = p.legacyStudentLessonID, let id = UUID(uuidString: raw) else { return nil }
                return (id, p)
            },
            uniquingKeysWith: { existing, _ in existing }
        )

        let contracts = try modelContext.fetch(FetchDescriptor<WorkContract>())
        let contractsByLegacySLAndStudent: [String: WorkContract] = Dictionary(
            contracts.compactMap { wc in
                guard let slRaw = wc.legacyStudentLessonID, let slID = UUID(uuidString: slRaw), let studentID = UUID(uuidString: wc.studentID) else { return nil }
                return (key(slID, studentID), wc)
            },
            uniquingKeysWith: { existing, _ in existing }
        )
        let contractsByLessonAndStudent: [String: WorkContract] = Dictionary(
            contracts.compactMap { wc in
                guard let lessonID = UUID(uuidString: wc.lessonID), let studentID = UUID(uuidString: wc.studentID) else { return nil }
                return (key(lessonID, studentID), wc)
            },
            uniquingKeysWith: { existing, _ in existing }
        )

        // Build a set of existing migration keys to ensure idempotency quickly.
        let existingNotes = try modelContext.fetch(FetchDescriptor<ScopedNote>())
        var existingMigrationKeys: Set<String> = Set(existingNotes.compactMap { $0.migrationKey })

        // Batch save control
        var pendingWrites = 0
        func flush(reason: String) {
            if modelContext.hasChanges {
                do {
                    try modelContext.save()
                } catch {
                    report.errors.append("Save failed (\(reason)): \(error.localizedDescription)")
                }
            }
            pendingWrites = 0
        }

        // 3A) StudentLesson → Presentation
        let slFetch = FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.isPresented == true || $0.givenAt != nil })
        let studentLessons = try modelContext.fetch(slFetch)
        for sl in studentLessons {
            guard let presentation = presentationsByLegacySL[sl.id] else { continue }
            let trimmedNotesString = sl.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            // Copy attached ScopedNotes from StudentLesson to Presentation
            for legacy in sl.scopedNotes {
                // migrationKey: studentLessonScopedNote:<slID>:<legacyScopedNoteID>
                let mk = "studentLessonScopedNote:\(sl.id.uuidString):\(legacy.id.uuidString)"
                if existingMigrationKeys.contains(mk) {
                    report.notesSkippedAsDuplicates += 1
                    report.presentationNotesSkipped += 1
                    continue
                }
                let newNote = ScopedNote(
                    createdAt: legacy.createdAt,
                    updatedAt: legacy.updatedAt,
                    body: legacy.body,
                    scope: legacy.scope,
                    legacyFingerprint: legacy.legacyFingerprint,
                    migrationKey: mk,
                    studentLesson: nil,
                    work: nil,
                    presentation: presentation,
                    workContract: nil
                )
                modelContext.insert(newNote)
                existingMigrationKeys.insert(mk)
                report.notesCreated += 1
                report.presentationNotesCreated += 1
                pendingWrites += 1
            }
            // Also migrate legacy StudentLesson freeform notes string → Presentation (single group note)
            if !trimmedNotesString.isEmpty {
                let mk2 = "studentLessonNotesString:\(sl.id.uuidString)"
                if existingMigrationKeys.contains(mk2) {
                    report.notesSkippedAsDuplicates += 1
                    report.presentationNotesSkipped += 1
                } else {
                    let created = sl.givenAt ?? sl.createdAt
                    let newNote = ScopedNote(
                        createdAt: created,
                        updatedAt: created,
                        body: trimmedNotesString,
                        scope: .all,
                        legacyFingerprint: nil,
                        migrationKey: mk2,
                        studentLesson: nil,
                        work: nil,
                        presentation: presentation,
                        workContract: nil
                    )
                    modelContext.insert(newNote)
                    existingMigrationKeys.insert(mk2)
                    report.notesCreated += 1
                    report.presentationNotesCreated += 1
                    pendingWrites += 1
                }
            }
            if sl.scopedNotes.isEmpty == false || !trimmedNotesString.isEmpty { report.presentationsTouched += 1 }
            if pendingWrites >= 100 { flush(reason: "batch StudentLesson→Presentation") }
        }

        // 3B) WorkModel → WorkContract and/or Presentation
        let works = try modelContext.fetch(FetchDescriptor<WorkModel>())
        for work in works {
            // Legacy note sources: ScopedNote on WorkModel and/or the WorkModel.notes string and Note items
            var legacyNotes: [(id: UUID, createdAt: Date, updatedAt: Date, body: String, scope: ScopedNote.Scope)] = []
            for n in work.scopedNotes {
                legacyNotes.append((id: n.id, createdAt: n.createdAt, updatedAt: n.updatedAt, body: n.body, scope: n.scope))
            }
            // If there is a legacy freeform notes string, migrate as a single group note
            let trimmed = work.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                // Synthesize a deterministic UUID for the string note key based on WorkModel.id
                let syntheticID = UUID(uuidString: work.id.uuidString) ?? work.id
                legacyNotes.append((id: syntheticID, createdAt: work.createdAt, updatedAt: work.completedAt ?? work.createdAt, body: trimmed, scope: .all))
            }
            // Append legacy notes from standard Note items
            for note in work.noteItems {
                let scope = convert(note.scope)
                legacyNotes.append((id: note.id, createdAt: note.createdAt, updatedAt: note.updatedAt, body: note.body, scope: scope))
            }

            guard !legacyNotes.isEmpty else { continue }

            // Try to resolve best targets for each note
            let slID = work.studentLessonID
            let participantStudentIDs: [UUID] = work.participants.map { $0.studentID }

            // Candidate presentation by legacy student lesson id
            var candidatePresentation: Presentation? = nil
            if let slID { candidatePresentation = presentationsByLegacySL[slID] }
            let lessonUUIDFromPresentation: UUID? = candidatePresentation.flatMap { UUID(uuidString: $0.lessonID) }

            for ln in legacyNotes {
                let scope = ln.scope
                switch scope {
                case .all:
                    // Group note: prefer Presentation if available; otherwise copy to each per-student WorkContract
                    if let presentation = candidatePresentation {
                        let mk = "workModel:\(work.id.uuidString):note:\(ln.id.uuidString):presentation:\(presentation.id.uuidString)"
                        if existingMigrationKeys.contains(mk) {
                            report.notesSkippedAsDuplicates += 1
                        } else {
                            let newNote = ScopedNote(
                                createdAt: ln.createdAt,
                                updatedAt: ln.updatedAt,
                                body: ln.body,
                                scope: .all,
                                legacyFingerprint: nil,
                                migrationKey: mk,
                                studentLesson: nil,
                                work: nil,
                                presentation: presentation,
                                workContract: nil
                            )
                            modelContext.insert(newNote)
                            existingMigrationKeys.insert(mk)
                            report.notesCreated += 1
                            report.presentationsTouched += 1
                            pendingWrites += 1
                        }
                    } else {
                        // No presentation: copy once per matched WorkContract
                        var matchedAny = false
                        for sid in participantStudentIDs {
                            if let wc = resolveContract(slID: slID, lessonID: lessonUUIDFromPresentation, studentID: sid, contractsByLegacySLAndStudent: contractsByLegacySLAndStudent, contractsByLessonAndStudent: contractsByLessonAndStudent) {
                                matchedAny = true
                                let mk = "workModel:\(work.id.uuidString):note:\(ln.id.uuidString):student:\(sid.uuidString)"
                                if existingMigrationKeys.contains(mk) {
                                    report.notesSkippedAsDuplicates += 1
                                } else {
                                    let newNote = ScopedNote(
                                        createdAt: ln.createdAt,
                                        updatedAt: ln.updatedAt,
                                        body: ln.body,
                                        scope: .all,
                                        legacyFingerprint: nil,
                                        migrationKey: mk,
                                        studentLesson: nil,
                                        work: nil,
                                        presentation: nil,
                                        workContract: wc
                                    )
                                    modelContext.insert(newNote)
                                    existingMigrationKeys.insert(mk)
                                    report.notesCreated += 1
                                    report.workContractsTouched += 1
                                    pendingWrites += 1
                                }
                            }
                        }
                        if !matchedAny { report.unmatched += 1 }
                    }
                case .student(let sID):
                    if let wc = resolveContract(slID: slID, lessonID: lessonUUIDFromPresentation, studentID: sID, contractsByLegacySLAndStudent: contractsByLegacySLAndStudent, contractsByLessonAndStudent: contractsByLessonAndStudent) {
                        let mk = "workModel:\(work.id.uuidString):note:\(ln.id.uuidString):student:\(sID.uuidString)"
                        if existingMigrationKeys.contains(mk) {
                            report.notesSkippedAsDuplicates += 1
                        } else {
                            let newNote = ScopedNote(
                                createdAt: ln.createdAt,
                                updatedAt: ln.updatedAt,
                                body: ln.body,
                                scope: .student(sID),
                                legacyFingerprint: nil,
                                migrationKey: mk,
                                studentLesson: nil,
                                work: nil,
                                presentation: nil,
                                workContract: wc
                            )
                            modelContext.insert(newNote)
                            existingMigrationKeys.insert(mk)
                            report.notesCreated += 1
                            report.workContractsTouched += 1
                            pendingWrites += 1
                        }
                    } else {
                        report.unmatched += 1
                    }
                case .students(let ids):
                    var matchedAny = false
                    for sid in ids {
                        if let wc = resolveContract(slID: slID, lessonID: lessonUUIDFromPresentation, studentID: sid, contractsByLegacySLAndStudent: contractsByLegacySLAndStudent, contractsByLessonAndStudent: contractsByLessonAndStudent) {
                            matchedAny = true
                            let mk = "workModel:\(work.id.uuidString):note:\(ln.id.uuidString):student:\(sid.uuidString)"
                            if existingMigrationKeys.contains(mk) {
                                report.notesSkippedAsDuplicates += 1
                            } else {
                                let newNote = ScopedNote(
                                    createdAt: ln.createdAt,
                                    updatedAt: ln.updatedAt,
                                    body: ln.body,
                                    scope: .student(sid),
                                    legacyFingerprint: nil,
                                    migrationKey: mk,
                                    studentLesson: nil,
                                    work: nil,
                                    presentation: nil,
                                    workContract: wc
                                )
                                modelContext.insert(newNote)
                                existingMigrationKeys.insert(mk)
                                report.notesCreated += 1
                                report.workContractsTouched += 1
                                pendingWrites += 1
                            }
                        }
                    }
                    if !matchedAny { report.unmatched += 1 }
                }
                if pendingWrites >= 100 { flush(reason: "batch WorkModel notes") }
            }
        }

        flush(reason: "final")
        let elapsed = Date().timeIntervalSince(start)
        debugPrint("NotesBackfillService: \n\(report.summaryString(elapsed: elapsed))")
        return report
    }

    private static func key(_ a: UUID, _ b: UUID) -> String { a.uuidString + ":" + b.uuidString }

    private static func resolveContract(
        slID: UUID?,
        lessonID: UUID?,
        studentID: UUID,
        contractsByLegacySLAndStudent: [String: WorkContract],
        contractsByLessonAndStudent: [String: WorkContract]
    ) -> WorkContract? {
        if let slID, let wc = contractsByLegacySLAndStudent[key(slID, studentID)] { return wc }
        if let lessonID, let wc = contractsByLessonAndStudent[key(lessonID, studentID)] { return wc }
        return nil
    }

    private static func convert(_ s: NoteScope) -> ScopedNote.Scope {
        switch s {
        case .all:
            return .all
        case .student(let id):
            return .student(id)
        case .students(let ids):
            return .students(ids)
        }
    }
}
