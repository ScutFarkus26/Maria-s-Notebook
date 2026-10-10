// OrderRequestMessage.swift
// Who order requests go to, and the email that asks for the items.

import Foundation

/// Preference keys for order requests. Synced across devices through
/// `SyncedPreferencesStore` and carried in backups.
enum OrderRequestPrefs {
    static let recipientNameKey = "Orders.recipientName"
    static let recipientEmailKey = "Orders.recipientEmail"
    static let signOffNameKey = "Orders.signOffName"
    static let ccEmailKey = "Orders.ccEmail"
    /// The guide's own wording for the email. Empty means the standard message.
    static let messageTemplateKey = "Orders.messageTemplate"
}

/// The person order requests go to.
struct OrderRequestRecipient: Equatable, Sendable {
    var name: String
    var email: String
    /// Copied on every request: commas or semicolons separate several.
    var cc: String = ""

    static func stored() -> OrderRequestRecipient {
        let store = SyncedPreferencesStore.shared
        return OrderRequestRecipient(
            name: store.string(forKey: OrderRequestPrefs.recipientNameKey)?.trimmed() ?? "",
            email: store.string(forKey: OrderRequestPrefs.recipientEmailKey)?.trimmed() ?? "",
            cc: store.string(forKey: OrderRequestPrefs.ccEmailKey)?.trimmed() ?? ""
        )
    }

    /// Every address in the email field — commas or semicolons separate several.
    var emails: [String] { AttendanceEmail.parseRecipients(from: email) }

    /// Every CC address, leaving out any already in To.
    var ccEmails: [String] {
        let to = Set(emails.map { $0.lowercased() })
        return AttendanceEmail.parseRecipients(from: cc).filter { !to.contains($0.lowercased()) }
    }

    var isConfigured: Bool { !emails.isEmpty }

    /// What the list shows as "asked": the name when there is one.
    var label: String { name.isEmpty ? email : name }
}

/// One item as the request email writes it.
struct OrderRequestLine: Equatable, Sendable {
    var title: String
    var link: String
    var quantity: Int
    var notes: String

    init(title: String, link: String, quantity: Int, notes: String) {
        self.title = title
        self.link = link
        self.quantity = quantity
        self.notes = notes
    }

    /// The item as the email prints it: its link trimmed to the product page
    /// and its title cut to a name (`OrderLinkCleaner`), however they were stored.
    init(_ item: CDOrderItem) {
        self.init(
            title: OrderLinkCleaner.shortTitle(item.displayTitle),
            link: OrderLinkCleaner.clean(item.urlString),
            quantity: Int(item.quantity),
            notes: item.notes
        )
    }
}

/// Builds the request email. Pure, so the wording is pinned by tests.
enum OrderRequestMessage {

    static func subject(for lines: [OrderRequestLine]) -> String {
        switch lines.count {
        case 0: return "Order request"
        case 1: return "Order request: \(lines[0].title)"
        default: return "Order request: \(lines.count) items"
        }
    }

    /// The words the guide can put in their own message, filled in when the
    /// email is written.
    enum Placeholder {
        static let name = "[Name]"
        static let items = "[Items]"
        static let signOff = "[Your name]"
    }

    /// The standard message written with placeholders, as Settings shows it
    /// before the guide changes anything.
    static let standardTemplate = """
        Hi \(Placeholder.name),

        Could you please order these for my classroom?

        \(Placeholder.items)

        Thank you!
        \(Placeholder.signOff)
        """

    /// The email body. With no `template` (or the standard one) it's the
    /// standard message, which says "this" or "these" to fit the count; with
    /// the guide's own template, the placeholders are filled in and the items
    /// are added at the end if the template leaves `[Items]` out.
    static func body(
        for lines: [OrderRequestLine],
        recipientName: String,
        signOff: String,
        template: String = ""
    ) -> String {
        let custom = template.trimmed()
        guard !custom.isEmpty, custom != standardTemplate.trimmed() else {
            return standardBody(for: lines, recipientName: recipientName, signOff: signOff)
        }
        return fill(custom, lines: lines, recipientName: recipientName, signOff: signOff)
    }

    private static func itemsText(for lines: [OrderRequestLine]) -> String {
        lines.enumerated()
            .map { index, line in itemBlock(number: index + 1, line: line).joined(separator: "\n") }
            .joined(separator: "\n\n")
    }

    private static func fill(
        _ template: String,
        lines: [OrderRequestLine],
        recipientName: String,
        signOff: String
    ) -> String {
        let name = recipientName.trimmed()
        let signature = signOff.trimmed()
        var text = template
        if name.isEmpty {
            // "Hi [Name]," reads "Hi," rather than "Hi ,".
            text = text.replacingOccurrences(of: " " + Placeholder.name, with: "", options: .caseInsensitive)
        }
        text = text.replacingOccurrences(of: Placeholder.name, with: name, options: .caseInsensitive)
        text = text.replacingOccurrences(of: Placeholder.signOff, with: signature, options: .caseInsensitive)

        let items = itemsText(for: lines)
        if text.range(of: Placeholder.items, options: .caseInsensitive) != nil {
            text = text.replacingOccurrences(of: Placeholder.items, with: items, options: .caseInsensitive)
        } else if !items.isEmpty {
            text = text.trimmed() + "\n\n" + items
        }
        return text.trimmed()
    }

    /// A numbered list, each item's link beside its name. Mail sends
    /// plain text in a proportional font, so blank lines carry the structure.
    private static func standardBody(for lines: [OrderRequestLine], recipientName: String, signOff: String) -> String {
        let name = recipientName.trimmed()
        let greeting = name.isEmpty ? "Hi," : "Hi \(name),"
        let ask = lines.count == 1
            ? "Could you please order this for my classroom?"
            : "Could you please order these for my classroom?"

        let items = lines.enumerated().map { index, line in
            itemBlock(number: index + 1, line: line)
        }

        var closing = ["Thank you!"]
        let signature = signOff.trimmed()
        if !signature.isEmpty { closing.append(signature) }

        let blocks: [[String]] = [[greeting], [ask]] + items + [closing]
        return blocks.map { $0.joined(separator: "\n") }.joined(separator: "\n\n")
    }

    private static let indent = "    "

    private static func itemBlock(number: Int, line: OrderRequestLine) -> [String] {
        // The link sits beside the name, so each line says what it opens.
        let link = line.link.trimmed()
        let heading = link.isEmpty
            ? "\(number). \(line.title.trimmed())"
            : "\(number). \(line.title.trimmed()) \u{2014} \(link)"
        // Always stated, even for one: the office should never have to ask how many.
        var block = [heading, "\(indent)Quantity: \(max(1, line.quantity))"]
        let notes = line.notes.trimmed()
        if !notes.isEmpty {
            block.append("\(indent)Note: \(notes)")
        }
        return block
    }
}
