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

    /// What the day's badge counts: children booked twice in one half (a
    /// child clashing in both halves counts once: she is one child either way,
    /// and one line in the warning), and start times given to more than one
    /// lesson, which the guide can't both give (plan "Lesson times on cards",
    /// decision 7), and lessons whose set time overlaps a co-teacher's group
    /// for one of their children (plan "Co-teacher times when scheduling",
    /// decision 6): one each. Those are their own kind, counted and spoken
    /// apart; they only borrow the amber look.
    struct DayClashes: Equatable {
        var children = 0
        /// Start times that two or more lessons share: one clash each.
        var sameTimes = 0
        /// The lessons at those start times, for the spoken line.
        var sameTimeLessons = 0
        /// Lessons with a set time while one of their children is away.
        var away = 0

        var total: Int { children + sameTimes + away }

        /// The plain badge's words for its kinds: rearranging never moves a
        /// lesson with a set time, so only changing a time clears these.
        var timedParts: [String] {
            var parts: [String] = []
            if sameTimes > 0 {
                parts.append(sameTimes == 1
                    ? "\(sameTimeLessons) lessons at the same time"
                    : "\(sameTimeLessons) lessons sharing \(sameTimes) start times")
            }
            if away > 0 {
                // "2 with a child away" after the same-time part; standing
                // alone it names the lessons.
                parts.append(parts.isEmpty
                    ? (away == 1 ? "1 lesson" : "\(away) lessons") + " while a child is with another teacher"
                    : AwayText.badgeCount(away))
            }
            return parts
        }

        /// The plain badge's help: what it counts, and what clears it.
        var plainHelp: String {
            if away == 0 { return "Two lessons start at the same time. Change one of the times." }
            let line = timedParts.joined(separator: ", ")
            let lead = line.prefix(1).uppercased() + line.dropFirst() + "."
            return sameTimes > 0
                ? lead + " Change one of the times."
                : lead + (away == 1 ? " Change its time to clear it." : " Change their times to clear it.")
        }

        /// "1 clash", "3 clashes".
        var badgeText: String { total == 1 ? "1 clash" : "\(total) clashes" }

        /// What VoiceOver says for the badge, and, when it is the Rearrange
        /// button, what pressing it does.
        var spokenLabel: String {
            var parts: [String] = []
            if children > 0 {
                parts.append(children == 1
                    ? "1 child booked twice in the same half"
                    : "\(children) children booked twice in the same half")
            }
            parts += timedParts
            let line = parts.joined(separator: ", ")
            let sentence = line.prefix(1).uppercased() + line.dropFirst() + "."
            return children > 0 ? sentence + " Rearrange this day." : sentence
        }
    }

    /// The day's clashes, from the children doubled up in each half and each
    /// lesson's set start time (minutes after midnight; untimed lessons absent).
    /// `awayClashes` is the number of timed lessons with a child away then.
    static func dayClashes(
        childClashes: [DayPeriod: Set<UUID>],
        setMinutes: [Int],
        awayClashes: Int = 0
    ) -> DayClashes {
        let perMinute = setMinutes.reduce(into: [Int: Int]()) { $0[$1, default: 0] += 1 }
        return DayClashes(
            children: childClashes.values.reduce(into: Set<UUID>()) { $0.formUnion($1) }.count,
            sameTimes: perMinute.values.filter { $0 > 1 }.count,
            sameTimeLessons: perMinute.values.filter { $0 > 1 }.reduce(0, +),
            away: awayClashes
        )
    }

    var dayClashes: DayClashes {
        Self.dayClashes(
            childClashes: clashingStudentIDs,
            setMinutes: scheduledLessonsForDay.compactMap { $0.setTimeMinute(using: calendar) },
            awayClashes: awayClashCount
        )
    }

    /// The day's timed lessons that overlap a co-teacher's group for one of
    /// their children. No words are needed to count, so no roster lookup.
    var awayClashCount: Int {
        guard !awayDay.isEmpty else { return 0 }
        return scheduledLessonsForDay.count { lesson in
            guard let start = lesson.setTimeMinute(using: calendar) else { return false }
            return !awayDay.clashes(children: lesson.studentIDs, start: start).isEmpty
        }
    }

    /// Only on a day with a clash. With a child doubled up it is the
    /// Rearrange button; with only lessons at the same time it is a plain
    /// badge, because rearranging never moves a lesson with a set time, so
    /// only changing one of the times can clear it.
    @ViewBuilder
    var balanceButton: some View {
        let clashes = dayClashes
        if clashes.children > 0 {
            Button(action: balanceDay) {
                clashBadge(clashes, systemImage: "wand.and.sparkles")
            }
            .buttonStyle(.plain)
            .help(clashes.sameTimes > 0 || clashes.away > 0
                ? "Rearrange this day so no child has two lessons in the same half. "
                    + "Lessons with a start time stay where they are."
                : "Rearrange this day so no child has two lessons in the same half")
            .accessibilityLabel(clashes.spokenLabel)
        } else if clashes.sameTimes > 0 || clashes.away > 0 {
            clashBadge(clashes, systemImage: "exclamationmark.triangle.fill")
                .help(clashes.plainHelp)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(clashes.spokenLabel)
        }
    }

    private func clashBadge(_ clashes: DayClashes, systemImage: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
            Text(clashes.badgeText)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(AppColors.attention)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .capsuleFill(AppColors.attention.opacity(UIConstants.OpacityConstants.light))
        .overlay(
            Capsule().stroke(
                AppColors.attention.opacity(UIConstants.OpacityConstants.moderate),
                lineWidth: 1
            )
        )
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
        dependencies.toastService.show(
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
