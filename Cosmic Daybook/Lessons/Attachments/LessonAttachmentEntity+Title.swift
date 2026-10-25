//
//  LessonAttachmentEntity+Title.swift
//  Cosmic Daybook
//
//  An attachment's title and when it last changed, as the Files card,
//  `LessonAttachmentService` and the MCP tools read them.
//

import Foundation

nonisolated extension CDLessonAttachment {
    /// `fileName` without its file extension: "Area of a Circle — remade album
    /// pages" for "Area of a Circle — remade album pages.pdf". `fileName` keeps
    /// the name as it was given; only the file on disk has a sanitized name
    /// (`fileRelativePath`, which can also carry a "-2"), so a title is never
    /// read from the path.
    var title: String {
        Self.titleStem(of: fileName, fileType: fileType)
    }

    /// When the file, its name or its note last changed: `modifiedAt`, or
    /// `attachedAt` on a record from before schema 21, which has none.
    var lastChanged: Date? {
        modifiedAt ?? attachedAt
    }

    /// `name` without a trailing ".<fileType>" (any case); `name` itself when
    /// it doesn't end that way, so "Lesson 3.2" stays whole for a PDF.
    static func titleStem(of name: String, fileType: String) -> String {
        let ext = fileType.trimmed()
        guard !ext.isEmpty, name.count > ext.count + 1,
              name.lowercased().hasSuffix("." + ext.lowercased()) else { return name }
        return String(name.dropLast(ext.count + 1))
    }
}
