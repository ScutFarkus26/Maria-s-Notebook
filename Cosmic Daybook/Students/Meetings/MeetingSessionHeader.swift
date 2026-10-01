import SwiftUI

/// Wording shared by the header and the phone's title.
enum MeetingSessionText {
    /// "Last met Sep 18, 13 days ago", or "First meeting".
    static func lastMetText(_ date: Date?, startsSentence: Bool = true) -> String {
        guard let date else { return startsSentence ? "First meeting" : "first meeting" }
        let signal = MeetingQueueSignals(lastMet: date)
        let days = signal.daysWaiting() ?? 0
        let ago = days == 0 ? "today" : "\(days) day\(days == 1 ? "" : "s") ago"
        return "\(startsSentence ? "Last" : "last") met \(DateFormatters.shortMonthDay.string(from: date)), \(ago)"
    }
}

/// The counts the header chips show.
struct MeetingSessionSummary: Equatable {
    var stuck: Int
    var focusCarried: Int
    var lessonsSince: Int
}

// MARK: - Header band

/// Whose meeting this is: the child, when she last met, and what's waiting.
struct MeetingSessionHeader<MoreMenu: View>: View {
    let student: CDStudent
    let lastMeetingDate: Date?
    let summary: MeetingSessionSummary
    let actions: MeetingSessionActions
    @ViewBuilder let moreMenu: () -> MoreMenu

    var body: some View {
        HStack(spacing: 16) {
            StudentAvatarView(student: student, size: 52)

            VStack(alignment: .leading, spacing: 6) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        name
                        details
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        name
                        details
                    }
                }
                MeetingSummaryChips(summary: summary, isButtons: false) { _ in }
            }

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                if let onPrevious = actions.onPrevious {
                    Button(action: onPrevious) {
                        Label("Previous Child", systemImage: "chevron.up")
                    }
                    .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                    .help("Previous child (⌥⌘↑)")
                }
                if let onNext = actions.onNext {
                    Button(action: onNext) {
                        Label("Next Child", systemImage: "chevron.down")
                    }
                    .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                    .help("Next child (⌥⌘↓)")
                }
                Menu {
                    moreMenu()
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var name: some View {
        Text(student.fullName)
            .font(.title2.weight(.semibold))
    }

    private var details: some View {
        Text(detailText)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private var detailText: String {
        var parts = [student.level.rawValue]
        if let birthday = student.birthday {
            parts.append("\(AgeUtils.quarterRoundedAgeComponents(birthday: birthday).years)")
        }
        parts.append(MeetingSessionText.lastMetText(lastMeetingDate, startsSentence: false))
        return parts.joined(separator: " · ")
    }
}

// MARK: - Chips

/// Stuck work, carried focus, lessons since. On a phone they are buttons that
/// open each part of the context.
struct MeetingSummaryChips: View {
    enum Chip { case stuck, focus, lessons, meetings }

    let summary: MeetingSessionSummary
    let isButtons: Bool
    let onTap: (Chip) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                if summary.stuck > 0 {
                    chip(.stuck, "\(summary.stuck) stuck work", systemImage: "exclamationmark.triangle",
                         tint: AppColors.warning, emphasized: true)
                }
                if summary.focusCarried > 0 {
                    chip(.focus, "\(summary.focusCarried) focus carried", systemImage: "scope",
                         tint: .accentColor, emphasized: true)
                }
                chip(.lessons, "\(summary.lessonsSince) lesson\(summary.lessonsSince == 1 ? "" : "s") since",
                     systemImage: "book.closed", tint: .secondary, emphasized: false)
                if isButtons {
                    chip(.meetings, "Past meetings", systemImage: "clock", tint: .secondary, emphasized: false)
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollDisabled(!isButtons)
    }

    @ViewBuilder
    private func chip(_ chip: Chip, _ title: String, systemImage: String, tint: Color, emphasized: Bool) -> some View {
        let label = Label(title, systemImage: systemImage)
            .font((isButtons ? Font.subheadline : Font.caption).weight(.semibold))
            .foregroundStyle(emphasized ? tint : Color.primary)
            .padding(.horizontal, isButtons ? 12 : 8)
            .padding(.vertical, isButtons ? 8 : 3)
            .background(Capsule().fill(tint.opacity(emphasized ? 0.14 : 0.10)))
        if isButtons {
            Button { onTap(chip) } label: { label }
                .buttonStyle(.plain)
        } else {
            label
        }
    }
}

// MARK: - More menu

/// The ⋯ menu: book the next meeting, or clear this one (behind a confirmation).
struct MeetingMoreMenuItems: View {
    let scheduledDate: Date?
    let onSchedule: ((Date?) -> Void)?
    let canClear: Bool
    let onPickDay: () -> Void
    /// Nil leaves Clear Meeting out (the queue's row menu).
    let onClear: (() -> Void)?

    var body: some View {
        if let onSchedule {
            Menu {
                Button("Today", systemImage: "calendar") { onSchedule(AppCalendar.startOfDay(Date())) }
                Button("Tomorrow", systemImage: "calendar.badge.clock") {
                    onSchedule(AppCalendar.addingDays(1, to: Date()))
                }
                Button("Pick a Day…", systemImage: "calendar.badge.plus", action: onPickDay)
                if scheduledDate != nil {
                    Divider()
                    Button("Clear", systemImage: "calendar.badge.minus", role: .destructive) { onSchedule(nil) }
                }
            } label: {
                Label(
                    scheduledDate.map { "Booked \(MeetingQueueRow.dayLabel($0))" } ?? "Schedule Meeting",
                    systemImage: "person.crop.circle.badge.clock"
                )
            }
        }
        if let onClear {
            Divider()
            Button("Clear Meeting…", systemImage: "trash", role: .destructive, action: onClear)
                .disabled(!canClear)
        }
    }
}
