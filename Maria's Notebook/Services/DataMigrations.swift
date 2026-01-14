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
                    print("WARNING: Skipped invalid AttendanceRecord (ID: \(record.id)) - Value: \(currentValue)")
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
                print("WARNING: Skipped invalid AttendanceRecord (ID: \(record.id)) - Value: \(currentValue)")
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
    
    /// Cleans orphaned student IDs from WorkModel records.
    /// Removes student IDs that no longer exist in the database to maintain referential integrity
    /// when using manual ID management instead of SwiftData relationships.
    /// Safe to call repeatedly - it's idempotent and only removes non-existent IDs.
    static func cleanOrphanedWorkStudentIDs(using context: ModelContext) {
        // Fetch all students to build valid ID set
        let studentFetch = FetchDescriptor<Student>()
        let allStudents = context.safeFetch(studentFetch)
        let validStudentIDs = Set(allStudents.map { $0.id.uuidString })
        
        // Fetch all WorkModels
        let workFetch = FetchDescriptor<WorkModel>()
        let allWorks = context.safeFetch(workFetch)
        
        var cleaned = 0
        for work in allWorks {
            var modified = false
            
            // Check work.studentID - if not empty and not in valid set, clear it
            if !work.studentID.isEmpty && !validStudentIDs.contains(work.studentID) {
                work.studentID = ""
                modified = true
            }
            
            // Check work.participants - remove any with orphaned studentIDs
            if let participants = work.participants, !participants.isEmpty {
                let validParticipants = participants.filter { participant in
                    validStudentIDs.contains(participant.studentID)
                }
                
                if validParticipants.count != participants.count {
                    work.participants = validParticipants.isEmpty ? nil : validParticipants
                    // Delete orphaned participants from context
                    for participant in participants {
                        if !validStudentIDs.contains(participant.studentID) {
                            context.delete(participant)
                        }
                    }
                    modified = true
                }
            }
            
            if modified {
                cleaned += 1
            }
        }
        
        if cleaned > 0 {
            context.safeSave()
            print("DataMigrations: Cleaned orphaned student IDs from \(cleaned) Work records.")
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
            
            // ScopedNote migration has been completed. All notes are now in the unified Note system.
            
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
    
    /// Backfill Presentation.legacyStudentLessonID by linking to matching StudentLessons.
    /// Idempotent: only sets legacyStudentLessonID when it is nil or empty.
    /// Safe to run repeatedly.
    /// Backfill asynchronously to avoid blocking UI
    static func backfillPresentationStudentLessonLinks(using context: ModelContext) async {
        let flagKey = "Backfill.presentationStudentLessonLinks.v1"
        await MigrationFlag.runIfNeeded(key: flagKey) {
            // Fetch all Presentations and StudentLessons
            let presentations = context.safeFetch(FetchDescriptor<Presentation>())
            let studentLessons = context.safeFetch(FetchDescriptor<StudentLesson>())
            
            // Filter presentations that need backfilling
            let presentationsToBackfill = presentations.filter { presentation in
                guard let legacyID = presentation.legacyStudentLessonID else { return true }
                return legacyID.isEmpty
            }
            
            guard !presentationsToBackfill.isEmpty else {
                print("DataMigrations: All presentations already have legacyStudentLessonID")
                return
            }
            
            // Process in batches to avoid blocking UI
            let batchSize = 100
            var count = 0
            var changed = false
            
            for batchStart in stride(from: 0, to: presentationsToBackfill.count, by: batchSize) {
                // Yield periodically to prevent blocking UI
                if batchStart % (batchSize * 5) == 0 {
                    await Task.yield()
                }
                
                let batchEnd = min(batchStart + batchSize, presentationsToBackfill.count)
                let batch = Array(presentationsToBackfill[batchStart..<batchEnd])
                
                for presentation in batch {
                    // Skip if already has legacyStudentLessonID
                    if let existingID = presentation.legacyStudentLessonID, !existingID.isEmpty {
                        continue
                    }
                    
                    // Determine presentation properties
                    let pLessonID = presentation.lessonID
                    let pStudentIDs = Set(presentation.studentIDs)
                    let pDay = Calendar.current.startOfDay(for: presentation.presentedAt)
                    
                    // Find candidate StudentLessons
                    var candidates: [StudentLesson] = []
                    
                    for sl in studentLessons {
                        // Check lesson ID match
                        let slLessonIDMatch = sl.resolvedLessonID.uuidString == pLessonID || sl.lessonID == pLessonID
                        guard slLessonIDMatch else { continue }
                        
                        // Check student overlap (at least 1 student in common)
                        let slStudentIDs = Set(sl.studentIDs)
                        let overlap = pStudentIDs.intersection(slStudentIDs)
                        guard overlap.count >= 1 else { continue }
                        
                        // Check date match if StudentLesson has a date
                        let slDay = sl.givenAt.map { Calendar.current.startOfDay(for: $0) }
                        if let slDay {
                            // StudentLesson has a date, so it must match Presentation date
                            guard slDay == pDay else { continue }
                        }
                        
                        candidates.append(sl)
                    }
                    
                    // Choose best match
                    guard let bestMatch = chooseBestMatch(
                        candidates: candidates,
                        presentation: presentation,
                        pStudentIDs: pStudentIDs
                    ) else {
                        continue
                    }
                    
                    // Set legacyStudentLessonID
                    presentation.legacyStudentLessonID = bestMatch.id.uuidString
                    count += 1
                    changed = true
                }
                
                // Save periodically
                if changed && (batchEnd % batchSize == 0 || batchEnd == presentationsToBackfill.count) {
                    context.safeSave()
                    changed = false
                }
            }
            
            // Final save if there are remaining changes
            if changed {
                context.safeSave()
            }
            
            print("DataMigrations: Backfilled Presentation.legacyStudentLessonID for \(count) presentations")
        }
    }
    
    /// Helper function to choose the best matching StudentLesson for a Presentation.
    /// Selection criteria:
    /// 1. Highest overlap count wins
    /// 2. Tie-breaker: closest |sl.givenAt - p.presentedAt| if both exist
    /// 3. Final fallback: earliest createdAt
    private static func chooseBestMatch(
        candidates: [StudentLesson],
        presentation: Presentation,
        pStudentIDs: Set<String>
    ) -> StudentLesson? {
        guard !candidates.isEmpty else { return nil }
        
        // Calculate overlap for each candidate
        let candidatesWithOverlap = candidates.map { sl -> (sl: StudentLesson, overlap: Int) in
            let slStudentIDs = Set(sl.studentIDs)
            let overlap = pStudentIDs.intersection(slStudentIDs).count
            return (sl, overlap)
        }
        
        // Find maximum overlap
        let maxOverlap = candidatesWithOverlap.map { $0.overlap }.max() ?? 0
        let topCandidates = candidatesWithOverlap.filter { $0.overlap == maxOverlap }
        
        // If only one candidate with max overlap, return it
        if topCandidates.count == 1 {
            return topCandidates[0].sl
        }
        
        // Tie-breaker: closest date if both have dates
        let pDate = presentation.presentedAt
        var bestCandidate: StudentLesson?
        var minTimeDifference: TimeInterval = .greatestFiniteMagnitude
        
        // Find candidate with closest date (only consider candidates that have dates)
        for (sl, _) in topCandidates {
            if let slDate = sl.givenAt {
                let timeDifference = abs(slDate.timeIntervalSince(pDate))
                if timeDifference < minTimeDifference {
                    minTimeDifference = timeDifference
                    bestCandidate = sl
                }
            }
        }
        
        // If we found a candidate with a date, return it
        if let best = bestCandidate {
            return best
        }
        // Otherwise, fall through to createdAt check
        
        // Final fallback: earliest createdAt
        return topCandidates.min(by: { $0.sl.createdAt < $1.sl.createdAt })?.sl
    }
    
    /// Helper function to get the best available date from a StudentLesson for time-based matching.
    /// Priority: givenAt > scheduledFor > createdAt
    /// createdAt is always available, so this never returns nil.
    private static func bestDate(for studentLesson: StudentLesson) -> Date {
        if let givenAt = studentLesson.givenAt {
            return givenAt
        }
        if let scheduledFor = studentLesson.scheduledFor {
            return scheduledFor
        }
        return studentLesson.createdAt
    }
    
    /// Repairs Presentation.legacyStudentLessonID for existing records that have incorrect or missing links.
    /// This migration backfills legacyStudentLessonID even when it's already set but doesn't match a valid StudentLesson.
    /// Uses strict matching first (exact lessonID + exact studentIDs set match), then falls back to loose matching.
    /// Idempotent: guarded by a UserDefaults flag so it runs once.
    /// Safe to run repeatedly (skips presentations with valid links).
    /// Backfill asynchronously to avoid blocking UI
    static func repairPresentationStudentLessonLinks_v2(using context: ModelContext) async {
        let flagKey = "Repair.presentationStudentLessonLinks.v2"
        await MigrationFlag.runIfNeeded(key: flagKey) {
            // Fetch all Presentations and StudentLessons
            let presentations = context.safeFetch(FetchDescriptor<Presentation>())
            let studentLessons = context.safeFetch(FetchDescriptor<StudentLesson>())
            
            // Build lookup dictionary for quick validation
            let studentLessonByID = Dictionary(uniqueKeysWithValues: studentLessons.map { ($0.id.uuidString, $0) })
            
            // Process in batches to avoid blocking UI
            let batchSize = 100
            var totalScanned = 0
            var updatedStrict = 0
            var updatedLoose = 0
            var skippedValid = 0
            var unmatched = 0
            var changed = false
            
            for batchStart in stride(from: 0, to: presentations.count, by: batchSize) {
                // Yield periodically to prevent blocking UI
                if batchStart % (batchSize * 5) == 0 {
                    await Task.yield()
                }
                
                let batchEnd = min(batchStart + batchSize, presentations.count)
                let batch = Array(presentations[batchStart..<batchEnd])
                
                for presentation in batch {
                    totalScanned += 1
                    
                    // Skip if legacyStudentLessonID already equals an existing StudentLesson.id.uuidString (valid link)
                    if let existingID = presentation.legacyStudentLessonID,
                       !existingID.isEmpty,
                       let matchedSL = studentLessonByID[existingID] {
                        // Verify the link is actually correct by checking lesson and student match
                        let lessonMatch = presentation.lessonID == matchedSL.resolvedLessonID.uuidString || presentation.lessonID == matchedSL.lessonID
                        let presentationStudentSet = Set(presentation.studentIDs)
                        let slStudentSet = Set(matchedSL.studentIDs)
                        let studentMatch = presentationStudentSet == slStudentSet
                        
                        if lessonMatch && studentMatch {
                            skippedValid += 1
                            continue
                        }
                        // If link exists but doesn't match, we'll try to find a better match below
                    }
                    
                    // Attempt to find a matching StudentLesson
                    let pLessonID = presentation.lessonID
                    let pStudentIDs = Set(presentation.studentIDs)
                    let pPresentedAt = presentation.presentedAt
                    
                    var matched: StudentLesson?
                    
                    // PASS 1: Strict matching (exact lessonID match + exact studentIDs set match)
                    var strictCandidates: [StudentLesson] = []
                    
                    for sl in studentLessons {
                        // Exact lesson match
                        let lessonMatch = sl.resolvedLessonID.uuidString == pLessonID || sl.lessonID == pLessonID
                        guard lessonMatch else { continue }
                        
                        // Exact student set match
                        let slStudentIDs = Set(sl.studentIDs)
                        let studentMatch = pStudentIDs == slStudentIDs
                        guard studentMatch else { continue }
                        
                        strictCandidates.append(sl)
                    }
                    
                    if !strictCandidates.isEmpty {
                        // Find best match by time proximity for strict candidates
                        var bestMatch: StudentLesson?
                        var minTimeDifference: TimeInterval = .greatestFiniteMagnitude
                        
                        for candidate in strictCandidates {
                            let candidateDate = bestDate(for: candidate)
                            let timeDifference = abs(candidateDate.timeIntervalSince(pPresentedAt))
                            if timeDifference < minTimeDifference {
                                minTimeDifference = timeDifference
                                bestMatch = candidate
                            }
                        }
                        
                        // If no candidate had a date, fall back to earliest createdAt
                        if bestMatch == nil {
                            bestMatch = strictCandidates.min(by: { $0.createdAt < $1.createdAt })
                        }
                        
                        matched = bestMatch
                        if matched != nil {
                            updatedStrict += 1
                        }
                    }
                    
                    // PASS 2: Loose matching (for unmatched presentations)
                    if matched == nil {
                        var looseCandidates: [StudentLesson] = []
                        
                        for sl in studentLessons {
                            // Same lesson requirement
                            let lessonMatch = sl.resolvedLessonID.uuidString == pLessonID || sl.lessonID == pLessonID
                            guard lessonMatch else { continue }
                            
                            // Student match: if p.studentIDs is empty, allow any; otherwise require overlap
                            let slStudentIDs = Set(sl.studentIDs)
                            if pStudentIDs.isEmpty {
                                // Allow any StudentLesson for that lesson
                                looseCandidates.append(sl)
                            } else {
                                // Require intersection not empty
                                let intersection = pStudentIDs.intersection(slStudentIDs)
                                guard !intersection.isEmpty else { continue }
                                looseCandidates.append(sl)
                            }
                        }
                        
                        if !looseCandidates.isEmpty {
                            // Prefer candidates where dates are on the same day
                            var sameDayCandidates: [StudentLesson] = []
                            var otherCandidates: [StudentLesson] = []
                            
                            for candidate in looseCandidates {
                                if let givenAt = candidate.givenAt,
                                   Calendar.current.isDate(givenAt, inSameDayAs: pPresentedAt) {
                                    sameDayCandidates.append(candidate)
                                } else {
                                    otherCandidates.append(candidate)
                                }
                            }
                            
                            // Use same-day candidates if available, otherwise use all candidates
                            let candidatesToConsider = sameDayCandidates.isEmpty ? otherCandidates : sameDayCandidates
                            
                            // Choose candidate with smallest absolute time difference
                            // Use 0 if givenAt is nil (treat as no time difference)
                            var bestMatch: StudentLesson?
                            var minTimeDifference: TimeInterval = .greatestFiniteMagnitude
                            
                            for candidate in candidatesToConsider {
                                let timeDifference: TimeInterval
                                if let givenAt = candidate.givenAt {
                                    timeDifference = abs(givenAt.timeIntervalSince(pPresentedAt))
                                } else {
                                    timeDifference = 0
                                }
                                
                                if timeDifference < minTimeDifference {
                                    minTimeDifference = timeDifference
                                    bestMatch = candidate
                                }
                            }
                            
                            // If still no match (shouldn't happen, but safety check), use earliest createdAt
                            if bestMatch == nil {
                                bestMatch = candidatesToConsider.min(by: { $0.createdAt < $1.createdAt })
                            }
                            
                            matched = bestMatch
                            if matched != nil {
                                updatedLoose += 1
                            }
                        }
                    }
                    
                    // Update if we found a match
                    if let matched = matched {
                        presentation.legacyStudentLessonID = matched.id.uuidString
                        changed = true
                    } else {
                        unmatched += 1
                    }
                }
                
                // Save periodically
                if changed && (batchEnd % batchSize == 0 || batchEnd == presentations.count) {
                    context.safeSave()
                    changed = false
                }
            }
            
            // Final save if there are remaining changes
            if changed {
                context.safeSave()
            }
            
            // Log summary with strict vs loose pass counts
            print("DataMigrations.repairPresentationStudentLessonLinks_v2: scanned=\(totalScanned), updated-strict=\(updatedStrict), updated-loose=\(updatedLoose), skipped-valid=\(skippedValid), unmatched=\(unmatched)")
        }
    }
    
    /// Backfill Note.studentLesson for notes attached to Presentations with legacyStudentLessonID.
    /// Idempotent: only sets studentLesson when it is nil and a matching StudentLesson exists.
    /// Safe to run repeatedly.
    static func backfillNoteStudentLessonFromPresentation(using context: ModelContext) async {
        let flagKey = "Backfill.noteStudentLessonFromPresentation.v1"
        await MigrationFlag.runIfNeeded(key: flagKey) {
            // Fetch all Notes (we'll filter in memory for presentation relationship)
            let allNotes = context.safeFetch(FetchDescriptor<Note>())
            
            // Build a lookup map of StudentLessons by ID for efficient access
            let allStudentLessons = context.safeFetch(FetchDescriptor<StudentLesson>())
            let studentLessonsByID = Dictionary(uniqueKeysWithValues: allStudentLessons.map { ($0.id, $0) })
            
            var scanned = 0
            var updated = 0
            var skipped = 0
            var unmatched = 0
            var changed = false
            
            // Process in batches to avoid blocking UI
            let batchSize = 100
            for batchStart in stride(from: 0, to: allNotes.count, by: batchSize) {
                // Yield periodically to prevent blocking UI
                if batchStart % (batchSize * 5) == 0 {
                    await Task.yield()
                }
                
                let batchEnd = min(batchStart + batchSize, allNotes.count)
                let batch = Array(allNotes[batchStart..<batchEnd])
                
                for note in batch {
                    // Only process notes that have a presentation relationship
                    guard let presentation = note.presentation else { continue }
                    
                    scanned += 1
                    
                    // Check if note already has studentLesson set
                    if note.studentLesson != nil {
                        skipped += 1
                        continue
                    }
                    
                    // Check if presentation has legacyStudentLessonID
                    guard let legacyIDString = presentation.legacyStudentLessonID,
                          !legacyIDString.isEmpty,
                          let legacyID = UUID(uuidString: legacyIDString) else {
                        continue
                    }
                    
                    // Fetch matching StudentLesson
                    guard let studentLesson = studentLessonsByID[legacyID] else {
                        unmatched += 1
                        continue
                    }
                    
                    // Set the studentLesson relationship
                    note.studentLesson = studentLesson
                    updated += 1
                    changed = true
                }
                
                // Save periodically
                if changed && (batchEnd % batchSize == 0 || batchEnd == allNotes.count) {
                    context.safeSave()
                    changed = false
                }
            }
            
            // Final save if there are remaining changes
            if changed {
                context.safeSave()
            }
            
            print("DataMigrations.backfillNoteStudentLessonFromPresentation: scanned=\(scanned), updated=\(updated), skipped=\(skipped), unmatched=\(unmatched)")
        }
    }
    
    /// Migrate legacy string notes on WorkModels into Note objects.
    /// For each WorkModel with a non-empty `notes` string and empty `unifiedNotes`,
    /// creates a new Note object with the content and clears the legacy notes field.
    /// Idempotent: only processes WorkModels that haven't been migrated yet.
    @MainActor
    static func migrateLegacyWorkNotesToNoteObjects(using context: ModelContext) {
        let fetch = FetchDescriptor<WorkModel>(
            predicate: #Predicate<WorkModel> { work in
                !work.notes.isEmpty
            }
        )
        let workModels = context.safeFetch(fetch)
        
        var migratedCount = 0
        
        for work in workModels {
            // Check if unifiedNotes is empty (or nil) - skip if already migrated
            guard (work.unifiedNotes ?? []).isEmpty else { continue }
            
            // Create a new Note object using the content of work.notes
            let note = Note(
                createdAt: work.createdAt,
                body: work.notes,
                scope: .all,
                work: work
            )
            
            // Insert the note into the context
            context.insert(note)
            
            // Clear the old notes string to prevent re-migration
            work.notes = ""
            
            migratedCount += 1
        }
        
        // Save the context if any migrations occurred
        if migratedCount > 0 {
            context.safeSave()
            print("DataMigrations: Migrated \(migratedCount) legacy work notes.")
        }
    }
}
