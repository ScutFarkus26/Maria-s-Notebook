//
//  MCPNotebookTools+CombinedReads.swift
//  Cosmic Daybook
//
//  The subjects that used to take several read tools each, now one tool with a
//  `view` (see MCPCombinedTools.swift). Each view is the old tool, unchanged.
//

import Foundation

extension MCPNotebookTools {

    /// The roster, or the one-paragraph orientation (`classroom_snapshot`).
    static func rosterTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        combinedReadTool(
            name: "list_students", title: "Students",
            intro: "The classroom's children. Without view you get the roster.",
            defaultView: "roster",
            views: [("roster", listStudentsTool(context: context)),
                    ("snapshot", classroomSnapshotTool(context: context))]
        )
    }

    /// Is the notebook syncing, and what did these tools change lately.
    static func notebookStatusTool(journal: MCPWriteJournal) -> MCPToolDefinition {
        combinedReadTool(
            name: "notebook_status", title: "Notebook Status",
            intro: "How the notebook itself is doing: its iCloud sync, and what Claude has changed in it.",
            views: [("sync", syncStatusTool()),
                    ("recent_writes", recentMCPWritesTool(journal: journal))]
        )
    }

    /// The teaching albums: search, read a page, or the guide's own marks.
    static func albumsTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        combinedReadTool(
            name: "albums", title: "Teaching Albums",
            intro: "The guide's Montessori teaching-album PDFs. Search finds pages; page returns one in full; "
                + "marks lists what the guide bookmarked, noted and highlighted, each followed with view page.",
            views: [("search", searchAlbumsTool()),
                    ("page", albumPageTool()),
                    ("marks", albumMarksTool(context: context))]
        )
    }

    /// Class-wide questions about who is due, ready, secure or unrecorded.
    static func classProgressTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        combinedReadTool(
            name: "class_progress", title: "Class Progress",
            intro: "Class-wide lists of who needs what next. pending reads the year plan, ready and "
                + "mastery_candidates read the presentation record, recall reads the spaced re-checks, "
                + "missing_observations reads the gaps in what was written down.",
            views: [("pending", studentsPendingTool(context: context)),
                    ("ready", studentsReadyTool(context: context)),
                    ("mastery_candidates", masteryCandidatesTool(context: context)),
                    ("recall", recallChecksTool(context: context)),
                    ("missing_observations", presentationsMissingObservationsTool(context: context))]
        )
    }

    /// The to-do list, or everything open for the children (`list_open_follow_ups`).
    static func todosTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        combinedReadTool(
            name: "list_todos", title: "Todos And Follow-Ups",
            intro: "The guide's to-dos and what is owed to the children. Without view you get the to-do list.",
            defaultView: "todos",
            views: [("todos", listTodosTool(context: context)),
                    ("open_follow_ups", listOpenFollowUpsTool(context: context))]
        )
    }

    /// Guardians on file, and the letters and reports sent home to them.
    static func familiesTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        combinedReadTool(
            name: "families", title: "Families",
            intro: "The children's families: who the guardians are, and what has been written home.",
            views: [("guardians", listGuardiansTool(context: context)),
                    ("communications", parentCommunicationsTool(context: context))]
        )
    }

    /// The plan for a span of days, or the meetings booked but not yet held.
    static func scheduleTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        combinedReadTool(
            name: "schedule_for_range", title: "Schedule",
            intro: "What is planned. Without view you get the plan for a day or span of days.",
            defaultView: "plan",
            views: [("plan", scheduleForRangeTool(context: context)),
                    ("meetings", scheduledMeetingsTool(context: context))]
        )
    }
}
