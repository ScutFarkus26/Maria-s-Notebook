import Foundation
import SwiftData

enum WorkMigrationService {
    private static let flagKey = "WorkMigration.v1.completed"

    static func runIfNeeded(using context: ModelContext) {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: flagKey) {
            return
        }
        do {
            try performMigration(using: context)
            try context.save()
            defaults.set(true, forKey: flagKey)
            defaults.synchronize()
        } catch {
            // Do not set the flag on failure; allow retry on next launch
            #if DEBUG
            print("WorkMigrationService error: \(error)")
            #endif
        }
    }

    // MARK: - Core Migration
    private static func performMigration(using context: ModelContext) throws {
        // Fetch all legacy WorkModel records
        let works = try context.fetch(FetchDescriptor<WorkModel>())
        if works.isEmpty { return }

        // Cache StudentLesson → LessonID for resolution
        // We'll resolve per-work to avoid fetching entire tables unnecessarily.

        for work in works {
            // Resolve Lesson from linked StudentLesson, if any
            guard let slID = work.studentLessonID else { continue }
            let slFetch = FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.id == slID })
            guard let sl = try context.fetch(slFetch).first else { continue }
            let lessonID = sl.lessonID
            let lessonIDString = lessonID.uuidString
            let legacyStudentLessonID = sl.id.uuidString

            // Build or reuse contracts per participant
            var contractsForThisWork: [WorkContract] = []

            for participant in (work.participants ?? []) {
                let studentID = participant.studentID
                let studentIDString = studentID.uuidString

                // Idempotency: try to find an existing contract by (studentID, lessonID, legacyStudentLessonID)
                let existingPredicate = #Predicate<WorkContract> { c in
                    c.studentID == studentIDString &&
                    c.lessonID == lessonIDString &&
                    c.legacyStudentLessonID == legacyStudentLessonID
                }
                let existingFetch = FetchDescriptor<WorkContract>(predicate: existingPredicate)
                if let existing = try context.fetch(existingFetch).first {
                    contractsForThisWork.append(existing)
                    continue
                }

                // Create new WorkContract
                let status: WorkStatus = (work.completedAt != nil && participant.completedAt != nil) ? .complete : .active
                let contract = WorkContract(
                    id: UUID(),
                    createdAt: work.createdAt,
                    studentID: studentIDString,
                    lessonID: lessonIDString,
                    presentationID: nil,
                    status: status,
                    scheduledDate: nil,
                    completedAt: participant.completedAt.map { AppCalendar.startOfDay($0) },
                    legacyStudentLessonID: legacyStudentLessonID
                )
                // Map kind from legacy WorkModel.WorkType
                switch work.workType {
                case .practice: contract.kind = WorkKind.practiceLesson
                case .followUp: contract.kind = WorkKind.followUpAssignment
                case .research: contract.kind = WorkKind.research
                }

                context.insert(contract)
                contractsForThisWork.append(contract)
            }

            if contractsForThisWork.isEmpty { continue }

            // Migrate WorkCheckIns → WorkPlanItem (scheduled only)
            for checkIn in (work.checkIns ?? []) where checkIn.status == .scheduled {
                let day = AppCalendar.startOfDay(checkIn.date)
                let note: String? = {
                    let p = checkIn.purpose.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                    if !p.isEmpty { return p }
                    let n = checkIn.note.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                    return n.isEmpty ? nil : n
                }()
                for contract in contractsForThisWork {
                    // Idempotency: avoid duplicate WorkPlanItem for same contract+date
                    let contractID = contract.id
                    let scheduledDay = day
                    let dupPredicate = #Predicate<WorkPlanItem> { p in
                        p.workID == contractID && p.scheduledDate == scheduledDay
                    }
                    let dupFetch = FetchDescriptor<WorkPlanItem>(predicate: dupPredicate)
                    let exists = try context.fetch(dupFetch).first != nil
                    if exists { continue }
                    let item = WorkPlanItem(workID: contractID, scheduledDate: scheduledDay, reason: .progressCheck, note: note)
                    context.insert(item)
                }
            }

            // Migrate WorkNotes → ScopedNote (contract-scoped)
            for note in (work.checkNotes ?? []) {
                // Compute scope
                let scope: ScopedNote.Scope = {
                    if let s = note.student { return .student(s.id) }
                    let parts = work.participants ?? []
                    if parts.count == 1, let only = parts.first { return .student(only.studentID) }
                    return .all
                }()

                for contract in contractsForThisWork {
                    let mk = "workNote:\(work.id.uuidString):\(note.id.uuidString):contract:\(contract.id.uuidString)"
                    // Idempotency: use migrationKey to skip duplicates
                    let snPredicate = #Predicate<ScopedNote> { n in
                        (n.migrationKey ?? "") == mk
                    }
                    let snFetch = FetchDescriptor<ScopedNote>(predicate: snPredicate)
                    if try context.fetch(snFetch).first != nil { continue }

                    let created = note.createdAt
                    let newNote = ScopedNote(
                        createdAt: created,
                        updatedAt: created,
                        body: note.text,
                        scope: scope,
                        legacyFingerprint: nil,
                        migrationKey: mk,
                        studentLesson: nil,
                        work: nil,
                        presentation: nil,
                        workContract: contract
                    )
                    context.insert(newNote)
                }
            }
        }
    }
}
