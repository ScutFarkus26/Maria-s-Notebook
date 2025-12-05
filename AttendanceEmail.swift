import Foundation
import SwiftUI

#if os(macOS)
import AppKit
import ObjectiveC
#endif

// MARK: - Settings Keys
public enum AttendanceEmailPrefs {
    public static let enabledKey = "AttendanceEmail.enabled"
    public static let toKey = "AttendanceEmail.to"
    public static let fromKey = "AttendanceEmail.from" // iOS preferred sending address
}

// MARK: - Report Generator
public struct AttendanceEmailReport {
    public static func makeSubject(for date: Date, calendar: Calendar = .current) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return "Attendance • \(df.string(from: calendar.startOfDay(for: date)))"
    }

    public static func makeBody(present: [String], tardy: [String], absent: [String], date: Date, calendar: Calendar = .current) -> String {
        let df = DateFormatter()
        df.dateStyle = .full
        df.timeStyle = .none
        var lines: [String] = []
        lines.append("Attendance Report")
        lines.append(df.string(from: calendar.startOfDay(for: date)))
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
        section("Present", names: present)
        section("Tardy", names: tardy)
        section("Absent", names: absent)
        return lines.joined(separator: "\n")
    }
}

/**
 Convenience helpers to read stored preferences and create prefilled mail senders.
 */
public enum AttendanceEmail {
    public static func storedToAddress() -> String? {
        let s = UserDefaults.standard.string(forKey: AttendanceEmailPrefs.toKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let s, !s.isEmpty else { return nil }
        return s
    }

    public static func storedFromAddress() -> String? {
        let s = UserDefaults.standard.string(forKey: AttendanceEmailPrefs.fromKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let s, !s.isEmpty else { return nil }
        return s
    }

    public static func makeSubject(for date: Date, calendar: Calendar = .current) -> String {
        AttendanceEmailReport.makeSubject(for: date, calendar: calendar)
    }

    public static func makeBody(present: [String], tardy: [String], absent: [String], date: Date, calendar: Calendar = .current) -> String {
        AttendanceEmailReport.makeBody(present: present, tardy: tardy, absent: absent, date: date, calendar: calendar)
    }

    #if os(iOS)
    public static func composerForCurrentPrefs(present: [String], tardy: [String], absent: [String], date: Date = Date(), calendar: Calendar = .current, onComplete: @escaping (MFMailComposeResult, Error?) -> Void) -> MailComposerView {
        let subject = makeSubject(for: date, calendar: calendar)
        let body = makeBody(present: present, tardy: tardy, absent: absent, date: date, calendar: calendar)
        let to = storedToAddress().map { [$0] } ?? []
        let from = storedFromAddress()
        return MailComposerView(toRecipients: to, subject: subject, body: body, preferredSender: from, onComplete: onComplete)
    }
    #endif

    #if os(macOS)
    public static func sendUsingMailAppForCurrentPrefs(present: [String], tardy: [String], absent: [String], date: Date = Date(), calendar: Calendar = .current, completion: @escaping (Bool) -> Void) {
        let subject = makeSubject(for: date, calendar: calendar)
        let body = makeBody(present: present, tardy: tardy, absent: absent, date: date, calendar: calendar)
        MacOSMailSender.send(to: storedToAddress(), subject: subject, body: body, completion: completion)
    }
    #endif
}

// MARK: - Settings View
public struct AttendanceEmailSettingsView: View {
    @AppStorage(AttendanceEmailPrefs.enabledKey) private var enabled: Bool = true
    @AppStorage(AttendanceEmailPrefs.toKey) private var toAddress: String = ""
    @AppStorage(AttendanceEmailPrefs.fromKey) private var fromAddress: String = ""

    public init() {}

    public var body: some View {
        Form {
            Section("Attendance Email") {
                Toggle("Show 'Send Attendance Email' Button", isOn: $enabled)
                TextField("Send To", text: $toAddress)
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
                #endif
                Text("Note: iOS uses the preferred address when possible. macOS uses your default Mail account.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - iOS Mail Composer Wrapper
#if os(iOS)
import MessageUI

public struct MailComposerView: UIViewControllerRepresentable {
    public typealias UIViewControllerType = MFMailComposeViewController

    public var toRecipients: [String]
    public var subject: String
    public var body: String
    public var preferredSender: String?
    public var onComplete: (MFMailComposeResult, Error?) -> Void

    public init(toRecipients: [String], subject: String, body: String, preferredSender: String?, onComplete: @escaping (MFMailComposeResult, Error?) -> Void) {
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
        if let preferred = preferredSender, !preferred.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            vc.setPreferredSendingEmailAddress(preferred)
        }
        return vc
    }

    public func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) { }

    public func makeCoordinator() -> Coordinator { Coordinator(onComplete: onComplete) }

    public final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onComplete: (MFMailComposeResult, Error?) -> Void
        init(onComplete: @escaping (MFMailComposeResult, Error?) -> Void) { self.onComplete = onComplete }
        public func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            onComplete(result, error)
            controller.dismiss(animated: true)
        }
    }
}
#endif

// MARK: - macOS Mail Sender Helper
#if os(macOS)
public enum MacOSMailSender {
    public static func send(to recipient: String?, subject: String, body: String, completion: @escaping (Bool) -> Void) {
        guard let service = NSSharingService(named: .composeEmail) else {
            completion(false)
            return
        }
        if let r = recipient, !r.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            service.recipients = [r]
        }
        service.subject = subject
        let delegate = SharingDelegate { success in
            completion(success)
        }
        service.delegate = delegate
        // Keep the delegate alive until completion by retaining it on the service via associated object.
        objc_setAssociatedObject(service, Unmanaged.passUnretained(delegate).toOpaque(), delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
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

