import Foundation
import OSLog
import CoreData

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
        var nextMeetingDate: Date?

        // Focus checklist draft persistence
        var pendingFocusTexts: [String]?
        var resolvedFocusIDs: [String]?
        var droppedFocusIDs: [String]?

        // Work review draft persistence (keyed by workID uuidString)
        var workReviewDrafts: [String: String]?
        var reviewedWorkIDs: [String]?

        var isEmpty: Bool {
            reflectionText.trimmed().isEmpty &&
            focusText.trimmed().isEmpty &&
            requestsText.trimmed().isEmpty &&
            guideNotesText.trimmed().isEmpty &&
            (pendingFocusTexts ?? []).allSatisfy { $0.trimmed().isEmpty } &&
            (workReviewDrafts ?? [:]).values.allSatisfy { $0.trimmed().isEmpty } &&
            (reviewedWorkIDs ?? []).isEmpty
        }
    }

    // MARK: - Load Current

    /// Loads current meeting data from UserDefaults.
    static func loadCurrent(studentID: UUID) -> CurrentMeetingData {
        let prefix = "StudentMeetings.current.\(studentID.uuidString)"
        let d = UserDefaults.standard
        return CurrentMeetingData(
            isCompleted: false,
            reflectionText: d.string(forKey: prefix + ".reflection") ?? "",
            focusText: d.string(forKey: prefix + ".focus") ?? "",
            requestsText: d.string(forKey: prefix + ".requests") ?? "",
            guideNotesText: d.string(forKey: prefix + ".guideNotes") ?? "",
            nextMeetingDate: d.object(forKey: prefix + ".nextMeetingDate") as? Date,
            pendingFocusTexts: d.stringArray(forKey: prefix + ".pendingFocusTexts"),
            resolvedFocusIDs: d.stringArray(forKey: prefix + ".resolvedFocusIDs"),
            droppedFocusIDs: d.stringArray(forKey: prefix + ".droppedFocusIDs"),
            workReviewDrafts: d.dictionary(forKey: prefix + ".workReviewDrafts") as? [String: String],
            reviewedWorkIDs: d.stringArray(forKey: prefix + ".reviewedWorkIDs")
        )
    }

    // MARK: - Save Current

    /// Saves current meeting data to UserDefaults.
    static func saveCurrent(studentID: UUID, data: CurrentMeetingData) {
        let prefix = "StudentMeetings.current.\(studentID.uuidString)"
        let d = UserDefaults.standard
        d.set(data.reflectionText, forKey: prefix + ".reflection")
        d.set(data.focusText, forKey: prefix + ".focus")
        d.set(data.requestsText, forKey: prefix + ".requests")
        d.set(data.guideNotesText, forKey: prefix + ".guideNotes")
        d.set(data.nextMeetingDate, forKey: prefix + ".nextMeetingDate")
        d.set(data.pendingFocusTexts, forKey: prefix + ".pendingFocusTexts")
        d.set(data.resolvedFocusIDs, forKey: prefix + ".resolvedFocusIDs")
        d.set(data.droppedFocusIDs, forKey: prefix + ".droppedFocusIDs")
        d.set(data.workReviewDrafts, forKey: prefix + ".workReviewDrafts")
        d.set(data.reviewedWorkIDs, forKey: prefix + ".reviewedWorkIDs")
    }

    // MARK: - Clear Current

    /// Clears current meeting data from UserDefaults.
    static func clearCurrent(studentID: UUID) {
        saveCurrent(studentID: studentID, data: CurrentMeetingData())
    }

    // MARK: - Save to History

    /// Saves current meeting data to Core Data history.
    ///
    /// - Parameters:
    ///   - studentID: CDStudent ID
    ///   - data: Current meeting data
    ///   - context: Managed object context
    /// - Returns: The created CDStudentMeeting, or nil if data was empty
    @discardableResult
    static func saveToHistory(studentID: UUID, data: CurrentMeetingData, context: NSManagedObjectContext) -> CDStudentMeeting? {
        let trimmedReflection = data.reflectionText.trimmed()
        let trimmedFocus = data.focusText.trimmed()
        let trimmedRequests = data.requestsText.trimmed()
        let trimmedGuide = data.guideNotesText.trimmed()

        guard !(trimmedReflection.isEmpty && trimmedFocus.isEmpty
               && trimmedRequests.isEmpty && trimmedGuide.isEmpty
               && (data.pendingFocusTexts ?? []).allSatisfy { $0.trimmed().isEmpty }) else {
            return nil
        }

        let entry = CDStudentMeeting(context: context)
        entry.studentIDUUID = studentID
        entry.date = Date()
        entry.completed = data.isCompleted
        entry.reflection = trimmedReflection
        entry.focus = trimmedFocus
        entry.requests = trimmedRequests
        entry.guideNotes = trimmedGuide
        do {
            try context.save()
        } catch {
            logger.warning("Failed to save meeting to history: \(error)")
        }
        return entry
    }

    // MARK: - Migrate History

    /// Migrates legacy history from UserDefaults to SwiftData.
    ///
    /// - Parameters:
    ///   - studentID: CDStudent ID
    ///   - existingMeetings: Existing SwiftData meetings (to check if migration needed)
    ///   - context: Model context
    static func migrateHistoryIfNeeded(studentID: UUID, existingMeetings: [CDStudentMeeting], context: NSManagedObjectContext) {
        // If we already have SwiftData meetings for this student, skip migration
        if !existingMeetings.isEmpty { return }

        let historyKey = "StudentMeetings.history.\(studentID.uuidString)"
        let d = UserDefaults.standard
        guard let data = d.data(forKey: historyKey) else { return }

        do {
            let decoded = try JSONDecoder().decode([LegacyMeetingEntry].self, from: data)
            var inserted = 0
            for entry in decoded {
                let m = CDStudentMeeting(context: context)
                m.studentIDUUID = studentID
                m.date = entry.date
                m.completed = entry.completed
                m.reflection = entry.reflection
                m.focus = entry.focus
                m.requests = entry.requests
                m.guideNotes = entry.guideNotes
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
