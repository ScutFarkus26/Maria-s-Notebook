import Foundation
import SwiftData
import OSLog

/// Assembles classroom data context for chat requests.
/// Uses a two-tier strategy:
/// - Tier 1: Classroom snapshot (student roster, subjects, weekly summary) — built once per session
/// - Tier 2: Selective student detail — loaded per-question when student names are detected
@MainActor
final class ChatContextAssembler {
    private static let logger = Logger.ai

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Tier 1: Classroom Snapshot

    /// Builds a compact classroom snapshot including roster, subjects, and weekly activity.
    func buildClassroomSnapshot() -> String {
        let queryService = DataQueryService(context: context)
        let students = queryService.fetchAllStudents()
        let lessons = queryService.fetchAllLessons()

        var lines: [String] = []
        lines.append("=== CLASSROOM SNAPSHOT ===")
        lines.append("Date: \(formattedDate(Date()))")
        lines.append("Total students: \(students.count)")
        lines.append("")

        // Student roster
        lines.append("--- Student Roster ---")
        for student in students.sorted(by: { $0.firstName < $1.firstName }) {
            let age = ageString(for: student.birthday)
            let nick = student.nickname.map { " (\($0))" } ?? ""
            lines.append("• \(student.firstName) \(student.lastName.prefix(1))\(nick) — \(student.level.rawValue), age \(age)")
        }
        lines.append("")

        // Subjects taught
        let subjects = Set(lessons.map { $0.subject }).filter { !$0.isEmpty }.sorted()
        if !subjects.isEmpty {
            lines.append("--- Subjects ---")
            lines.append(subjects.joined(separator: ", "))
            lines.append("")
        }

        // This week's activity summary
        let weekStart = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let recentPresentations = queryService.fetchStudentLessons(from: weekStart, to: Date())
            .filter { $0.isPresented }
        lines.append("--- This Week ---")
        lines.append("Presentations given: \(recentPresentations.count)")

        // Attendance summary for the week
        let attendanceRecords = fetchAttendanceRecords(from: weekStart, to: Date())
        let absences = attendanceRecords.filter { $0.status == .absent }
        let tardies = attendanceRecords.filter { $0.status == .tardy }
        if !absences.isEmpty || !tardies.isEmpty {
            lines.append("Absences this week: \(absences.count)")
            lines.append("Tardies this week: \(tardies.count)")
        }

        // Open work summary
        let openWork = queryService.fetchOpenWorkModels()
        lines.append("Open work items: \(openWork.count)")

        return lines.joined(separator: "\n")
    }

    // MARK: - Tier 2: Question-Specific Context

    /// Builds additional context for students mentioned in the question.
    /// Returns the context string and the set of matched student IDs.
    func buildQuestionContext(question: String, existingMentionedIDs: Set<UUID>) -> (context: String, mentionedIDs: Set<UUID>) {
        let queryService = DataQueryService(context: context)
        let allStudents = queryService.fetchAllStudents()

        // Match student names in the question
        let matched = matchStudents(in: question, from: allStudents)
        guard !matched.isEmpty else {
            return ("", existingMentionedIDs)
        }

        var newMentionedIDs = existingMentionedIDs
        var lines: [String] = []
        lines.append("")
        lines.append("=== STUDENT DETAILS ===")

        let lessonsDict = queryService.fetchLessonsDictionary()

        for student in matched.prefix(3) { // Cap at 3 students per question
            newMentionedIDs.insert(student.id)
            lines.append("")
            lines.append("--- \(student.firstName) \(student.lastName) ---")

            let age = ageString(for: student.birthday)
            lines.append("Age: \(age), Level: \(student.level.rawValue)")
            if let started = student.dateStarted {
                lines.append("Started: \(formattedDate(started))")
            }

            // Recent presentations (last 5)
            let studentLessons = queryService.fetchStudentLessons(for: student.id)
                .filter { $0.isPresented }
                .sorted { ($0.givenAt ?? $0.createdAt) > ($1.givenAt ?? $1.createdAt) }
                .prefix(5)

            if !studentLessons.isEmpty {
                lines.append("Recent presentations:")
                for sl in studentLessons {
                    let lesson = lessonsDict[UUID(uuidString: sl.lessonID) ?? UUID()]
                    let name = lesson?.name ?? "Unknown"
                    let subject = lesson?.subject ?? ""
                    let date = formattedDate(sl.givenAt ?? sl.createdAt)
                    lines.append("  • \(name) (\(subject)) — \(date)")
                    if !sl.notes.isEmpty {
                        lines.append("    Notes: \(sl.notes.prefix(100))")
                    }
                }
            }

            // Active work items
            let studentIDString = student.id.uuidString
            let allWork = queryService.fetchOpenWorkModels()
            let studentWork = allWork.filter { $0.studentID == studentIDString }
            if !studentWork.isEmpty {
                lines.append("Active work:")
                for work in studentWork.prefix(5) {
                    let status = WorkStatus(rawValue: work.statusRaw)?.displayName ?? work.statusRaw
                    lines.append("  • \(work.title) [\(status)]")
                }
            }

            // Recent notes
            let recentNotes = fetchRecentNotes(for: student.id, limit: 3)
            if !recentNotes.isEmpty {
                lines.append("Recent notes:")
                for note in recentNotes {
                    let date = formattedDate(note.createdAt)
                    let body = String(note.body.prefix(120))
                    lines.append("  • \(date): \(body)")
                }
            }

            // Attendance this month
            let monthStart = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
            let attendance = fetchAttendanceRecords(from: monthStart, to: Date())
                .filter { $0.studentID == studentIDString }
            let absentCount = attendance.filter { $0.status == .absent }.count
            let tardyCount = attendance.filter { $0.status == .tardy }.count
            if absentCount > 0 || tardyCount > 0 {
                lines.append("Attendance (30 days): \(absentCount) absent, \(tardyCount) tardy")
            }
        }

        return (lines.joined(separator: "\n"), newMentionedIDs)
    }

    // MARK: - Name Matching

    /// Fuzzy-matches student names in the question text.
    /// Supports: first name, nickname, "FirstName LastInitial" (e.g., "Etty D").
    private func matchStudents(in question: String, from students: [Student]) -> [Student] {
        let lowered = question.lowercased()
        var matched: [Student] = []
        var matchedIDs: Set<UUID> = []

        for student in students {
            guard !matchedIDs.contains(student.id) else { continue }

            // Check "firstName lastInitial" pattern (e.g., "Etty D")
            let firstLast = "\(student.firstName.lowercased()) \(student.lastName.prefix(1).lowercased())"
            if lowered.contains(firstLast) {
                matched.append(student)
                matchedIDs.insert(student.id)
                continue
            }

            // Check full first name as whole word
            let firstName = student.firstName.lowercased()
            if matchesWholeWord(firstName, in: lowered) {
                matched.append(student)
                matchedIDs.insert(student.id)
                continue
            }

            // Check nickname
            if let nickname = student.nickname?.lowercased(), !nickname.isEmpty,
               matchesWholeWord(nickname, in: lowered) {
                matched.append(student)
                matchedIDs.insert(student.id)
            }
        }

        return matched
    }

    /// Checks if a word appears as a whole word in text (not as a substring of another word).
    private func matchesWholeWord(_ word: String, in text: String) -> Bool {
        guard !word.isEmpty else { return false }
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: word))\\b"
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    // MARK: - Data Fetching Helpers

    private func fetchAttendanceRecords(from startDate: Date, to endDate: Date) -> [AttendanceRecord] {
        let descriptor = FetchDescriptor<AttendanceRecord>(
            predicate: #Predicate { record in
                record.date >= startDate && record.date <= endDate
            }
        )
        return context.safeFetch(descriptor)
    }

    private func fetchRecentNotes(for studentID: UUID, limit: Int) -> [Note] {
        let descriptor = FetchDescriptor<Note>(
            predicate: #Predicate { note in
                note.searchIndexStudentID == studentID
            },
            sortBy: [SortDescriptor(\Note.createdAt, order: .reverse)]
        )
        var limited = descriptor
        limited.fetchLimit = limit
        return context.safeFetch(limited)
    }

    // MARK: - Formatting

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func ageString(for birthday: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month], from: birthday, to: Date())
        let years = components.year ?? 0
        let months = components.month ?? 0
        if years > 0 {
            return "\(years)y \(months)m"
        }
        return "\(months)m"
    }
}
