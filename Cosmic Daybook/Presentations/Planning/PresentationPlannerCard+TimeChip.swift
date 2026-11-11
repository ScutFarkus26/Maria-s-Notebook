// PresentationPlannerCard+TimeChip.swift
// A Scheduled card's start-time chip (docs/Plans/Plan - Lesson times on
// cards.md, Phase 3): "10:00" in blue when the guide set a time, a dashed
// "Set time" with a clock when not, and amber when another lesson that day
// starts at the same minute. It leads the line of children's names rather
// than ending the title row, as the plan first had it: a day column is about
// 170 points wide, and a chip beside the title squeezed most titles down to a
// letter or two. On the names line it wraps like a name chip instead.
//
// The chip is a button that opens the time picker as a popover anchored to the
// chip itself (a sheet on the iPhone). Which card's picker is up is the day
// column's state, so its right-click menu and VoiceOver can open the same
// popover. The card stays one combined accessibility element: the time is
// spoken in its label and the picker is a custom action (decision 10).
//
// Split from the card for SwiftLint's type-length limit; the state these read
// is declared in PresentationPlannerCard.swift.

import SwiftUI

extension PresentationPlannerCard {

    /// What the chip shows and does. Nil on the card draws no chip (the inbox,
    /// where a lesson has no day yet).
    struct TimeChip {
        /// The start time the guide set; nil draws "Set time".
        let time: LessonClockTime?
        /// Another lesson that day starts at the same minute (decision 7).
        var isClash = false
        /// Whether this card's picker is up. Nil (a drag preview) draws the
        /// chip as plain, with nothing to press.
        var isPickerShown: Binding<Bool>?
        /// The picker the chip opens, built by the day column, which knows the
        /// day's other times and saves the change.
        var picker: (() -> LessonTimePicker)?
    }

    /// The popover's item: the picker is about this card's lesson.
    struct TimePickerTarget: Identifiable {
        let id: UUID
    }

    /// The chip's three looks, decided once so the tests and the drawing agree.
    enum TimeChipStyle: Equatable {
        case unset
        case set
        case clash

        init(_ chip: TimeChip) {
            if chip.time == nil {
                self = .unset
            } else {
                self = chip.isClash ? .clash : .set
            }
        }

        var tint: Color {
            switch self {
            case .unset: .secondary
            case .set: AppColors.info
            case .clash: PresentationPlannerCard.clashRing
            }
        }
    }

    // MARK: - Drawing

    /// AM/PM, where a card has no time chip — kept monochrome deliberately:
    /// the card already spends color on the subject area, the age strip and
    /// the two warnings, and a fourth color language would make none of them
    /// read. The week calendar turns it off; its cards carry a time chip.
    @ViewBuilder
    var periodBadge: some View {
        if let period, showsPeriodBadge {
            Text(period.abbreviation)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, UIConstants.CardSize.statusPillHorizontal)
                .padding(.vertical, 2)
                .capsuleFill(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
                .accessibilityLabel(period.label)
        }
    }

    @ViewBuilder
    func timeChipView(_ chip: TimeChip) -> some View {
        if let isShown = chip.isPickerShown, let picker = chip.picker {
            Button {
                isShown.wrappedValue = true
            } label: {
                timeChipLabel(chip)
                    // A hit area bigger than the chip without making the title
                    // row any taller (Apple: at least 28 pt on iOS, 20 on the Mac).
                    .padding(.vertical, Self.chipHitPadding)
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                    .padding(.vertical, -Self.chipHitPadding)
                    .padding(.horizontal, -4)
            }
            .buttonStyle(.plain)
            #if os(macOS)
            .help(chip.time == nil ? "Set a start time" : "Change the start time")
            #endif
            .lessonTimePicker(item: pickerTarget(isShown), arrowEdge: .bottom) { _ in picker() }
        } else {
            timeChipLabel(chip)
        }
    }

    #if os(macOS)
    private static let chipHitPadding: CGFloat = 3
    #else
    private static let chipHitPadding: CGFloat = 7
    #endif

    private func timeChipLabel(_ chip: TimeChip) -> some View {
        let style = TimeChipStyle(chip)
        return HStack(spacing: 3) {
            switch style {
            case .unset:
                Image(systemName: "clock")
                Text("Set time")
            case .set:
                Text(chip.time.map { LessonTimeText.chip($0) } ?? "")
                    .monospacedDigit()
            case .clash:
                // A glyph as well as the color, as the name chips do, so the
                // clash reads to a guide who can't tell amber from blue.
                Image(systemName: "exclamationmark.triangle.fill")
                    .imageScale(.small)
                Text(chip.time.map { LessonTimeText.chip($0) } ?? "")
                    .monospacedDigit()
            }
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(style.tint)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, UIConstants.CardSize.statusPillHorizontal)
        .padding(.vertical, 2)
        .background {
            if style == .unset {
                Capsule().strokeBorder(
                    Color.secondary.opacity(UIConstants.OpacityConstants.moderate),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                )
            } else {
                Capsule().fill(style.tint.opacity(UIConstants.OpacityConstants.light))
            }
        }
        .accessibilityHidden(true)
    }

    private func pickerTarget(_ isShown: Binding<Bool>) -> Binding<TimePickerTarget?> {
        let id = snapshot.id
        return Binding(
            get: { isShown.wrappedValue ? TimePickerTarget(id: id) : nil },
            set: { isShown.wrappedValue = $0 != nil }
        )
    }

    // MARK: - VoiceOver

    /// "Set Time" or "Change Time", opening the same picker as the chip.
    @ViewBuilder
    var timeAccessibilityAction: some View {
        if let chip = timeChip, let isShown = chip.isPickerShown, chip.picker != nil {
            Button(chip.time == nil ? "Set Time" : "Change Time") {
                isShown.wrappedValue = true
            }
        }
    }

    /// The card's spoken label: lesson, children, half, time, then the notes
    /// that change the plan. The card combines its children, so the chip's and
    /// the badge's own words are replaced by this — whatever isn't said here
    /// isn't said.
    static func spokenLabel(
        lessonName: String,
        studentNames: [String],
        period: DayPeriod?,
        timeChip: TimeChip?,
        showFirstLine: String?
    ) -> String {
        let time = timeChip?.time
        return [
            lessonName,
            studentNames.joined(separator: ", "),
            period?.label,
            time.map { LessonTimeText.spokenPhrase($0) },
            time != nil && timeChip?.isClash == true ? "another lesson at the same time" : nil,
            showFirstLine
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: ", ")
    }
}
