import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// The chat's context used to read every lesson for any message naming a child,
// the whole class's presented lessons and open work once per named child, and
// everyone's last 30 days of attendance; classroom_snapshot read every lesson
// row to list the area names. The text handed to the model must not change by
// a byte.

// swiftlint:disable file_length line_length function_parameter_count
/// `ChatContextAssembler` as it stood before its reads were scoped, kept
/// verbatim (renamed) as the reference the new one must match.
/// Uses a two-tier strategy:
/// - Tier 1: Classroom snapshot (student roster, areas, weekly summary, todos) — built once per session
/// - Tier 2: Selective student detail — loaded per-question when student names are detected
private final class LegacyChatContextAssembler { // swiftlint:disable:this type_body_length
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    // MARK: - Tier 1: Classroom Snapshot

    /// Builds a deliberately minimal classroom snapshot. Sensitive details are
    /// fetched only when the guide's question names a child or a local notebook
    /// tool requests a specific record.
    func buildClassroomSnapshot() -> String {
        let queryService = DataQueryService(context: context)
        let students = queryService.fetchAllStudents(excludeTest: true)
        let lessons = queryService.fetchAllLessons()

        var lines: [String] = []
        lines.append("=== CLASSROOM SNAPSHOT ===")
        lines.append("Date: \(formattedDate(Date()))")
        lines.append("Enrolled student count: \(students.count)")
        lines.append("")

        appendAreasSection(&lines, lessons: lessons)
        lines.append("Use notebook lookup tools for dates, observations, presentations, work, attendance, and student-specific facts.")

        return lines.joined(separator: "\n")
    }

    // MARK: - Classroom Snapshot Helpers

    private func appendAreasSection(_ lines: inout [String], lessons: [CDLesson]) {
        let areas = Set(lessons.map(\.area)).filter { !$0.isEmpty }.sorted()
        if !areas.isEmpty {
            lines.append("--- Areas ---")
            lines.append(areas.joined(separator: ", "))
            lines.append("")
        }
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
                lessonsDict: lessonsDict, studentsDict: studentsDict,
                question: question
            )
        }

        return (lines.joined(separator: "\n"), newMentionedIDs)
    }

    // MARK: - Question Context Helpers

    private func appendStudentDetail(
        _ lines: inout [String], student: CDStudent, queryService: DataQueryService,
        lessonsDict: [UUID: CDLesson], studentsDict: [UUID: CDStudent],
        question: String
    ) {
        lines.append("")
        lines.append("--- \(student.fullName) ---")
        let lower = question.lowercased()
        let asksAge = lower.contains("age") || lower.contains("birthday") || lower.contains("old")
        let asksPresentation = lower.contains("lesson") || lower.contains("present") || lower.contains("given")
        let asksWork = lower.contains("work") || lower.contains("practice") || lower.contains("assignment")
        let asksNotes = lower.contains("note") || lower.contains("observ") || lower.contains("noticed")
        let asksAttendance = lower.contains("attend") || lower.contains("absent") || lower.contains("tardy")
        let asksTodos = lower.contains("todo") || lower.contains("remind") || lower.contains("task")

        if asksAge {
            let age = ageString(for: student.birthday)
            lines.append("Age: \(age), Birthday: \(formattedDate(student.birthday))")
        }
        if asksPresentation {
            appendStudentPresentations(&lines, student: student, lessonsDict: lessonsDict, studentsDict: studentsDict)
        }
        if asksWork {
            appendStudentActiveWork(&lines, student: student, queryService: queryService)
            appendStudentCompletedWork(&lines, student: student)
        }
        if asksNotes {
            appendStudentNotes(&lines, student: student)
        }
        if asksAttendance {
            appendStudentAttendance(&lines, student: student)
        }
        if asksTodos {
            appendStudentTodos(&lines, student: student)
        }
        if !asksAge && !asksPresentation && !asksWork && !asksNotes && !asksAttendance && !asksTodos {
            lines.append("No specific record type was requested. Ask for observations, presentations, work, attendance, or age to retrieve only that information.")
        }
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
            let area = lessonsDict[pres.lessonIDUUID ?? UUID()]?.area ?? ""
            let areaStr = area.isEmpty ? "" : " (\(area))"
            let date = formattedDate(pres.presentedAt ?? pres.createdAt)
            var line = "  • \(lessonName)\(areaStr) — \(date)"
            if pres.needsPractice { line += " [needs practice]" }
            if pres.needsAnotherPresentation { line += " [needs re-presentation]" }
            if !pres.followUpWork.isEmpty { line += " → follow-up: \(pres.followUpWork.prefix(80))" }
            lines.append(line)
            if !pres.notes.isEmpty { lines.append("    Notes: \(pres.notes.prefix(120))") }
            let presNotes = (pres.unifiedNotes?.allObjects as? [CDNote]) ?? []
            for note in presNotes.prefix(2) where !note.body.isEmpty {
                lines.append("    Observation: \(note.body.prefix(120))")
            }
            let otherStudents = pres.resolvedStudentIDs.filter { $0 != studentID }
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
        let monthStart = AppCalendar.shared.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let completedWork = fetchCompletedWorkForStudent(studentID: studentID.uuidString, since: monthStart)
        guard !completedWork.isEmpty else { return }
        lines.append("Completed work (last 30 days):")
        for work in completedWork.prefix(5) {
            let outcomeStr = " [\(work.status.displayName)]"
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
        let monthStart = AppCalendar.shared.date(byAdding: .day, value: -30, to: Date()) ?? Date()
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

    private func fetchCompletedWorkForStudent(studentID: String, since date: Date) -> [CDWorkModel] {
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(
            format: "statusRaw IN %@ AND studentID == %@", WorkStatus.closedRawValues, studentID
        )
        request.sortDescriptors = [NSSortDescriptor(key: "completedAt", ascending: false)]
        return context.safeFetch(request).filter { work in
            guard let completedAt = work.completedAt else { return false }
            return completedAt >= date
        }
    }

    private func fetchTodosForStudent(studentID: UUID) -> [CDTodoItem] {
        // CDTodoItem stores studentIDs as Transformable [String], so we fetch all open and filter
        let studentIDString = studentID.uuidString
        let request = CDFetchRequest(CDTodoItem.self)
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
        let components = AppCalendar.shared.dateComponents([.year, .month], from: birthday, to: Date())
        let years = components.year ?? 0
        let months = components.month ?? 0
        if years > 0 {
            return "\(years)y \(months)m"
        }
        return "\(months)m"
    }
}

// swiftlint:enable line_length function_parameter_count

@Suite("Chat context assembler scoped reads")
@MainActor
struct ChatContextAssemblerScopedReadsTests {

    private struct Classroom {
        let ora: CDStudent
        let dalia: CDStudent
        let etty: CDStudent
    }

    private func daysAgo(_ days: Int, hour: Int = 10) -> Date {
        let calendar = AppCalendar.shared
        let day = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: Date())) ?? Date()
        return calendar.date(byAdding: .hour, value: hour, to: day) ?? day
    }

    /// Four children; lessons across areas (one area empty, one repeated);
    /// presentations, open and closed work, notes, attendance and a todo.
    private func seedClassroom(in context: NSManagedObjectContext) throws -> Classroom {
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        ora.birthday = daysAgo(3_000)
        let dalia = CoreDataTestHelpers.seedStudent(in: context, firstName: "Dalia", lastName: "Roth")
        let etty = CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Klein")
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stern")

        let areas = ["Math", "Language", "Geometry", "", "Math", "Biology", "History"]
        let lessons = areas.enumerated().map { index, area in
            CoreDataTestHelpers.seedLesson(in: context, name: "Lesson \(index)", area: area, sequence: "Seq")
        }
        try seedPresentations(lessons: lessons, ora: ora, dalia: dalia, maya: maya, in: context)
        try seedWork(lessons: lessons, ora: ora, dalia: dalia, in: context)
        try seedDays(ora: ora, dalia: dalia, etty: etty, maya: maya, in: context)

        #expect(CoreDataTestHelpers.save(context))
        return Classroom(ora: ora, dalia: dalia, etty: etty)
    }

    /// Twelve presentations for Ora: some without a title snapshot, so the
    /// lesson dictionary names them; a tie on the day; group ones with Dalia;
    /// flags, notes, follow-up work and an observation. One for Maya alone.
    private func seedPresentations(
        lessons: [CDLesson], ora: CDStudent, dalia: CDStudent, maya: CDStudent, in context: NSManagedObjectContext
    ) throws {
        for index in 0..<12 {
            let lesson = lessons[index % lessons.count]
            let students = index.isMultiple(of: 3) ? [ora, dalia] : [ora]
            let presentation: CDLessonAssignment
            if index.isMultiple(of: 2) {
                presentation = PresentationFactory.makeDraft(lesson: lesson, students: students, context: context)
                presentation.markPresented(at: daysAgo(index == 4 ? 6 : index))
            } else {
                presentation = PresentationFactory.makeDraft(
                    lessonID: try #require(lesson.id), studentIDs: students.compactMap(\.id), context: context
                )
                presentation.markPresented(at: daysAgo(index), snapshotLesson: false)
            }
            presentation.needsPractice = index == 1
            presentation.needsAnotherPresentation = index == 2
            presentation.followUpWork = index == 3 ? "Copy the chart" : ""
            presentation.notes = index == 5 ? "Went well" : ""
            if index == 0 {
                let note = CoreDataTestHelpers.seedNote(in: context, body: "Asked for more")
                note.lessonAssignment = presentation
            }
        }
        let other = PresentationFactory.makeDraft(lesson: lessons[1], students: [maya], context: context)
        other.markPresented(at: daysAgo(2))
    }

    /// Ten open items for Ora, statuses interleaved (past the eight listed),
    /// one with a note, a kind and a due date; one for Dalia; one closed.
    private func seedWork(
        lessons: [CDLesson], ora: CDStudent, dalia: CDStudent, in context: NSManagedObjectContext
    ) throws {
        let oraID = try #require(ora.id)
        let statuses: [WorkStatus] = [
            .review, .active, .active, .review, .active, .review, .active, .active, .review, .active
        ]
        for (index, status) in statuses.enumerated() {
            let lessonID = try #require(lessons[index % lessons.count].id)
            let work = CoreDataTestHelpers.seedWorkModel(
                in: context, title: "Work \(index)", studentID: oraID, lessonID: lessonID
            )
            work.statusRaw = status.rawValue
            work.assignedAt = daysAgo(20 - index)
            work.dueAt = index == 3 ? daysAgo(-5) : nil
            work.kindRaw = index == 2 ? WorkKind.allCases.first?.rawValue : nil
            if index == 1 {
                let note = CoreDataTestHelpers.seedNote(in: context, body: "Needs the beads")
                note.work = work
            }
        }
        let daliaWork = CoreDataTestHelpers.seedWorkModel(
            in: context, title: "Dalia's map", studentID: try #require(dalia.id)
        )
        daliaWork.statusRaw = WorkStatus.review.rawValue
        let closed = CoreDataTestHelpers.seedWorkModel(in: context, title: "Finished chart", studentID: oraID)
        closed.statusRaw = WorkStatus.mastered.rawValue
        closed.completedAt = daysAgo(3)
    }

    private struct Mark {
        let student: CDStudent
        let daysAgo: Int
        let status: AttendanceStatus
    }

    /// Attendance in and out of the 30-day window for four children, a note
    /// about Ora, and a todo naming her.
    private func seedDays(
        ora: CDStudent, dalia: CDStudent, etty: CDStudent, maya: CDStudent, in context: NSManagedObjectContext
    ) throws {
        let marks = [
            Mark(student: ora, daysAgo: 1, status: .present), Mark(student: ora, daysAgo: 2, status: .absent),
            Mark(student: ora, daysAgo: 3, status: .tardy), Mark(student: ora, daysAgo: 4, status: .present),
            Mark(student: ora, daysAgo: 5, status: .unmarked), Mark(student: ora, daysAgo: 40, status: .absent),
            Mark(student: dalia, daysAgo: 1, status: .absent), Mark(student: dalia, daysAgo: 2, status: .present),
            Mark(student: etty, daysAgo: 1, status: .tardy), Mark(student: maya, daysAgo: 3, status: .present)
        ]
        for mark in marks {
            let record = CoreDataTestHelpers.seedAttendance(
                in: context, studentID: try #require(mark.student.id), date: daysAgo(mark.daysAgo)
            )
            record.status = mark.status
        }

        let oraID = try #require(ora.id)
        let note = CoreDataTestHelpers.seedNote(in: context, body: "Concentrated for an hour")
        note.searchIndexStudentID = oraID
        note.createdAt = daysAgo(1)

        let todo = CDTodoItem(context: context)
        todo.title = "Call Ora's family"
        todo.studentIDsArray = [oraID.uuidString]
        todo.dueDate = daysAgo(-2)
    }

    private let questions = [
        "How is Ora doing?",
        "What lessons has Ora been given, what work is she on, her attendance, notes and todos? How old is she?",
        "Compare Ora and Dalia: lessons, work and attendance.",
        "What lessons has Etty had?",
        "Attendance for Ora, Dalia, Etty and Maya",
        "What is on for tomorrow?"
    ]

    private func expectSameContext(in context: NSManagedObjectContext) throws {
        let classroom = try seedClassroom(in: context)
        let current = ChatContextAssembler(context: context)
        let legacy = LegacyChatContextAssembler(context: context)
        let known: Set<UUID> = [try #require(classroom.etty.id)]

        for question in questions {
            let new = current.buildQuestionContext(question: question, existingMentionedIDs: known)
            let old = legacy.buildQuestionContext(question: question, existingMentionedIDs: known)
            #expect(new.context == old.context, "\(question)")
            #expect(new.mentionedIDs == old.mentionedIDs, "\(question)")
        }
        // Not vacuous: the sections the scoped reads feed are in the text.
        let full = current.buildQuestionContext(question: questions[1], existingMentionedIDs: []).context
        #expect(full.contains("Recent presentations (last 10):"))
        #expect(full.contains("Active work (10):"))
        #expect(full.contains("Also with: Dalia"))
        #expect(full.contains("Attendance (30 days): 2 present, 1 absent, 1 tardy out of 4 days"))
        let pair = current.buildQuestionContext(question: questions[2], existingMentionedIDs: []).context
        #expect(pair.contains("--- Dalia Roth ---"))

        #expect(current.buildClassroomSnapshot() == legacy.buildClassroomSnapshot())
        #expect(current.buildClassroomSnapshot().contains("Biology, Geometry, History, Language, Math"))
    }

    @Test("Question context and snapshot match the old reads on the in-memory store")
    func sameContextInMemory() throws {
        try expectSameContext(in: try CoreDataTestHelpers.makeContext())
    }

    @Test("Question context and snapshot match the old reads on SQLite")
    func sameContextOnSQLite() throws {
        try expectSameContext(in: try CoreDataTestHelpers.makeSplitStoreContext())
    }

    @Test("The area list follows unsaved lesson edits, as the whole-row read did")
    func areasFollowUnsavedEdits() throws {
        for context in [try CoreDataTestHelpers.makeContext(), try CoreDataTestHelpers.makeSplitStoreContext()] {
            let math = CoreDataTestHelpers.seedLesson(in: context, name: "Checkerboard", area: "Math")
            let history = CoreDataTestHelpers.seedLesson(in: context, name: "Clock of Eras", area: "History")
            #expect(CoreDataTestHelpers.save(context))
            let current = ChatContextAssembler(context: context)
            let legacy = LegacyChatContextAssembler(context: context)
            #expect(current.buildClassroomSnapshot() == legacy.buildClassroomSnapshot())

            CoreDataTestHelpers.seedLesson(in: context, name: "Parts of the Leaf", area: "Botany")
            math.area = "Mathematics"
            context.delete(history)
            let snapshot = current.buildClassroomSnapshot()
            #expect(snapshot == legacy.buildClassroomSnapshot())
            #expect(snapshot.contains("Botany, Mathematics"))
            #expect(!snapshot.contains("History"))
            #expect(DataQueryService(context: context).fetchLessonAreas() == ["Botany", "Mathematics"])
        }
    }
}
