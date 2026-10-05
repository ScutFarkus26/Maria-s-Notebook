import Foundation
import CoreData

// What the Restock tab says: who changed a staple and when, the hold menu's
// header, and what she typed into "We need…".

extension AssistantRestockModel {

    // MARK: - What she typed

    /// What she typed, without the period (or comma, or other mark) that
    /// ends a sentence: "Kleenex." is Kleenex.
    static func entry(_ text: String) -> String {
        var entry = text.trimmed()
        while let last = entry.last, ".,;:!?…".contains(last) {
            entry = String(entry.dropLast()).trimmed()
        }
        return entry
    }

    /// A pasted web link ("amazon.com/dp/…", "https://…"); nil for a name.
    /// Without "://" it needs a site with a real ending: "Glue" would
    /// otherwise read as https://Glue, and "Mr.Sketch" as a site.
    static func pastedLink(_ text: String) -> URL? {
        let entry = entry(text)
        guard entry.contains("://") || hasSiteEnding(entry) else { return nil }
        return OrderService.webURL(from: entry)
    }

    /// Whether the text before any "/" is a site: words joined by dots,
    /// the last a common ending (.com, .shop…) or a country's two letters.
    private static func hasSiteEnding(_ text: String) -> Bool {
        let site = text.prefix { $0 != "/" && $0 != "?" && $0 != "#" }.lowercased()
        let parts = site.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count > 1, parts.allSatisfy({ !$0.isEmpty }), let ending = parts.last else { return false }
        if ending.count == 2 { return ending.allSatisfy { $0.isASCII && $0.isLetter } }
        return siteEndings.contains(String(ending))
    }

    private static let siteEndings: Set<String> = [
        "com", "org", "net", "edu", "gov", "info", "biz", "shop", "store", "online", "site",
        "app", "dev", "art", "xyz", "kids", "education", "school", "museum"
    ]

    // MARK: - Who and when

    /// "You · 8:12 AM", "Your guide · Oct 1": who set a Low or Out staple's
    /// level, and when. Nil for a Stocked one.
    func markedBy(_ staple: CDSupply) -> String? {
        guard staple.level.isNeeded, let at = staple.levelChangedAt else { return nil }
        return "\(who(staple).capitalizedFirst) · \(Self.when(at, now: now()))"
    }

    /// The hold menu's header: "Out since Oct 1, marked by your guide ·
    /// Bathrooms · From the office", "Added Sep 3 by your guide · Sink ·
    /// Your guide orders it", and the note on a line of its own.
    func menuHeader(_ staple: CDSupply) -> String {
        var parts: [String] = []
        if let at = staple.levelChangedAt {
            let who = Self.midSentence(who(staple))
            if staple.level.isNeeded {
                parts.append("\(staple.level.displayName) since \(Self.when(at, now: now())), marked by \(who)")
            } else if hasHistory(staple) {
                parts.append("Restocked \(Self.when(at, now: now())) by \(who)")
            } else {
                // No line of history: as it was put on the shelf.
                parts.append("Added \(Self.when(staple.createdAt ?? at, now: now())) by \(who)")
            }
        } else {
            parts.append(staple.level.displayName)
        }
        if !staple.location.isEmpty { parts.append(staple.location) }
        parts.append(staple.source == .office ? "From the office" : "Your guide orders it")
        let line = parts.joined(separator: " · ")
        return staple.notes.isEmpty ? line : "\(line)\n\(staple.notes)"
    }

    /// The line under an office-run row: "Bathrooms · you, 8:12 AM" for a
    /// staple, "Added by your guide" for a one-off.
    func runDetail(_ need: CDOrderItem) -> String {
        staple(for: need)?.location ?? ""
    }

    /// The office-run hold menu's header: "Marked Out by your guide · Oct 3"
    /// for a Low or Out staple, "Added by your guide · Oct 3" for a one-off
    /// (and for a need whose staple is Stocked or not here). It always names
    /// who, "you" included, since the row itself says nothing of it.
    func runWho(_ need: CDOrderItem) -> String {
        if let staple = staple(for: need), staple.level.isNeeded, let at = staple.levelChangedAt {
            let who = Self.midSentence(who(staple))
            return "Marked \(staple.level.displayName) by \(who) · \(Self.when(at, now: now()))"
        }
        let who = Self.midSentence(author.reads(changedByID: need.addedByID, name: need.addedByName))
        guard let at = need.createdAt else { return "Added by \(who)" }
        return "Added by \(who) · \(Self.when(at, now: now()))"
    }

    /// "You" reads "you" inside a sentence ("marked by you").
    static func midSentence(_ who: String) -> String {
        who == "You" ? "you" : who
    }

    /// "Low · not asked yet", "Asked Sep 30 · waiting 3 days": where one of
    /// the guide's orders stands.
    func orderStatus(_ need: CDOrderItem) -> String {
        Self.orderStatus(need, stapleLevel: staple(for: need)?.level, now: now())
    }

    static func orderStatus(_ need: CDOrderItem, stapleLevel: RestockLevel?, now: Date) -> String {
        switch need.stage {
        case .toRequest:
            if let stapleLevel, stapleLevel.isNeeded { return "\(stapleLevel.displayName) · not asked yet" }
            return "Not asked yet"
        case .requested:
            guard let asked = need.requestedAt else { return "Asked" }
            let calendar = Calendar.current
            let days = calendar.dateComponents(
                [.day], from: calendar.startOfDay(for: asked), to: calendar.startOfDay(for: now)
            ).day ?? 0
            let date = asked.formatted(.dateTime.month(.abbreviated).day())
            switch days {
            case ...0: return "Asked today"
            case 1: return "Asked \(date) · waiting 1 day"
            default: return "Asked \(date) · waiting \(days) days"
            }
        case .confirmed:
            return need.confirmedAt.map { "Confirmed \($0.formatted(.dateTime.month(.abbreviated).day()))" }
                ?? "Confirmed"
        case .received:
            return "Received"
        }
    }

    private func who(_ staple: CDSupply) -> String {
        author.reads(changedByID: staple.levelChangedByID, name: staple.levelChangedByName)
    }

    private func hasHistory(_ staple: CDSupply) -> Bool {
        guard let id = staple.id?.uuidString.uppercased() else { return false }
        return staplesWithHistory.contains(id)
    }

    /// The time for today ("8:12 AM"), the date before ("Oct 1").
    static func when(_ date: Date, now: Date) -> String {
        Calendar.current.isDate(date, inSameDayAs: now)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(.dateTime.month(.abbreviated).day())
    }
}

extension String {
    /// "your guide" → "Your guide".
    var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}
