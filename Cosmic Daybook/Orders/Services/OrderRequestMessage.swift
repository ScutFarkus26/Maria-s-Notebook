// OrderRequestMessage.swift
// Who order requests go to, and the email that asks for the items.

import Foundation

/// Preference keys for order requests. Synced across devices through
/// `SyncedPreferencesStore` and carried in backups.
enum OrderRequestPrefs {
    static let recipientNameKey = "Orders.recipientName"
    static let recipientEmailKey = "Orders.recipientEmail"
    static let signOffNameKey = "Orders.signOffName"
}

/// The person order requests go to.
struct OrderRequestRecipient: Equatable, Sendable {
    var name: String
    var email: String

    static func stored() -> OrderRequestRecipient {
        let store = SyncedPreferencesStore.shared
        return OrderRequestRecipient(
            name: store.string(forKey: OrderRequestPrefs.recipientNameKey)?.trimmed() ?? "",
            email: store.string(forKey: OrderRequestPrefs.recipientEmailKey)?.trimmed() ?? ""
        )
    }

    /// Every address in the email field — commas or semicolons separate several.
    var emails: [String] { AttendanceEmail.parseRecipients(from: email) }

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

    init(_ item: CDOrderItem) {
        self.init(
            title: item.displayTitle,
            link: item.urlString,
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

    /// A numbered list, each item's link on the line under its name. Mail sends
    /// plain text in a proportional font, so blank lines carry the structure.
    static func body(for lines: [OrderRequestLine], recipientName: String, signOff: String) -> String {
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
        // Always stated, even for one: the office should never have to ask how many.
        var block = [
            "\(number). \(line.title.trimmed())",
            "\(indent)Quantity: \(max(1, line.quantity))"
        ]
        let link = line.link.trimmed()
        if !link.isEmpty {
            block.append(indent + link)
        }
        let notes = line.notes.trimmed()
        if !notes.isEmpty {
            block.append("\(indent)Note: \(notes)")
        }
        return block
    }
}
