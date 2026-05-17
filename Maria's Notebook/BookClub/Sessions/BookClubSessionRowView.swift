import SwiftUI
import CoreData

struct BookClubSessionRowView: View {
    let session: CDBookClubSession
    let packet: CDBookClubPacket?
    let roster: [CDStudent]
    let nextMeeting: CDBookClubMeeting?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "books.vertical.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(titleText)
                    .font(.headline)
                    .lineLimit(1)

                if !rosterSummary.isEmpty {
                    Text(rosterSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 12) {
                    if let range = dateRangeText {
                        Label(range, systemImage: "calendar")
                            .labelStyle(.titleAndIcon)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let next = nextMeetingText {
                        Label(next, systemImage: "clock")
                            .labelStyle(.titleAndIcon)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var titleText: String {
        let trimmed = session.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if let packet, !packet.title.isEmpty { return packet.title }
        return "Book Club"
    }

    private var rosterSummary: String {
        guard !roster.isEmpty else { return "" }
        let names = roster.prefix(3).map { StudentFormatter.firstName(for: $0) }
        let extra = roster.count - names.count
        var summary = names.joined(separator: ", ")
        if extra > 0 {
            summary += " +\(extra)"
        }
        return summary
    }

    private var dateRangeText: String? {
        guard let start = session.startDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        if let end = session.endDate {
            return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
        }
        return formatter.string(from: start)
    }

    private var nextMeetingText: String? {
        guard let meeting = nextMeeting, let date = meeting.date else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Next: \(formatter.localizedString(for: date, relativeTo: Date()))"
    }
}
