// AttendanceExpandedView+Delight.swift
// The Daybook Assistant's small pleasures that the notebook's roll keeps:
// "Welcome back, Maya" and the school day's number. Its bells and Day 100's
// confetti stay in the Assistant (Simplify round two, 2026-11-03).

import SwiftUI

extension AttendanceExpandedView {

    /// A mark made here completed the roll: "Everyone's here · 8:14" (or "for
    /// day 100").
    func rollCompleted() {
        let milestone = viewModel.isToday ? viewModel.milestone : nil
        finishedLine = AttendanceRules.completionText(
            viewModel.rows,
            at: viewModel.isToday ? Date() : nil,
            everyone: milestone?.everyoneHere ?? "Everyone's here"
        )
    }

    /// The welcome line's timing and "Day 37" in the title.
    var delightFollowUps: AttendanceDelightFollowUps {
        AttendanceDelightFollowUps(
            welcome: viewModel.welcome,
            welcomeLine: $welcomeLine,
            dayLabel: showsDayInTitle ? viewModel.dayLabel : nil,
            showsDayInTitle: showsDayInTitle
        )
    }
}

/// The attendance screen's welcome line and title, as a modifier so
/// its body stays one line there.
struct AttendanceDelightFollowUps: ViewModifier {
    let welcome: AttendanceViewModel.Welcome?
    @Binding var welcomeLine: String?
    let dayLabel: String?
    /// Only the Attendance screen's own title; Today keeps its own.
    let showsDayInTitle: Bool

    func body(content: Content) -> some View {
        titled(content)
            .onChange(of: welcome) { _, welcome in
                welcomeLine = welcome.map { "Welcome back, \($0.name)" }
            }
            .task(id: welcomeLine) {
                guard welcomeLine != nil, (try? await Task.sleep(for: .seconds(3))) != nil else { return }
                welcomeLine = nil
            }
    }

    /// Up to the Attendance screen's date (`AttendanceDayLabelKey`). Not a
    /// navigation subtitle: on the iPhone that draws twice, under the date
    /// and under the large title.
    @ViewBuilder
    private func titled(_ content: Content) -> some View {
        if showsDayInTitle {
            content.preference(key: AttendanceDayLabelKey.self, value: dayLabel)
        } else {
            content
        }
    }
}

/// "Day 37" from the roll up to the Attendance screen's date: under it on
/// the iPhone, beside it on the Mac and iPad.
struct AttendanceDayLabelKey: PreferenceKey {
    static let defaultValue: String? = nil

    static func reduce(value: inout String?, nextValue: () -> String?) {
        value = value ?? nextValue()
    }
}
