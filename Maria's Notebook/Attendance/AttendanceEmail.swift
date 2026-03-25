// swiftlint:disable file_length
import Foundation
import SwiftUI
import OSLog

#if os(macOS)
import AppKit
import ObjectiveC
#endif

/// Preference keys for Attendance Email feature.
/// - Note: Values are stored in UserDefaults via @AppStorage.
public enum AttendanceEmailPrefs {
    public static let enabledKey = "AttendanceEmail.enabled"
    public static let toKey = "AttendanceEmail.to"
    public static let fromKey = "AttendanceEmail.from" // iOS preferred sending address
}

// MARK: - Report Generator
public struct AttendanceEmailReport {
    public static func makeSubject(
        for date: Date,
        calendar: Calendar = .current
    ) -> String {
        let dayStr = DateFormatters.mediumDate.string(from: calendar.startOfDay(for: date))
        return "Attendance \u{2022} \(dayStr)"
    }

    public static func makeBody(
        present: [String],
        tardy: [String],
        absent: [String],
        date: Date,
        calendar: Calendar = .current
    ) -> String {
        var lines: [String] = []
        lines.append("Attendance Report")
        lines.append(DateFormatters.fullDate.string(from: calendar.startOfDay(for: date)))
        lines.append("")
        func section(_ title: String, names: [String]) {
            lines.append("\(title) (\(names.count)):")
            if names.isEmpty {
                lines.append("  — none —")
            } else {
                for n in names { lines.append("  • \(n)") }
            }
            lines.append("")
        }
        section("On Time", names: present)
        section("Tardy", names: tardy)
        section("Absent", names: absent)
        return lines.joined(separator: "\n")
    }
}

/// Convenience helpers to read stored preferences and create prefilled mail senders.
/// Includes platform-aware availability checks.
@MainActor
public enum AttendanceEmail {
    public static func storedToAddress() -> String? {
        let s = SyncedPreferencesStore.shared.string(forKey: AttendanceEmailPrefs.toKey)?.trimmed()
        guard let s, !s.isEmpty else { return nil }
        return s
    }

    public static func storedFromAddress() -> String? {
        let s = SyncedPreferencesStore.shared.string(forKey: AttendanceEmailPrefs.fromKey)?.trimmed()
        guard let s, !s.isEmpty else { return nil }
        return s
    }

    /// Indicates whether the current platform can compose/send email using the built-in mechanisms.
    /// - iOS: Uses MFMailComposeViewController.canSendMail().
    /// - macOS: Checks for NSSharingService(named: .composeEmail).
    public static var isAvailable: Bool {
    #if os(iOS)
        // Import is in iOS block below; we avoid a hard dependency here by deferring to MessageUI only at compile time.
        return MFMailComposeViewController.canSendMail()
    #elseif os(macOS)
        return NSSharingService(named: .composeEmail) != nil
    #else
        return false
    #endif
    }

    /// Parses a user-entered recipients string into an array of
    /// email addresses by splitting on commas/semicolons and trimming
    /// whitespace.
    /// - Parameter string: A raw recipients string,
    ///   e.g., "a@example.com, b@example.com".
    /// - Returns: An array of non-empty email strings.
    /// - Note: Multi-recipient support is implemented and used in
    ///   all composer/send flows.
    public static func parseRecipients(from string: String?) -> [String] {
        guard let string, !string.trimmed().isEmpty else { return [] }
        let separators = CharacterSet(charactersIn: ",;")
        return string
            .components(separatedBy: separators)
            .map { $0.trimmed() }
            .filter { !$0.isEmpty }
    }

    public static func makeSubject(for date: Date, calendar: Calendar = .current) -> String {
        AttendanceEmailReport.makeSubject(for: date, calendar: calendar)
    }

    public static func makeBody(
        present: [String],
        tardy: [String],
        absent: [String],
        date: Date,
        calendar: Calendar = .current
    ) -> String {
        AttendanceEmailReport.makeBody(
            present: present,
            tardy: tardy,
            absent: absent,
            date: date,
            calendar: calendar
        )
    }

    /// Builds a mailto: URL with the provided recipients, subject, and body.
    /// - Note: Useful as a fallback when `isAvailable` is false.
    public static func makeMailtoURL(to recipients: [String], subject: String, body: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = recipients.joined(separator: ",")
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        return components.url
    }

    /// Convenience to build a mailto: URL using current
    /// preferences and a generated subject/body.
    public static func mailtoURLForCurrentPrefs(
        present: [String],
        tardy: [String],
        absent: [String],
        date: Date = Date(),
        calendar: Calendar = .current
    ) -> URL? {
        let to = parseRecipients(from: storedToAddress())
        let subject = makeSubject(for: date, calendar: calendar)
        let body = makeBody(
            present: present,
            tardy: tardy,
            absent: absent,
            date: date,
            calendar: calendar
        )
        return makeMailtoURL(to: to, subject: subject, body: body)
    }

    #if os(iOS)
    /// Creates a prefilled mail composer using current preferences.
    /// - Important: Check `AttendanceEmail.isAvailable` before
    ///   presenting. If unavailable, consider using
    ///   `mailtoURLForCurrentPrefs(...)` as a fallback.
    public static func composerForCurrentPrefs(
        present: [String],
        tardy: [String],
        absent: [String],
        date: Date = Date(),
        calendar: Calendar = .current,
        onComplete: @escaping (MFMailComposeResult, Error?) -> Void
    ) -> MailComposerView {
        let subject = makeSubject(for: date, calendar: calendar)
        let body = makeBody(
            present: present,
            tardy: tardy,
            absent: absent,
            date: date,
            calendar: calendar
        )
        let to = parseRecipients(from: storedToAddress())
        let from = storedFromAddress()
        return MailComposerView(
            toRecipients: to,
            subject: subject,
            body: body,
            preferredSender: from,
            onComplete: onComplete
        )
    }
    #endif

    #if os(macOS)
    public static func sendUsingMailAppForCurrentPrefs(
        present: [String],
        tardy: [String],
        absent: [String],
        date: Date = Date(),
        calendar: Calendar = .current,
        completion: @escaping (Bool) -> Void
    ) {
        let subject = makeSubject(for: date, calendar: calendar)
        let body = makeBody(
            present: present,
            tardy: tardy,
            absent: absent,
            date: date,
            calendar: calendar
        )
        MacOSMailSender.send(
            to: storedToAddress(),
            subject: subject,
            body: body,
            completion: completion
        )
    }

    /// Attempts to open a mailto: URL using current preferences.
    /// Returns true if the URL was opened successfully.
    /// - Note: Use this as a fallback when
    ///   NSSharingService(.composeEmail) is unavailable.
    public static func openMailtoFallbackForCurrentPrefs(
        present: [String],
        tardy: [String],
        absent: [String],
        date: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        let to = parseRecipients(from: storedToAddress())
        let subject = makeSubject(for: date, calendar: calendar)
        let body = makeBody(
            present: present,
            tardy: tardy,
            absent: absent,
            date: date,
            calendar: calendar
        )
        guard let url = makeMailtoURL(
            to: to,
            subject: subject,
            body: body
        ) else { return false }
        return NSWorkspace.shared.open(url)
    }

    /// Tries to send via Mail share service; if unavailable,
    /// opens a mailto: fallback.
    /// - Returns: true if either the share service succeeded or
    ///   the fallback URL was opened; false otherwise.
    /// - Important: This does not change existing behavior
    ///   unless you call it from your UI.
    public static func sendOrFallbackUsingMailAppForCurrentPrefs(
        present: [String],
        tardy: [String],
        absent: [String],
        date: Date = Date(),
        calendar: Calendar = .current,
        completion: @escaping (Bool) -> Void
    ) {
        if NSSharingService(named: .composeEmail) != nil {
            sendUsingMailAppForCurrentPrefs(
                present: present,
                tardy: tardy,
                absent: absent,
                date: date,
                calendar: calendar,
                completion: completion
            )
        } else {
            let opened = openMailtoFallbackForCurrentPrefs(
                present: present,
                tardy: tardy,
                absent: absent,
                date: date,
                calendar: calendar
            )
            Task { @MainActor in
                completion(opened)
            }
        }
    }
    #endif
}

// MARK: - Settings View

/// Settings form for configuring Attendance Email behavior.
/// - Note: The "Preferred 'From' Address" applies to iOS only;
///   macOS always uses the default Mail account.
public struct AttendanceEmailSettingsView: View {
    @SyncedAppStorage(AttendanceEmailPrefs.enabledKey) private var enabled: Bool = true
    @SyncedAppStorage(AttendanceEmailPrefs.toKey) private var toAddress: String = ""
    @SyncedAppStorage(AttendanceEmailPrefs.fromKey) private var fromAddress: String = ""

    public init() {}

    public var body: some View {
        Form {
            Section("Attendance Email") {
                Toggle("Show 'Send Attendance Email' Button", isOn: $enabled)
                TextField("Send To", text: $toAddress)
                #if os(macOS)
                .help("You can enter multiple addresses separated by commas or semicolons.")
                #endif
                #if os(iOS)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                #endif
                #if os(iOS)
                TextField("Preferred 'From' Address (iOS)", text: $fromAddress)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                #else
                TextField("Preferred 'From' Address (iOS only)", text: $fromAddress)
                    .disabled(true)
                    .foregroundStyle(.secondary)
                    .help("macOS uses your default Mail account; this setting applies to iOS only.")
                #endif
                Text("Note: iOS uses the preferred address when possible. macOS uses your default Mail account.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: enabled) { _, _ in SettingsCategory.markModified(.communication) }
        .onChange(of: toAddress) { _, _ in SettingsCategory.markModified(.communication) }
        .onChange(of: fromAddress) { _, _ in SettingsCategory.markModified(.communication) }
    }
}
#Preview {
    AttendanceEmailSettingsView()
}

// MARK: - iOS Mail Composer Wrapper
#if os(iOS)
import MessageUI

/// SwiftUI wrapper for MFMailComposeViewController.
/// - Important: Check AttendanceEmail.isAvailable before presenting.
public struct MailComposerView: UIViewControllerRepresentable {
    public typealias UIViewControllerType = MFMailComposeViewController

    public var toRecipients: [String]
    public var subject: String
    public var body: String
    public var preferredSender: String?
    public var onComplete: (MFMailComposeResult, Error?) -> Void

    public init(
        toRecipients: [String],
        subject: String,
        body: String,
        preferredSender: String?,
        onComplete: @escaping (MFMailComposeResult, Error?) -> Void
    ) {
        self.toRecipients = toRecipients
        self.subject = subject
        self.body = body
        self.preferredSender = preferredSender
        self.onComplete = onComplete
    }

    public func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients(toRecipients)
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        if let preferred = preferredSender, !preferred.trimmed().isEmpty {
            vc.setPreferredSendingEmailAddress(preferred)
        }
        return vc
    }

    public func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) { }

    public func makeCoordinator() -> Coordinator { Coordinator(onComplete: onComplete) }

    @MainActor
    public final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onComplete: (MFMailComposeResult, Error?) -> Void
        init(onComplete: @escaping (MFMailComposeResult, Error?) -> Void) {
            self.onComplete = onComplete
        }
        public func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            onComplete(result, error)
            controller.dismiss(animated: true)
        }
    }
}
#endif

// MARK: - macOS Mail Sender Helper

/// Helper for composing email via the system Mail service on macOS.
/// - Note: Uses NSSharingService(.composeEmail). Completion
///   reflects success/failure callbacks provided by the service.
#if os(macOS)
@MainActor
public enum MacOSMailSender {
    private static let logger = Logger.attendance
    public static func send(
        to recipient: String?,
        subject: String,
        body: String,
        completion: @escaping (Bool) -> Void
    ) {
        guard let service = NSSharingService(named: .composeEmail) else {
            Task { @MainActor in
                completion(false)
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
        let timeoutTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
            } catch {
                logger.warning("Task sleep interrupted: \(error)")
            }
            if !hasCompleted {
                hasCompleted = true
                completion(false) // Timeout treated as failure
            }
        }
        
        let delegate = SharingDelegate { success in
            Task { @MainActor in
                if !hasCompleted {
                    hasCompleted = true
                    timeoutTask.cancel()
                    completion(success)
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
        service.perform(withItems: [body])
    }

    private final class SharingDelegate: NSObject, NSSharingServiceDelegate {
        private let completion: (Bool) -> Void
        init(completion: @escaping (Bool) -> Void) { self.completion = completion }

        func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
            completion(true)
            clearAssociation(from: sharingService)
        }
        func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
            completion(false)
            clearAssociation(from: sharingService)
        }
        private func clearAssociation(from service: NSSharingService) {
            objc_removeAssociatedObjects(service)
        }
    }
}
#endif
