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
//
// When some of the lesson's children are away with a co-teacher that day it
// is handed `LessonTimeAway`, ready-made words and minutes, and shows them up
// front (docs/Plans/Plan - Co-teacher times when scheduling.md, decision 4):
// an Everyone's free row above the grid, a mark on each quick time that
// overlaps a group, and the Away list under the grid. Marked times stay
// enabled. With nothing away it draws exactly as it did before.

import SwiftUI

/// Who is away that day, as the picker shows it: plain words and minutes,
/// made by the caller from the day's co-teacher groups, so the picker never
/// sees a `Date` or Core Data (decision 4).
nonisolated struct LessonTimeAway: Equatable, Sendable {
    /// The Away list, one ready-made row per group in time order:
    /// "9:15–9:45 · Lucy T, Ora P · Miss Nicole".
    var rows: [String]
    /// Minute after midnight → the sentence for a lesson starting then, for
    /// each start whose 30 minutes overlap a group:
    /// "Lucy T is with Morah Devora until 10:20".
    var sentences: [Int: String]
    /// Starts (minutes after midnight) when everyone is free, at most four, in order.
    var suggestions: [Int]
    /// "Free all morning" or "Free all afternoon", when a half has no group.
    var freeWords: String?

    init(rows: [String] = [], sentences: [Int: String] = [:], suggestions: [Int] = [], freeWords: String? = nil) {
        self.rows = rows
        self.sentences = sentences
        self.suggestions = suggestions
        self.freeWords = freeWords
    }

    /// Nothing to show: the picker draws as it does with no away times at all.
    var isEmpty: Bool {
        rows.isEmpty && sentences.isEmpty && suggestions.isEmpty && (freeWords ?? "").isEmpty
    }
}

struct LessonTimePicker: View {
    /// The popover's fixed width (Apple: give popover content a fixed size).
    static let popoverWidth: CGFloat = 300

    /// The mark on a quick time when a child is away during it. Not
    /// `person.slash`, which means Absent on the cards.
    static let awaySymbol = "figure.walk.departure"

    /// The most chips the Everyone's free row shows (decision 5).
    static let maxSuggestions = 4

    let lessonTitle: String
    let current: LessonClockTime?
    /// Start times (minutes after midnight) other lessons that day already have.
    let takenMinutes: Set<Int>
    /// The half the lesson is in now: where "Another time" starts when no time is set.
    let startingHalf: DayPeriod
    /// Who is away that day; nil (or empty) when nobody in the lesson is.
    let away: LessonTimeAway?
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
        away: LessonTimeAway? = nil,
        set: @escaping (_ hour: Int, _ minute: Int) -> Void,
        remove: @escaping () -> Void
    ) {
        self.lessonTitle = lessonTitle
        self.current = current
        self.takenMinutes = takenMinutes
        self.startingHalf = startingHalf
        self.away = away?.isEmpty == false ? away : nil
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
            if let away, showsFreeRow {
                everyonesFree(away)
            }
            quickTimes("Morning", LessonTimeChoices.morning)
            quickTimes("Afternoon", LessonTimeChoices.afternoon)
            if let away, !away.rows.isEmpty {
                awayList(away.rows)
            }
            if showsTakenNote {
                Text("A dot marks a time that already has a lesson.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if showsAwayNote {
                Text("\(Image(systemName: Self.awaySymbol)) marks a time when a child is with another teacher.")
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
            sectionHeader(title)
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

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .accessibilityAddTraits(.isHeader)
    }

    private func quickTime(_ time: LessonClockTime) -> some View {
        let isCurrent = time == current
        let taken = isTaken(time)
        let sentence = awaySentence(for: time)
        return Button {
            choose(time)
            dismiss()
        } label: {
            Text(LessonTimeText.chip(time))
        }
        .buttonStyle(QuickTimeButtonStyle(isCurrent: isCurrent, isTaken: taken, isAway: sentence != nil))
        .accessibilityLabel(LessonTimeText.spoken(time))
        .accessibilityValue(spokenValue(for: time))
        .accessibilityHint("Sets the start time.")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .awayHelp(sentence)
    }

    /// Hands a time back to the caller: the quick times and the free chips both
    /// come through here.
    func choose(_ time: LessonClockTime) {
        setTime(time.hour, time.minute)
    }

    /// Another lesson that day already starts then (the lesson's own time aside).
    func isTaken(_ time: LessonClockTime) -> Bool {
        time != current && takenMinutes.contains(time.minutesAfterMidnight)
    }

    /// Why a start is marked: the sentence for a lesson starting then, or nil
    /// when nobody is away during it.
    func awaySentence(for time: LessonClockTime) -> String? {
        guard let sentence = away?.sentences[time.minutesAfterMidnight], !sentence.isEmpty else { return nil }
        return sentence
    }

    /// VoiceOver's value for a quick time: the state, with both joined when a
    /// time is taken and marked (Apple: the state goes in the value).
    func spokenValue(for time: LessonClockTime) -> String {
        let parts = [isTaken(time) ? "Already has a lesson" : nil, awaySentence(for: time)].compactMap { $0 }
        return parts.joined(separator: ". ")
    }

    /// The quick times that carry the away mark.
    var markedQuickMinutes: [Int] {
        (LessonTimeChoices.morning + LessonTimeChoices.afternoon).filter {
            awaySentence(for: LessonClockTime(minutesAfterMidnight: $0)) != nil
        }
    }

    // MARK: - Away

    /// The Everyone's free row shows when there is a chip or a "Free all…" line.
    var showsFreeRow: Bool {
        guard let away else { return false }
        return !suggestedTimes.isEmpty || !(away.freeWords ?? "").isEmpty
    }

    /// The free chips, in order, four at most.
    var suggestedTimes: [LessonClockTime] {
        (away?.suggestions ?? []).prefix(Self.maxSuggestions).map(LessonClockTime.init(minutesAfterMidnight:))
    }

    /// The legend for the away mark shows only when a quick time carries one.
    var showsAwayNote: Bool { !markedQuickMinutes.isEmpty }

    /// "Everyone's free": up to four chips the width of a quick time, then the
    /// "Free all…" words. A chip sets its time, quarter hour or not, and closes.
    private func everyonesFree(_ away: LessonTimeAway) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.verySmall) {
            sectionHeader("Everyone's free")
            let chips = suggestedTimes
            if !chips.isEmpty {
                Grid(horizontalSpacing: AppTheme.Spacing.verySmall, verticalSpacing: AppTheme.Spacing.verySmall) {
                    GridRow {
                        ForEach(chips, id: \.self) { time in
                            freeChip(time)
                        }
                        // Empty cells keep each chip as wide as a quick time below.
                        ForEach(chips.count..<Self.columns, id: \.self) { _ in
                            Color.clear.frame(height: 1).accessibilityHidden(true)
                        }
                    }
                }
            }
            if let words = away.freeWords, !words.isEmpty {
                Text(words)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func freeChip(_ time: LessonClockTime) -> some View {
        Button {
            choose(time)
            dismiss()
        } label: {
            Text(LessonTimeText.chip(time))
        }
        .buttonStyle(QuickTimeButtonStyle(isCurrent: time == current, isTaken: false, isAway: false))
        .accessibilityLabel(LessonTimeText.spoken(time))
        .accessibilityValue("Everyone's free")
        .accessibilityHint("Sets the start time.")
        .accessibilityAddTraits(time == current ? .isSelected : [])
    }

    /// The Away list: one row per group, in time order.
    private func awayList(_ rows: [String]) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xsmall) {
            sectionHeader("Away")
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                Text(row)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
/// still be picked: a deliberate double-booking is rare but real, decision 7),
/// and dimmed with a small leaving figure in the top leading corner when a
/// child is away during it (co-teacher times, decision 4: never drawn disabled).
private struct QuickTimeButtonStyle: ButtonStyle {
    let isCurrent: Bool
    let isTaken: Bool
    let isAway: Bool

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
            .overlay(alignment: .topLeading) {
                if isAway {
                    Image(systemName: LessonTimePicker.awaySymbol)
                        .font(.system(size: 6, weight: .bold))
                        .foregroundStyle(foreground)
                        .padding(.top, 2)
                        .padding(.leading, 3)
                        .accessibilityHidden(true)
                }
            }
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
        if isTaken || isAway { return AnyShapeStyle(.secondary) }
        return AnyShapeStyle(.primary)
    }

    private var background: AnyShapeStyle {
        if isCurrent { return AnyShapeStyle(Color.accentColor) }
        return AnyShapeStyle(.quaternary)
    }
}

// MARK: - Help

private extension View {
    /// The away sentence as the pointer's help text (the Mac and iPad); nothing
    /// when the time isn't marked.
    @ViewBuilder
    func awayHelp(_ sentence: String?) -> some View {
        if let sentence {
            help(sentence)
        } else {
            self
        }
    }
}
