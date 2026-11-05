//
//  MCPRetiredTools.swift
//  Cosmic Daybook
//
//  Tool names the server no longer lists. A session, a skill or a saved prompt
//  may still call one, so `tools/call` answers each with one plain sentence
//  saying where it went, rather than "unknown tool". The same names, and what
//  replaced them, are under "Retired" in docs/Technical notes/MCP_SERVER.md;
//  MCPToolRegistryTests asserts every one answers.
//

import Foundation

extension MCPNotebookTools {

    /// Retired tool name → the sentence `tools/call` answers it with.
    static let retiredTools: [String: String] = {
        var table: [String: String] = [:]

        // Folded into student_record (round-two Simplify, Phase 6).
        let studentSections: [(old: String, section: String)] = [
            ("student_attendance", "attendance"),
            ("student_curriculum_map", "curriculum_map"),
            ("student_meetings", "meetings"),
            ("student_observations", "observations"),
            ("student_presentation_history", "presentation_history"),
            ("student_tracks", "tracks"),
            ("student_work", "work")
        ]
        for (old, section) in studentSections {
            table[old] = moved(old, into: "student_record", pass: "sections: [\"\(section)\"]")
        }

        // Folded into a tool with a `view` (MCPCombinedTools.swift).
        let views: [(old: String, newHome: String)] = [
            ("classroom_snapshot", "list_students/snapshot"),
            ("sync_status", "notebook_status/sync"),
            ("recent_mcp_writes", "notebook_status/recent_writes"),
            ("search_albums", "albums/search"),
            ("get_album_page", "albums/page"),
            ("album_marks", "albums/marks"),
            ("students_pending", "class_progress/pending"),
            ("students_ready", "class_progress/ready"),
            ("mastery_candidates", "class_progress/mastery_candidates"),
            ("recall_checks", "class_progress/recall"),
            ("presentations_missing_observations", "class_progress/missing_observations"),
            ("list_open_follow_ups", "list_todos/open_follow_ups"),
            ("list_guardians", "families/guardians"),
            ("parent_communications", "families/communications"),
            ("scheduled_meetings", "schedule_for_range/meetings")
        ]
        for (old, newHome) in views {
            let parts = newHome.split(separator: "/").map(String.init)
            table[old] = moved(old, into: parts[0], pass: "view: \"\(parts[1])\"")
        }

        table["list_lessons_by_area"] = moved(
            "list_lessons_by_area", into: "find_lessons", pass: "area (and sub_area)"
        )
        table["list_orders"] = moved(
            "list_orders", into: "list_supplies",
            pass: "stage: \"open\" (or to_request, asked_for, confirmed, received, all)"
        )
        table["add_order_items"] = moved(
            "add_order_items", into: "mark_supplies", pass: "new_needs: [the same entries]"
        )
        table["update_order_items"] = moved(
            "update_order_items", into: "mark_supplies", pass: "needs: [the same entries]"
        )

        // Features Claude no longer reaches: the feature stays in the app, or is gone.
        let inTheAppOnly = "stays in the app; Claude no longer reaches it."
        table["list_going_outs"] = "list_going_outs is retired: Going Out \(inTheAppOnly)"
        table["update_going_out"] = "update_going_out is retired: Going Out \(inTheAppOnly)"
        table["list_procedures"] = "list_procedures is retired: Procedures \(inTheAppOnly)"
        table["book_club"] = "book_club is retired: Book Club \(inTheAppOnly)"
        table["list_stories"] = "list_stories is retired: the story shelf \(inTheAppOnly)"
        table["project_detail"] = "project_detail is retired: list_projects still shows the running projects, "
            + "but their sessions and notes stay in the app."
        table["update_project"] = "update_project is retired: projects \(inTheAppOnly) "
            + "(list_projects still shows the running ones)."
        table["add_project_session"] = "add_project_session is retired: project sessions \(inTheAppOnly)"

        // Retired in Phases 1 and 2.
        table["list_reminders"] = "list_reminders is retired: Apple Reminders sync was removed, and to-dos live in "
            + "Tide. list_todos shows the notebook's own check-ins and follow-ups."
        table["classroom_jobs"] = "classroom_jobs is retired: Classroom Jobs was removed from the app."
        table["assign_job"] = "assign_job is retired: Classroom Jobs was removed from the app."
        table["practice_sessions"] = "practice_sessions is retired: practice is recorded as work check-ins now. "
            + "student_record with sections: [\"work\"] shows a child's work and its check-ins, "
            + "and work_detail shows one item's."
        return table
    }()

    private static func moved(_ old: String, into tool: String, pass argument: String) -> String {
        "\(old) moved into \(tool); call \(tool) with \(argument) and the same other arguments."
    }
}
