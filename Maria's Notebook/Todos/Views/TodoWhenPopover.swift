// swiftlint:disable file_length
import SwiftUI

// Things-inspired "When" scheduling popover with quick-pick shortcuts and a mini calendar.
// swiftlint:disable:next type_body_length
struct TodoWhenPopover: View {
    @Binding var scheduledDate: Date?
    @Binding var dueDate: Date?
    @Binding var isSomeday: Bool
    var onDismiss: () -> Void = {}

    @State private var displayedMonth: Date = Date()
    @State private var showDeadlinePicker = false

    private let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Text("When")
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.horizontal, AppTheme.Spacing.medium)
                .padding(.top, AppTheme.Spacing.compact)
                .padding(.bottom, AppTheme.Spacing.small)

            // Quick-pick chips
            quickPickSection
                .padding(.horizontal, AppTheme.Spacing.compact)
                .padding(.bottom, AppTheme.Spacing.compact)

            Divider()

            // Mini calendar
            miniCalendar
                .padding(AppTheme.Spacing.compact)

            Divider()

            // Deadline section
            deadlineSection
                .padding(AppTheme.Spacing.compact)
        }
        .frame(minWidth: 280, maxWidth: 320)
        .onAppear {
            // Start the calendar on the month of the scheduled date or today
            if let scheduled = scheduledDate {
                displayedMonth = scheduled
            } else {
                displayedMonth = Date()
            }
        }
    }

    // MARK: - Quick Picks

    private var quickPickSection: some View {
        let columns = [
            GridItem(.flexible(), spacing: AppTheme.Spacing.small),
            GridItem(.flexible(), spacing: AppTheme.Spacing.small),
            GridItem(.flexible(), spacing: AppTheme.Spacing.small)
        ]

        return LazyVGrid(columns: columns, spacing: AppTheme.Spacing.small) {
            quickPickButton("Today", icon: "star.fill", tint: .blue) {
                scheduledDate = AppCalendar.startOfDay(Date())
                isSomeday = false
                onDismiss()
            }
            quickPickButton("Tomorrow", icon: "sunrise", tint: .orange) {
                scheduledDate = AppCalendar.addingDays(1, to: AppCalendar.startOfDay(Date()))
                isSomeday = false
                onDismiss()
            }
            quickPickButton("Next Week", icon: "calendar.badge.plus", tint: .purple) {
                scheduledDate = nextMonday()
                isSomeday = false
                onDismiss()
            }
            quickPickButton("Someday", icon: "moon.zzz", tint: .secondary) {
                scheduledDate = nil
                isSomeday = true
                onDismiss()
            }
            quickPickButton("Clear", icon: "xmark.circle", tint: .secondary) {
                scheduledDate = nil
                dueDate = nil
                isSomeday = false
                onDismiss()
            }
        }
    }

    private func quickPickButton(
        _ title: String, icon: String, tint: Color, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                Text(title)
                    .font(AppTheme.ScaledFont.captionSmallSemibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppTheme.Spacing.small)
            .foregroundStyle(tint)
            .background(
                tint.opacity(UIConstants.OpacityConstants.faint),
                in: RoundedRectangle(
                    cornerRadius: UIConstants.CornerRadius.medium, style: .continuous
                )
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: UIConstants.CornerRadius.medium, style: .continuous
                )
                .strokeBorder(
                    tint.opacity(UIConstants.OpacityConstants.light),
                    lineWidth: UIConstants.StrokeWidth.thin
                )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Mini Calendar

    private var miniCalendar: some View {
        VStack(spacing: AppTheme.Spacing.small) {
            // Month navigation
            HStack {
                Button {
                    adaptiveWithAnimation(
                        .easeInOut(duration: UIConstants.AnimationDuration.fast)
                    ) {
                        displayedMonth = calendar.date(
                            byAdding: .month, value: -1, to: displayedMonth
                        ) ?? displayedMonth
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(monthYearString(displayedMonth))
                    .font(AppTheme.ScaledFont.bodySemibold)

                Spacer()

                Button {
                    adaptiveWithAnimation(.easeInOut(duration: UIConstants.AnimationDuration.fast)) {
                        displayedMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Weekday headers
            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { sym in
                    Text(sym)
                        .font(AppTheme.ScaledFont.captionSmallSemibold)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Day grid
            let weeks = weeksForMonth(displayedMonth)
            VStack(spacing: 4) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 4) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, date in
                            calendarDayCell(date)
                        }
                    }
                }
            }
        }
    }

    private func calendarDayCell(_ date: Date?) -> some View {
        Group {
            if let d = date {
                let isToday = calendar.isDateInToday(d)
                let isSelected = scheduledDate.map { AppCalendar.isSameDay($0, d) } ?? false
                let isDeadline = dueDate.map { AppCalendar.isSameDay($0, d) } ?? false
                let isPast = d < AppCalendar.startOfDay(Date()) && !isToday

                Button {
                    scheduledDate = AppCalendar.startOfDay(d)
                    isSomeday = false
                    onDismiss()
                } label: {
                    VStack(spacing: 1) {
                        Text("\(calendar.component(.day, from: d))")
                            .font(AppTheme.ScaledFont.caption)
                            .fontWeight(isSelected ? .bold : (isToday ? .semibold : .regular))
                            .foregroundStyle(
                                isSelected ? .white :
                                isPast ? .secondary.opacity(UIConstants.OpacityConstants.half) :
                                isToday ? .blue : .primary
                            )
                            .frame(width: 28, height: 28)
                            .background(
                                isSelected ? Circle().fill(Color.blue) :
                                isToday ? Circle().fill(Color.blue.opacity(UIConstants.OpacityConstants.light)) :
                                Circle().fill(Color.clear)
                            )

                        // Deadline dot indicator
                        Circle()
                            .fill(isDeadline ? Color.red : Color.clear)
                            .frame(width: 4, height: 4)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            } else {
                Color.clear.frame(height: 33).frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Deadline Section

    private var deadlineSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            if let deadline = dueDate {
                // Show current deadline with remove button
                HStack(spacing: AppTheme.Spacing.small) {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.destructive)
                    Text("Deadline: \(deadlineDateString(deadline))")
                        .font(AppTheme.ScaledFont.captionSemibold)
                        .foregroundStyle(.primary)
                    Spacer()
                    Button {
                        dueDate = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, AppTheme.Spacing.small)
                .padding(.vertical, AppTheme.Spacing.verySmall)
                .background(Color.red.opacity(UIConstants.OpacityConstants.faint), in: Capsule(style: .continuous))

                if showDeadlinePicker {
                    DatePicker("Deadline", selection: Binding(
                        get: { dueDate ?? Date() },
                        set: { dueDate = AppCalendar.startOfDay($0) }
                    ), displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                }

                Button {
                    adaptiveWithAnimation(UIConstants.SpringAnimation.standard) {
                        showDeadlinePicker.toggle()
                    }
                } label: {
                    Text(showDeadlinePicker ? "Done" : "Change Deadline")
                        .font(AppTheme.ScaledFont.captionSemibold)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    dueDate = scheduledDate ?? AppCalendar.startOfDay(Date())
                    showDeadlinePicker = true
                } label: {
                    HStack(spacing: AppTheme.Spacing.verySmall) {
                        Image(systemName: "flag")
                            .font(.system(size: 12))
                        Text("Add Deadline")
                            .font(AppTheme.ScaledFont.captionSemibold)
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                if showDeadlinePicker {
                    DatePicker("Deadline", selection: Binding(
                        get: { dueDate ?? Date() },
                        set: { dueDate = AppCalendar.startOfDay($0) }
                    ), displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                }
            }
        }
    }

    // MARK: - Helpers

    private func nextMonday() -> Date {
        let today = AppCalendar.startOfDay(Date())
        var nextDate = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        while calendar.component(.weekday, from: nextDate) != 2 { // 2 = Monday
            nextDate = calendar.date(byAdding: .day, value: 1, to: nextDate) ?? nextDate
        }
        return nextDate
    }

    private func monthYearString(_ date: Date) -> String {
        DateFormatters.monthYear.string(from: date)
    }

    private func deadlineDateString(_ date: Date) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        return DateFormatters.shortMonthDay.string(from: date)
    }

    private var weekdaySymbols: [String] {
        let base = DateFormatters.weekdayAbbrev.shortStandaloneWeekdaySymbols
            ?? DateFormatters.weekdayAbbrev.shortWeekdaySymbols
            ?? ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
        let start = max(1, min(7, calendar.firstWeekday)) - 1
        guard start > 0, start < base.count else { return base }
        return Array(base[start...]) + Array(base[..<start])
    }

    private func weeksForMonth(_ month: Date) -> [[Date?]] {
        let comps = calendar.dateComponents([.year, .month], from: month)
        let startOfMonth = calendar.date(from: comps) ?? month
        let daysInMonth = calendar.range(of: .day, in: .month, for: startOfMonth)?.count ?? 30
        let firstWeekdayOfMonth = calendar.component(.weekday, from: startOfMonth)
        let leadingEmpty = (firstWeekdayOfMonth - calendar.firstWeekday + 7) % 7

        var cells: [Date?] = Array(repeating: nil, count: leadingEmpty)
        for day in 0..<daysInMonth {
            cells.append(calendar.date(byAdding: .day, value: day, to: startOfMonth))
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }
}

// MARK: - TodoSchedulePickerButton

/// A button that shows the current schedule state and opens a TodoWhenPopover on tap.
/// Designed for use inside Form/Section rows.
struct TodoSchedulePickerButton: View {
    @Binding var scheduledDate: Date?
    @Binding var dueDate: Date?
    @Binding var isSomeday: Bool
    @State private var showPopover = false

    var body: some View {
        Button {
            showPopover = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: displayIcon)
                    .font(.system(size: 12))
                Text(displayText)
                    .font(AppTheme.ScaledFont.bodySemibold)
            }
            .foregroundStyle(displayColor)
            .padding(.horizontal, AppTheme.Spacing.small)
            .padding(.vertical, AppTheme.Spacing.xxsmall)
            .background(displayColor.opacity(UIConstants.OpacityConstants.faint), in: Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            TodoWhenPopover(
                scheduledDate: $scheduledDate,
                dueDate: $dueDate,
                isSomeday: $isSomeday,
                onDismiss: { showPopover = false }
            )
        }
    }

    private var displayText: String {
        if isSomeday { return "Someday" }
        if let date = scheduledDate {
            return formatScheduleDate(date)
        }
        if let date = dueDate {
            return formatScheduleDate(date)
        }
        return "None"
    }

    private var displayIcon: String {
        if isSomeday { return "moon.zzz" }
        if scheduledDate != nil || dueDate != nil { return "calendar" }
        return "calendar.badge.plus"
    }

    private var displayColor: Color {
        if isSomeday { return .secondary }
        if let date = scheduledDate ?? dueDate {
            if Calendar.current.isDateInToday(date) { return .blue }
            if Calendar.current.isDateInTomorrow(date) { return .orange }
            return .purple
        }
        return .secondary
    }

    private func formatScheduleDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInTomorrow(date) { return "Tomorrow" }
        return DateFormatters.shortMonthDay.string(from: date)
    }
}
