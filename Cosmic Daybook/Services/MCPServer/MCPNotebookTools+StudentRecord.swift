//
//  MCPNotebookTools+StudentRecord.swift
//  Cosmic Daybook
//
//  One tool for everything the notebook holds about a single child. It
//  replaces seven reads that each took the same student_name (student_attendance,
//  student_curriculum_map, student_meetings, student_observations,
//  student_presentation_history, student_tracks, student_work): the caller
//  names the child once and the sections wanted, and each section is the old
//  tool's body, unchanged, in MCPNotebookTools+StudentRecordSections.swift
//  and MCPNotebookTools+StudentRecordCurriculum.swift.
//
//  Calling a section's old name still answers: `MCPNotebookTools.retiredTools`
//  says where it moved.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    /// The parts of a child's record `student_record` can return.
    enum StudentRecordSection: String, CaseIterable, Sendable {
        case attendance
        case curriculumMap = "curriculum_map"
        case meetings
        case observations
        case presentationHistory = "presentation_history"
        case tracks
        case work

        /// The heading a multi-section reply prints above the section.
        var heading: String { rawValue }

        static var allNames: String { allCases.map(\.rawValue).joined(separator: ", ") }
    }

    static func studentRecordTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "student_record",
            title: "Student Record",
            description: "Everything the notebook holds about one child, by section — name the child "
                + "once and ask for the sections you need. attendance: a tally over the last N days, "
                + "then every day she was not simply present. curriculum_map: the whole elementary "
                + "cycle, area by area, with each lesson's state (not presented, presented, chosen, "
                + "repeated, mastered), dates and recall, and areas untouched for the guide's "
                + "threshold; records, never readiness. meetings: her meeting history, newest first "
                + "(read it before create_meeting_entry). observations: her notes, newest first, with "
                + "dates, tags and full text. presentation_history: dated presentations, newest first; "
                + "pass lesson to ask \"has she ever had X\". tracks: where she stands on the lesson "
                + "sequences she has started. work: the work she is carrying and what she recently "
                + "finished; use it rather than inferring work from her presentations. With more than "
                + "one section each is headed by its name.",
            inputSchema: studentRecordSchema,
            annotations: .readOnly,
            handler: { arguments in
                let modelContext = context()
                let requested = try studentRecordSections(arguments)
                let student = try resolveStudentReference(
                    requireString(arguments, "student_name"), in: modelContext
                )
                var parts: [String] = []
                for section in requested {
                    let body = try studentRecordSection(section, arguments: arguments, for: student, in: modelContext)
                    parts.append(requested.count == 1 ? body : "## \(section.heading)\n\(body)")
                }
                return parts.joined(separator: "\n\n")
            }
        )
    }

    private static var studentRecordSchema: JSONValue {
        var properties: [String: JSONValue] = [
            "student_name": [
                "type": "string",
                "description": "The student's first name, full name, nickname, or id"
            ],
            "sections": [
                "type": "array",
                "items": ["type": "string", "enum": .array(StudentRecordSection.allCases.map { .string($0.rawValue) })],
                "description": "Which parts of the record to return, in the order wanted"
            ],
            "days_back": [
                "type": "integer",
                "description": .string("attendance: 1-365 (default 30). observations: 1-120 (default 30), "
                    + "ignored when since is given.")
            ],
            "limit": [
                "type": "integer",
                "description": .string("Most rows to return. observations 1-200 (default 40); meetings 1-100 "
                    + "(default 5); presentation_history 1-200 (default 10); work: finished items, 1-30 (default 10).")
            ],
            "granularity": [
                "type": "string",
                "enum": ["area", "keyLesson", "allLessons"],
                "description": .string("curriculum_map. area: one line per area with counts. keyLesson (default): "
                    + "the milestones — hand-marked key lessons, the first lesson of every sub-area, and the "
                    + "Great Lesson stories. allLessons: every lesson.")
            ],
            "lesson": [
                "type": "string",
                "description": "presentation_history: only this lesson (an id from find_lessons, or its name)"
            ],
            "include_completed": [
                "type": "boolean",
                "description": "work: also list recently completed work (default true)"
            ],
            "include_inactive": [
                "type": "boolean",
                "description": "tracks: also include sequences she has finished (default false)"
            ]
        ]
        let window = dayWindowSchema("in the record (observations, meetings, presentation_history, curriculum_map)")
        properties.merge(window) { current, _ in current }
        return [
            "type": "object",
            "properties": .object(properties),
            "required": ["student_name", "sections"]
        ]
    }

    /// The sections asked for, in order, each once. A bare string is taken as
    /// a list of one.
    private static func studentRecordSections(_ arguments: [String: JSONValue]) throws -> [StudentRecordSection] {
        var names = stringArrayArgument(arguments, "sections")
        if names.isEmpty, let single = arguments["sections"]?.stringValue?.trimmed(), !single.isEmpty {
            names = [single]
        }
        guard !names.isEmpty else {
            throw MCPToolError("Pass sections: one or more of \(StudentRecordSection.allNames).")
        }
        var seen: Set<StudentRecordSection> = []
        return try names.compactMap { name in
            guard let section = StudentRecordSection(rawValue: name.lowercased()) else {
                throw MCPToolError("Unknown section \"\(name)\". Use one or more of \(StudentRecordSection.allNames).")
            }
            return seen.insert(section).inserted ? section : nil
        }
    }

    private static func studentRecordSection(
        _ section: StudentRecordSection, arguments: [String: JSONValue],
        for student: CDStudent, in modelContext: NSManagedObjectContext
    ) throws -> String {
        switch section {
        case .attendance: return try attendanceSection(arguments, for: student, in: modelContext)
        case .curriculumMap: return try curriculumMapSection(arguments, for: student, in: modelContext)
        case .meetings: return try meetingsSection(arguments, for: student, in: modelContext)
        case .observations: return try observationsSection(arguments, for: student, in: modelContext)
        case .presentationHistory: return try presentationHistorySection(arguments, for: student, in: modelContext)
        case .tracks: return tracksSection(arguments, for: student, in: modelContext)
        case .work: return try workSection(arguments, for: student, in: modelContext)
        }
    }
}
