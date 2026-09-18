//
//  MCPNotebookTools+Watching.swift
//  Cosmic Daybook
//
//  The `watching_only` form of `list_open_follow_ups`: the same rows the
//  app's Watching list shows, per child, built by `WatchListFetcher` and
//  `WatchListBuilder` so the two can never disagree about what is being
//  watched. The default form of the tool stays a superset (every open todo,
//  not only the "Watch…" ones) and is unchanged.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    /// One line per row, grouped per child; the whole class last.
    ///
    /// With no student named, departed children are left out, as Today does.
    /// With a student named, her rows are listed whatever her status — that
    /// is what her own page shows — and whole-class notes are omitted.
    static func listWatching(
        studentID: UUID?, studentName: String, in modelContext: NSManagedObjectContext
    ) -> String {
        let everything = WatchListFetcher.fetchAll(in: modelContext)
        let items: [WatchItem]
        if let studentID {
            items = WatchListBuilder.items(for: studentID, in: everything)
        } else {
            items = WatchListBuilder.restricted(
                toRoster: WatchListFetcher.enrolledIDs(in: modelContext), everything
            )
        }

        guard !items.isEmpty else {
            return studentName.isEmpty
                ? "Nothing is being watched — no flagged notes, Watch todos, or open goals."
                : "Nothing is being watched for \(studentName)."
        }

        let students = modelContext.safeFetch(CDFetchRequest(CDStudent.self))
        let nameByID = Dictionary(
            students.compactMap { student in student.id.map { ($0, student.fullName) } },
            uniquingKeysWith: { first, _ in first }
        )
        let groups = WatchListBuilder.grouped(items) { nameByID[$0] ?? "Unknown student" }

        let sections = groups.map { group -> String in
            let lines = group.items.map(watchingLine)
            return "\(group.name):\n" + lines.joined(separator: "\n")
        }
        return sections.joined(separator: "\n\n")
    }

    private static func watchingLine(_ item: WatchItem) -> String {
        let kind: String
        switch item.kind {
        case .flaggedNote: kind = "note"
        case .watchTodo: kind = "todo"
        case .goal: kind = "focusItem"
        }
        var details: [String] = []
        if item.date > .distantPast {
            details.append("touched \(dayString(item.date))")
        }
        if let dueDate = item.dueDate {
            details.append("due \(dayString(dueDate))")
        }
        let suffix = details.isEmpty ? "" : " (\(details.joined(separator: "; ")))"
        return "- [\(kind) id=\(item.sourceID.uuidString)] \(item.text)\(suffix)"
    }
}
