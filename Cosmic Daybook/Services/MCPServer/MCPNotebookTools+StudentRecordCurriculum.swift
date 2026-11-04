//
//  MCPNotebookTools+StudentRecordCurriculum.swift
//  Cosmic Daybook
//
//  The Three-Year View and the dated presentations for one child.
//  The section builders behind student_record (MCPNotebookTools+StudentRecord.swift):
//  each is the body of a tool that used to stand alone.
//

import CoreData
import Foundation

extension MCPNotebookTools {
    // MARK: - Curriculum Map

    static func curriculumMapSection(
        _ arguments: [String: JSONValue], for student: CDStudent, in modelContext: NSManagedObjectContext
    ) throws -> String {
        guard let studentID = student.id else { throw MCPToolError("That student record has no identifier.") }
        let granularity = try granularityArgument(arguments)
        let since: Date? = try dayArgument(arguments, "since").map(AppCalendar.startOfDay)

        let input = CurriculumMapLoader.snapshot(in: modelContext)
        let cells = ClassGridEngine.cells(for: studentID, input: input)
        let settings = CurriculumMapSettings()
        let today = Date()
        let calendar = AppCalendar.shared
        let timeline = CurriculumTimeline.make(
            dateStarted: student.dateStarted,
            fallbackAnchor: cells.values.compactMap { $0.events.first?.date }.min(),
            today: today, zoom: .years, calendar: calendar
        )

        var lines: [String] = [studentHeadline(student, timeline: timeline)]
        lines.append(contentsOf: greatLessonLines(input: input, cells: cells))
        let shown = ClassGridEngine.lessons(input.lessons, at: granularity)
        var untouched: [String] = []
        for area in areasInOrder(input.lessons) {
            let areaLessons = input.lessons.filter { sameFiling($0.area, area) }
            let summary = ClassGridEngine.aggregate(
                areaLessons.compactMap { cells[$0.id] }, lessonCount: areaLessons.count
            )
            let days = settings.untouchedDays(for: area)
            let isUntouched = ClassGridEngine.isUntouched(
                lastPresented: summary.lastPresented, days: days, today: today, calendar: calendar
            )
            if isUntouched {
                let last = summary.lastPresented.map { "last presentation \(dayString($0))" } ?? "never presented"
                untouched.append("\(area) (\(last); flagged after \(days) days)")
            }
            lines.append("")
            lines.append(areaHeadline(area, summary: summary))
            guard granularity != .area else { continue }
            lines.append(contentsOf: areaLessonLines(
                shown.filter { sameFiling($0.area, area) }, area: area, areaLessons: areaLessons,
                cells: cells, since: since
            ))
        }
        lines.append("")
        lines.append(untouched.isEmpty
            ? "Untouched areas: none."
            : "Untouched areas (no presentation within the threshold): " + untouched.joined(separator: "; "))
        return lines.joined(separator: "\n")
    }

    /// One line per lesson in curriculum order — sub-areas in the album order
    /// the class map uses (`ClassGridYearsModel.orderedSequences`), not
    /// alphabetically (bug hunt 2026-10-12, #27); `since` keeps only lessons
    /// with activity on or after the day.
    private static func areaLessonLines(
        _ lessons: [CurriculumLessonRef], area: String, areaLessons: [CurriculumLessonRef],
        cells: [UUID: CurriculumCell], since: Date?
    ) -> [String] {
        let sequenceRank: [String: Int] = Dictionary(
            ClassGridYearsModel.orderedSequences(in: area, lessons: areaLessons)
                .enumerated().map { ($0.element.trimmed().lowercased(), $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
        let rank: (CurriculumLessonRef) -> Int = { sequenceRank[$0.sequence.trimmed().lowercased()] ?? Int.max }
        let rows = lessons
            .filter { lesson in
                guard let since else { return true }
                guard let cell = cells[lesson.id], let activity = cell.lastActivity else { return false }
                return activity >= since
            }
            .sorted { lhs, rhs in
                let (left, right) = (rank(lhs), rank(rhs))
                return left != right ? left < right : curriculumOrder(lhs, rhs)
            }
        guard !rows.isEmpty else {
            return [since.map { "  (nothing since \(dayString($0)))" } ?? "  (no key lessons filed)"]
        }
        return rows.map { lessonLine($0, cell: cells[$0.id]) }
    }

    private static func studentHeadline(_ student: CDStudent, timeline: CurriculumTimeline) -> String {
        let started = timeline.anchorIsEstimated
            ? "no start date on file — years counted from the first record"
            : "started \(dayString(timeline.anchor))"
        let id = student.id?.uuidString ?? "unknown"
        let year = CurriculumTimeline.yearBadge(timeline.currentYear)
        return "[student id=\(id)] \(student.fullName) — \(year) (\(started))"
    }

    private static func greatLessonLines(input: CurriculumMapInput, cells: [UUID: CurriculumCell]) -> [String] {
        let byRaw = ClassGridEngine.greatLessonLessons(in: input.lessons)
        var lines: [String] = ["", "Great Lessons:"]
        for great in GreatLesson.allCases {
            let stories = byRaw[great.rawValue] ?? []
            guard !stories.isEmpty else {
                lines.append("- \(great.displayName): no lesson tagged (tag the story in its lesson editor)")
                continue
            }
            let summary = ClassGridEngine.aggregate(stories.compactMap { cells[$0.id] }, lessonCount: stories.count)
            let names = stories.map(\.name).joined(separator: ", ")
            var detail = MapToolState.name(summary.state)
            if let first = summary.firstPresented { detail += " \(dayString(first))" }
            lines.append("- \(great.displayName): \(detail) [\(names)]")
        }
        return lines
    }

    private static func areaHeadline(_ area: String, summary: CurriculumAggregate) -> String {
        var parts: [String] = ["\(summary.presentedCount) of \(summary.lessonCount) presented"]
        if let last = summary.lastPresented { parts.append("last presentation \(dayString(last))") }
        if let activity = summary.lastActivity { parts.append("last activity \(dayString(activity))") }
        return "\(area): " + parts.joined(separator: "; ")
    }

    private static func lessonLine(_ lesson: CurriculumLessonRef, cell: CurriculumCell?) -> String {
        let filing = lesson.sequence.isEmpty ? "" : " (\(lesson.sequence))"
        guard let cell else {
            return "- [lesson id=\(lesson.id.uuidString)] \(lesson.name)\(filing) — notPresented"
        }
        var parts: [String] = [MapToolState.name(cell.state)]
        if cell.isConfirmed, cell.state < .mastered { parts.append("confirmed ready for next") }
        if let first = cell.firstPresented { parts.append("presented \(dayString(first))") }
        if let last = cell.lastPresented, last != cell.firstPresented { parts.append("again \(dayString(last))") }
        if !cell.evidence.workIDs.isEmpty { parts.append("\(cell.evidence.workIDs.count) work") }
        if cell.practiceCount > 0 { parts.append("\(cell.practiceCount) practice") }
        if let recall = cell.recall { parts.append("recall \(recall.rawValue)") }
        if let activity = cell.lastActivity { parts.append("last activity \(dayString(activity))") }
        return "- [lesson id=\(lesson.id.uuidString)] \(lesson.name)\(filing) — " + parts.joined(separator: "; ")
    }

    // MARK: - Presentation History

    static func presentationHistorySection(
        _ arguments: [String: JSONValue], for student: CDStudent, in modelContext: NSManagedObjectContext
    ) throws -> String {
        guard let studentID = student.id else {
            throw MCPToolError("That student record has no identifier.")
        }
        let limit = intArgument(arguments, "limit", default: 10, range: 1...200)
        let since: Date? = try dayArgument(arguments, "since").map(AppCalendar.startOfDay)
        let lesson: CDLesson? = try nonEmpty(arguments["lesson"]?.stringValue)
            .map { try resolveLessonReference($0, in: modelContext) }

        let request = CDFetchRequest(CDLessonAssignment.self)
        var clauses: [NSPredicate] = [
            NSPredicate(format: "stateRaw == %@", LessonAssignmentState.presented.rawValue)
        ]
        if let lessonID = lesson?.id?.uuidString {
            clauses.append(NSPredicate(format: "lessonID == %@", lessonID))
        }
        if let since {
            clauses.append(NSPredicate(format: "presentedAt >= %@", since as NSDate))
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: clauses)
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \CDLessonAssignment.presentedAt, ascending: false)
        ]
        let matching = modelContext.safeFetch(request).filter { $0.resolvedStudentIDs.contains(studentID) }
        let shown = matching.prefix(limit)

        var scope: [String] = []
        if let lesson { scope.append("of \(lesson.name)") }
        if let since { scope.append("since \(dayString(since))") }
        let scopeText = scope.isEmpty ? "" : " " + scope.joined(separator: ", ")
        let record = lesson.map { presentationRecordLine(for: studentID, lesson: $0, in: modelContext) } ?? ""

        guard !shown.isEmpty else {
            return "No presentations\(scopeText) are recorded for \(student.fullName).\(record)"
        }

        let ordinals = repeatOrdinals(Array(shown), for: studentID, in: modelContext)
        let lines = shown.compactMap { assignment -> String? in
            guard let id = assignment.id else { return nil }
            let snapshotTitle = assignment.lessonTitleSnapshot?.trimmed() ?? ""
            let title = snapshotTitle.isEmpty ? (assignment.lesson?.name ?? "Lesson") : snapshotTitle
            // Linked notes are counted for this child only: a note about
            // another child on the same group presentation is not hers.
            let notes = ((assignment.unifiedNotes?.allObjects as? [CDNote]) ?? [])
                .filter { $0.scope.applies(to: studentID) && !$0.body.trimmed().isEmpty }
            let noteText = notes.isEmpty
                ? "no linked observation"
                : "\(notes.count) linked observation(s)\(observationScopeNote(notes, for: studentID, in: modelContext))"
            return "- [presentation id=\(id.uuidString)] \(dayString(assignment.presentedAt)) — "
                + "\(title)\(repeatSuffix(assignment, ordinal: ordinals[id])) (\(noteText))"
        }
        let count = matching.count > shown.count
            ? " (showing \(shown.count) of \(matching.count); raise limit or pass since for the rest)"
            : " (\(shown.count))"
        return "Presentations\(scopeText) for \(student.fullName)\(count):\n"
            + lines.joined(separator: "\n") + record
    }

    // MARK: - Lessons Given More Than Once

    /// Presentation id → which giving of that lesson it was for this child:
    /// one more than the days she had it before that row's day.
    ///
    /// Counted from the whole record (`PresentationRecordIndex`, read for the
    /// shown rows' lessons only), not from the rows fetched: a `since` window
    /// used to number its own rows, so the second giving read as the first
    /// once the first fell outside it.
    private static func repeatOrdinals(
        _ rows: [CDLessonAssignment], for studentID: UUID, in modelContext: NSManagedObjectContext
    ) -> [UUID: Int] {
        let student = studentID.uuidString
        let index = PresentationRecordIndex(
            lessonIDs: Set(rows.map(\.lessonID)), students: [student], in: modelContext
        )
        var ordinals: [UUID: Int] = [:]
        for row in rows {
            guard let id = row.id, let presentedAt = row.presentedAt,
                  let days = index.given(student: student, lesson: row.lessonID)?.days else { continue }
            let day = AppCalendar.startOfDay(presentedAt)
            ordinals[id] = days.filter { AppCalendar.startOfDay($0) < day }.count + 1
        }
        return ordinals
    }

    /// " (2nd time; second pass)" — the ordinal, and the reason if the record
    /// carries one. Empty for a lesson given once, and for the first giving of
    /// one given several times: only a repeat needs saying.
    private static func repeatSuffix(_ assignment: CDLessonAssignment, ordinal: Int?) -> String {
        guard let ordinal, ordinal > 1 else { return "" }
        let purpose = RepeatPurpose.parse(notes: assignment.notes)
            .map { "; \($0.displayName.lowercased())" } ?? ""
        return " (\(ordinalText(ordinal)) time\(purpose))"
    }

    // MARK: - Detail

    /// The child's `CDLessonPresentation` for the lesson, as a closing line —
    /// its state and the dates it carries. Empty when there is no record.
    private static func presentationRecordLine(
        for studentID: UUID, lesson: CDLesson, in modelContext: NSManagedObjectContext
    ) -> String {
        guard let lessonID = lesson.id?.uuidString else { return "" }
        let request = CDFetchRequest(CDLessonPresentation.self)
        request.predicate = NSPredicate(
            format: "studentID == %@ AND lessonID == %@", studentID.uuidString, lessonID
        )
        let records = modelContext.safeFetch(request)
            .sorted { ($0.presentedAt ?? .distantPast) > ($1.presentedAt ?? .distantPast) }
        guard let record = records.first else {
            return "\nNo presentation record of \(lesson.name) for this child either."
        }
        var parts: [String] = [record.state.rawValue]
        if let presented = record.presentedAt { parts.append("presented \(dayString(presented))") }
        if let mastered = record.masteredAt { parts.append("mastered \(dayString(mastered))") }
        return "\nPresentation record of \(lesson.name): " + parts.joined(separator: "; ") + "."
    }

    /// ", shared with Ora Pardo" when a linked note is about several children,
    /// or ", written for the whole class" — so a group note is not mistaken
    /// for one about this child alone.
    private static func observationScopeNote(
        _ notes: [CDNote], for studentID: UUID, in modelContext: NSManagedObjectContext
    ) -> String {
        if notes.contains(where: { $0.scope == .all }) {
            return ", written for the whole class"
        }
        let others = Set(notes.flatMap { $0.scope.studentIDs ?? [] }).subtracting([studentID])
        guard !others.isEmpty else { return "" }
        return ", shared with \(studentNames(for: Array(others), in: modelContext))"
    }
}
