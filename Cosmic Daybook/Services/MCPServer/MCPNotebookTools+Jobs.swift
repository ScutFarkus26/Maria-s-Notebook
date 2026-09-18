//
//  MCPNotebookTools+Jobs.swift
//  Cosmic Daybook
//
//  The job roster and the supply shelf's neighbour: who holds which classroom
//  job in a given week.
//
//  Assignments are keyed by the Monday of their week, matching the roster
//  screen — assigning for any day in a week lands on that Monday, so the same
//  child is never rostered twice for one week.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    // MARK: - Classroom Jobs

    static func classroomJobsTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "classroom_jobs",
            title: "Classroom Jobs",
            description: "The job roster: every active job and who holds it for a given week.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "week_of": [
                        "type": "string",
                        "description": "Any day in the week to show, YYYY-MM-DD (default this week)"
                    ],
                    "include_inactive": [
                        "type": "boolean",
                        "description": "Also list retired jobs (default false)"
                    ]
                ]
            ],
            annotations: .readOnly,
            handler: { arguments in
                let modelContext = context()
                let day = try dayArgument(arguments, "week_of") ?? Date()
                let includeInactive = arguments["include_inactive"]?.boolValue ?? false
                return describeJobs(weekOf: day, includeInactive: includeInactive, in: modelContext)
            }
        )
    }

    private static func describeJobs(
        weekOf day: Date, includeInactive: Bool, in modelContext: NSManagedObjectContext
    ) -> String {
        let weekStart = startOfWeek(for: day)
        let jobs = modelContext.safeFetch(CDFetchRequest(CDClassroomJob.self))
            .filter { includeInactive || $0.isActive }
            .sorted { $0.sortOrder < $1.sortOrder }
        guard !jobs.isEmpty else { return "No classroom jobs are set up." }

        let names = studentNameIndex(in: modelContext)
        let assignments = modelContext.safeFetch(CDFetchRequest(CDJobAssignment.self))
            .filter { assignment in
                guard let start = assignment.weekStartDate else { return false }
                return AppCalendar.startOfDay(start) == weekStart
            }
        let holdersByJob = Dictionary(grouping: assignments, by: \.jobID)

        let lines = jobs.map { job -> String in
            let id = job.id?.uuidString ?? "unknown"
            let holders = (holdersByJob[id] ?? [])
                .compactMap { names[$0.studentID] }
                .sorted()
            let who = holders.isEmpty ? "unassigned" : holders.joined(separator: ", ")
            let retired = job.isActive ? "" : " (retired)"
            return "- [job id=\(id)] \(job.name)\(retired): \(who)"
        }
        return "Jobs for the week of \(dayString(weekStart)):\n" + lines.joined(separator: "\n")
    }

    static func assignJobTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "assign_job",
            title: "Assign Classroom Job",
            description: "Give a student a classroom job for a week, or clear the job's roster "
                + "for that week. The week is keyed to its Monday, so any day in the week works.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "job": [
                        "type": "string",
                        "description": "The job's id or its exact name"
                    ],
                    "student_name": [
                        "type": "string",
                        "description": "The student taking it on (omit with clear: true)"
                    ],
                    "week_of": [
                        "type": "string",
                        "description": "Any day in the week, YYYY-MM-DD (default this week)"
                    ],
                    "clear": [
                        "type": "boolean",
                        "description": "Remove everyone from this job for that week"
                    ]
                ],
                "required": ["job"]
            ],
            annotations: .idempotentWrite,
            handler: { arguments in
                try assignJob(arguments: arguments, in: context())
            }
        )
    }

    private static func assignJob(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let job = try resolveJob(requireString(arguments, "job"), in: modelContext)
        guard let jobID = job.id else {
            throw MCPToolError("That job has no identifier.")
        }
        let weekStart = startOfWeek(for: try dayArgument(arguments, "week_of") ?? Date())

        let existing = modelContext.safeFetch(CDFetchRequest(CDJobAssignment.self))
            .filter { assignment in
                guard let start = assignment.weekStartDate else { return false }
                return assignment.jobID == jobID.uuidString && AppCalendar.startOfDay(start) == weekStart
            }

        if arguments["clear"]?.boolValue == true {
            existing.forEach { modelContext.delete($0) }
            guard modelContext.safeSave() else {
                modelContext.rollback()
                throw MCPToolError("The roster could not be cleared.")
            }
            return "Cleared \(job.name) for the week of \(dayString(weekStart))."
        }

        let student = try resolveStudentReference(
            requireString(arguments, "student_name"), in: modelContext
        )
        guard let studentID = student.id else {
            throw MCPToolError("That student record has no identifier.")
        }
        if existing.contains(where: { $0.studentID == studentID.uuidString }) {
            return "\(student.fullName) already has \(job.name) for the week of \(dayString(weekStart))."
        }
        // maxStudents of 0 means the job is uncapped, which is how the roster
        // screen reads it too.
        if job.maxStudents > 0 && existing.count >= job.maxStudents {
            throw MCPToolError(
                "\(job.name) already has \(existing.count) student(s) that week, which is its limit."
            )
        }

        let assignment = CDJobAssignment(context: modelContext)
        assignment.id = UUID()
        assignment.jobID = jobID.uuidString
        assignment.studentID = studentID.uuidString
        assignment.weekStartDate = weekStart
        assignment.createdAt = Date()
        assignment.job = job

        guard modelContext.safeSave() else {
            modelContext.rollback()
            throw MCPToolError("The job assignment could not be saved.")
        }
        return "Gave \(job.name) to \(student.fullName) for the week of \(dayString(weekStart))."
    }

    private static func resolveJob(
        _ reference: String, in modelContext: NSManagedObjectContext
    ) throws -> CDClassroomJob {
        let jobs = modelContext.safeFetch(CDFetchRequest(CDClassroomJob.self))
        if let id = UUID(uuidString: reference) {
            guard let job = jobs.first(where: { $0.id == id }) else {
                throw MCPToolError("No classroom job with id \(reference) was found.")
            }
            return job
        }
        let token = reference.folding(options: .diacriticInsensitive, locale: .current)
            .trimmed().lowercased()
        let matches = jobs.filter {
            $0.name.folding(options: .diacriticInsensitive, locale: .current).lowercased() == token
        }
        guard let job = matches.first, matches.count == 1 else {
            guard matches.isEmpty else {
                throw MCPToolError("More than one job is called \"\(reference)\".")
            }
            throw MCPToolError("No classroom job called \"\(reference)\" was found.")
        }
        return job
    }

    /// Job weeks are keyed to their Monday, matching the roster screen.
    private static func startOfWeek(for date: Date) -> Date {
        let calendar = AppCalendar.shared
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)
        // Gregorian weekday: Sunday == 1, Monday == 2.
        let daysSinceMonday = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -daysSinceMonday, to: day) ?? day
    }
}
