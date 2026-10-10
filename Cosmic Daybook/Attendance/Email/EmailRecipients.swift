// EmailRecipients.swift
// The addresses in what the guide typed into an address field, for every
// email the apps compose. Shared with the Daybook Assistant (its front-desk
// email reads the same recipients).

import Foundation

extension AttendanceEmail {
    /// What was typed into an address field: the email addresses in it, and
    /// the entries that aren't one.
    public struct Recipients: Equatable, Sendable {
        public var addresses: [String] = []
        public var leftOut: [String] = []
    }

    /// The addresses in what was typed, in order. Commas, semicolons, spaces
    /// and new lines all separate them; only address-shaped entries count
    /// ("name@site.org"), with any "<…>" or quotes around them dropped.
    /// Every email the apps compose (attendance, order requests, the
    /// Assistant's front desk) reads its recipients through this.
    public static func parseRecipients(from string: String?) -> [String] {
        checkRecipients(string).addresses
    }

    /// The addresses in what was typed, and what was left out.
    public static func checkRecipients(_ string: String?) -> Recipients {
        var result = Recipients()
        guard let string else { return result }
        let separators = CharacterSet(charactersIn: ",;").union(.whitespacesAndNewlines)
        let wrapping = CharacterSet(charactersIn: "<>\"'()[]")
        for entry in string.components(separatedBy: separators) where !entry.isEmpty {
            var address = entry.trimmingCharacters(in: wrapping)
            if address.lowercased().hasPrefix("mailto:") { address = String(address.dropFirst(7)) }
            if isAddress(address) {
                result.addresses.append(address)
            } else {
                result.leftOut.append(entry)
            }
        }
        return result
    }

    /// The plain line Settings shows under an address field when some of
    /// what was typed isn't an address; nil when it all is.
    public static func leftOutNote(for string: String?) -> String? {
        let leftOut = checkRecipients(string).leftOut.map { "“\($0)”" }
        guard let first = leftOut.first, let last = leftOut.last else { return nil }
        if leftOut.count == 1 {
            return "\(first) isn't an email address, so no email goes to it."
        }
        let list = leftOut.dropLast().joined(separator: ", ") + " and " + last
        return "\(list) aren't email addresses, so no email goes to them."
    }

    /// One "@" with something before it, and after it a site with a dot and
    /// an ending of two or more letters: "office@school.org".
    static func isAddress(_ text: String) -> Bool {
        let parts = text.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, let local = parts.first, let site = parts.last, !local.isEmpty else {
            return false
        }
        let labels = site.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count > 1, labels.allSatisfy({ !$0.isEmpty }), let ending = labels.last,
              ending.count >= 2, ending.allSatisfy(\.isLetter) else { return false }
        return site.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." }
    }
}
