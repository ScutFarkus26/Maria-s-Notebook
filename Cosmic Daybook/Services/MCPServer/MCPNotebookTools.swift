//
//  MCPNotebookTools.swift
//  Cosmic Daybook
//
//  The toolset the MCP server exposes to Claude Desktop. The goal is total
//  coverage: anything the guide can see or change in the app should be
//  reachable here. Two boundaries are deliberate — nothing deletes a record
//  outright (remove_student_from_work is the one exception, and it refuses
//  until the guide has seen exactly what it will change), and
//  record_parent_communication files a letter without sending it.
//
//  Tools are grouped below only to keep this list readable; the order is what
//  the client sees in tools/list. Each domain's implementation lives in its
//  own MCPNotebookTools+<Domain>.swift file.
//
//  Every write goes through the same service the equivalent in-app control
//  uses, never straight to Core Data — see Documentation/Architecture/
//  MCP_SERVER.md for the tool-to-backing-path table.
//
//  All handlers run on the main actor and read through the app's shared
//  Core Data stack, the same entry point the Siri intents use.
//

import CoreData
import Foundation

/// Supplies the managed object context tools should query. Injectable so
/// tests can point the tools at an in-memory stack.
typealias MCPContextProvider = @MainActor @Sendable () -> NSManagedObjectContext

enum MCPNotebookTools {
    /// Builds the full toolset backed by the given context provider.
    static func makeTools(
        context: @escaping MCPContextProvider = { AppBootstrapping.getSharedCoreDataStack().viewContext },
        dependencies: @escaping MCPDependenciesProvider = { MCPAppServices.dependencies },
        journal: MCPWriteJournal = .shared
    ) -> [MCPToolDefinition] {
        rosterAndLessonTools(context: context, journal: journal)
            + observationTools(context: context)
            + scheduleAndWorkTools(context: context)
            + dayToDayTools(context: context)
            + classroomTools(context: context)
            + schoolCalendarTools(context: context, dependencies: dependencies)
            + appServiceTools(context: context, dependencies: dependencies)
    }

    /// The school calendar: which days are in session, and the year settings.
    private static func schoolCalendarTools(
        context: @escaping MCPContextProvider,
        dependencies: @escaping MCPDependenciesProvider
    ) -> [MCPToolDefinition] {
        [
            schoolCalendarTool(context: context, dependencies: dependencies),
            setSchoolDaysTool(context: context),
            updateSchoolCalendarTool(dependencies: dependencies)
        ]
    }

    /// Tools that need the app's dependency container, not just a context.
    private static func appServiceTools(
        context: @escaping MCPContextProvider,
        dependencies: @escaping MCPDependenciesProvider
    ) -> [MCPToolDefinition] {
        [
            createBackupTool(dependencies: dependencies),
            draftParentReportTool(context: context, dependencies: dependencies)
        ]
    }

    private static func rosterAndLessonTools(
        context: @escaping MCPContextProvider,
        journal: MCPWriteJournal
    ) -> [MCPToolDefinition] {
        [
            listStudentsTool(context: context),
            updateStudentTool(context: context),
            searchNotebookTool(),
            classroomSnapshotTool(context: context),
            syncStatusTool(),
            recentMCPWritesTool(journal: journal),
            findLessonsTool(context: context),
            listLessonsByAreaTool(context: context),
            createLessonTool(context: context),
            updateLessonTool(context: context),
            reorderLessonsTool(context: context),
            searchAlbumsTool(),
            albumPageTool(),
            albumMarksTool(context: context),
            studentTracksTool(context: context),
            studentCurriculumMapTool(context: context),
            classCurriculumMapTool(context: context),
            weeklySchedulesTool(context: context),
            yearPlanTool(context: context),
            studentsPendingTool(context: context),
            studentsReadyTool(context: context),
            updateYearPlanEntryTool(context: context),
            skipYearPlanEntriesTool(context: context),
            clearYearPlanTool(context: context),
            listTemplatesTool(context: context)
        ]
    }

    private static func observationTools(
        context: @escaping MCPContextProvider
    ) -> [MCPToolDefinition] {
        [
            studentObservationsTool(context: context),
            createObservationTool(context: context),
            updateObservationTool(context: context),
            studentPresentationHistoryTool(context: context),
            presentationsMissingObservationsTool(context: context),
            recordPresentationTool(context: context),
            markMasteredTool(context: context),
            masteryCandidatesTool(context: context),
            createMeetingEntryTool(context: context),
            studentMeetingsTool(context: context),
            scheduledMeetingsTool(context: context),
            scheduleMeetingTool(context: context),
            practiceSessionsTool(context: context),
            recallChecksTool(context: context)
        ]
    }

    private static func scheduleAndWorkTools(
        context: @escaping MCPContextProvider
    ) -> [MCPToolDefinition] {
        [
            scheduleForRangeTool(context: context),
            schedulePresentationTool(context: context),
            reschedulePresentationTool(context: context),
            discardPresentationTool(context: context),
            updatePresentationRosterTool(context: context),
            studentWorkTool(context: context),
            workDetailTool(context: context),
            assignWorkTool(context: context),
            updateWorkTool(context: context),
            removeStudentFromWorkTool(context: context)
        ]
    }

    private static func dayToDayTools(
        context: @escaping MCPContextProvider
    ) -> [MCPToolDefinition] {
        [
            attendanceForDayTool(context: context),
            studentAttendanceTool(context: context),
            markAttendanceTool(context: context),
            listOpenFollowUpsTool(context: context),
            listTodosTool(context: context),
            addFollowUpTool(context: context),
            updateTodoTool(context: context),
            resolveFollowUpTool(context: context)
        ]
    }

    private static func classroomTools(
        context: @escaping MCPContextProvider
    ) -> [MCPToolDefinition] {
        [
            listGuardiansTool(context: context),
            updateGuardianTool(context: context),
            parentCommunicationsTool(context: context),
            recordParentCommunicationTool(context: context),
            listGoingOutsTool(context: context),
            updateGoingOutTool(context: context),
            classroomJobsTool(context: context),
            assignJobTool(context: context),
            listSuppliesTool(context: context),
            adjustSupplyTool(context: context),
            listProjectsTool(context: context),
            projectDetailTool(context: context),
            updateProjectTool(context: context),
            addProjectSessionTool(context: context),
            listIssuesTool(context: context),
            updateIssueTool(context: context),
            listProceduresTool(context: context),
            listStoriesTool(context: context),
            communityTopicsTool(context: context),
            updateCommunityTopicTool(context: context),
            listResourcesTool(context: context),
            bookClubTool(context: context),
            listRemindersTool(context: context),
            dayPadTool(context: context)
        ]
    }
}

// MARK: - Shared Helpers

extension MCPNotebookTools {
    /// Formats dates for tool output; the server's instructions promise ISO 8601.
    static let isoDay: DateFormatter = DateFormatters.isoDayPOSIX

    static func dayString(_ date: Date?) -> String {
        date.map { isoDay.string(from: $0) } ?? "undated"
    }

    /// Resolves a student by first name, full name, or nickname
    /// (diacritic- and case-insensitive), mirroring NotebookTools'
    /// resolver. Ambiguity and misses throw tool errors the model can
    /// relay to the teacher.
    static func resolveStudent(named name: String, in context: NSManagedObjectContext) throws -> CDStudent {
        let token = name.folded()
        guard !token.isEmpty else {
            throw MCPToolError("A student name is required.")
        }
        let matches = context.safeFetch(CDFetchRequest(CDStudent.self)).filter { student in
            let first = student.firstName.folded()
            let full = student.fullName.folded()
            let nickname = (student.nickname ?? "").folded()
            return token == first || token == full || (!nickname.isEmpty && token == nickname)
        }
        guard !matches.isEmpty else {
            throw MCPToolError("No student named \"\(name)\" was found.")
        }
        guard matches.count == 1, let student = matches.first else {
            let names = matches.map(\.fullName).sorted().joined(separator: ", ")
            throw MCPToolError(
                "More than one student matches \"\(name)\": \(names). Ask which student the guide means."
            )
        }
        return student
    }

    // MARK: Argument Extraction

    static func requireString(_ arguments: [String: JSONValue], _ key: String) throws -> String {
        guard let value = arguments[key]?.stringValue?.trimmed(), !value.isEmpty else {
            throw MCPToolError("Missing required argument: \(key)")
        }
        return value
    }

    static func intArgument(_ arguments: [String: JSONValue], _ key: String,
                            default defaultValue: Int, range: ClosedRange<Int>) -> Int {
        let value = arguments[key]?.intValue ?? defaultValue
        return min(max(value, range.lowerBound), range.upperBound)
    }

    static func stringArrayArgument(_ arguments: [String: JSONValue], _ key: String) -> [String] {
        (arguments[key]?.arrayValue ?? []).compactMap { $0.stringValue?.trimmed() }.filter { !$0.isEmpty }
    }
}

// MARK: - Day Windows

extension MCPNotebookTools {
    /// The inclusive `since` … `until` day window the history reads share.
    ///
    /// Both ends are whole days, not instants: `start` is the start of the
    /// `since` day and `endExclusive` the start of the day *after* `until`, so
    /// a record stamped at any hour of either day falls inside. An unset end
    /// stays unbounded rather than snapping to the end of today — a caller who
    /// passes neither argument gets exactly the window the tool had before.
    struct DayWindow {
        let sinceDay: Date?
        let untilDay: Date?

        var isSet: Bool { sinceDay != nil || untilDay != nil }
        var start: Date? { sinceDay.map(AppCalendar.startOfDay) }
        var endExclusive: Date? { untilDay.map { AppCalendar.dayRange(for: $0).end } }
        /// The last instant of the `until` day, for APIs that compare `<=`.
        var endInclusive: Date? { endExclusive.map { $0.addingTimeInterval(-1) } }

        /// True when the date falls inside the window. An undated record is
        /// outside a window the caller asked for and inside one they did not.
        func contains(_ date: Date?) -> Bool {
            guard let date else { return !isSet }
            if let start, date < start { return false }
            if let endExclusive, date >= endExclusive { return false }
            return true
        }

        /// " since 2026-01-01", " through 2026-03-01", or both — for headers.
        var phrase: String {
            var parts: [String] = []
            if let sinceDay { parts.append("since \(MCPNotebookTools.dayString(sinceDay))") }
            if let untilDay { parts.append("through \(MCPNotebookTools.dayString(untilDay))") }
            return parts.isEmpty ? "" : " " + parts.joined(separator: " ")
        }
    }

    /// Parses the optional `since` / `until` arguments. A window that runs
    /// backwards is a mistake worth naming, not an empty result the caller has
    /// to puzzle over.
    static func dayWindowArgument(_ arguments: [String: JSONValue]) throws -> DayWindow {
        let since = try dayArgument(arguments, "since")
        let until = try dayArgument(arguments, "until")
        if let since, let until, AppCalendar.startOfDay(since) > AppCalendar.startOfDay(until) {
            throw MCPToolError(
                "since (\(dayString(since))) is after until (\(dayString(until))); swap them."
            )
        }
        return DayWindow(sinceDay: since, untilDay: until)
    }

    /// The `since` / `until` schema properties, worded the same everywhere.
    static func dayWindowSchema(_ what: String) -> [String: JSONValue] {
        [
            "since": [
                "type": "string",
                "description": .string("YYYY-MM-DD. Only \(what) on or after this day (inclusive).")
            ],
            "until": [
                "type": "string",
                "description": .string("YYYY-MM-DD. Only \(what) on or before this day (inclusive).")
            ]
        ]
    }
}
