import SwiftUI

/// The custom cadence's meeting days, as a row of weekday toggles. The mask's
/// bit 1 is Sunday through bit 7 Saturday, as `BookClubCadence.custom` reads it.
struct BookClubWeekdayPicker: View {
    @Binding var weekdayMask: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Meeting days")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(1...7, id: \.self) { day in
                    let isOn = (weekdayMask & (Int64(1) << day)) != 0
                    Button {
                        weekdayMask ^= (Int64(1) << day)
                    } label: {
                        Text(Self.shortLabel(day))
                            .font(.caption)
                            .frame(width: 32, height: 28)
                            .surface(
                                UIConstants.CornerRadius.small,
                                fill: isOn ? Color.accentColor : Color.secondary.opacity(0.15)
                            )
                            .foregroundStyle(isOn ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private static func shortLabel(_ day: Int) -> String {
        switch day {
        case 1: return "Sun"
        case 2: return "Mon"
        case 3: return "Tue"
        case 4: return "Wed"
        case 5: return "Thu"
        case 6: return "Fri"
        case 7: return "Sat"
        default: return ""
        }
    }
}

/// A new session's meetings before they are created: number, date, reading
/// and leader.
struct BookClubSchedulePreview: View {
    let meetings: [BookClubScheduleGenerator.GeneratedMeeting]
    let roster: [CDStudent]

    var body: some View {
        Section("Preview") {
            if meetings.isEmpty {
                Text("Choose a packet with reading items to preview.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(meetings.enumerated()), id: \.offset) { _, meeting in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("Meeting \(meeting.ordinal)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(meeting.date, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(meeting.readingLabel)
                                .font(.callout)
                        }
                        Spacer()
                        if let leaderID = meeting.leaderStudentID,
                           let leader = roster.first(where: { $0.id == leaderID }) {
                            Text(leader.shortName)
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .capsuleFill(Color.secondary.opacity(0.15))
                        }
                    }
                }
            }
        }
    }
}
