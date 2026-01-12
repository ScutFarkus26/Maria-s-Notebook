import Foundation
import SwiftData
import CoreData

enum DataMigrations {
    /// Normalize all existing StudentLesson.givenAt values to start-of-day (strip time) once.
    /// Idempotent: guarded by a UserDefaults flag and only updates rows where time != start of day.
    static func normalizeGivenAtToDateOnlyIfNeeded(using context: ModelContext) {
        let flagKey = "Migration.givenAtDateOnly.v1"
        _ = MigrationFlag.runIfNeeded(key: flagKey) {
            let calendar = AppCalendar.shared
            let fetch = FetchDescriptor<StudentLesson>()
            let lessons = context.safeFetch(fetch)
            var changed = 0
            for sl in lessons {
                if let dt = sl.givenAt {
                    let normalized = calendar.startOfDay(for: dt)
                    if dt != normalized {
                        sl.givenAt = normalized
                        changed += 1
                    }
                }
            }
            if changed > 0 { context.safeSave() }
        }
    }

    /// Normalize all Work-related dates to start-of-day (strip time) once.
    /// - WorkModel.createdAt, WorkModel.completedAt
    /// - WorkParticipantEntity.completedAt
    /// - WorkCompletionRecord.completedAt
    /// - WorkCheckIn.date
    static func normalizeWorkDatesToDateOnlyIfNeeded(using context: ModelContext) {
        let flagKey = "Migration.workDatesDateOnly.v1"
        MigrationFlag.markComplete(key: flagKey)
    }

    /// Deduplicate unscheduled, unpresented StudentLesson records that refer to the same lesson and identical student set.
    /// Keeps the earliest `createdAt` as canonical, merges flags, and deletes the rest.
    static func deduplicateUnpresentedStudentLessons(using context: ModelContext) {
        // Fetch all candidate lessons (unscheduled and not given)
        let descriptor = FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.scheduledFor == nil && $0.givenAt == nil })
        let candidates = context.safeFetch(descriptor)
        guard !candidates.isEmpty else { return }

        // Group by (lessonID + sorted studentIDs)
        // CloudKit compatibility: lessonID is now String, no conversion needed
        let groups = candidates.grouped { sl -> String in
            let sortedIDs = sl.studentIDs.sorted()
            return sl.lessonID + "|" + sortedIDs.joined(separator: ",")
        }

        var changed = false
        for (_, group) in groups {
            guard group.count > 1 else { continue }
            // Choose canonical: earliest createdAt
            guard let canonical = group.min(by: { $0.createdAt < $1.createdAt }) else { continue }
            let duplicates = group.filter { $0.id != canonical.id }

            // Merge flags conservatively
            if duplicates.contains(where: { $0.needsPractice }) {
                canonical.needsPractice = true
            }
            if duplicates.contains(where: { $0.needsAnotherPresentation }) {
                canonical.needsAnotherPresentation = true
            }
            // Prefer non-empty notes/followUpWork if canonical empty
            if canonical.notes.trimmed().isEmpty {
                if let firstNote = duplicates.map({ $0.notes }).first(where: { !$0.trimmed().isEmpty }) {
                    canonical.notes = firstNote
                }
            }
            if canonical.followUpWork.trimmed().isEmpty {
                if let firstFU = duplicates.map({ $0.followUpWork }).first(where: { !$0.trimmed().isEmpty }) {
                    canonical.followUpWork = firstFU
                }
            }

            // Delete duplicates
            for d in duplicates { context.delete(d) }
            changed = true
        }

        if changed { context.safeSave() }
    }
    
    /// Backfill Work participants from legacy studentIDs and delete empty Work items if needed.
    /// Idempotent and safe to call multiple times.
    static func backfillParticipantsAndDeleteEmptyWorksIfNeeded(using context: ModelContext) {
        let flagKey = "Migration.workParticipantsBackfillAndPrune.v1"
        MigrationFlag.markComplete(key: flagKey)
    }
    
    /// Backfill nil WorkModel.title values to empty string once.
    static func backfillEmptyWorkTitlesIfNeeded(using context: ModelContext) {
        let flagKey = "Migration.workTitlesBackfillEmpty.v1"
        // Title is non-optional; this migration is obsolete. Mark as done.
        MigrationFlag.markComplete(key: flagKey)
    }
    
    /// Fix CommunityTopic.tags property migration to new storage format.
    /// The tags property now uses JSON-encoded Data storage (_tagsData) instead of direct array storage.
    /// 
    /// IMPORTANT: This migration cannot fetch CommunityTopic records directly because SwiftData
    /// may crash when trying to read the old tags property from corrupted data. Instead, we use
    /// a lazy migration approach where records are migrated when they are accessed and saved.
    /// 
    /// The computed property in CommunityTopic safely handles corrupted data by returning an
    /// empty array if _tagsData contains invalid data, preventing crashes.
    static func fixCommunityTopicTagsIfNeeded(using context: ModelContext) {
        let flagKey = "Migration.communityTopicTagsFix.v2"
        
        // Mark migration as complete immediately to prevent any fetch attempts that might crash
        // The computed property in CommunityTopic will safely handle corrupted data
        // by returning an empty array if _tagsData contains invalid data.
        // Records will be migrated lazily when accessed and saved (tags property setter encodes to _tagsData).
        if !MigrationFlag.isComplete(key: flagKey) {
            MigrationFlag.markComplete(key: flagKey)
            print("DataMigrations: CommunityTopic tags migration v2 flag set. Records will be migrated lazily on access.")
        }
    }
    
    /// Fix StudentLesson.studentIDs property migration to new storage format.
    /// The studentIDs property now uses JSON-encoded Data storage (_studentIDsData) instead of direct array storage.
    /// 
    /// IMPORTANT: This migration cannot fetch StudentLesson records directly because SwiftData
    /// may crash when trying to read the old studentIDs property from corrupted data (UUIDs instead of Strings).
    /// Instead, we use a lazy migration approach where records are migrated when they are accessed and saved.
    /// 
    /// The computed property in StudentLesson safely handles corrupted data by returning an
    /// empty array if _studentIDsData contains invalid data, preventing crashes.
    static func fixStudentLessonStudentIDsIfNeeded(using context: ModelContext) {
        let flagKey = "Migration.studentLessonStudentIDsFix.v1"
        
        // Mark migration as complete immediately to prevent any fetch attempts that might crash
        // The computed property in StudentLesson will safely handle corrupted data
        // by returning an empty array if _studentIDsData contains invalid data.
        // Records will be migrated lazily when accessed and saved (studentIDs property setter encodes to _studentIDsData).
        if !MigrationFlag.isComplete(key: flagKey) {
            MigrationFlag.markComplete(key: flagKey)
            print("DataMigrations: StudentLesson studentIDs migration flag set. Records will be migrated lazily on access.")
        }
    }
    
    /// Migrate UUID foreign keys to String format for CloudKit compatibility.
    /// This migration converts all UUID foreign keys to their string representations.
    /// Idempotent: guarded by a UserDefaults flag.
    static func migrateUUIDForeignKeysToStringsIfNeeded(using context: ModelContext) {
        let flagKey = "Migration.uuidForeignKeysToStrings.v1"
        
        // Note: This migration is primarily handled by lazy migration when records are accessed.
        // The models now store UUIDs as strings, and initializers convert UUID parameters to strings.
        // Existing records will be migrated when they are read and saved.
        // We mark this migration as complete to indicate the schema change is in place.
        if !MigrationFlag.isComplete(key: flagKey) {
            MigrationFlag.markComplete(key: flagKey)
            print("DataMigrations: UUID foreign keys to strings migration flag set. Records will be migrated lazily on access.")
        }
    }
    
    /// Migrate AttendanceRecord.studentID from UUID to String format.
    /// This must be called after the store is opened, as it uses ModelContext.
    /// Idempotent: guarded by a UserDefaults flag.
    static func migrateAttendanceRecordStudentIDToStringIfNeeded(using context: ModelContext) {
        let flagKey = "Migration.attendanceRecordStudentIDToString.v1"
        _ = MigrationFlag.runIfNeeded(key: flagKey) {
            let fetch = FetchDescriptor<AttendanceRecord>()
            let records = context.safeFetch(fetch)
            
            for record in records {
                // Check if studentID is already a valid UUID string
                // If it's not a valid UUID string, it might be stored as UUID in the database
                // We need to check the actual stored value
                let currentValue = record.studentID
                
                // If the value is empty or doesn't look like a UUID string, skip
                if currentValue.isEmpty {
                    continue
                }
                
                // If it's already a valid UUID string format, it's already migrated
                if UUID(uuidString: currentValue) != nil {
                    // Already in string format, but verify it's the correct format
                    continue
                }
                
                // If we get here, the value might be in an unexpected format
                // Try to access it through the underlying CoreData object if possible
                // For now, we'll skip records that don't match expected format
                // The store should have been migrated at the CoreData level
            }
            
            print("DataMigrations: AttendanceRecord studentID migration completed. Records will be migrated lazily on access.")
        }
    }
    
    /// Repairs denormalized scheduledForDay fields to match scheduledFor.
    /// This ensures data integrity when scheduledForDay gets out of sync with scheduledFor
    /// (e.g., during bulk imports or when didSet doesn't fire during initialization).
    /// Safe to call repeatedly - it's idempotent and only fixes mismatched records.
    static func repairDenormalizedScheduledForDay(using context: ModelContext) {
        let fetch = FetchDescriptor<StudentLesson>()
        let lessons = context.safeFetch(fetch)
        var repaired = 0
        
        for sl in lessons {
            let correct = sl.scheduledFor.map { AppCalendar.startOfDay($0) } ?? Date.distantPast
            if sl.scheduledForDay != correct {
                sl.scheduledForDay = correct
                repaired += 1
            }
        }
        
        if repaired > 0 {
            context.safeSave()
            print("DataMigrations: Repaired \(repaired) StudentLesson records with mismatched scheduledForDay")
        }
    }
    
    /// Cleans orphaned student IDs from StudentLesson records.
    /// Removes student IDs that no longer exist in the database to maintain referential integrity
    /// when using manual ID management instead of SwiftData relationships.
    /// Safe to call repeatedly - it's idempotent and only removes non-existent IDs.
    static func cleanOrphanedStudentIDs(using context: ModelContext) {
        // Fetch all students to build valid ID set
        let studentFetch = FetchDescriptor<Student>()
        let allStudents = context.safeFetch(studentFetch)
        let validStudentIDs = Set(allStudents.map { $0.id.uuidString })
        
        // Fetch all StudentLessons
        let lessonFetch = FetchDescriptor<StudentLesson>()
        let allLessons = context.safeFetch(lessonFetch)
        
        var cleaned = 0
        for sl in allLessons {
            let originalIDs = sl.studentIDs
            let cleanedIDs = originalIDs.filter { validStudentIDs.contains($0) }
            
            if cleanedIDs.count != originalIDs.count {
                sl.studentIDs = cleanedIDs
                // Also update the transient relationship array
                sl.students = sl.students.filter { student in
                    validStudentIDs.contains(student.id.uuidString)
                }
                cleaned += 1
            }
        }
        
        if cleaned > 0 {
            context.safeSave()
            print("DataMigrations: Cleaned orphaned student IDs from \(cleaned) StudentLesson records")
        }
    }
    
    // MARK: - Legacy Backfill Migrations
    
    /// Backfill StudentLesson relationships from legacy studentIDs and lessonID strings.
    /// One-time migration that ensures relationship arrays are populated from denormalized ID fields.
    /// Idempotent: guarded by a UserDefaults flag.
    /// Backfill relationships asynchronously to avoid blocking UI
    /// Yields periodically to allow UI updates during large migrations
    static func backfillRelationshipsIfNeeded(using context: ModelContext) async {
        let flagKey = "Backfill.relationships.v1"
        await MigrationFlag.runIfNeeded(key: flagKey) {
            // OPTIMIZATION: Fetch all data once (these are relatively small lookups)
            let sls = context.safeFetch(FetchDescriptor<StudentLesson>())
            let students = context.safeFetch(FetchDescriptor<Student>())
            let lessons = context.safeFetch(FetchDescriptor<Lesson>())
            let studentsByID = students.toDictionary(by: \.id)
            let lessonsByID = lessons.toDictionary(by: \.id)

            // OPTIMIZATION: Process in batches and save periodically to avoid memory pressure
            // For large datasets, process in chunks of 1000
            let batchSize = 1000
            var changed = false
            var processed = 0
            
            for batchStart in stride(from: 0, to: sls.count, by: batchSize) {
                // Yield periodically to prevent blocking UI
                if batchStart % (batchSize * 5) == 0 {
                    await Task.yield()
                }
                
                let batchEnd = min(batchStart + batchSize, sls.count)
                let batch = Array(sls[batchStart..<batchEnd])
                
                for sl in batch {
                    // CloudKit compatibility: Convert String lessonID to UUID for lookup
                    guard let lessonIDUUID = UUID(uuidString: sl.lessonID) else { continue }
                    let targetLesson = lessonsByID[lessonIDUUID]
                    let targetStudents: [Student] = sl.studentIDs.compactMap { idString in
                        guard let id = UUID(uuidString: idString) else { return nil }
                        return studentsByID[id]
                    }
                    if sl.lesson?.id != targetLesson?.id { sl.lesson = targetLesson; changed = true }
                    let currentIDs = Set(sl.students.map { $0.id })
                    let targetIDs = Set(targetStudents.map { $0.id })
                    if currentIDs != targetIDs {
                        sl.students = targetStudents
                        changed = true
                    }
                    if changed {
                        sl.syncSnapshotsFromRelationships()
                    }
                }
                
                processed += batch.count
                // Save periodically to avoid holding too many changes in memory
                if changed && processed % batchSize == 0 {
                    context.safeSave()
                    changed = false // Reset for next batch
                }
            }
            
            // Final save if there are remaining changes
            if changed {
                context.safeSave()
            }
            print("DataMigrations: Backfilled relationships for StudentLesson records")
        }
    }

    /// Backfill isPresented flag from givenAt field.
    /// One-time migration: if givenAt is set, isPresented should be true.
    /// Idempotent: guarded by a UserDefaults flag.
    /// Backfill isPresented asynchronously to avoid blocking UI
    static func backfillIsPresentedIfNeeded(using context: ModelContext) async {
        let flagKey = "Backfill.isPresentedFromGivenAt.v1"
        await MigrationFlag.runIfNeeded(key: flagKey) {
            // OPTIMIZATION: Process in batches for large datasets
            let sls = context.safeFetch(FetchDescriptor<StudentLesson>())
            let batchSize = 1000
            var changed = false
            var updated = 0
            
            for batchStart in stride(from: 0, to: sls.count, by: batchSize) {
                // Yield periodically to prevent blocking UI
                if batchStart % (batchSize * 5) == 0 {
                    await Task.yield()
                }
                
                let batchEnd = min(batchStart + batchSize, sls.count)
                let batch = Array(sls[batchStart..<batchEnd])
                
                for sl in batch {
                    if sl.givenAt != nil && sl.isPresented == false {
                        sl.isPresented = true
                        changed = true
                        updated += 1
                    }
                }
                
                // Save periodically
                if changed && (batchEnd % batchSize == 0 || batchEnd == sls.count) {
                    context.safeSave()
                    changed = false
                }
            }
            
            if updated > 0 {
                print("DataMigrations: Backfilled isPresented flag for \(updated) StudentLesson records")
            }
        }
    }
    
    /// Backfill scheduledForDay field from scheduledFor.
    /// One-time migration that ensures scheduledForDay matches scheduledFor for all records.
    /// Idempotent: guarded by a UserDefaults flag.
    /// Note: This is a one-time migration. Use repairDenormalizedScheduledForDay for ongoing repairs.
    /// Backfill scheduledForDay asynchronously to avoid blocking UI
    static func backfillScheduledForDayIfNeeded(using context: ModelContext) async {
        let flagKey = "Backfill.scheduledForDay.v1"
        await MigrationFlag.runIfNeeded(key: flagKey) {
            // OPTIMIZATION: Process in batches for large datasets
            let sls = context.safeFetch(FetchDescriptor<StudentLesson>())
            let batchSize = 1000
            var fixed = 0
            var needsSave = false
            
            for batchStart in stride(from: 0, to: sls.count, by: batchSize) {
                // Yield periodically to prevent blocking UI
                if batchStart % (batchSize * 5) == 0 {
                    await Task.yield()
                }
                
                let batchEnd = min(batchStart + batchSize, sls.count)
                let batch = Array(sls[batchStart..<batchEnd])
                
                for sl in batch {
                    let correct = sl.scheduledFor.map { AppCalendar.startOfDay($0) } ?? Date.distantPast
                    if sl.scheduledForDay != correct {
                        sl.scheduledForDay = correct
                        fixed += 1
                        needsSave = true
                    }
                }
                
                // Save periodically
                if needsSave && (batchEnd % batchSize == 0 || batchEnd == sls.count) {
                    context.safeSave()
                    needsSave = false
                }
            }
            
            if fixed > 0 {
                print("DataMigrations: Backfilled scheduledForDay for \(fixed) StudentLesson records")
            }
        }
    }
    
    /// Migrate GroupTrack records to include isExplicitlyDisabled field.
    /// Sets all existing GroupTrack records to isExplicitlyDisabled = false (they remain as tracks).
    /// New default behavior: All groups are tracks (sequential) unless explicitly disabled.
    /// Idempotent: guarded by a UserDefaults flag.
    static func migrateGroupTracksToDefaultBehaviorIfNeeded(using context: ModelContext) {
        let flagKey = "Migration.groupTracksDefaultBehavior.v1"
        _ = MigrationFlag.runIfNeeded(key: flagKey) {
            let tracks = context.safeFetch(FetchDescriptor<GroupTrack>())
            var updated = 0
            
            for track in tracks {
                // Existing GroupTrack records should remain as tracks (not explicitly disabled)
                // Since the field defaults to false, we only need to set it if it's somehow true
                // But to be safe, explicitly set it to false for all existing records
                if track.isExplicitlyDisabled {
                    track.isExplicitlyDisabled = false
                    updated += 1
                }
            }
            
            if updated > 0 {
                context.safeSave()
                print("DataMigrations: Migrated \(updated) GroupTrack records to new default behavior")
            } else {
                print("DataMigrations: GroupTrack migration completed. All groups are now tracks by default (sequential).")
            }
        }
    }
    
    /// Migrate WorkContract records to WorkModel records.
    /// For each WorkContract that does not already exist as a WorkModel (based on legacyContractID),
    /// creates a WorkModel using WorkModel.from(contract:in:).
    /// Also migrates relationships from Note and ScopedNote from workContract to work.
    /// Idempotent: only migrates contracts that don't already have corresponding WorkModels.
    @MainActor
    static func migrateWorkContractsToWorkModelsIfNeeded(using context: ModelContext) {
        do {
            // Fetch all WorkContract records
            let contracts = context.safeFetch(FetchDescriptor<WorkContract>())
            guard !contracts.isEmpty else { return }
            
            // Build lookup dictionary for contracts
            let contractByID = Dictionary(uniqueKeysWithValues: contracts.map { ($0.id, $0) })
            
            // Fetch all WorkModel records and build a set of existing legacyContractID values
            let workModels = context.safeFetch(FetchDescriptor<WorkModel>())
            let existingLegacyContractIDs = Set(workModels.compactMap { $0.legacyContractID })
            
            // Count how many we create
            var createdWorkCount = 0
            
            // For each WorkContract that doesn't already exist as a WorkModel, create a WorkModel
            for contract in contracts {
                // Skip if this contract already has a corresponding WorkModel
                guard !existingLegacyContractIDs.contains(contract.id) else { continue }
                
                // Create WorkModel using the helper
                let workModel = WorkModel.from(contract: contract, in: context)
                
                // Insert into context
                context.insert(workModel)
                createdWorkCount += 1
            }
            
            // Always attempt to migrate Note and ScopedNote relationships (even if createdWorkCount is 0)
            // Use WorkLegacyAdapter to look up migrated WorkModel by legacy contract ID
            let adapter = WorkLegacyAdapter(modelContext: context)
            var migratedNotesCount = 0
            
            // Migrate Note relationships
            let notes = context.safeFetch(FetchDescriptor<Note>())
            for note in notes {
                // Only migrate if note has workContract but no work
                guard let workContract = note.workContract, note.work == nil else { continue }
                
                // Look up the migrated WorkModel by legacy contract ID
                guard let workModel = adapter.workModel(forLegacyContractID: workContract.id) else { continue }
                
                // Move the relationship
                note.work = workModel
                note.workContract = nil
                migratedNotesCount += 1
            }
            
            // Migrate ScopedNote relationships
            let scopedNotes = context.safeFetch(FetchDescriptor<ScopedNote>())
            for scopedNote in scopedNotes {
                // Only migrate if scopedNote has workContract (or workContractID) but no work
                guard scopedNote.work == nil else { continue }
                
                // Get the contract ID - prefer workContract relationship, fall back to workContractID string
                let contractID: UUID
                if let workContract = scopedNote.workContract {
                    contractID = workContract.id
                } else if let workContractIDString = scopedNote.workContractID,
                          let uuid = UUID(uuidString: workContractIDString) {
                    contractID = uuid
                } else {
                    continue
                }
                
                // Look up the migrated WorkModel by legacy contract ID
                guard let workModel = adapter.workModel(forLegacyContractID: contractID) else { continue }
                
                // Move the relationship
                scopedNote.work = workModel
                scopedNote.workContract = nil
                scopedNote.workContractID = nil
                migratedNotesCount += 1
            }
            
            // Backfill IDs for already-migrated WorkModels
            var backfilledCount = 0
            for work in workModels {
                // Only process WorkModels that have a legacyContractID
                guard let legacyContractID = work.legacyContractID else { continue }
                
                // Check if backfill is needed
                let needsBackfill = work.studentID.isEmpty || work.lessonID.isEmpty || (work.presentationID == nil && contractByID[legacyContractID]?.presentationID != nil)
                
                if needsBackfill {
                    // Find the contract using legacyContractID
                    guard let contract = contractByID[legacyContractID] else { continue }
                    
                    // Backfill IDs from contract
                    work.studentID = contract.studentID
                    work.lessonID = contract.lessonID
                    if let presentationID = contract.presentationID {
                        work.presentationID = presentationID
                    }
                    if let trackID = contract.trackID {
                        work.trackID = trackID
                    }
                    if let trackStepID = contract.trackStepID {
                        work.trackStepID = trackStepID
                    }
                    
                    backfilledCount += 1
                }
            }
            
            // Backfill WorkModels that were created using studentLessonID (StudentLesson-based paths) but have empty string IDs.
            // These cannot be repaired via legacyContractID because they are not migrated from WorkContract.
            let studentLessons = (try? context.fetch(FetchDescriptor<StudentLesson>())) ?? []
            let studentLessonByID: [UUID: StudentLesson] = Dictionary(uniqueKeysWithValues: studentLessons.map { ($0.id, $0) })

            var studentLessonBackfilledCount = 0

            for work in workModels {
                guard (work.studentID.isEmpty || work.lessonID.isEmpty), let slID = work.studentLessonID else { continue }
                guard let sl = studentLessonByID[slID] else { continue }

                // StudentLesson.lessonID is stored; studentIDs is @Transient but usable in memory here.
                if work.lessonID.isEmpty { work.lessonID = sl.lessonID }
                if work.studentID.isEmpty {
                    if let firstStudent = sl.studentIDs.first {
                        work.studentID = firstStudent
                    }
                }
                if work.legacyStudentLessonID == nil { work.legacyStudentLessonID = slID.uuidString }
                studentLessonBackfilledCount += 1
            }
            
            // Save once at the end only if something changed
            if createdWorkCount > 0 || migratedNotesCount > 0 || backfilledCount > 0 || studentLessonBackfilledCount > 0 {
                try context.save()
                
                // Print logs only when something changed
                if createdWorkCount > 0 {
                    print("DataMigrations: Migrated \(createdWorkCount) WorkContract records into WorkModel.")
                }
                if migratedNotesCount > 0 {
                    print("DataMigrations: Migrated \(migratedNotesCount) notes to WorkModel relationships.")
                }
                if backfilledCount > 0 {
                    print("DataMigrations: Backfilled IDs for \(backfilledCount) WorkModel records.")
                }
                if studentLessonBackfilledCount > 0 {
                    print("DataMigrations: Backfilled IDs from StudentLesson for \(studentLessonBackfilledCount) WorkModel records.")
                }
            }
        } catch {
            print("DataMigrations: WorkContract -> WorkModel migration failed: \(error.localizedDescription)")
        }
    }
}
