import Foundation
import OSLog
import CoreData

/// Service for migrating existing CDWorkCheckIn entries to CDPracticeSession records
struct PracticeSessionMigration {
    private static let logger = Logger.work

    let context: NSManagedObjectContext

    // MARK: - Migration Status

    /// Check if migration has already been performed
    func isMigrationCompleted() -> Bool {
        return UserDefaults.standard.bool(forKey: "PracticeSessionMigrationCompleted")
    }

    /// Mark migration as completed
    private func markMigrationCompleted() {
        UserDefaults.standard.set(true, forKey: "PracticeSessionMigrationCompleted")
    }

    // MARK: - Migration

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func performMigration() throws -> MigrationResult {
        guard !isMigrationCompleted() else {
            return MigrationResult(
                sessionsCreated: 0,
                checkInsMigrated: 0,
                errors: [],
                skipped: true
            )
        }

        var sessionsCreated = 0
        var checkInsMigrated = 0
        var errors: [PracticeSessionMigrationError] = []

        let request = CDFetchRequest(CDWorkCheckIn.self)
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]

        let allCheckIns: [CDWorkCheckIn]
        do {
            allCheckIns = try context.fetch(request)
        } catch {
            Self.logger.warning("Failed to fetch CDWorkCheckIn records: \(error)")
            throw PracticeSessionMigrationError.fetchFailed
        }

        // Filter to completed check-ins
        let checkIns = allCheckIns.filter(\.isCompleted)

        // Group check-ins by date and work item to identify potential group sessions
        var checkInsByDateAndWork: [String: [CDWorkCheckIn]] = [:]

        for checkIn in checkIns {
            guard let work = checkIn.work else {
                if let ciID = checkIn.id {
                    errors.append(.missingWork(checkInID: ciID))
                }
                continue
            }

            let key = "\(AppCalendar.startOfDay(checkIn.date ?? Date()))_\(work.id?.uuidString ?? "")"
            checkInsByDateAndWork[key, default: []].append(checkIn)
        }

        // Create practice sessions from grouped check-ins
        for (_, checkInGroup) in checkInsByDateAndWork {
            guard let firstCheckIn = checkInGroup.first,
                  firstCheckIn.work != nil else {
                continue
            }

            var studentIDs: Set<String> = []
            var workItemIDs: Set<String> = []
            var allNotes: [String] = []

            for checkIn in checkInGroup {
                if let checkInWork = checkIn.work {
                    if let wid = checkInWork.id {
                        workItemIDs.insert(wid.uuidString)
                    }
                    if !checkInWork.studentID.isEmpty {
                        studentIDs.insert(checkInWork.studentID)
                    }
                }
                let noteText = checkIn.latestUnifiedNoteText
                if !noteText.isEmpty {
                    allNotes.append(noteText)
                }
            }

            // Create practice session
            let session = CDPracticeSession(context: context)
            session.date = firstCheckIn.date
            session.duration = 0
            session.studentIDs = Array(studentIDs) as NSArray
            session.workItemIDs = Array(workItemIDs) as NSArray
            session.sharedNotes = allNotes.joined(separator: "\n\n")
            session.location = nil

            // Migrate notes from check-in to practice session
            let checkInNotes = (firstCheckIn.notes?.allObjects as? [CDNote]) ?? []
            for note in checkInNotes {
                note.practiceSession = session
                note.workCheckIn = nil
            }

            sessionsCreated += 1
            checkInsMigrated += checkInGroup.count
        }

        // Save all changes
        try context.save()

        // Mark migration as completed
        markMigrationCompleted()

        return MigrationResult(
            sessionsCreated: sessionsCreated,
            checkInsMigrated: checkInsMigrated,
            errors: errors,
            skipped: false
        )
    }

    /// Resets migration status (for testing or re-migration)
    func resetMigration() {
        UserDefaults.standard.removeObject(forKey: "PracticeSessionMigrationCompleted")
    }
}

// MARK: - Supporting Types

/// Result of a migration operation
struct MigrationResult {
    let sessionsCreated: Int
    let checkInsMigrated: Int
    let errors: [PracticeSessionMigrationError]
    let skipped: Bool

    var isSuccess: Bool {
        errors.isEmpty && !skipped
    }

    var summary: String {
        if skipped {
            return "Migration already completed"
        }
        if errors.isEmpty {
            return "Successfully migrated \(checkInsMigrated) check-ins into \(sessionsCreated) practice sessions"
        } else {
            return "Migrated \(checkInsMigrated) check-ins with \(errors.count) errors"
        }
    }
}

/// Errors that can occur during practice session migration
enum PracticeSessionMigrationError: Error, LocalizedError {
    case fetchFailed
    case missingWork(checkInID: UUID)
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .fetchFailed:
            return "Failed to fetch check-ins for migration"
        case .missingWork(let checkInID):
            return "Check-in \(checkInID) has no associated work item"
        case .saveFailed:
            return "Failed to save migrated data"
        }
    }
}
