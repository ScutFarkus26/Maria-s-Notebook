// OrderLinkCleaner.swift
// Product links trimmed to the page itself, and page titles cut to the name a
// person would say. An Amazon search result's link carries ~500 characters of
// tracking, and the office email used to print every one of them.

import Foundation

nonisolated enum OrderLinkCleaner {

    /// Query parameters that only say where a click came from. `utm_*` goes too.
    static let trackingParameters: Set<String> = [
        "fbclid", "gclid", "gclsrc", "dclid", "gbraid", "wbraid", "msclkid", "yclid", "twclid", "ttclid",
        "igshid", "mc_cid", "mc_eid", "_hsenc", "_hsmi", "mkt_tok", "srsltid", "_gl"
    ]

    /// How long a title may run before `shortTitle` looks for a place to cut it.
    static let shortTitleLimit = 60

    // MARK: - Links

    /// The link as it is stored and printed. An Amazon product page
    /// (`/dp/ASIN`, `/gp/product/ASIN`) becomes `https://www.amazon.com/dp/ASIN`;
    /// anywhere else only tracking parameters go, and the rest of the link is
    /// left exactly as it was. Text that isn't a web link comes back trimmed.
    /// Runs when a link is added and when the request email is built, so links
    /// stored before it existed print clean too.
    static func clean(_ link: String) -> String {
        let trimmed = link.trimmed()
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host?.lowercased(), !host.isEmpty else { return trimmed }
        if let asin = amazonProductID(host: host, path: components.path) {
            return "https://www.amazon.com/dp/\(asin)"
        }
        // Percent-encoded, so what stays is byte for byte what was there.
        guard let items = components.percentEncodedQueryItems, !items.isEmpty else { return trimmed }
        let kept = items.filter { !isTracking($0.name) }
        guard kept.count != items.count else { return trimmed }
        components.percentEncodedQueryItems = kept.isEmpty ? nil : kept
        return components.string ?? trimmed
    }

    /// The product's ASIN when `host` is Amazon's US store and `path` names a
    /// product page, upper-cased.
    static func amazonProductID(host: String, path: String) -> String? {
        guard host == "amazon.com" || host.hasSuffix(".amazon.com") else { return nil }
        let parts = path.split(separator: "/").map(String.init)
        for (index, part) in parts.enumerated() {
            let candidate: String?
            switch part.lowercased() {
            case "dp":
                candidate = index + 1 < parts.count ? parts[index + 1] : nil
            case "gp" where index + 2 < parts.count && parts[index + 1].lowercased() == "product":
                candidate = parts[index + 2]
            default:
                candidate = nil
            }
            if let candidate, isASIN(candidate) { return candidate.uppercased() }
        }
        return nil
    }

    /// Ten letters and digits: Amazon's product number (an ISBN-10 for books).
    private static func isASIN(_ text: String) -> Bool {
        text.count == 10 && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    private static func isTracking(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return lowered.hasPrefix("utm_") || trackingParameters.contains(lowered)
    }

    // MARK: - Titles

    /// A page title cut to a name: the text before the first " | ", and when
    /// that is still over 60 characters, the text before the last ", " or " - "
    /// that starts within the first 60. A title with no such break stays whole.
    /// The result is only a starting point: the guide can edit it.
    ///
    /// "Anker Nano Phone Charger, 30W Portble and Foldable USB C GaN Charger |
    /// For iPhone 18 Pro/17/…" → "Anker Nano Phone Charger".
    static func shortTitle(_ title: String) -> String {
        let whole = title.trimmed()
        let head = whole.components(separatedBy: " | ").first?.trimmed() ?? ""
        let short = head.isEmpty ? whole : head
        guard short.count > shortTitleLimit else { return short }

        let limit = short.index(short.startIndex, offsetBy: shortTitleLimit)
        var cut: String.Index?
        for separator in [", ", " - "] {
            // The separator must start before the limit; it may end just past it.
            let searchEnd = short.index(limit, offsetBy: separator.count - 1, limitedBy: short.endIndex)
                ?? short.endIndex
            guard let found = short.range(of: separator, options: .backwards, range: short.startIndex..<searchEnd),
                  found.lowerBound > short.startIndex else { continue }
            cut = max(cut ?? found.lowerBound, found.lowerBound)
        }
        guard let cut else { return short }
        return String(short[..<cut]).trimmed()
    }
}
