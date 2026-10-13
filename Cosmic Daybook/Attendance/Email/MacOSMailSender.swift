import Foundation
import OSLog

#if os(macOS)
import AppKit
import ObjectiveC
#endif

// MARK: - macOS Mail Sender Helper

#if os(macOS)
public enum MacOSMailSender {
    private static let logger = Logger.attendance

    /// How a compose request ended. Nothing in AppKit reports that Mail sent
    /// a message: `didShareItems` means only that the message reached Mail
    /// (its compose window), so a caller that records a send asks the guide.
    public enum Outcome: Sendable, Equatable {
        /// The message reached Mail.
        case handedToMail
        /// The guide cancelled.
        case cancelled
        /// This Mac has no compose-email service.
        case unavailable
        /// An error, or no word within 30 seconds: the compose window may
        /// still have opened.
        case failed
    }

    /// Opens the message in Mail; `completion` is true when it reached Mail,
    /// false otherwise. Callers that record a send use `compose`, which says
    /// how it ended.
    public static func send(
        to recipient: String?,
        subject: String,
        body: String,
        attachmentURL: URL? = nil,
        completion: @escaping (Bool) -> Void
    ) {
        compose(to: recipient, subject: subject, body: body, attachmentURL: attachmentURL) { outcome in
            completion(outcome == .handedToMail)
        }
    }

    /// Opens the message in Mail and says how the request ended.
    public static func compose(
        to recipient: String?,
        subject: String,
        body: String,
        attachmentURL: URL? = nil,
        completion: @escaping (Outcome) -> Void
    ) {
        guard let service = NSSharingService(named: .composeEmail) else {
            Task {
                completion(.unavailable)
            }
            return
        }
        if let r = recipient {
            let recipients = AttendanceEmail.parseRecipients(from: r)
            if !recipients.isEmpty {
                service.recipients = recipients
            }
        }
        service.subject = subject
        
        // Timeout fallback: ensure completion is called even if delegate callbacks don't fire
        var hasCompleted = false
        let timeoutTask = Task {
            do {
                try await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
            } catch {
                logger.warning("Task sleep interrupted: \(error)")
            }
            if !hasCompleted {
                hasCompleted = true
                completion(.failed) // No word: the window may still have opened
            }
        }

        let delegate = SharingDelegate { outcome in
            Task {
                if !hasCompleted {
                    hasCompleted = true
                    timeoutTask.cancel()
                    completion(outcome)
                }
            }
        }
        service.delegate = delegate
        // Keep the delegate alive until completion by retaining it on the service via associated object.
        objc_setAssociatedObject(
            service,
            Unmanaged.passUnretained(delegate).toOpaque(),
            delegate,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        var items: [Any] = [body]
        if let attachmentURL {
            items.append(attachmentURL)
        }
        service.perform(withItems: items)
    }

    private final class SharingDelegate: NSObject, NSSharingServiceDelegate {
        private let completion: (Outcome) -> Void
        init(completion: @escaping (Outcome) -> Void) { self.completion = completion }

        func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
            completion(.handedToMail)
            clearAssociation(from: sharingService)
        }
        func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
            let nsError = error as NSError
            let cancelled = nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError
            completion(cancelled ? .cancelled : .failed)
            clearAssociation(from: sharingService)
        }
        private func clearAssociation(from service: NSSharingService) {
            objc_removeAssociatedObjects(service)
        }
    }
}
#endif
