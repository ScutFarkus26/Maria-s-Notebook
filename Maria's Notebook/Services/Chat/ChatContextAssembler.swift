// swiftlint:disable file_length
import Foundation
import CoreData
import OSLog

/// Assembles classroom data context for chat requests.
/// Uses a two-tier strategy:
/// - Tier 1: Classroom snapshot (student roster, subjects, weekly summary, todos) — built once per session
/// - Tier 2: Selective student detail — loaded per-question when student names are detected
@MainActor
// swiftlint:disable:next type_body_length
final class ChatContextAssembler {
    private static let logger = Logger.ai

    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    // Deprecated ModelContext init removed - no longer needed with Core Data.

    // MARK: - Tier 1: Classroom Snapshot

    /// Builds a compact classroom snapshot including roster, subjects, weekly activity, and open todos.
    func buildClassroomSnapshot() -> String {
        let queryService = DataQueryService(context: context)
        let students = queryService.fetchAllStudents(excludeTest: true)
        let lessons = queryService.fetchAllLessons()
        let lessonsDict = queryService.fetchLessonsDictionary()
        let studentsDict = queryService.fetchStudentsDictionary()
        let weekStart = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()

        var lines: [String] = []
        lines.append("=== CLASSROOM SNAPSHOT ===")
        lines.append("Date: \(formattedDate(Date()))")
        lines.append("Total students: \(students.count)")
        lines.append("")

        appendRosterSection(&lines, students: students)
        appendSubjectsSection(&lines, lessons: lessons)
        appendWeeklyActivitySection(
            &lines, weekStart: weekStart,
            lessonsDict: lessonsDict, studentsDict: studentsDict
        )
        appendOpenWorkSection(&lines, queryService: queryService, studentsDict: studentsDict)
        appendCompletedWorkSection(&lines, weekStart: weekStart, studentsDict: studentsDict)
        appendClassNotesSection(&lines)
        appendTodosSection(&lines, studentsDict: studentsDict)

        return lines.joined(separator: "\n")
    }

    // MARK: - Classroom Snapshot Helpers

    private func appendRosterSection(_ lines: inout [String], students: [CDStudent]) {
        lines.append("--- Student Roster ---")
        for student in students.sorted(by: { $0.firstName < $1.firstName }) {
            let age = ageString(for: student.birthday)
            let nick = student.nickname.map { " (\($0))" } ?? ""
            let bday = formattedDate(student.birthday)
            let nameStr = "\(student.firstName) \(student.lastName.prefix(1))\(nick)"
            lines.append("• \(nameStr) — \(student.level.rawValue), age \(age), born \(bday)")
        }
        lines.append("")
    }

    private func appendSubjectsSection(_ lines: inout [String], lessons: [CDLesson]) {
        let subjects = Set(lessons.map(\.subject)).filter { !$0.isEmpty }.sorted()
        if !subjects.isEmpty {
            lines.append("--- Subjects ---")
            lines.append(subjects.joined(separator: ", "))
            lines.append("")
        }
    }

    private func appendWeeklyActivitySection(
        _ lines: inout [String], weekStart: Date,
        lessonsDict: [UUID: CDLesson], studentsDict: [UUID: CDStudent]
    ) {
        let recentPresentations = fetchPresentations(from: weekStart, to: Date(), state: .presented)
        let nextWeek = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        let scheduledPresentations = fetchPresentations(from: Date(), to: nextWeek, state: .scheduled)

        lines.append("--- This Week ---")
        lines.append("Presentations given: \(recentPresentations.count)")
        if !scheduledPresentations.isEmpty {
            lines.append("Upcoming scheduled: \(scheduledPresentations.count)")
        }

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
                lines.append("  Students absent: \(Array(Set(absentNames)).sorted().joined(separator: ", "))")
            }
            lines.append("Tardies this week: \(tardies.count)")
        }
    }

    private func appendOpenWorkSection(
        _ lines: inout [String], queryService: DataQueryService, studentsDict: [UUID: CDStudent]
    ) {
        let openWork = queryService.fetchOpenWorkModels()
        lines.append("Open work items: \(openWork.count)")
        if !openWork.isEmpty {
            let workByStudent = Dictionary(grouping: openWork) { $0.studentID }
            for (studentIDStr, works) in workByStudent.sorted(by: { $0.value.count > $1.value.count }).prefix(8) {
                if let student = studentsDict[uuidString: studentIDStr] {
                    let titles = works.prefix(3).map(\.title).joined(separator: ", ")
                    let moreCount = works.count > 3 ? " +\(works.count - 3) more" : ""
                    lines.append("  • \(student.firstName): \(titles)\(moreCount)")
                }
            }
        }
        lines.append("")
    }

    private func appendCompletedWorkSection(
        _ lines: inout [String], weekStart: Date, studentsDict: [UUID: CDStudent]
    ) {
        let recentCompleted = fetchRecentCompletedWork(since: weekStart)
        guard !recentCompleted.isEmpty else { return }
        lines.append("--- Recently Completed Work ---")
        for work in recentCompleted.prefix(8) {
            let studentName = studentsDict[uuidString: work.studentID]?.firstName ?? "Unknown"
            let outcome = work.completionOutcomeRaw.flatMap { CompletionOutcome(rawValue: $0)?.displayName } ?? ""
            let outcomeStr = outcome.isEmpty ? "" : " [\(outcome)]"
            lines.append("  • \(studentName): \(work.title)\(outcomeStr)")
        }
        lines.append("")
    }

    private func appendClassNotesSection(_ lines: inout [String]) {
        let recentClassNotes = fetchRecentClassNotes(limit: 5)
        guard !recentClassNotes.isEmpty else { return }
        lines.append("--- Recent Class Notes ---")
        for note in recentClassNotes {
            let date = formattedDate(note.createdAt)
            let body = String(note.body.prefix(150))
            lines.append("  • \(date): \(body)")
        }
        lines.append("")
    }

    private func appendTodosSection(_ lines: inout [String], studentsDict: [UUID: CDStudent]) {
        let openTodos = fetchOpenTodos()
        guard !openTodos.isEmpty else { return }
        lines.append("--- Teacher Todos ---")
        for todo in openTodos.prefix(10) {
            var line = "  • \(todo.title)"
            if todo.priority != .none { line += " [\(todo.priority.rawValue)]" }
            if let due = todo.dueDate { line += " (due \(formattedDate(due)))" }
            if !todo.studentIDsArray.isEmpty {
                let names = todo.studentUUIDs.compactMap { studentsDict[$0]?.firstName }
                if !names.isEmpty { line += " — \(names.joined(separator: ", "))" }
            }
            lines.append(line)
        }
        lines.append("")
    }

    // MARK: - Tier 2: Question-Specific Context

    /// Builds additional context for students mentioned in the question.
    /// Returns the context string and the set of matched student IDs.
    func buildQuestionContext(
        question: String,
        existingMentionedIDs: Set<UUID>
    ) -> (context: String, mentionedIDs: Set<UUID>) {
        let queryService = DataQueryService(context: context)
        let allStudents = queryService.fetchAllStudents(excludeTest: true)

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

        for student in matched.prefix(3) {
            guard let studentID = student.id else { continue }
            newMentionedIDs.insert(studentID)
            appendStudentDetail(
                &lines, student: student, queryService: queryService,
                lessonsDict: lessonsDict, studentsDict: studentsDict
            )
        }

        return (lines.joined(separator: "\n"), newMentionedIDs)
    }

    // MARK: - Question Context Helpers

    private func appendStudentDetail(
        _ lines: inout [String], student: CDStudent, queryService: DataQueryService,
        lessonsDict: [UUID: CDLesson], studentsDict: [UUID: CDStudent]
    ) {
        lines.append("")
        lines.append("--- \(student.firstName) \(student.lastName) ---")
        let age = ageString(for: student.birthday)
        lines.append("Age: \(age), Birthday: \(formattedDate(student.birthday)), Level: \(student.level.rawValue)")
        if let started = student.dateStarted { lines.append("Started: \(formattedDate(started))") }

        appendStudentPresentations(&lines, student: student, lessonsDict: lessonsDict, studentsDict: studentsDict)
        appendStudentActiveWork(&lines, student: student, queryService: queryService)
        appendStudentCompletedWork(&lines, student: student)
        appendStudentNotes(&lines, student: student)
        appendStudentAttendance(&lines, student: student)
        appendStudentTodos(&lines, student: student)
    }

    private func appendStudentPresentations(
        _ lines: inout [String], student: CDStudent,
        lessonsDict: [UUID: CDLesson], studentsDict: [UUID: CDStudent]
    ) {
        guard let studentID = student.id else { return }
        let studentPresentations = fetchPresentationsForStudent(studentID: studentID, limit: 10)
        guard !studentPresentations.isEmpty else { return }
        lines.append("Recent presentations (last \(studentPresentations.count)):")
        for pres in studentPresentations {
            let fallbackLesson = lessonsDict[pres.lessonIDUUID ?? UUID()]
            let lessonName = pres.lessonTitleSnapshot ?? fallbackLesson?.name ?? "Unknown"
            let subject = lessonsDict[pres.lessonIDUUID ?? UUID()]?.subject ?? ""
            let subjectStr = subject.isEmpty ? "" : " (\(subject))"
            let date = formattedDate(pres.presentedAt ?? pres.createdAt)
            var line = "  • \(lessonName)\(subjectStr) — \(date)"
            if pres.needsPractice { line += " [needs practice]" }
            if pres.needsAnotherPresentation { line += " [needs re-presentation]" }
            if !pres.followUpWork.isEmpty { line += " → follow-up: \(pres.followUpWork.prefix(80))" }
            lines.append(line)
            if !pres.notes.isEmpty { lines.append("    Notes: \(pres.notes.prefix(120))") }
            let presNotes = (pres.unifiedNotes?.allObjects as? [CDNote]) ?? []
            for note in presNotes.prefix(2) where !note.body.isEmpty {
                lines.append("    Observation: \(note.body.prefix(120))")
            }
            let otherStudents = pres.studentUUIDs.filter { $0 != studentID }
                .compactMap { studentsDict[$0]?.firstName }
            if !otherStudents.isEmpty { lines.append("    Also with: \(otherStudents.joined(separator: ", "))") }
        }
    }

    private func appendStudentActiveWork(
        _ lines: inout [String], student: CDStudent, queryService: DataQueryService
    ) {
        guard let studentID = student.id else { return }
        let studentIDString = studentID.uuidString
        let studentWork = queryService.fetchOpenWorkModels().filter { $0.studentID == studentIDString }
        guard !studentWork.isEmpty else { return }
        lines.append("Active work (\(studentWork.count)):")
        for work in studentWork.prefix(8) {
            let status = WorkStatus(rawValue: work.statusRaw)?.displayName ?? work.statusRaw
            let kind = work.kindRaw.flatMap { WorkKind(rawValue: $0)?.displayName } ?? ""
            let kindStr = kind.isEmpty ? "" : " (\(kind))"
            var line = "  • \(work.title) [\(status)]\(kindStr)"
            if let assigned = work.assignedAt as Date? { line += " assigned \(formattedDate(assigned))" }
            if let due = work.dueAt { line += " due \(formattedDate(due))" }
            lines.append(line)
            let workNotes = (work.unifiedNotes?.allObjects as? [CDNote]) ?? []
            for note in workNotes.prefix(2) where !note.body.isEmpty {
                lines.append("    Note: \(note.body.prefix(100))")
            }
        }
    }

    private func appendStudentCompletedWork(_ lines: inout [String], student: CDStudent) {
        guard let studentID = student.id else { return }
        let monthStart = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let completedWork = fetchCompletedWorkForStudent(studentID: studentID.uuidString, since: monthStart)
        guard !completedWork.isEmpty else { return }
        lines.append("Completed work (last 30 days):")
        for work in completedWork.prefix(5) {
            let outcome = work.completionOutcomeRaw
                .flatMap { CompletionOutcome(rawValue: $0)?.displayName } ?? ""
            let outcomeStr = outcome.isEmpty ? "" : " [\(outcome)]"
            let date = work.completedAt.map { formattedDate($0) } ?? ""
            lines.append("  • \(work.title)\(outcomeStr) — \(date)")
        }
    }

    private func appendStudentNotes(_ lines: inout [String], student: CDStudent) {
        guard let studentID = student.id else { return }
        let recentNotes = fetchRecentNotes(for: studentID, limit: 5)
        guard !recentNotes.isEmpty else { return }
        lines.append("Recent notes:")
        for note in recentNotes {
            let date = formattedDate(note.createdAt)
            let body = String(note.body.prefix(150))
            let ctx = note.attachedTo
            let ctxStr = ctx == "general" ? "" : " [\(ctx)]"
            lines.append("  • \(date)\(ctxStr): \(body)")
        }
    }

    private func appendStudentAttendance(_ lines: inout [String], student: CDStudent) {
        guard let studentID = student.id else { return }
        let monthStart = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let attendance = fetchAttendanceRecords(from: monthStart, to: Date())
            .filter { $0.studentID == studentID.uuidString }
        let presentCount = attendance.filter { $0.status == .present }.count
        let absentCount = attendance.filter { $0.status == .absent }.count
        let tardyCount = attendance.filter { $0.status == .tardy }.count
        let totalRecords = attendance.filter { $0.status != .unmarked }.count
        if totalRecords > 0 {
            lines.append(
                "Attendance (30 days): \(presentCount) present, " +
                "\(absentCount) absent, \(tardyCount) tardy " +
                "out of \(totalRecords) days"
            )
        }
    }

    private func appendStudentTodos(_ lines: inout [String], student: CDStudent) {
        guard let studentID = student.id else { return }
        let studentTodos = fetchTodosForStudent(studentID: studentID)
        guard !studentTodos.isEmpty else { return }
        lines.append("Todos for \(student.firstName):")
        for todo in studentTodos.prefix(5) {
            let status = todo.isCompleted ? "[done]" : "[open]"
            var line = "  • \(todo.title) \(status)"
            if let due = todo.dueDate { line += " due \(formattedDate(due))" }
            lines.append(line)
        }
    }

    // MARK: - Name Matching

    /// Fuzzy-matches student names in the question text.
    /// Supports: first name, nickname, "FirstName LastInitial" (e.g., "Etty D").
    private func matchStudents(in question: String, from students: [CDStudent]) -> [CDStudent] {
        let lowered = question.lowercased()
        var matched: [CDStudent] = []
        var matchedIDs: Set<UUID> = []

        for student in students {
            guard let studentID = student.id, !matchedIDs.contains(studentID) else { continue }

            // Check "firstName lastInitial" pattern (e.g., "Etty D")
            let firstLast = "\(student.firstName.lowercased()) \(student.lastName.prefix(1).lowercased())"
            if lowered.contains(firstLast) {
                matched.append(student)
                matchedIDs.insert(studentID)
                continue
            }

            // Check full first name as whole word
            let firstName = student.firstName.lowercased()
            if matchesWholeWord(firstName, in: lowered) {
                matched.append(student)
                matchedIDs.insert(studentID)
                continue
            }

            // Check nickname
            if let nickname = student.nickname?.lowercased(), !nickname.isEmpty,
               matchesWholeWord(nickname, in: lowered) {
                matched.append(student)
                matchedIDs.insert(studentID)
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

    private func fetchPresentations(
        from startDate: Date, to endDate: Date,
        state: LessonAssignmentState
    ) -> [CDLessonAssignment] {
        let stateRaw = state.rawValue
        if state == .presented {
            let request = CDFetchRequest(CDLessonAssignment.self)
            request.predicate = NSPredicate(format: "stateRaw == %@ AND presentedAt != nil", stateRaw)
            request.sortDescriptors = [NSSortDescriptor(key: "presentedAt", ascending: false)]
            return context.safeFetch(request).filter { pres in
                guard let presentedAt = pres.presentedAt else { return false }
                return presentedAt >= startDate && presentedAt <= endDate
            }
        } else {
            let request = CDFetchRequest(CDLessonAssignment.self)
            request.predicate = NSPredicate(format: "stateRaw == %@", stateRaw)
            request.sortDescriptors = [NSSortDescriptor(key: "scheduledForDay", ascending: true)]
            return context.safeFetch(request).filter { pres in
                guard let day = pres.scheduledForDay else { return false }
                return day >= startDate && day <= endDate
            }
        }
    }

    private func fetchPresentationsForStudent(studentID: UUID, limit: Int) -> [CDLessonAssignment] {
        let presentedRaw = LessonAssignmentState.presented.rawValue
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "stateRaw == %@", presentedRaw)
        request.sortDescriptors = [NSSortDescriptor(key: "presentedAt", ascending: false)]
        let allPresented = context.safeFetch(request)
        let studentIDString = studentID.uuidString
        return Array(allPresented.filter { $0.studentIDs.contains(studentIDString) }.prefix(limit))
    }

    private func fetchAttendanceRecords(from startDate: Date, to endDate: Date) -> [CDAttendanceRecord] {
        let request = CDFetchRequest(CDAttendanceRecord.self)
        request.predicate = NSPredicate(format: "date >= %@ AND date <= %@", startDate as NSDate, endDate as NSDate)
        return context.safeFetch(request)
    }

    private func fetchRecentNotes(for studentID: UUID, limit: Int) -> [CDNote] {
        let request = CDFetchRequest(CDNote.self)
        request.predicate = NSPredicate(format: "searchIndexStudentID == %@", studentID as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        request.fetchLimit = limit
        return context.safeFetch(request)
    }

    private func fetchRecentClassNotes(limit: Int) -> [CDNote] {
        let request = CDFetchRequest(CDNote.self)
        request.predicate = NSPredicate(format: "scopeIsAll == YES")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        request.fetchLimit = limit
        return context.safeFetch(request)
    }

    private func fetchRecentCompletedWork(since date: Date) -> [CDWorkModel] {
        let completeRaw = WorkStatus.complete.rawValue
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(format: "statusRaw == %@", completeRaw)
        request.sortDescriptors = [NSSortDescriptor(key: "completedAt", ascending: false)]
        return context.safeFetch(request).filter { work in
            guard let completedAt = work.completedAt else { return false }
            return completedAt >= date
        }
    }

    private func fetchCompletedWorkForStudent(studentID: String, since date: Date) -> [CDWorkModel] {
        let completeRaw = WorkStatus.complete.rawValue
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(format: "statusRaw == %@ AND studentID == %@", completeRaw, studentID)
        request.sortDescriptors = [NSSortDescriptor(key: "completedAt", ascending: false)]
        return context.safeFetch(request).filter { work in
            guard let completedAt = work.completedAt else { return false }
            return completedAt >= date
        }
    }

    private func fetchOpenTodos() -> [CDTodoItemEntity] {
        let request = CDFetchRequest(CDTodoItemEntity.self)
        request.predicate = NSPredicate(format: "isCompleted == NO")
        request.sortDescriptors = [NSSortDescriptor(key: "orderIndex", ascending: true)]
        return context.safeFetch(request)
    }

    private func fetchTodosForStudent(studentID: UUID) -> [CDTodoItemEntity] {
        // TodoItem stores studentIDs as Transformable [String], so we fetch all open and filter
        let studentIDString = studentID.uuidString
        let request = CDFetchRequest(CDTodoItemEntity.self)
        request.predicate = NSPredicate(format: "isCompleted == NO")
        return context.safeFetch(request).filter { $0.studentIDsArray.contains(studentIDString) }
    }

    // MARK: - Formatting

    private func formattedDate(_ date: Date?) -> String {
        guard let date else { return "Unknown" }
        return DateFormatters.mediumDate.string(from: date)
    }

    private func formattedDate(_ date: Date) -> String {
        DateFormatters.mediumDate.string(from: date)
    }

    private func ageString(for birthday: Date?) -> String {
        guard let birthday else { return "Unknown" }
        let components = Calendar.current.dateComponents([.year, .month], from: birthday, to: Date())
        let years = components.year ?? 0
        let months = components.month ?? 0
        if years > 0 {
            return "\(years)y \(months)m"
        }
        return "\(months)m"
    }
}
