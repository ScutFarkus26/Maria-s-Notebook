//
//  MCPNotebookTools+AlbumMarks.swift
//  Maria's Notebook
//
//  The guide's own marks on their teaching albums: bookmarks, page notes and
//  highlights.
//
//  `search_albums` and `get_album_page` read what the album says; these read
//  what the guide thought about it. Album identity is the PDF filename, so
//  these cite the same album/page pair the album tools use and a mark can be
//  followed straight to its page.
//
//  Pencil ink is deliberately not returned — it is PencilKit drawing data with
//  no text to render.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    static func albumMarksTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "album_marks",
            title: "Album Marks",
            description: "The guide's bookmarks, page notes and highlights across their teaching "
                + "albums — what they flagged and what they wrote in the margin. Pass an album "
                + "filename to narrow to one album. Follow any result with get_album_page.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "album": [
                        "type": "string",
                        "description": .string("The album's PDF filename, as cited by "
                            + "search_albums. Omit for marks across every album.")
                    ],
                    "kind": [
                        "type": "string",
                        "enum": ["bookmark", "note", "highlight"],
                        "description": "Only this kind of mark (default: all three)"
                    ],
                    "search": [
                        "type": "string",
                        "description": "Match against the mark's text or the lesson title it sits under"
                    ],
                    "limit": [
                        "type": "integer",
                        "description": "Maximum marks to return, 1-100 (default 50)"
                    ]
                ]
            ],
            annotations: .readOnly,
            handler: { arguments in
                describeAlbumMarks(arguments: arguments, in: context())
            }
        )
    }

    /// One mark, flattened out of its three entity types so bookmarks, notes and
    /// highlights can be sorted and paged together.
    private struct AlbumMark {
        let kind: String
        let albumID: String
        let pageIndex: Int32
        let lessonTitle: String?
        let text: String?
        let detail: String?
    }

    private static func describeAlbumMarks(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) -> String {
        let album: String? = nonEmpty(arguments["album"]?.stringValue)
        let kind: String? = nonEmpty(arguments["kind"]?.stringValue)
        let search: String? = nonEmpty(arguments["search"]?.stringValue)?.lowercased()
        let limit: Int = intArgument(arguments, "limit", default: 50, range: 1...100)

        let marks: [AlbumMark] = collectMarks(kind: kind, in: modelContext)
        var kept: [AlbumMark] = []
        for mark in marks {
            if let album, mark.albumID != album { continue }
            if let search, !markMatches(mark, search) { continue }
            kept.append(mark)
        }
        guard !kept.isEmpty else {
            let where_ = album.map { " in \($0)" } ?? ""
            return "No album marks\(where_) match that."
        }

        let sorted: [AlbumMark] = kept.sorted { lhs, rhs in
            if lhs.albumID != rhs.albumID { return lhs.albumID < rhs.albumID }
            return lhs.pageIndex < rhs.pageIndex
        }
        let shown: [AlbumMark] = Array(sorted.prefix(limit))
        let lines = shown.map { mark -> String in
            // Page indexes are zero-based in storage; album citations are one-based.
            let citation = "[albumPage album=\"\(mark.albumID)\" page=\(mark.pageIndex + 1)]"
            var parts: [String] = ["- \(citation) \(mark.kind)"]
            if let title = nonEmpty(mark.lessonTitle) {
                parts.append("under \(title)")
            }
            if let colour = nonEmpty(mark.detail) {
                parts.append(colour)
            }
            let head: String = parts.joined(separator: " — ")
            guard let text = nonEmpty(mark.text) else { return head }
            return head + "\n    " + text
        }
        let more: String = sorted.count > shown.count
            ? "\n(\(sorted.count - shown.count) more not shown.)"
            : ""
        return "\(sorted.count) album mark(s):\n" + lines.joined(separator: "\n") + more
    }

    private static func collectMarks(
        kind: String?, in modelContext: NSManagedObjectContext
    ) -> [AlbumMark] {
        var marks: [AlbumMark] = []
        if kind == nil || kind == "bookmark" {
            marks += modelContext.safeFetch(CDFetchRequest(CDAlbumBookmark.self)).map {
                AlbumMark(kind: "bookmark", albumID: $0.albumID, pageIndex: $0.pageIndex,
                          lessonTitle: $0.lessonTitle, text: nil, detail: nil)
            }
        }
        if kind == nil || kind == "note" {
            marks += modelContext.safeFetch(CDFetchRequest(CDAlbumPageNote.self)).map {
                AlbumMark(kind: "note", albumID: $0.albumID, pageIndex: $0.pageIndex,
                          lessonTitle: $0.lessonTitle, text: $0.text, detail: nil)
            }
        }
        if kind == nil || kind == "highlight" {
            marks += modelContext.safeFetch(CDFetchRequest(CDAlbumHighlight.self)).map {
                AlbumMark(kind: "highlight", albumID: $0.albumID, pageIndex: $0.pageIndex,
                          lessonTitle: $0.lessonTitle, text: $0.text, detail: $0.colorName)
            }
        }
        return marks
    }

    private static func markMatches(_ mark: AlbumMark, _ needle: String) -> Bool {
        if let text = mark.text, text.lowercased().contains(needle) { return true }
        if let title = mark.lessonTitle, title.lowercased().contains(needle) { return true }
        return false
    }
}
