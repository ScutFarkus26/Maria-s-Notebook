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
        let names = roster.prefix(3).map(\.shortName)
        let extra = roster.count - names.count
        var summary = names.joined(separator: ", ")
        if extra > 0 {
            summary += " +\(extra)"
        }
        return summary
    }

    private var dateRangeText: String? {
        guard let start = session.startDate else { return nil }
        let formatter = DateFormatters.mediumDate
        if let end = session.endDate {
            return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
        }
        return formatter.string(from: start)
    }

    /// Built once — this row renders per session in a scrolling list.
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .named
        return formatter
    }()

    private var nextMeetingText: String? {
        guard let meeting = nextMeeting, let date = meeting.date else { return nil }
        return Self.nextMeetingText(for: date, now: Date(), calendar: .current)
    }

    /// "Next: today", "Next: tomorrow", "Next: in 3 days", "Next: 2 days ago".
    /// A meeting is a day, not a time: counted from the time of day it read
    /// "Next: 9 hours ago" on the morning of the meeting.
    static func nextMeetingText(for date: Date, now: Date, calendar: Calendar) -> String {
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)
        ).day ?? 0
        let phrase: String
        switch days {
        case 0: phrase = "today"
        case 1: phrase = "tomorrow"
        default: phrase = relativeFormatter.localizedString(from: DateComponents(day: days))
        }
        return "Next: \(phrase)"
    }
}
