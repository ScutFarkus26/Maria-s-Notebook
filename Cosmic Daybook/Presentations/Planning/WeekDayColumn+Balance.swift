// WeekDayColumn+Balance.swift
// The day column's clash warning, and the button that clears it.
//
// The button lives in the day header — the one part of a column that does not
// scroll away under a long morning — and it exists only on days that have a
// clash, so four clean days carry no chrome for it at all. It is the badge and
// the fix in one control: a guide who can read "2 clashes" from across the
// strip can press the same thing he just read.
//
// It says "clashes" and not "Fix", because two halves cannot always separate a
// day and the toast has to be free to come back with a child still doubled up.

import SwiftUI

extension WeekDayColumn {
    /// Children called twice in the same half, by the half they clash in.
    ///
    /// Keyed by half because a card only ever draws the ring for its own half —
    /// a child doubled up in the morning should not light up on the single
    /// afternoon lesson she is properly booked for.
    var clashingStudentIDs: [DayPeriod: Set<UUID>] {
        DayBalanceService.clashes(for: scheduledLessonsForDay, using: calendar)
    }

    /// How many children are doubled up today. A child clashing in both halves
    /// counts once: she is one child either way, and one line in the warning.
    var clashCount: Int {
        clashingStudentIDs.values.reduce(into: Set<UUID>()) { $0.formUnion($1) }.count
    }

    @ViewBuilder
    var balanceButton: some View {
        let count = clashCount
        if count > 0 {
            Button(action: balanceDay) {
                HStack(spacing: 3) {
                    Image(systemName: "wand.and.sparkles")
                    Text(count == 1 ? "1 clash" : "\(count) clashes")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppColors.attention)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(AppColors.attention.opacity(UIConstants.OpacityConstants.light))
                )
                .overlay(
                    Capsule().stroke(
                        AppColors.attention.opacity(UIConstants.OpacityConstants.moderate),
                        lineWidth: 1
                    )
                )
            }
            .buttonStyle(.plain)
            .help("Rearrange this day so no child has two lessons in the same half")
            .accessibilityLabel(
                count == 1
                    ? "1 child booked twice in the same half. Rearrange this day."
                    : "\(count) children booked twice in the same half. Rearrange this day."
            )
        }
    }

    /// Rearranges the day, then says what it managed — including what it did
    /// not, because a guide who is told nothing will go looking for a ring that
    /// was never going to clear.
    func balanceDay() {
        let context = viewContext
        var result: DayBalanceService.Result?
        adaptiveWithAnimation(Self.balanceAnimation) {
            result = DayBalanceService.balance(
                day: day,
                assignments: scheduledLessonsForDay,
                calendar: calendar,
                context: context
            )
        }
        guard let result else { return }

        let restoring = result.previousTimes
        ToastService.shared.show(
            DayBalanceService.summary(for: result, context: context),
            type: result.isClean ? .success : .warning,
            duration: 4,
            // Nothing moved, nothing to take back — offering Undo there would
            // be a button that does nothing.
            undoAction: restoring.isEmpty ? nil : {
                // Toast buttons fire on the main actor; this only borrows that.
                MainActor.assumeIsolated {
                    adaptiveWithAnimation(Self.balanceAnimation) {
                        DayBalanceService.restore(restoring, in: context)
                    }
                }
            }
        )
    }

    /// Shared by the rearrange and its Undo, so a day travels back along the
    /// path it came.
    static var balanceAnimation: Animation {
        .spring(response: 0.32, dampingFraction: 0.86)
    }
}
