import Foundation
import OSLog

/// One reading item on a book club packet — e.g. "Chapters 1–3".
/// Stored as JSON on `CDBookClubPacket.readingItemsJSON`,
/// and copied into `CDBookClubMeeting.readingLabel` when a session is generated.
struct BookClubReadingItem: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var ordinal: Int
    var label: String

    init(id: UUID = UUID(), ordinal: Int, label: String) {
        self.id = id
        self.ordinal = ordinal
        self.label = label
    }
}

extension BookClubReadingItem {
    static func decode(_ json: String) -> [BookClubReadingItem] {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return [] }
        do {
            return try JSONDecoder().decode([BookClubReadingItem].self, from: data)
        } catch {
            Logger.bookClub.warning("Failed to decode reading items: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    static func encode(_ items: [BookClubReadingItem]) -> String {
        guard !items.isEmpty else { return "" }
        do {
            let data = try JSONEncoder().encode(items)
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            Logger.bookClub.warning("Failed to encode reading items: \(error.localizedDescription, privacy: .public)")
            return ""
        }
    }
}
