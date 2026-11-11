import SwiftUI

struct InboxStatusSection: View {
    @Binding var scheduledFor: Date?
    /// The lesson's title, at the top of the time picker.
    var lessonTitle: String = ""
    /// The presentation being edited, left out of the day's taken times.
    var presentationID: UUID?

    @Environment(\.calendar) private var calendar

    /// The date picker shows days only, so a new day keeps the time of day
    /// already there: a set time stays set, at the same clock time.
    private var day: Binding<Date?> {
        Binding(
            get: { scheduledFor },
            set: { scheduledFor = ScheduledDateEdits.changingDay(of: scheduledFor, to: $0, using: calendar) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            HStack(spacing: AppTheme.Spacing.small) {
                Image(systemName: "tray")
                    .foregroundStyle(.secondary)
                    .font(.system(size: UIConstants.CardSize.iconSize))
                Text("Inbox Status")
                    .font(AppTheme.ScaledFont.calloutSemibold)
                    .foregroundStyle(.secondary)
            }

            if scheduledFor != nil {
                scheduledView
            } else {
                unscheduledView
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scheduledView: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            HStack(spacing: AppTheme.Spacing.small) {
                Image(systemName: "calendar")
                    .foregroundStyle(.blue)
                    .font(.system(size: UIConstants.CardSize.iconSize))
                Text("Scheduled")
                    .font(AppTheme.ScaledFont.body)
                    .foregroundStyle(.blue)
            }
            .padding(.horizontal, AppTheme.Spacing.compact)
            .padding(.vertical, AppTheme.Spacing.small)
            .surface(
                UIConstants.CornerRadius.medium,
                fill: Color.blue.opacity(UIConstants.OpacityConstants.light),
                style: .continuous
            )

            OptionalDatePicker(
                toggleLabel: "Change Date",
                dateLabel: "Schedule For",
                date: day,
                displayedComponents: [.date],
                defaultHour: UIConstants.morningHour
            )

            DayHalfPicker(date: $scheduledFor)

            ScheduledTimeRow(
                scheduledFor: $scheduledFor, lessonTitle: lessonTitle, presentationID: presentationID
            )

            Button {
                scheduledFor = nil
            } label: {
                Label("Remove from Schedule", systemImage: "xmark.circle")
                    .font(AppTheme.ScaledFont.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private var unscheduledView: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            HStack(spacing: AppTheme.Spacing.small) {
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
                    .font(.system(size: UIConstants.CardSize.iconSize))
                Text("Unscheduled")
                    .font(AppTheme.ScaledFont.body)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, AppTheme.Spacing.compact)
            .padding(.vertical, AppTheme.Spacing.small)
            .surface(
                UIConstants.CornerRadius.medium,
                fill: Color.secondary.opacity(UIConstants.OpacityConstants.faint),
                style: .continuous
            )

            OptionalDatePicker(
                toggleLabel: "Schedule Lesson",
                dateLabel: "Schedule For",
                date: $scheduledFor,
                displayedComponents: [.date],
                defaultHour: UIConstants.morningHour
            )

            DayHalfPicker(date: $scheduledFor)
        }
    }

}

/// The sheet's Time row: "Time" and the set time, or "None", which opens the
/// lesson time picker (docs/Plans/Plan - Lesson times on cards.md, Phase 4).
/// Set and remove go through `ScheduledDateEdits`, on the date the sheet
/// saves later.
struct ScheduledTimeRow: View {
    @Binding var scheduledFor: Date?
    let lessonTitle: String
    let presentationID: UUID?

    @Environment(\.calendar) private var calendar
    @Environment(\.managedObjectContext) private var viewContext
    @State private var timeTarget: TimeTarget?

    /// One opening of the time picker: the day's other start times, read when it opens.
    private struct TimeTarget: Identifiable {
        let id = UUID()
        let takenMinutes: Set<Int>
    }

    private var setTime: LessonClockTime? {
        ScheduledDateEdits.clockTime(of: scheduledFor, using: calendar)
    }

    /// "Time" and the set time, or "None"; either opens the time picker.
    var body: some View {
        HStack(spacing: AppTheme.Spacing.small) {
            Label("Time", systemImage: "clock")
                .font(AppTheme.ScaledFont.body)
            Spacer(minLength: AppTheme.Spacing.small)
            Button {
                guard let scheduledFor else { return }
                timeTarget = TimeTarget(takenMinutes: ScheduledDateEdits.takenMinutes(
                    on: scheduledFor, excluding: presentationID, in: viewContext, using: calendar
                ))
            } label: {
                Text(setTime.map { LessonTimeText.spoken($0) } ?? "None")
                    .monospacedDigit()
                    .foregroundStyle(setTime == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Start time")
            .accessibilityValue(setTime.map { LessonTimeText.spoken($0) } ?? "None")
            .accessibilityHint(setTime == nil ? "Sets a start time" : "Changes or removes the start time")
            .lessonTimePicker(item: $timeTarget) { target in
                LessonTimePicker(
                    lessonTitle: lessonTitle,
                    current: setTime,
                    takenMinutes: target.takenMinutes,
                    startingHalf: scheduledFor.map { DayPeriod(scheduledFor: $0, using: calendar) } ?? .morning,
                    set: { hour, minute in
                        scheduledFor = ScheduledDateEdits.settingTime(
                            hour: hour, minute: minute, on: scheduledFor, using: calendar
                        )
                    },
                    remove: {
                        scheduledFor = ScheduledDateEdits.removingTime(from: scheduledFor, using: calendar)
                    }
                )
            }
        }
    }
}
