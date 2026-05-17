import Foundation
import SwiftUI

/// Filter state + filtering logic for the Book Club packets list.
@Observable
@MainActor
final class BookClubPacketsViewModel {
    var searchText: String = ""
    var gradeFilter: StoryGradeBand?
    var themeFilter: String?

    func filter(packets: [CDBookClubPacket]) -> [CDBookClubPacket] {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return packets.filter { packet in
            if !term.isEmpty {
                let title = packet.title.lowercased()
                let author = packet.author.lowercased()
                let themesMatch = packet.themesArray.contains { $0.lowercased().contains(term) }
                if !title.contains(term), !author.contains(term), !themesMatch {
                    return false
                }
            }

            if let gradeFilter, let band = packet.gradeBand, !band.intersects(gradeFilter) {
                return false
            }

            if let themeFilter, !packet.themesArray.contains(where: { $0.caseInsensitiveCompare(themeFilter) == .orderedSame }) {
                return false
            }

            return true
        }
    }

    var hasActiveFilters: Bool {
        !searchText.isEmpty || gradeFilter != nil || themeFilter != nil
    }

    func clearAll() {
        searchText = ""
        gradeFilter = nil
        themeFilter = nil
    }
}
