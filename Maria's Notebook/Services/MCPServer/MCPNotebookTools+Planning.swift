//
//  MCPNotebookTools+Planning.swift
//  Maria's Notebook
//
//  The structures a guide plans against: the weekly timetable of one-to-one
//  slots, and the year plan of lessons pencilled in ahead of the calendar.
//
//  A year-plan entry is not a scheduled presentation — it is an intention with
//  a target date that gets promoted into a real assignment later. Both appear
//  here so the difference stays visible; schedule_for_range shows only what has
//  actually been put on the calendar.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    // MARK: - Weekly Schedules

    static func weeklySchedulesTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "weekly_schedules",
            title: "Weekly Schedules",
            description: "The recurring weekly timetables — named schedules and the student "
                + "slots inside them, by weekday and time. These repeat every week and are "
                + "separate from the dated calendar.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "student_name": [
                        "type": "string",
                        "description": "Only slots belonging to this student"
                    ],
                    "weekday": [
                        "type": "string",
                        "enum": [
                            "Sunday", "Monday", "Tuesday", "Wednesday",
                            "Thursday", "Friday", "Saturday"
                        ],
                        "description": "Only slots on this weekday"
                    ]
                ]
            ],
            handler: { arguments in
                try describeWeeklySchedules(arguments: arguments, in: context())
            }
        )
    }

    private static func describeWeeklySchedules(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let student = try nonEmpty(arguments["student_name"]?.stringValue)
            .map { try resolveStudentReference($0, in: modelContext) }
        let studentKey: String? = student?.id?.uuidString
        let weekday: String? = nonEmpty(arguments["weekday"]?.stringValue)

        let schedules: [CDSchedule] = modelContext.safeFetch(CDFetchRequest(CDSchedule.self))
        guard !schedules.isEmpty else { return "No weekly schedules are set up." }

        let names = studentNameIndex(in: modelContext)
        var sections: [String] = []
        for schedule in schedules.sorted(by: { $0.name < $1.name }) {
            let slots: [CDScheduleSlot] = keptSlots(
                of: schedule, studentKey: studentKey, weekday: weekday
            )
            guard !slots.isEmpty else { continue }
            let id: String = schedule.id?.uuidString ?? "unknown"
            var lines: [String] = ["[schedule id=\(id)] \(schedule.name)"]
            lines.append(contentsOf: slots.map { slot in
                let who: String = names[slot.studentID] ?? "unassigned"
                let time: String = nonEmpty(slot.timeString).map { " \($0)" } ?? ""
                let note: String = nonEmpty(slot.notes).map { " — \($0)" } ?? ""
                return "  - \(slot.weekdayRaw)\(time): \(who)\(note)"
            })
            sections.append(lines.joined(separator: "\n"))
        }

        guard !sections.isEmpty else {
            let who = student.map { " for \($0.fullName)" } ?? ""
            return "No schedule slots\(who) match that."
        }
        return sections.joined(separator: "\n\n")
    }

    private static func keptSlots(
        of schedule: CDSchedule, studentKey: String?, weekday: String?
    ) -> [CDScheduleSlot] {
        let all: [CDScheduleSlot] = (schedule.slots?.allObjects as? [CDScheduleSlot]) ?? []
        var kept: [CDScheduleSlot] = []
        for slot in all {
            if let studentKey, slot.studentID != studentKey { continue }
            if let weekday, slot.weekdayRaw != weekday { continue }
            kept.append(slot)
        }
        return kept.sorted { lhs, rhs in
            let leftDay: Int = weekdayOrder(lhs.weekdayRaw)
            let rightDay: Int = weekdayOrder(rhs.weekdayRaw)
            if leftDay != rightDay { return leftDay < rightDay }
            return lhs.sortOrder < rhs.sortOrder
        }
    }

    /// Sorts slots Sunday-first, matching `Weekday`'s own order rather than
    /// alphabetically (which would put Friday before Monday).
    private static func weekdayOrder(_ raw: String) -> Int {
        Weekday.allCases.firstIndex { $0.rawValue == raw } ?? Weekday.allCases.count
    }

    // MARK: - Year Plan

    static func yearPlanTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "year_plan",
            title: "Year Plan",
            description: "Lessons pencilled in for a student across the year, with their target "
                + "dates and whether each is still planned, has been promoted onto the calendar, "
                + "or was skipped. An entry here is an intention, not a scheduled presentation.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "student_name": [
                        "type": "string",
                        "description": "The student's first name, full name, or nickname"
                    ],
                    "status": [
                        "type": "string",
                        "enum": ["planned", "promoted", "skipped"],
                        "description": "Only entries in this state (default: planned)"
                    ]
                ],
                "required": ["student_name"]
            ],
            handler: { arguments in
                try describeYearPlan(arguments: arguments, in: context())
            }
        )
    }

    private static func describeYearPlan(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let student = try resolveStudentReference(
            requireString(arguments, "student_name"), in: modelContext
        )
        guard let studentID = student.id else {
            throw MCPToolError("That student record has no identifier.")
        }
        let statusRaw: String = nonEmpty(arguments["status"]?.stringValue) ?? "planned"
        guard let status = YearPlanEntryStatus(rawValue: statusRaw) else {
            let allowed = "planned, promoted, skipped"
            throw MCPToolError("status must be one of: \(allowed). Got \"\(statusRaw)\".")
        }

        let request = CDFetchRequest(CDYearPlanEntry.self)
        request.predicate = NSPredicate(format: "studentID == %@", studentID.uuidString)
        let entries: [CDYearPlanEntry] = modelContext.safeFetch(request)
            .filter { $0.status == status }
            .sorted { ($0.plannedDate ?? .distantFuture) < ($1.plannedDate ?? .distantFuture) }
        guard !entries.isEmpty else {
            return "\(student.fullName) has no \(status.rawValue) year-plan entries."
        }

        let lessons = lessonNameIndex(in: modelContext)
        // The header already says which status these are, so the lines don't repeat it.
        let lines = entries.map { "- " + yearPlanEntryLine($0, lessons: lessons) }
        return "\(student.fullName), \(status.rawValue) (\(entries.count)):\n"
            + lines.joined(separator: "\n")
    }

    /// One year-plan entry as a line, without a list marker. Shared so
    /// `year_plan` and `update_year_plan_entry` describe an entry the same way.
    static func yearPlanEntryLine(
        _ entry: CDYearPlanEntry, lessons: [UUID: String], includeStatus: Bool = false
    ) -> String {
        let id: String = entry.id?.uuidString ?? "unknown"
        let lesson: String = entry.lessonUUID.flatMap { lessons[$0] } ?? "a lesson"
        var details: [String] = []
        if includeStatus {
            details.append(entry.status.rawValue)
        }
        if let planned = entry.plannedDate {
            details.append("target \(dayString(planned))")
        }
        if entry.isBehindPace {
            details.append("behind pace")
        }
        if let group = nonEmpty(entry.sequenceGroupKey) {
            details.append(group)
        }
        let suffix: String = details.isEmpty ? "" : " (\(details.joined(separator: "; ")))"
        return "[yearPlanEntry id=\(id)] \(lesson)\(suffix)"
    }

    static func lessonNameIndex(in modelContext: NSManagedObjectContext) -> [UUID: String] {
        let lessons: [CDLesson] = modelContext.safeFetch(CDFetchRequest(CDLesson.self))
        return Dictionary(
            lessons.compactMap { lesson in lesson.id.map { ($0, lesson.name) } },
            uniquingKeysWith: { first, _ in first }
        )
    }

    // MARK: - Templates

    static func listTemplatesTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "list_templates",
            title: "List Templates",
            description: "The reusable scaffolding the teacher has set up: meeting prompts, note "
                + "templates, todo templates, and sample work with its steps. Naming a kind "
                + "returns just that kind.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "kind": [
                        "type": "string",
                        "enum": ["meeting", "note", "todo", "sample_work"],
                        "description": "Which templates to list (default: all kinds)"
                    ]
                ]
            ],
            handler: { arguments in
                describeTemplates(kind: nonEmpty(arguments["kind"]?.stringValue), in: context())
            }
        )
    }

    private static func describeTemplates(
        kind: String?, in modelContext: NSManagedObjectContext
    ) -> String {
        var sections: [String] = []
        if kind == nil || kind == "meeting" {
            sections.append(contentsOf: meetingTemplateSection(in: modelContext))
        }
        if kind == nil || kind == "note" {
            sections.append(contentsOf: noteTemplateSection(in: modelContext))
        }
        if kind == nil || kind == "todo" {
            sections.append(contentsOf: todoTemplateSection(in: modelContext))
        }
        if kind == nil || kind == "sample_work" {
            sections.append(contentsOf: sampleWorkSection(in: modelContext))
        }
        guard !sections.isEmpty else { return "No templates are set up." }
        return sections.joined(separator: "\n\n")
    }

    private static func meetingTemplateSection(
        in modelContext: NSManagedObjectContext
    ) -> [String] {
        let templates: [CDMeetingTemplateEntity] = modelContext
            .safeFetch(CDFetchRequest(CDMeetingTemplateEntity.self))
            .filter(\.isActive)
            .sorted { $0.sortOrder < $1.sortOrder }
        guard !templates.isEmpty else { return [] }
        let lines = templates.map { template -> String in
            let id: String = template.id?.uuidString ?? "unknown"
            let builtIn: String = template.isBuiltIn ? " (built in)" : ""
            return "- [meetingTemplate id=\(id)] \(template.name)\(builtIn)"
        }
        return ["Meeting templates:\n" + lines.joined(separator: "\n")]
    }

    private static func noteTemplateSection(in modelContext: NSManagedObjectContext) -> [String] {
        let templates: [CDNoteTemplateEntity] = modelContext
            .safeFetch(CDFetchRequest(CDNoteTemplateEntity.self))
            .sorted { $0.sortOrder < $1.sortOrder }
        guard !templates.isEmpty else { return [] }
        let lines = templates.map { template -> String in
            let id: String = template.id?.uuidString ?? "unknown"
            let body: String = nonEmpty(template.body).map { "\n    \($0)" } ?? ""
            return "- [noteTemplate id=\(id)] \(template.title)\(body)"
        }
        return ["Note templates:\n" + lines.joined(separator: "\n")]
    }

    private static func todoTemplateSection(in modelContext: NSManagedObjectContext) -> [String] {
        let templates: [CDTodoTemplateEntity] = modelContext
            .safeFetch(CDFetchRequest(CDTodoTemplateEntity.self))
            .sorted { $0.useCount > $1.useCount }
        guard !templates.isEmpty else { return [] }
        let lines = templates.map { template -> String in
            let id: String = template.id?.uuidString ?? "unknown"
            let used: String = template.useCount > 0 ? " (used \(template.useCount)×)" : ""
            return "- [todoTemplate id=\(id)] \(template.name): \(template.title)\(used)"
        }
        return ["Todo templates:\n" + lines.joined(separator: "\n")]
    }

    private static func sampleWorkSection(in modelContext: NSManagedObjectContext) -> [String] {
        let samples: [CDSampleWorkEntity] = modelContext
            .safeFetch(CDFetchRequest(CDSampleWorkEntity.self))
            .sorted { $0.orderIndex < $1.orderIndex }
        guard !samples.isEmpty else { return [] }
        var lines: [String] = []
        for sample in samples {
            let id: String = sample.id?.uuidString ?? "unknown"
            // The relationship is typed NSManagedObject, so the lesson name is
            // read by key rather than through CDLesson.
            let lessonName: String? = (sample.lesson as? CDLesson)?.name
            let lesson: String = lessonName.map { " — \($0)" } ?? ""
            lines.append("- [sampleWork id=\(id)] \(sample.title)\(lesson)")
            let steps: [CDSampleWorkStepEntity] =
                ((sample.steps?.allObjects as? [CDSampleWorkStepEntity]) ?? [])
                .sorted { $0.orderIndex < $1.orderIndex }
            for step in steps {
                lines.append("    • \(step.title)")
            }
        }
        return ["Sample work:\n" + lines.joined(separator: "\n")]
    }
}
