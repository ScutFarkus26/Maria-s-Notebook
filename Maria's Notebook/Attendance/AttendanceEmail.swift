// swiftlint:disable file_length
import Foundation
import SwiftUI
import OSLog

#if os(macOS)
import AppKit
import ObjectiveC
#endif

/// Preference keys for Attendance Email feature.
/// - CDNote: Values are stored in UserDefaults via @AppStorage.
public enum AttendanceEmailPrefs {
    public static let enabledKey = "AttendanceEmail.enabled"
    public static let toKey = "AttendanceEmail.to"
    public static let fromKey = "AttendanceEmail.from" // iOS preferred sending address
    public static let nameOrderKey = "AttendanceEmail.nameOrder"
    public static let groupByLevelKey = "AttendanceEmail.groupByLevel"
}

// MARK: - Report Formatting

/// How each student's name is written — and sorted — in the report body.
public enum AttendanceEmailNameOrder: String, CaseIterable, Identifiable, Sendable {
    case firstLast
    case lastFirst

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .firstLast: return "First Last"
        case .lastFirst: return "Last, First"
        }
    }
}

/// The levels the report groups by, listed in the order their groups appear.
/// - CDNote: Raw values match `CDStudent.Level`, so a student's level maps straight across.
///   Lower Elementary trails because that class transferred out; any straggler belongs last.
public enum AttendanceEmailLevel: String, CaseIterable, Sendable {
    case upper = "Upper"
    case adolescent = "Adolescent"
    case lower = "Lower"

    public var title: String {
        switch self {
        case .upper: return "Upper Elementary"
        case .adolescent: return "Adolescent"
        case .lower: return "Lower Elementary"
        }
    }
}

/// One student on the report. The name stays split so the body can reorder and group it.
public struct AttendanceEmailStudent: Sendable, Hashable {
    public let firstName: String
    public let lastName: String
    /// nil when the student's level isn't one the report groups by.
    public let level: AttendanceEmailLevel?

    public init(firstName: String, lastName: String, level: AttendanceEmailLevel?) {
        self.firstName = firstName
        self.lastName = lastName
        self.level = level
    }

    /// The name written in the requested order, tolerating a missing half.
    public func name(order: AttendanceEmailNameOrder) -> String {
        let first = firstName.trimmed()
        let last = lastName.trimmed()
        guard !first.isEmpty else { return last }
        guard !last.isEmpty else { return first }
        switch order {
        case .firstLast: return "\(first) \(last)"
        case .lastFirst: return "\(last), \(first)"
        }
    }
}

extension AttendanceEmailStudent {
    init(_ student: CDStudent) {
        self.init(
            firstName: student.firstName,
            lastName: student.lastName,
            level: AttendanceEmailLevel(rawValue: student.level.rawValue)
        )
    }
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
        present: [AttendanceEmailStudent],
        tardy: [AttendanceEmailStudent],
        absent: [AttendanceEmailStudent],
        date: Date,
        calendar: Calendar = .current,
        nameOrder: AttendanceEmailNameOrder = .firstLast,
        groupByLevel: Bool = false
    ) -> String {
        var lines: [String] = []
        lines.append("Attendance Report")
        lines.append(DateFormatters.fullDate.string(from: calendar.startOfDay(for: date)))
        lines.append("")
        for (title, students) in [("On Time", present), ("Tardy", tardy), ("Absent", absent)] {
            lines += sectionLines(
                title,
                students: students,
                nameOrder: nameOrder,
                groupByLevel: groupByLevel
            )
        }
        return lines.joined(separator: "\n")
    }

    private static func sectionLines(
        _ title: String,
        students: [AttendanceEmailStudent],
        nameOrder: AttendanceEmailNameOrder,
        groupByLevel: Bool
    ) -> [String] {
        var lines = ["\(title) (\(students.count)):"]
        if students.isEmpty {
            lines.append("  — none —")
        } else if groupByLevel {
            for group in grouped(students, by: nameOrder) {
                lines.append("  \(group.title) (\(group.students.count)):")
                lines += group.students.map { "    • \($0.name(order: nameOrder))" }
            }
        } else {
            lines += sorted(students, by: nameOrder).map { "  • \($0.name(order: nameOrder))" }
        }
        lines.append("")
        return lines
    }

    /// Sorts on the field the chosen name order leads with, so the list reads in order.
    static func sorted(
        _ students: [AttendanceEmailStudent],
        by order: AttendanceEmailNameOrder
    ) -> [AttendanceEmailStudent] {
        let lead: KeyPath<AttendanceEmailStudent, String>
        let follow: KeyPath<AttendanceEmailStudent, String>
        switch order {
        case .firstLast: (lead, follow) = (\.firstName, \.lastName)
        case .lastFirst: (lead, follow) = (\.lastName, \.firstName)
        }
        return students.sorted { lhs, rhs in
            let leading = lhs[keyPath: lead].localizedCaseInsensitiveCompare(rhs[keyPath: lead])
            if leading != .orderedSame { return leading == .orderedAscending }
            return lhs[keyPath: follow].localizedCaseInsensitiveCompare(rhs[keyPath: follow]) == .orderedAscending
        }
    }

    /// Level groups in report order, dropping levels nobody is in. A student whose level
    /// isn't one the report knows about lands in a trailing "Other" group rather than vanishing.
    static func grouped(
        _ students: [AttendanceEmailStudent],
        by order: AttendanceEmailNameOrder
    ) -> [(title: String, students: [AttendanceEmailStudent])] {
        var groups = AttendanceEmailLevel.allCases.map { level in
            (title: level.title, students: sorted(students.filter { $0.level == level }, by: order))
        }
        groups.append((title: "Other", students: sorted(students.filter { $0.level == nil }, by: order)))
        return groups.filter { !$0.students.isEmpty }
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

    /// Falls back to "First Last" so an unset preference reads the way the report always has.
    public static func storedNameOrder() -> AttendanceEmailNameOrder {
        let raw = SyncedPreferencesStore.shared.string(forKey: AttendanceEmailPrefs.nameOrderKey)
        return raw.flatMap(AttendanceEmailNameOrder.init(rawValue:)) ?? .firstLast
    }

    public static func storedGroupByLevel() -> Bool {
        SyncedPreferencesStore.shared.bool(forKey: AttendanceEmailPrefs.groupByLevelKey)
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
    /// - CDNote: Multi-recipient support is implemented and used in
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

    /// Builds the body using the teacher's stored name-order and grouping preferences.
    public static func makeBody(
        present: [AttendanceEmailStudent],
        tardy: [AttendanceEmailStudent],
        absent: [AttendanceEmailStudent],
        date: Date,
        calendar: Calendar = .current
    ) -> String {
        AttendanceEmailReport.makeBody(
            present: present,
            tardy: tardy,
            absent: absent,
            date: date,
            calendar: calendar,
            nameOrder: storedNameOrder(),
            groupByLevel: storedGroupByLevel()
        )
    }

    /// Builds a mailto: URL with the provided recipients, subject, and body.
    /// - CDNote: Useful as a fallback when `isAvailable` is false.
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

    #if os(iOS)
    /// Creates a prefilled mail composer using current preferences.
    /// - Important: Check `AttendanceEmail.isAvailable` before
    ///   presenting. If unavailable, consider using
    ///   `mailtoURLForCurrentPrefs(...)` as a fallback.
    public static func composerForCurrentPrefs(
        present: [AttendanceEmailStudent],
        tardy: [AttendanceEmailStudent],
        absent: [AttendanceEmailStudent],
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
        present: [AttendanceEmailStudent],
        tardy: [AttendanceEmailStudent],
        absent: [AttendanceEmailStudent],
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
    /// - CDNote: Use this as a fallback when
    ///   NSSharingService(.composeEmail) is unavailable.
    public static func openMailtoFallbackForCurrentPrefs(
        present: [AttendanceEmailStudent],
        tardy: [AttendanceEmailStudent],
        absent: [AttendanceEmailStudent],
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

    #endif
}

// MARK: - Settings View

/// Settings form for configuring Attendance Email behavior.
/// - CDNote: The "Preferred 'From' Address" applies to iOS only;
///   macOS always uses the default Mail account.
public struct AttendanceEmailSettingsView: View {
    @SyncedAppStorage(AttendanceEmailPrefs.enabledKey) private var enabled: Bool = true
    @SyncedAppStorage(AttendanceEmailPrefs.toKey) private var toAddress: String = ""
    @SyncedAppStorage(AttendanceEmailPrefs.fromKey) private var fromAddress: String = ""
    @SyncedAppStorage(AttendanceEmailPrefs.groupByLevelKey) private var groupByLevel: Bool = false
    @SyncedAppStorage(AttendanceEmailPrefs.nameOrderKey)
    private var nameOrderRaw: String = AttendanceEmailNameOrder.firstLast.rawValue

    public init() {}

    /// SyncedAppStorage stores primitives, so the picker reads and writes the raw value.
    private var nameOrder: Binding<AttendanceEmailNameOrder> {
        Binding(
            get: { AttendanceEmailNameOrder(rawValue: nameOrderRaw) ?? .firstLast },
            set: { nameOrderRaw = $0.rawValue }
        )
    }

    private var nameOrderPicker: some View {
        Picker("Name order", selection: nameOrder) {
            ForEach(AttendanceEmailNameOrder.allCases) { order in
                Text(order.title).tag(order)
            }
        }
    }

    private var groupingFootnote: some View {
        Text("Grouping lists Upper Elementary first, then Adolescents.")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    public var body: some View {
        platformBody
            .onChange(of: enabled) { _, _ in SettingsCategory.markModified(.communication) }
            .onChange(of: toAddress) { _, _ in SettingsCategory.markModified(.communication) }
            .onChange(of: fromAddress) { _, _ in SettingsCategory.markModified(.communication) }
            .onChange(of: nameOrderRaw) { _, _ in SettingsCategory.markModified(.communication) }
            .onChange(of: groupByLevel) { _, _ in SettingsCategory.markModified(.communication) }
    }

    @ViewBuilder
    private var platformBody: some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("Attendance email") {
                Toggle("Enabled", isOn: $enabled)
                    .labelsHidden()
            }
            LabeledContent("Send to") {
                TextField("Email addresses", text: $toAddress)
                    .frame(minWidth: 260)
            }
            LabeledContent("From account") {
                Text("Default Mail account")
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Name order") {
                nameOrderPicker
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)
            }
            LabeledContent("Group by level") {
                Toggle("Group by level", isOn: $groupByLevel)
                    .labelsHidden()
            }
            groupingFootnote
            Text("You can enter multiple addresses separated by commas or semicolons.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        #else
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
            Section("Report Format") {
                nameOrderPicker
                Toggle("Group by Level", isOn: $groupByLevel)
                groupingFootnote
            }
        }
        #endif
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

    /// A file to attach to the composed message.
    public struct Attachment {
        public let data: Data
        public let mimeType: String
        public let fileName: String

        public init(data: Data, mimeType: String, fileName: String) {
            self.data = data
            self.mimeType = mimeType
            self.fileName = fileName
        }
    }

    public var toRecipients: [String]
    public var subject: String
    public var body: String
    public var preferredSender: String?
    public var attachments: [Attachment]
    public var onComplete: (MFMailComposeResult, Error?) -> Void

    public init(
        toRecipients: [String],
        subject: String,
        body: String,
        preferredSender: String?,
        attachments: [Attachment] = [],
        onComplete: @escaping (MFMailComposeResult, Error?) -> Void
    ) {
        self.toRecipients = toRecipients
        self.subject = subject
        self.body = body
        self.preferredSender = preferredSender
        self.attachments = attachments
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
        for attachment in attachments {
            vc.addAttachmentData(
                attachment.data,
                mimeType: attachment.mimeType,
                fileName: attachment.fileName
            )
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

#if os(macOS)
@MainActor
public enum MacOSMailSender {
    private static let logger = Logger.attendance
    public static func send(
        to recipient: String?,
        subject: String,
        body: String,
        attachmentURL: URL? = nil,
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
        var items: [Any] = [body]
        if let attachmentURL {
            items.append(attachmentURL)
        }
        service.perform(withItems: items)
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
