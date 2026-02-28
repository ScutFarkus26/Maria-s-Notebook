import Foundation
import SwiftData
import OSLog

/// Assembles classroom data context for chat requests.
/// Uses a two-tier strategy:
/// - Tier 1: Classroom snapshot (student roster, subjects, weekly summary, todos) — built once per session
/// - Tier 2: Selective student detail — loaded per-question when student names are detected
@MainActor
final class ChatContextAssembler {
    private static let logger = Logger.ai

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Tier 1: Classroom Snapshot

    /// Builds a compact classroom snapshot including roster, subjects, weekly activity, and open todos.
    func buildClassroomSnapshot() -> String {
        let queryService = DataQueryService(context: context)
        let students = queryService.fetchAllStudents(excludeTest: true)
        let lessons = queryService.fetchAllLessons()

        var lines: [String] = []
        lines.append("=== CLASSROOM SNAPSHOT ===")
        lines.append("Date: \(formattedDate(Date()))")
        lines.append("Total students: \(students.count)")
        lines.append("")

        // Student roster with birthday for age comparisons
        lines.append("--- Student Roster ---")
        for student in students.sorted(by: { $0.firstName < $1.firstName }) {
            let age = ageString(for: student.birthday)
            let nick = student.nickname.map { " (\($0))" } ?? ""
            let bday = formattedDate(student.birthday)
            lines.append("• \(student.firstName) \(student.lastName.prefix(1))\(nick) — \(student.level.rawValue), age \(age), born \(bday)")
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

        // Presentations this week (modern LessonAssignment model)
        let recentPresentations = fetchPresentations(from: weekStart, to: Date(), state: .presented)
        let scheduledPresentations = fetchPresentations(from: Date(), to: Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date(), state: .scheduled)

        lines.append("--- This Week ---")
        lines.append("Presentations given: \(recentPresentations.count)")
        if !scheduledPresentations.isEmpty {
            lines.append("Upcoming scheduled: \(scheduledPresentations.count)")
        }

        // Recent presentation details (who got what)
        let lessonsDict = queryService.fetchLessonsDictionary()
        let studentsDict = queryService.fetchStudentsDictionary()
        if !recentPresentations.isEmpty {
            lines.append("Recent presentations:")
            for pres in recentPresentations.prefix(10) {
                let lessonName = pres.lessonTitleSnapshot ?? lessonsDict[pres.lessonIDUUID ?? UUID()]?.name ?? "Unknown"
                let studentNames = pres.studentUUIDs.compactMap { studentsDict[$0]?.firstName }.joined(separator: ", ")
                let date = formattedDate(pres.presentedAt ?? pres.createdAt)
                var line = "  • \(lessonName) → \(studentNames) (\(date))"
                if pres.needsPractice { line += " [needs practice]" }
                if pres.needsAnotherPresentation { line += " [needs re-presentation]" }
                lines.append(line)
            }
        }

        // Attendance summary for the week
        let attendanceRecords = fetchAttendanceRecords(from: weekStart, to: Date())
        let absences = attendanceRecords.filter { $0.status == .absent }
        let tardies = attendanceRecords.filter { $0.status == .tardy }
        if !absences.isEmpty || !tardies.isEmpty {
            lines.append("Absences this week: \(absences.count)")
            if !absences.isEmpty {
                let absentNames = absences.compactMap { rec -> String? in
                    guard let uuid = UUID(uuidString: rec.studentID) else { return nil }
                    return studentsDict[uuid]?.firstName
                }
                let uniqueAbsent = Array(Set(absentNames)).sorted()
                lines.append("  Students absent: \(uniqueAbsent.joined(separator: ", "))")
            }
            lines.append("Tardies this week: \(tardies.count)")
        }

        // Open work summary
        let openWork = queryService.fetchOpenWorkModels()
        lines.append("Open work items: \(openWork.count)")
        if !openWork.isEmpty {
            // Group by student
            let workByStudent = Dictionary(grouping: openWork) { $0.studentID }
            for (studentIDStr, works) in workByStudent.sorted(by: { $0.value.count > $1.value.count }).prefix(8) {
                if let uuid = UUID(uuidString: studentIDStr), let student = studentsDict[uuid] {
                    let titles = works.prefix(3).map { $0.title }.joined(separator: ", ")
                    let moreCount = works.count > 3 ? " +\(works.count - 3) more" : ""
                    lines.append("  • \(student.firstName): \(titles)\(moreCount)")
                }
            }
        }
        lines.append("")

        // Recent completed work (last 7 days)
        let recentCompleted = fetchRecentCompletedWork(since: weekStart)
        if !recentCompleted.isEmpty {
            lines.append("--- Recently Completed Work ---")
            for work in recentCompleted.prefix(8) {
                let studentName = UUID(uuidString: work.studentID).flatMap { studentsDict[$0]?.firstName } ?? "Unknown"
                let outcome = work.completionOutcomeRaw.flatMap { CompletionOutcome(rawValue: $0)?.displayName } ?? ""
                let outcomeStr = outcome.isEmpty ? "" : " [\(outcome)]"
                lines.append("  • \(studentName): \(work.title)\(outcomeStr)")
            }
            lines.append("")
        }

        // Class-wide notes (last 7 days)
        let recentClassNotes = fetchRecentClassNotes(limit: 5)
        if !recentClassNotes.isEmpty {
            lines.append("--- Recent Class Notes ---")
            for note in recentClassNotes {
                let date = formattedDate(note.createdAt)
                let body = String(note.body.prefix(150))
                lines.append("  • \(date): \(body)")
            }
            lines.append("")
        }

        // Open todos
        let openTodos = fetchOpenTodos()
        if !openTodos.isEmpty {
            lines.append("--- Teacher Todos ---")
            for todo in openTodos.prefix(10) {
                var line = "  • \(todo.title)"
                if todo.priority != .none {
                    line += " [\(todo.priority.rawValue)]"
                }
                if let due = todo.dueDate {
                    line += " (due \(formattedDate(due)))"
                }
                if !todo.studentIDs.isEmpty {
                    let names = todo.studentUUIDs.compactMap { studentsDict[$0]?.firstName }
                    if !names.isEmpty {
                        line += " — \(names.joined(separator: ", "))"
                    }
                }
                lines.append(line)
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Tier 2: Question-Specific Context

    /// Builds additional context for students mentioned in the question.
    /// Returns the context string and the set of matched student IDs.
    func buildQuestionContext(question: String, existingMentionedIDs: Set<UUID>) -> (context: String, mentionedIDs: Set<UUID>) {
        let queryService = DataQueryService(context: context)
        let allStudents = queryService.fetchAllStudents(excludeTest: true)

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
        let studentsDict = queryService.fetchStudentsDictionary()

        for student in matched.prefix(3) { // Cap at 3 students per question
            newMentionedIDs.insert(student.id)
            lines.append("")
            lines.append("--- \(student.firstName) \(student.lastName) ---")

            let age = ageString(for: student.birthday)
            lines.append("Age: \(age), Birthday: \(formattedDate(student.birthday)), Level: \(student.level.rawValue)")
            if let started = student.dateStarted {
                lines.append("Started: \(formattedDate(started))")
            }

            let studentIDString = student.id.uuidString

            // Recent presentations (LessonAssignment model — last 10)
            let studentPresentations = fetchPresentationsForStudent(studentID: student.id, limit: 10)
            if !studentPresentations.isEmpty {
                lines.append("Recent presentations (last \(studentPresentations.count)):")
                for pres in studentPresentations {
                    let lessonName = pres.lessonTitleSnapshot ?? lessonsDict[pres.lessonIDUUID ?? UUID()]?.name ?? "Unknown"
                    let lesson = lessonsDict[pres.lessonIDUUID ?? UUID()]
                    let subject = lesson?.subject ?? ""
                    let subjectStr = subject.isEmpty ? "" : " (\(subject))"
                    let date = formattedDate(pres.presentedAt ?? pres.createdAt)
                    var line = "  • \(lessonName)\(subjectStr) — \(date)"
                    if pres.needsPractice { line += " [needs practice]" }
                    if pres.needsAnotherPresentation { line += " [needs re-presentation]" }
                    if !pres.followUpWork.isEmpty { line += " → follow-up: \(pres.followUpWork.prefix(80))" }
                    lines.append(line)

                    // Include presentation notes
                    if !pres.notes.isEmpty {
                        lines.append("    Notes: \(pres.notes.prefix(120))")
                    }
                    // Include attached unified notes
                    for note in (pres.unifiedNotes ?? []).prefix(2) {
                        if !note.body.isEmpty {
                            lines.append("    Observation: \(note.body.prefix(120))")
                        }
                    }

                    // Show who else was in this presentation
                    let otherStudents = pres.studentUUIDs
                        .filter { $0 != student.id }
                        .compactMap { studentsDict[$0]?.firstName }
                    if !otherStudents.isEmpty {
                        lines.append("    Also with: \(otherStudents.joined(separator: ", "))")
                    }
                }
            }

            // Active work items (with more detail)
            let allOpenWork = queryService.fetchOpenWorkModels()
            let studentWork = allOpenWork.filter { $0.studentID == studentIDString }
            if !studentWork.isEmpty {
                lines.append("Active work (\(studentWork.count)):")
                for work in studentWork.prefix(8) {
                    let status = WorkStatus(rawValue: work.statusRaw)?.displayName ?? work.statusRaw
                    let kind = work.kindRaw.flatMap { WorkKind(rawValue: $0)?.displayName } ?? ""
                    let kindStr = kind.isEmpty ? "" : " (\(kind))"
                    var line = "  • \(work.title) [\(status)]\(kindStr)"
                    if let assigned = work.assignedAt as Date? {
                        line += " assigned \(formattedDate(assigned))"
                    }
                    if let due = work.dueAt {
                        line += " due \(formattedDate(due))"
                    }
                    lines.append(line)

                    // Include work notes
                    for note in (work.unifiedNotes ?? []).prefix(2) {
                        if !note.body.isEmpty {
                            lines.append("    Note: \(note.body.prefix(100))")
                        }
                    }
                }
            }

            // Recently completed work
            let monthStart = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
            let completedWork = fetchCompletedWorkForStudent(studentID: studentIDString, since: monthStart)
            if !completedWork.isEmpty {
                lines.append("Completed work (last 30 days):")
                for work in completedWork.prefix(5) {
                    let outcome = work.completionOutcomeRaw.flatMap { CompletionOutcome(rawValue: $0)?.displayName } ?? ""
                    let outcomeStr = outcome.isEmpty ? "" : " [\(outcome)]"
                    let date = work.completedAt.map { formattedDate($0) } ?? ""
                    lines.append("  • \(work.title)\(outcomeStr) — \(date)")
                }
            }

            // Recent notes (more generous limit)
            let recentNotes = fetchRecentNotes(for: student.id, limit: 5)
            if !recentNotes.isEmpty {
                lines.append("Recent notes:")
                for note in recentNotes {
                    let date = formattedDate(note.createdAt)
                    let body = String(note.body.prefix(150))
                    let context = note.attachedTo
                    let contextStr = context == "general" ? "" : " [\(context)]"
                    lines.append("  • \(date)\(contextStr): \(body)")
                }
            }

            // Attendance this month
            let attendance = fetchAttendanceRecords(from: monthStart, to: Date())
                .filter { $0.studentID == studentIDString }
            let presentCount = attendance.filter { $0.status == .present }.count
            let absentCount = attendance.filter { $0.status == .absent }.count
            let tardyCount = attendance.filter { $0.status == .tardy }.count
            let totalRecords = attendance.filter { $0.status != .unmarked }.count
            if totalRecords > 0 {
                lines.append("Attendance (30 days): \(presentCount) present, \(absentCount) absent, \(tardyCount) tardy out of \(totalRecords) days")
            }

            // Todos linked to this student
            let studentTodos = fetchTodosForStudent(studentID: student.id)
            if !studentTodos.isEmpty {
                lines.append("Todos for \(student.firstName):")
                for todo in studentTodos.prefix(5) {
                    let status = todo.isCompleted ? "[done]" : "[open]"
                    var line = "  • \(todo.title) \(status)"
                    if let due = todo.dueDate {
                        line += " due \(formattedDate(due))"
                    }
                    lines.append(line)
                }
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

    private func fetchPresentations(from startDate: Date, to endDate: Date, state: LessonAssignmentState) -> [LessonAssignment] {
        let stateRaw = state.rawValue
        if state == .presented {
            let descriptor = FetchDescriptor<LessonAssignment>(
                predicate: #Predicate { pres in
                    pres.stateRaw == stateRaw && pres.presentedAt != nil
                },
                sortBy: [SortDescriptor(\LessonAssignment.presentedAt, order: .reverse)]
            )
            return context.safeFetch(descriptor).filter { pres in
                guard let presentedAt = pres.presentedAt else { return false }
                return presentedAt >= startDate && presentedAt <= endDate
            }
        } else {
            let descriptor = FetchDescriptor<LessonAssignment>(
                predicate: #Predicate { pres in
                    pres.stateRaw == stateRaw
                },
                sortBy: [SortDescriptor(\LessonAssignment.scheduledForDay)]
            )
            return context.safeFetch(descriptor).filter { pres in
                pres.scheduledForDay >= startDate && pres.scheduledForDay <= endDate
            }
        }
    }

    private func fetchPresentationsForStudent(studentID: UUID, limit: Int) -> [LessonAssignment] {
        let presentedRaw = LessonAssignmentState.presented.rawValue
        let descriptor = FetchDescriptor<LessonAssignment>(
            predicate: #Predicate { pres in
                pres.stateRaw == presentedRaw
            },
            sortBy: [SortDescriptor(\LessonAssignment.presentedAt, order: .reverse)]
        )
        let allPresented = context.safeFetch(descriptor)
        let studentIDString = studentID.uuidString
        return Array(allPresented.filter { $0.studentIDs.contains(studentIDString) }.prefix(limit))
    }

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

    private func fetchRecentClassNotes(limit: Int) -> [Note] {
        let descriptor = FetchDescriptor<Note>(
            predicate: #Predicate { note in
                note.scopeIsAll == true
            },
            sortBy: [SortDescriptor(\Note.createdAt, order: .reverse)]
        )
        var limited = descriptor
        limited.fetchLimit = limit
        return context.safeFetch(limited)
    }

    private func fetchRecentCompletedWork(since date: Date) -> [WorkModel] {
        let completeRaw = WorkStatus.complete.rawValue
        let descriptor = FetchDescriptor<WorkModel>(
            predicate: #Predicate { work in
                work.statusRaw == completeRaw
            },
            sortBy: [SortDescriptor(\WorkModel.completedAt, order: .reverse)]
        )
        return context.safeFetch(descriptor).filter { work in
            guard let completedAt = work.completedAt else { return false }
            return completedAt >= date
        }
    }

    private func fetchCompletedWorkForStudent(studentID: String, since date: Date) -> [WorkModel] {
        let completeRaw = WorkStatus.complete.rawValue
        let descriptor = FetchDescriptor<WorkModel>(
            predicate: #Predicate { work in
                work.statusRaw == completeRaw && work.studentID == studentID
            },
            sortBy: [SortDescriptor(\WorkModel.completedAt, order: .reverse)]
        )
        return context.safeFetch(descriptor).filter { work in
            guard let completedAt = work.completedAt else { return false }
            return completedAt >= date
        }
    }

    private func fetchOpenTodos() -> [TodoItem] {
        let descriptor = FetchDescriptor<TodoItem>(
            predicate: #Predicate { todo in
                todo.isCompleted == false
            },
            sortBy: [SortDescriptor(\TodoItem.orderIndex)]
        )
        return context.safeFetch(descriptor)
    }

    private func fetchTodosForStudent(studentID: UUID) -> [TodoItem] {
        // TodoItem stores studentIDs as [String], so we fetch all open and filter
        let studentIDString = studentID.uuidString
        let descriptor = FetchDescriptor<TodoItem>(
            predicate: #Predicate { todo in
                todo.isCompleted == false
            }
        )
        return context.safeFetch(descriptor).filter { $0.studentIDs.contains(studentIDString) }
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
