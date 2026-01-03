import Foundation
import SwiftData

/// Helper for migrating legacy notes to the unified Note system
/// This can be run manually or as part of a migration process
@MainActor
struct NoteMigrationHelper {
    let modelContext: ModelContext
    
    /// Checks if a note with the given ID already exists (already migrated)
    private func noteExists(id: UUID) -> Bool {
        let fetch = FetchDescriptor<Note>(predicate: #Predicate { $0.id == id })
        return (try? modelContext.fetch(fetch).first) != nil
    }
    
    /// Migrates all ScopedNote objects to Note objects
    /// - Returns: Count of notes migrated
    func migrateScopedNotes() throws -> Int {
        let fetch = FetchDescriptor<ScopedNote>()
        let scopedNotes = try modelContext.fetch(fetch)
        var migrated = 0
        
        for scopedNote in scopedNotes {
            // Skip if already migrated (Note with same ID exists)
            if noteExists(id: scopedNote.id) {
                continue
            }
            // Extract student IDs from scope or parent relationships
            let studentIDs = extractStudentIDs(from: scopedNote)
            
            // Determine scope for new Note
            let scope: NoteScope = {
                if studentIDs.isEmpty {
                    return .all
                } else if studentIDs.count == 1 {
                    return .student(studentIDs[0])
                } else {
                    return .students(studentIDs)
                }
            }()
            
            // Create new Note object
            let note = Note(
                id: scopedNote.id, // Preserve original ID
                createdAt: scopedNote.createdAt,
                updatedAt: scopedNote.updatedAt,
                body: scopedNote.body,
                scope: scope,
                category: .general, // ScopedNote doesn't have category
                includeInReport: false
            )
            
            // Set appropriate relationship based on ScopedNote's parent
            if let studentLesson = scopedNote.studentLesson {
                note.studentLesson = studentLesson
            } else if let presentation = scopedNote.presentation {
                note.presentation = presentation
            } else if let workContract = scopedNote.workContract {
                note.workContract = workContract
            } else if let work = scopedNote.work {
                note.work = work
            }
            
            modelContext.insert(note)
            migrated += 1
        }
        
        try modelContext.save()
        return migrated
    }
    
    /// Migrates all WorkNote objects to Note objects
    /// - Returns: Count of notes migrated
    func migrateWorkNotes() throws -> Int {
        let fetch = FetchDescriptor<WorkNote>()
        let workNotes = try modelContext.fetch(fetch)
        var migrated = 0
        
        for workNote in workNotes {
            // Skip if already migrated (Note with same ID exists)
            if noteExists(id: workNote.id) {
                continue
            }
            
            // Extract student ID from WorkNote's student relationship
            let scope: NoteScope = {
                if let student = workNote.student {
                    return .student(student.id)
                }
                return .all
            }()
            
            // Create new Note object
            let note = Note(
                id: workNote.id, // Preserve original ID
                createdAt: workNote.createdAt,
                updatedAt: workNote.createdAt,
                body: workNote.text,
                scope: scope,
                category: .general,
                includeInReport: false
            )
            
            // Set work relationship if available
            if let work = workNote.work {
                note.work = work
            }
            
            modelContext.insert(note)
            migrated += 1
        }
        
        try modelContext.save()
        return migrated
    }
    
    /// Migrates all MeetingNote objects to Note objects
    /// - Returns: Count of notes migrated
    func migrateMeetingNotes() throws -> Int {
        let fetch = FetchDescriptor<MeetingNote>()
        let meetingNotes = try modelContext.fetch(fetch)
        var migrated = 0
        
        for meetingNote in meetingNotes {
            // Skip if already migrated (Note with same ID exists)
            if noteExists(id: meetingNote.id) {
                continue
            }
            
            // MeetingNote doesn't have student scope, so use .all
            let note = Note(
                id: meetingNote.id, // Preserve original ID
                createdAt: meetingNote.createdAt,
                updatedAt: meetingNote.createdAt,
                body: meetingNote.content,
                scope: .all,
                category: .general,
                includeInReport: false
            )
            
            // Set community topic relationship if available
            if let topic = meetingNote.topic {
                note.communityTopic = topic
            }
            
            modelContext.insert(note)
            migrated += 1
        }
        
        try modelContext.save()
        return migrated
    }
    
    /// Extracts student IDs from a ScopedNote, trying scope first, then parent relationships
    private func extractStudentIDs(from scopedNote: ScopedNote) -> [UUID] {
        // First, try to get from scope
        let fromScope: [UUID] = {
            switch scopedNote.scope {
            case .all: return []
            case .student(let id): return [id]
            case .students(let ids): return ids
            }
        }()
        
        if !fromScope.isEmpty {
            return fromScope
        }
        
        // Fallback: infer from parent relationships
        var studentIDs: [UUID] = []
        
        // If attached to a WorkContract, get student from contract
        if let contract = scopedNote.workContract,
           let studentID = UUID(uuidString: contract.studentID) {
            studentIDs.append(studentID)
        }
        
        // If attached to a StudentLesson, get student from lesson
        if let studentLesson = scopedNote.studentLesson {
            // StudentLesson can have multiple students, so get all of them
            let lessonStudentIDs = studentLesson.studentIDs.compactMap { UUID(uuidString: $0) }
            studentIDs.append(contentsOf: lessonStudentIDs)
        }
        
        // If attached to a Presentation, get students from presentation
        if let presentation = scopedNote.presentation {
            for studentIDString in presentation.studentIDs {
                if let studentID = UUID(uuidString: studentIDString) {
                    studentIDs.append(studentID)
                }
            }
        }
        
        return studentIDs
    }
    
    /// Migrates all legacy notes to the unified Note system
    /// - Returns: Summary of migration results
    func migrateAll() throws -> MigrationSummary {
        let scopedCount = try migrateScopedNotes()
        let workCount = try migrateWorkNotes()
        let meetingCount = try migrateMeetingNotes()
        
        return MigrationSummary(
            scopedNotesMigrated: scopedCount,
            workNotesMigrated: workCount,
            meetingNotesMigrated: meetingCount
        )
    }
}

struct MigrationSummary {
    let scopedNotesMigrated: Int
    let workNotesMigrated: Int
    let meetingNotesMigrated: Int
    
    var total: Int {
        scopedNotesMigrated + workNotesMigrated + meetingNotesMigrated
    }
}

// MARK: - Verification Helper
extension NoteMigrationHelper {
    /// Verifies that migrated notes are correct
    /// - Returns: Verification results
    func verifyMigration() throws -> VerificationResults {
        var results = VerificationResults()
        
        // Check ScopedNote migrations
        let scopedNotes = try modelContext.fetch(FetchDescriptor<ScopedNote>())
        for scopedNote in scopedNotes {
            let targetID = scopedNote.id
            if let migratedNote = try? modelContext.fetch(
                FetchDescriptor<Note>(predicate: #Predicate<Note> { $0.id == targetID })
            ).first {
                // Verify content matches
                if migratedNote.body == scopedNote.body &&
                   migratedNote.createdAt == scopedNote.createdAt {
                    results.scopedNotesVerified += 1
                } else {
                    results.scopedNotesErrors += 1
                }
            } else {
                results.scopedNotesNotMigrated += 1
            }
        }
        
        // Check WorkNote migrations
        let workNotes = try modelContext.fetch(FetchDescriptor<WorkNote>())
        for workNote in workNotes {
            let targetID = workNote.id
            if let migratedNote = try? modelContext.fetch(
                FetchDescriptor<Note>(predicate: #Predicate<Note> { $0.id == targetID })
            ).first {
                if migratedNote.body == workNote.text &&
                   migratedNote.createdAt == workNote.createdAt {
                    results.workNotesVerified += 1
                } else {
                    results.workNotesErrors += 1
                }
            } else {
                results.workNotesNotMigrated += 1
            }
        }
        
        // Check MeetingNote migrations
        let meetingNotes = try modelContext.fetch(FetchDescriptor<MeetingNote>())
        for meetingNote in meetingNotes {
            let targetID = meetingNote.id
            if let migratedNote = try? modelContext.fetch(
                FetchDescriptor<Note>(predicate: #Predicate<Note> { $0.id == targetID })
            ).first {
                if migratedNote.body == meetingNote.content &&
                   migratedNote.createdAt == meetingNote.createdAt {
                    results.meetingNotesVerified += 1
                } else {
                    results.meetingNotesErrors += 1
                }
            } else {
                results.meetingNotesNotMigrated += 1
            }
        }
        
        return results
    }
}

struct VerificationResults {
    var scopedNotesVerified: Int = 0
    var scopedNotesErrors: Int = 0
    var scopedNotesNotMigrated: Int = 0
    
    var workNotesVerified: Int = 0
    var workNotesErrors: Int = 0
    var workNotesNotMigrated: Int = 0
    
    var meetingNotesVerified: Int = 0
    var meetingNotesErrors: Int = 0
    var meetingNotesNotMigrated: Int = 0
    
    var totalVerified: Int {
        scopedNotesVerified + workNotesVerified + meetingNotesVerified
    }
    
    var totalErrors: Int {
        scopedNotesErrors + workNotesErrors + meetingNotesErrors
    }
    
    var totalNotMigrated: Int {
        scopedNotesNotMigrated + workNotesNotMigrated + meetingNotesNotMigrated
    }
    
    var isComplete: Bool {
        totalErrors == 0 && totalNotMigrated == 0
    }
}

