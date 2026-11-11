// LessonTimePicker.swift
// What a lesson's time chip opens: the lesson's title, the quick start times
// in two groups (Morning, Afternoon), "Another time" for any other, and
// "Remove Time" once a time is set (docs/Plans/Plan - Lesson times on cards.md,
// idea A without the length row).
//
// It works in hours and minutes only: it is handed the current time (or none)
// and the day's taken minutes, and hands back `set(hour, minute)` or `remove()`.
// It never sees a `Date` from outside and never touches Core Data, so every
// caller stores the time through the planner's own rules.
//
// It applies as you go (decision 8): a quick time sets and closes; "Another
// time" sets on each change. No Done button here: on the Mac and iPad a popover
// saves its work when it closes; the iPhone's sheet adds Done around it
// (`LessonTimePickerPresenter`). Present it with `lessonTimePicker(item:…)`.

import SwiftUI

struct LessonTimePicker: View {
    /// The popover's fixed width (Apple: give popover content a fixed size).
    static let popoverWidth: CGFloat = 300

    let lessonTitle: String
    let current: LessonClockTime?
    /// Start times (minutes after midnight) other lessons that day already have.
    let takenMinutes: Set<Int>
    /// The half the lesson is in now: where "Another time" starts when no time is set.
    let startingHalf: DayPeriod
    private let setTime: (_ hour: Int, _ minute: Int) -> Void
    private let removeTime: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var fieldTime: Date
    #if os(iOS)
    @State private var showsWheel: Bool
    #endif

    init(
        lessonTitle: String,
        current: LessonClockTime?,
        takenMinutes: Set<Int> = [],
        startingHalf: DayPeriod = .morning,
        showsOtherTime: Bool = false,
        set: @escaping (_ hour: Int, _ minute: Int) -> Void,
        remove: @escaping () -> Void
    ) {
        self.lessonTitle = lessonTitle
        self.current = current
        self.takenMinutes = takenMinutes
        self.startingHalf = startingHalf
        self.setTime = set
        self.removeTime = remove
        _fieldTime = State(initialValue: LessonTimeText.fieldDate(
            current ?? LessonTimeChoices.suggestedStart(for: startingHalf)
        ))
        #if os(iOS)
        _showsWheel = State(initialValue: showsOtherTime)
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text(lessonTitle)
                .font(.headline)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            quickTimes("Morning", LessonTimeChoices.morning)
            quickTimes("Afternoon", LessonTimeChoices.afternoon)
            if showsTakenNote {
                Text("A dot marks a time that already has a lesson.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            otherTime
            if current != nil {
                Divider()
                Button("Remove Time", systemImage: "clock.badge.xmark") {
                    removeTime()
                    dismiss()
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(AppTheme.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        // iOS 27 release note 167448274: inside a popover these reset to the
        // defaults, so set them again here.
        .controlSize(.regular)
        .buttonBorderShape(.roundedRectangle)
        .onChange(of: fieldTime) { _, newValue in
            let picked = LessonTimeText.clockTime(from: newValue)
            guard picked != current else { return }
            setTime(picked.hour, picked.minute)
        }
        .onChange(of: current) { _, newValue in
            guard let newValue else { return }
            let date = LessonTimeText.fieldDate(newValue)
            if date != fieldTime { fieldTime = date }
        }
    }

    // MARK: - Quick times

    private func quickTimes(_ title: String, _ minutes: [Int]) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.verySmall) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .accessibilityAddTraits(.isHeader)
            Grid(horizontalSpacing: AppTheme.Spacing.verySmall, verticalSpacing: AppTheme.Spacing.verySmall) {
                ForEach(Array(stride(from: 0, to: minutes.count, by: Self.columns)), id: \.self) { start in
                    GridRow {
                        ForEach(minutes[start..<min(start + Self.columns, minutes.count)], id: \.self) { minute in
                            quickTime(LessonClockTime(minutesAfterMidnight: minute))
                        }
                    }
                }
            }
        }
    }

    private static let columns = 5

    private func quickTime(_ time: LessonClockTime) -> some View {
        let isCurrent = time == current
        let isTaken = !isCurrent && takenMinutes.contains(time.minutesAfterMidnight)
        return Button {
            setTime(time.hour, time.minute)
            dismiss()
        } label: {
            Text(LessonTimeText.chip(time))
        }
        .buttonStyle(QuickTimeButtonStyle(isCurrent: isCurrent, isTaken: isTaken))
        .accessibilityLabel(LessonTimeText.spoken(time))
        .accessibilityValue(isTaken ? "Already has a lesson" : "")
        .accessibilityHint("Sets the start time.")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    /// The note explains the dots only when one is showing.
    private var showsTakenNote: Bool {
        let quick = Set(LessonTimeChoices.morning + LessonTimeChoices.afternoon)
        return takenMinutes.contains { quick.contains($0) && $0 != current?.minutesAfterMidnight }
    }

    // MARK: - Another time

    @ViewBuilder
    private var otherTime: some View {
        #if os(macOS)
        DatePicker("Another time", selection: $fieldTime, displayedComponents: .hourAndMinute)
            .datePickerStyle(.stepperField)
            .environment(\.timeZone, LessonTimeText.fieldTimeZone)
            .environment(\.calendar, LessonTimeText.fieldCalendar)
        #else
        // A row that opens a wheel: a compact picker would open a second
        // popover, and popovers must never stack (Apple guidance).
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            Button {
                withAnimation(.snappy) { showsWheel.toggle() }
            } label: {
                HStack {
                    Text("Another time")
                    Spacer()
                    if let current, !isQuickTime(current) {
                        Text(LessonTimeText.chip(current))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(showsWheel ? 180 : 0))
                }
                .contentShape(Rectangle())
                .frame(minHeight: 34)
            }
            .buttonStyle(.plain)
            .accessibilityValue(showsWheel ? "Open" : "")
            .accessibilityHint("Shows a wheel for any start time.")
            if showsWheel {
                DatePicker("Another time", selection: $fieldTime, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .environment(\.timeZone, LessonTimeText.fieldTimeZone)
                    .environment(\.calendar, LessonTimeText.fieldCalendar)
            }
        }
        #endif
    }

    private func isQuickTime(_ time: LessonClockTime) -> Bool {
        LessonTimeChoices.quickTimes(for: time.half).contains(time.minutesAfterMidnight)
    }
}

// MARK: - Quick-time button

/// One quick time: filled with the accent color when it is the lesson's time,
/// dimmed with an amber dot when another lesson that day already has it (it can
/// still be picked: a deliberate double-booking is rare but real, decision 7).
private struct QuickTimeButtonStyle: ButtonStyle {
    let isCurrent: Bool
    let isTaken: Bool

    #if os(macOS)
    private let height: CGFloat = 26
    #else
    private let height: CGFloat = 34
    #endif

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(isCurrent ? .semibold : .regular))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(background, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if isTaken {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 5, height: 5)
                        .padding(4)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }

    private var foreground: AnyShapeStyle {
        if isCurrent { return AnyShapeStyle(Color.white) }
        if isTaken { return AnyShapeStyle(.secondary) }
        return AnyShapeStyle(.primary)
    }

    private var background: AnyShapeStyle {
        if isCurrent { return AnyShapeStyle(Color.accentColor) }
        return AnyShapeStyle(.quaternary)
    }
}
