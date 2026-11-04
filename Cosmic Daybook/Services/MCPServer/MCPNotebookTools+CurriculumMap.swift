//
//  MCPNotebookTools+CurriculumMap.swift
//  Cosmic Daybook
//
//  The Three-Year View over MCP: one child across the whole plane, and one
//  lesson (or area) across the whole class. Both read the same
//  ClassGridEngine cells the screens draw, so "presented but never
//  chosen" means one thing in the app and in a conversation.
//
//  These are the tools to call for "what has Ora not had yet", "plan the
//  next month for Dalia", and "who has not had the distributive law" — the
//  last returns a set of names ready to hand to schedule_presentation.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    // MARK: - Class Map

    static func classCurriculumMapTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "class_curriculum_map",
            title: "Class Curriculum Map",
            description: "Every enrolled child's state on one lesson — or their best state in one "
                + "area — grouped by state and ordered by enrollment year, so \"who has not had the "
                + "distributive law\" comes back as names ready for schedule_presentation. Pass a "
                + "lesson name or id, or an area name.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "lesson_or_area": [
                        "type": "string",
                        "description": .string("A lesson name or id (from find_lessons), or a top-level "
                            + "area such as \"Biology\"")
                    ],
                    "state": [
                        "type": "string",
                        "enum": ["notPresented", "presented", "chosen", "repeated", "mastered"],
                        "description": "Only the children in this state"
                    ]
                ],
                "required": ["lesson_or_area"]
            ],
            annotations: .readOnly,
            handler: { arguments in
                try describeClassCurriculumMap(arguments: arguments, in: context())
            }
        )
    }

    private static func describeClassCurriculumMap(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let reference = try requireString(arguments, "lesson_or_area")
        let filter: ChecklistDisplayStatus? = try stateArgument(arguments)
        let input = CurriculumMapLoader.snapshot(in: modelContext)
        let hidden = TestStudentsFilter.normalizedHiddenNames()
        let students = input.students
            .filter { $0.isEnrolled && !hidden.contains($0.fullName.normalizedForComparison()) }
            .sorted(by: enrollmentOrder)
        guard !students.isEmpty else { return "No enrolled students." }

        let (title, lessonIDs) = try resolveMapScope(reference, lessons: input.lessons, in: modelContext)
        // Only the lesson (or area) asked about: the same cells the whole grid
        // holds for it, without finalising every other (child, lesson) pair.
        let all = ClassGridEngine.cells(input: input, lessons: Set(lessonIDs))
        let today = Date()
        let calendar = AppCalendar.shared

        var byState: [ChecklistDisplayStatus: [String]] = [:]
        for student in students {
            let cells = lessonIDs.compactMap { all[student.id]?[$0] }
            let summary = ClassGridEngine.aggregate(cells, lessonCount: lessonIDs.count)
            let year = student.dateStarted.map { started in
                let number = CurriculumTimeline.enrollmentYear(anchor: started, on: today, calendar: calendar)
                return CurriculumTimeline.yearBadge(number)
            } ?? "year unknown"
            var line = "[student id=\(student.id.uuidString)] \(student.fullName) (\(year)"
            if let last = summary.lastPresented { line += ", last presentation \(dayString(last))" }
            if let recall = summary.recall { line += ", recall \(recall.rawValue)" }
            line += ")"
            byState[summary.state, default: []].append(line)
        }

        var lines: [String] = ["\(title) — \(students.count) enrolled child(ren):"]
        for state in MapToolState.all.reversed() where filter == nil || filter == state {
            let names = byState[state] ?? []
            lines.append("")
            lines.append("\(MapToolState.label(state)) (\(names.count)):")
            lines.append(contentsOf: names.isEmpty ? ["  none"] : names.map { "- \($0)" })
        }
        return lines.joined(separator: "\n")
    }

    /// An exact area name first, then a lesson reference. Trying the lesson
    /// first let a partial match win — "Biology" answered for "Introduction to
    /// Biology" — and swallowed an ambiguous name (bug hunt 2026-10-12, #25).
    /// An ambiguous lesson name is passed on; a reference matching nothing
    /// lists the areas.
    private static func resolveMapScope(
        _ reference: String, lessons: [CurriculumLessonRef], in modelContext: NSManagedObjectContext
    ) throws -> (title: String, lessonIDs: [UUID]) {
        let areas = areasInOrder(lessons)
        if UUID(uuidString: reference) == nil, let area = areas.first(where: { sameFiling($0, reference) }) {
            return ("\(area) (best state across the area)", lessons.filter { sameFiling($0.area, area) }.map(\.id))
        }
        let table = allCurriculumLessons(in: modelContext)
        let token = reference.folded()
        guard UUID(uuidString: reference) != nil || table.contains(where: { $0.name.folded().contains(token) }) else {
            throw MCPToolError(
                "\"\(reference)\" is neither a lesson nor an area. Use find_lessons for a lesson; "
                    + "areas are: \(areas.joined(separator: ", "))."
            )
        }
        let lesson = try LessonReferences(in: modelContext, table: table).resolve(reference)
        guard let id = lesson.id else { throw MCPToolError("That lesson record has no identifier.") }
        return (describeLesson(lesson), [id])
    }

    // MARK: - Arguments & Ordering

    static func granularityArgument(_ arguments: [String: JSONValue]) throws -> CurriculumGranularity {
        guard let raw = nonEmpty(arguments["granularity"]?.stringValue) else { return .keyLessons }
        guard let granularity = CurriculumGranularity(rawValue: raw) else {
            throw MCPToolError("granularity must be one of: area, keyLesson, allLessons. Got \"\(raw)\".")
        }
        return granularity
    }

    private static func stateArgument(_ arguments: [String: JSONValue]) throws -> ChecklistDisplayStatus? {
        guard let raw = nonEmpty(arguments["state"]?.stringValue) else { return nil }
        guard let state = MapToolState.state(named: raw) else {
            let allowed = MapToolState.all.map(MapToolState.name).joined(separator: ", ")
            throw MCPToolError("state must be one of: \(allowed). Got \"\(raw)\".")
        }
        return state
    }

    static func areasInOrder(_ lessons: [CurriculumLessonRef]) -> [String] {
        let unique = Set(lessons.map(\.area).filter { !$0.isEmpty })
        let existing = Array(unique).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return FilterOrderStore.loadAreaOrder(existing: existing)
    }

    static func curriculumOrder(_ lhs: CurriculumLessonRef, _ rhs: CurriculumLessonRef) -> Bool {
        if !sameFiling(lhs.sequence, rhs.sequence) {
            return lhs.sequence.localizedCaseInsensitiveCompare(rhs.sequence) == .orderedAscending
        }
        return ClassGridEngine.precedes(lhs, rhs)
    }

    /// Longest-enrolled first, so the cohorts read as bands; name within a cohort.
    private static func enrollmentOrder(_ lhs: CurriculumStudentRef, _ rhs: CurriculumStudentRef) -> Bool {
        switch (lhs.dateStarted, rhs.dateStarted) {
        case let (l?, r?) where l != r: return l < r
        case (nil, .some): return false
        case (.some, nil): return true
        default: return lhs.fullName.localizedCaseInsensitiveCompare(rhs.fullName) == .orderedAscending
        }
    }
}

/// The Claude tools' words for a Three Years mark. The screens now say Not yet,
/// Practicing and Reviewing (the Class Grid's one ladder); the tools keep the
/// old map's names (notPresented, chosen, repeated) for the `state` argument and
/// in what they print, so a conversation reads as it always did.
enum MapToolState {
    /// The five marks Three Years draws, lowest first.
    static let all: [ChecklistDisplayStatus] = [.notReady, .presented, .practicing, .reviewing, .mastered]

    static func name(_ state: ChecklistDisplayStatus) -> String {
        switch state {
        case .notReady, .ready, .planned: "notPresented"
        case .presented: "presented"
        case .practicing: "chosen"
        case .reviewing: "repeated"
        case .mastered: "mastered"
        }
    }

    static func label(_ state: ChecklistDisplayStatus) -> String {
        switch state {
        case .notReady, .ready, .planned: "Not yet presented"
        case .presented: "Presented"
        case .practicing: "Chosen"
        case .reviewing: "Repeated"
        case .mastered: "Mastered"
        }
    }

    static func state(named name: String) -> ChecklistDisplayStatus? {
        all.first { Self.name($0) == name }
    }
}
