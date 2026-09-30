// AttendanceExpandedView+Delight.swift
// The Daybook Assistant's small pleasures on the notebook's roll: "Welcome
// back, Maya", the school day's number, Day 100's confetti, and (on the
// iPhone's tiles, if turned on) the Montessori bells.

import SwiftUI

extension AttendanceExpandedView {

    /// A mark made here completed the roll: "Everyone's here · 8:14" (or "for
    /// day 100"), the confetti on day 100, and the bells' run.
    func rollCompleted() {
        let milestone = viewModel.isToday ? viewModel.milestone : nil
        finishedLine = AttendanceRules.completionText(
            viewModel.rows,
            at: viewModel.isToday ? Date() : nil,
            everyone: milestone?.everyoneHere ?? "Everyone's here"
        )
        if milestone == .hundredthDay { confettiBursts += 1 }
        #if os(iOS)
        if isCompact { AttendanceBells.shared.play(milestone == .hundredthDay ? .hundredthDay : .everyoneMarked) }
        #endif
    }

    #if os(iOS)
    /// Her mark's bell on the iPhone's tiles, if the bells are on: the next
    /// one up the scale for a child here, the low C damped for an absence,
    /// nothing for clearing. `before` is the row as it was before the mark.
    func ring(after before: AttendanceRow) {
        guard isCompact, AttendanceBells.isOn,
              let marked = viewModel.rows.first(where: { $0.id == before.id }),
              marked.status != before.status else { return }
        switch TileTapMotion.Kind(marked.status) {
        case .here:
            AttendanceBells.shared.play(.here(count: viewModel.rows.count(where: \.isHere)))
        case .away:
            AttendanceBells.shared.play(.away)
        case .cleared:
            break
        }
    }
    #endif

    /// The welcome line's timing, the confetti, and "Day 37" in the title.
    var delightFollowUps: AttendanceDelightFollowUps {
        AttendanceDelightFollowUps(
            welcome: viewModel.welcome,
            welcomeLine: $welcomeLine,
            confettiBursts: confettiBursts,
            dayLabel: showsDayInTitle ? viewModel.dayLabel : nil,
            showsDayInTitle: showsDayInTitle
        )
    }
}

/// The attendance screen's welcome line, confetti and title, as a modifier so
/// its body stays one line there.
struct AttendanceDelightFollowUps: ViewModifier {
    let welcome: AttendanceViewModel.Welcome?
    @Binding var welcomeLine: String?
    let confettiBursts: Int
    let dayLabel: String?
    /// Only the Attendance screen's own title; Today keeps its own.
    let showsDayInTitle: Bool

    func body(content: Content) -> some View {
        titled(content)
            .overlay { HundredthDayConfetti(trigger: confettiBursts) }
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
