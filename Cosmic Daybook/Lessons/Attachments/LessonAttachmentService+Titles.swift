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
    /// title is `title`: the same sanitized stem, in any case. Sequence- and
    /// area-wide files never match. The oldest wins if there are several.
    func existingAttachment(titled title: String, on lesson: CDLesson) -> CDLessonAttachment? {
        let own = ((lesson.attachments?.allObjects as? [CDLessonAttachment]) ?? [])
            .filter { !$0.isDeleted && $0.scope == .lesson }
            .sorted { ($0.attachedAt ?? .distantPast) < ($1.attachedAt ?? .distantPast) }
        return own.first { attachment in
            let wanted = Self.titleKey(CDLessonAttachment.titleStem(of: title, fileType: attachment.fileType))
            return !wanted.isEmpty && wanted == Self.titleKey(attachment.title)
        }
    }

    /// How two titles compare: their sanitized stems, lowercased. A title that
    /// sanitizes to nothing (all Hebrew, say) compares as itself, lowercased.
    nonisolated static func titleKey(_ title: String) -> String {
        let trimmed = title.trimmed()
        let sanitized = ManagedPDFFileStorage.sanitizeFilenameComponent(trimmed, fallback: "")
        return (sanitized.isEmpty ? trimmed : sanitized).lowercased()
    }

    /// `title` with `.ext` on the end, unless it already ends that way.
    nonisolated static func fileName(title: String, ext: String) -> String {
        guard !ext.isEmpty else { return title }
        return CDLessonAttachment.titleStem(of: title, fileType: ext) + "." + ext
    }
}
