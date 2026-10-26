//
//  LessonAttachmentService+Titles.swift
//  Cosmic Daybook
//
//  How an attachment's title is compared and turned into its name.
//

import CoreData
import Foundation

extension LessonAttachmentService {
    /// The lesson's own attachment (lesson scope, held by this lesson) whose
    /// title is `title` (`sameTitle`); a ".<ext>" of the attachment's own kind
    /// on the end of `title` is let off. Sequence- and area-wide files never
    /// match. The oldest wins if there are several.
    func existingAttachment(titled title: String, on lesson: CDLesson) -> CDLessonAttachment? {
        let wanted = title.trimmed()
        let own = ((lesson.attachments?.allObjects as? [CDLessonAttachment]) ?? [])
            .filter { !$0.isDeleted && $0.scope == .lesson }
            .sorted { ($0.attachedAt ?? .distantPast) < ($1.attachedAt ?? .distantPast) }
        return own.first { attachment in
            Self.sameTitle(CDLessonAttachment.titleStem(of: wanted, fileType: attachment.fileType), attachment.title)
        }
    }

    /// Whether two titles are the same: trimmed, then compared as written,
    /// in any case and with or without accents. Never through the name on
    /// disk, which keeps ASCII only: "Fractions ½" and "Fractions ¼", or two
    /// Hebrew titles, would read as one there. An empty title matches nothing.
    nonisolated static func sameTitle(_ lhs: String, _ rhs: String) -> Bool {
        let left = lhs.trimmed()
        guard !left.isEmpty else { return false }
        return left.compare(rhs.trimmed(), options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    /// `title` with `.ext` on the end, unless it already ends that way.
    nonisolated static func fileName(title: String, ext: String) -> String {
        guard !ext.isEmpty else { return title }
        return CDLessonAttachment.titleStem(of: title, fileType: ext) + "." + ext
    }
}
