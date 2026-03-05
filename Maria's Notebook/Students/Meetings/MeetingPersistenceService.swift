import Foundation
import OSLog
import SwiftData

// MARK: - Meeting Persistence Service

/// Service for managing meeting persistence via UserDefaults and SwiftData.
enum MeetingPersistenceService {
    private static let logger = Logger.students

    // MARK: - Current Meeting Data

    /// Data structure for current meeting state (stored in UserDefaults).
    struct CurrentMeetingData {
        var isCompleted: Bool = false
        var reflectionText: String = ""
        var focusText: String = ""
        var requestsText: String = ""
        var guideNotesText: String = ""

        var isEmpty: Bool {
            reflectionText.trimmed().isEmpty &&
            focusText.trimmed().isEmpty &&
            requestsText.trimmed().isEmpty &&
            guideNotesText.trimmed().isEmpty
        }
    }

    // MARK: - Load Current

    /// Loads current meeting data from UserDefaults.
    static func loadCurrent(studentID: UUID) -> CurrentMeetingData {
        let prefix = "StudentMeetings.current.\(studentID.uuidString)"
        let d = UserDefaults.standard
        return CurrentMeetingData(
            isCompleted: d.bool(forKey: prefix + ".completed"),
            reflectionText: d.string(forKey: prefix + ".reflection") ?? "",
            focusText: d.string(forKey: prefix + ".focus") ?? "",
            requestsText: d.string(forKey: prefix + ".requests") ?? "",
            guideNotesText: d.string(forKey: prefix + ".guideNotes") ?? ""
        )
    }

    // MARK: - Save Current

    /// Saves current meeting data to UserDefaults.
    static func saveCurrent(studentID: UUID, data: CurrentMeetingData) {
        let prefix = "StudentMeetings.current.\(studentID.uuidString)"
        let d = UserDefaults.standard
        d.set(data.isCompleted, forKey: prefix + ".completed")
        d.set(data.reflectionText, forKey: prefix + ".reflection")
        d.set(data.focusText, forKey: prefix + ".focus")
        d.set(data.requestsText, forKey: prefix + ".requests")
        d.set(data.guideNotesText, forKey: prefix + ".guideNotes")
    }

    // MARK: - Clear Current

    /// Clears current meeting data from UserDefaults.
    static func clearCurrent(studentID: UUID) {
        saveCurrent(studentID: studentID, data: CurrentMeetingData())
    }

    // MARK: - Save to History

    /// Saves current meeting data to SwiftData history.
    ///
    /// - Parameters:
    ///   - studentID: Student ID
    ///   - data: Current meeting data
    ///   - context: Model context
    /// - Returns: true if saved successfully
    @discardableResult
    static func saveToHistory(studentID: UUID, data: CurrentMeetingData, context: ModelContext) -> Bool {
        let trimmedReflection = data.reflectionText.trimmed()
        let trimmedFocus = data.focusText.trimmed()
        let trimmedRequests = data.requestsText.trimmed()
        let trimmedGuide = data.guideNotesText.trimmed()

        guard !(trimmedReflection.isEmpty && trimmedFocus.isEmpty
               && trimmedRequests.isEmpty && trimmedGuide.isEmpty) else {
            return false
        }

        let entry = StudentMeeting(
            studentID: studentID,
            date: Date(),
            completed: data.isCompleted,
            reflection: trimmedReflection,
            focus: trimmedFocus,
            requests: trimmedRequests,
            guideNotes: trimmedGuide
        )
        context.insert(entry)
        do {
            try context.save()
        } catch {
            logger.warning("Failed to save meeting to history: \(error)")
        }
        return true
    }

    // MARK: - Migrate History

    /// Migrates legacy history from UserDefaults to SwiftData.
    ///
    /// - Parameters:
    ///   - studentID: Student ID
    ///   - existingMeetings: Existing SwiftData meetings (to check if migration needed)
    ///   - context: Model context
    static func migrateHistoryIfNeeded(studentID: UUID, existingMeetings: [StudentMeeting], context: ModelContext) {
        // If we already have SwiftData meetings for this student, skip migration
        if !existingMeetings.isEmpty { return }

        let historyKey = "StudentMeetings.history.\(studentID.uuidString)"
        let d = UserDefaults.standard
        guard let data = d.data(forKey: historyKey) else { return }

        do {
            let decoded = try JSONDecoder().decode([LegacyMeetingEntry].self, from: data)
            var inserted = 0
            for entry in decoded {
                let m = StudentMeeting(
                    studentID: studentID,
                    date: entry.date,
                    completed: entry.completed,
                    reflection: entry.reflection,
                    focus: entry.focus,
                    requests: entry.requests,
                    guideNotes: entry.guideNotes
                )
                context.insert(m)
                inserted += 1
            }
            if inserted > 0 {
                do {
                    try context.save()
                } catch {
                    logger.warning("Failed to save migrated meeting history: \(error)")
                }
            }
            d.removeObject(forKey: historyKey)
        } catch {
            // If decoding fails, leave defaults as-is
        }
    }

    // MARK: - Legacy Types

    private struct LegacyMeetingEntry: Identifiable, Codable {
        let id: UUID
        let date: Date
        let completed: Bool
        let reflection: String
        let focus: String
        let requests: String
        let guideNotes: String
    }
}
