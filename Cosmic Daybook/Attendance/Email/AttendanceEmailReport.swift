import Foundation
import SwiftUI

// The attendance email's text and the pieces that send it, shared with the
// Daybook Assistant (compiled there by path) so an assistant's email to the
// front desk reads exactly like the guide's. The guide's own settings and the
// Mac's Mail sender stay in the notebook (`AttendanceEmail+Prefs.swift`,
// `AttendanceEmail.swift`).

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
    /// Names sit one step in from the heading above them. Mail sends the report as plain
    /// text in a proportional font, where indentation reads faintly, so the layout leans on
    /// blank lines and capitalization to carry the hierarchy.
    private static let nameIndent = "    "

    /// "Jan 15, 2024", for the subject. Kept here rather than borrowed from
    /// `DateFormatters` because the Daybook Assistant compiles this file too.
    private static let subjectFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    /// "Monday, January 15, 2024", under the report's title.
    private static let headerFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter
    }()

    public static func makeSubject(
        for date: Date,
        calendar: Calendar = .current
    ) -> String {
        let dayStr = subjectFormatter.string(from: calendar.startOfDay(for: date))
        return "Attendance \u{2022} \(dayStr)"
    }

    public static func makeBody(
        present: [AttendanceEmailStudent],
        tardy: [AttendanceEmailStudent],
        absent: [AttendanceEmailStudent],
        leftEarly: [AttendanceEmailStudent] = [],
        date: Date,
        calendar: Calendar = .current,
        nameOrder: AttendanceEmailNameOrder = .firstLast,
        groupByLevel: Bool = false
    ) -> String {
        let header = [
            "Attendance Report",
            headerFormatter.string(from: calendar.startOfDay(for: date))
        ]
        // Left Early appears only on a day someone left, so an ordinary day's report
        // doesn't gain a "(0) None" section.
        let statuses: [StatusList] = [
            StatusList(title: "On Time", students: present),
            StatusList(title: "Tardy", students: tardy),
            StatusList(title: "Left Early", students: leftEarly, optional: true),
            StatusList(title: "Absent", students: absent)
        ].filter { !$0.optional || !$0.students.isEmpty }
        let body: [String]
        let levels = groupByLevel ? levelBlocks(statuses, nameOrder: nameOrder) : []
        if levels.isEmpty {
            // Also the path when grouping is on but nobody is on the roster today, which
            // would otherwise leave the report with no lists under its date at all.
            body = stack(
                statuses.map {
                    statusBlock($0.title.uppercased(), students: $0.students, nameOrder: nameOrder)
                },
                gap: 1
            )
        } else {
            // Two blank lines between levels against one inside them, so each class reads whole.
            body = stack(levels, gap: 2)
        }
        return stack([header, body], gap: 1).joined(separator: "\n")
    }

    /// A titled list of students; an `optional` one is left out wherever it would be empty.
    struct StatusList {
        let title: String
        let students: [AttendanceEmailStudent]
        var optional = false
    }

    /// One block per level anyone is in today: the level's name over its own On Time,
    /// Tardy, and Absent lists, so a reader sees each class whole instead of hunting
    /// through three separate lists for it.
    private static func levelBlocks(
        _ statuses: [StatusList],
        nameOrder: AttendanceEmailNameOrder
    ) -> [[String]] {
        levelsAttending(statuses.map { (title: $0.title, students: $0.students) }).map { level in
            let sections: [[String]] = statuses.compactMap { status in
                let students = status.students.filter { $0.level == level.level }
                if status.optional && students.isEmpty { return nil }
                return statusBlock(status.title, students: students, nameOrder: nameOrder)
            }
            return stack([[level.title.uppercased()]] + sections, gap: 1)
        }
    }

    /// A heading with its count over the names under it, or "None" when nobody is in it.
    private static func statusBlock(
        _ title: String,
        students: [AttendanceEmailStudent],
        nameOrder: AttendanceEmailNameOrder
    ) -> [String] {
        let heading = "\(title) (\(students.count))"
        guard !students.isEmpty else { return [heading, "\(nameIndent)None"] }
        return [heading] + sorted(students, by: nameOrder).map {
            "\(nameIndent)\u{2022} \($0.name(order: nameOrder))"
        }
    }

    /// Stacks blocks of lines with `gap` blank lines between them. Empty blocks drop out,
    /// so a level nobody is in can't leave a hole in the spacing.
    private static func stack(_ blocks: [[String]], gap: Int) -> [String] {
        Array(blocks.filter { !$0.isEmpty }.joined(separator: Array(repeating: "", count: gap)))
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

    /// The levels to write up, in report order, skipping any nobody is in today. A student
    /// whose level isn't one the report knows about lands in a trailing "Other" group
    /// rather than vanishing.
    static func levelsAttending(
        _ statuses: [(title: String, students: [AttendanceEmailStudent])]
    ) -> [(title: String, level: AttendanceEmailLevel?)] {
        let everyone = statuses.flatMap(\.students)
        var levels: [(title: String, level: AttendanceEmailLevel?)] =
            AttendanceEmailLevel.allCases.map { (title: $0.title, level: $0) }
        levels.append((title: "Other", level: nil))
        return levels.filter { level in everyone.contains { $0.level == level.level } }
    }
}

/// One attendance email, ready for Mail: who it goes to and what it says.
/// Identifiable so a screen can present its composer with `sheet(item:)`.
public struct AttendanceEmailDraft: Identifiable, Sendable {
    public let id = UUID()
    public let recipients: [String]
    public let subject: String
    public let body: String

    /// For Mail apps other than Apple's, when the composer isn't available.
    public var mailtoURL: URL? {
        AttendanceEmail.makeMailtoURL(to: recipients, subject: subject, body: body)
    }
}

/// Recipients and mailto links, shared by every email the apps compose.
public enum AttendanceEmail {
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
