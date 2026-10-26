//
//  AttachmentReplacement.swift
//  Cosmic Daybook
//
//  Replace with Newer Version… on a lesson's Files card (plan "Lesson file
//  attachments", Phase 3).
//

import Foundation
import OSLog
import UniformTypeIdentifiers

/// Replace with Newer Version… on the Files card: the picked file goes to
/// `LessonAttachmentService.replace`, and a toast says what happened.
@MainActor
enum AttachmentReplacement {
    private static let logger = Logger.lessons

    /// What the picker offers and the service accepts: the card's own kinds
    /// (PDFs, images and Pages documents), each checked by its content.
    static let acceptedTypes: [UTType] = [.pdf, .image, UTType(filenameExtension: "pages") ?? .data]

    static let sameFileMessage = "That's the same file — nothing changed."

    /// "Replaced Area of a Circle".
    static func replacedMessage(title: String) -> String {
        "Replaced \(title)"
    }

    /// Replaces `attachment` with the picked file, holding the file's
    /// security-scoped access until the replace is done, then shows a toast:
    /// replaced, the same file, or why it couldn't be.
    static func replace(
        _ attachment: CDLessonAttachment,
        withPicked result: Result<[URL], Error>,
        using service: LessonAttachmentService,
        toasts: ToastService = .shared
    ) async {
        let url: URL
        switch result {
        case .success(let urls):
            guard let first = urls.first else { return }
            url = first
        case .failure(let error):
            if (error as? CocoaError)?.code == .userCancelled { return }
            logger.error("Replace picker failed: \(error.localizedDescription, privacy: .public)")
            toasts.showError(AppErrorMessages.importMessage(for: error))
            return
        }

        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let outcome = try await service.replace(attachment, withFileAt: url, allowedTypes: acceptedTypes)
            switch outcome {
            case .replaced, .noteChanged:
                toasts.showSuccess(replacedMessage(title: attachment.title))
            case .unchanged:
                toasts.showInfo(sameFileMessage)
            }
        } catch let problem as LessonAttachmentService.Problem {
            toasts.showError(problem.errorDescription ?? fallbackMessage)
        } catch {
            logger.error("Couldn't replace a lesson file: \(error.localizedDescription, privacy: .public)")
            toasts.showError(AppErrorMessages.importMessage(for: error))
        }
    }

    private static let fallbackMessage = "Couldn't replace the file. Try again."
}
