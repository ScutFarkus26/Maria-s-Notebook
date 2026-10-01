import SwiftUI

// MARK: - Toolbar and stepping

extension AssistantAttendanceView {

    // MARK: - Toolbar

    @ToolbarContentBuilder
    var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if let viewModel, !viewModel.isToday {
                Button("Today") { viewModel.load(Date()) }
            }
        }
        ToolbarItem(placement: .principal) {
            if let viewModel {
                dayHeader(viewModel)
            }
        }
        // Stands in for the hidden status bar's clock, on today only: another
        // day adds a Today button, and the bar has no room for both.
        if hidesStatusBar, viewModel?.isToday ?? true {
            if #available(iOS 26.0, *) {
                // Plain text, not a glass button beside the classroom button.
                clockItem.sharedBackgroundVisibility(.hidden)
            } else {
                clockItem
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showingClassroom = true
            } label: {
                Label("Classroom", systemImage: "person.crop.circle")
                    .labelStyle(.iconOnly)
            }
            .accessibilityHint("Your guide, what the tiles mean, your name, and leaving the classroom")
        }
    }

    private var clockItem: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            TimelineView(.everyMinute) { context in
                // As the status bar shows it ("8:24 AM"): omitting AM/PM
                // makes the formatter pad the hour ("08:24").
                Text(context.date.formatted(date: .omitted, time: .shortened))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .fixedSize() // iOS 27's toolbar otherwise truncates it to "1:43…".
            }
        }
    }

    private func dayHeader(_ viewModel: AssistantAttendanceViewModel) -> some View {
        HStack(spacing: 4) {
            Button {
                step(viewModel, forward: false)
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!viewModel.canStepBack)
            .accessibilityLabel("Previous school day")

            Button {
                showingDatePicker = true
            } label: {
                // One line: "Today  Tue, Sep 29 · Day 37", and on a milestone
                // "Day 100" or "First Day" in Today's place. An SE never has
                // room for the day number beside its clock (the greeting
                // has it); the toolbar doesn't limit the title's width, so
                // `ViewThatFits` can't tell.
                ViewThatFits(in: .horizontal) {
                    dayLine(viewModel, detail: hidesStatusBar ? .milestone : .full)
                    dayLine(viewModel, detail: .milestone)
                    dayLine(viewModel, detail: .dateOnly)
                }
            }
            .accessibilityLabel(dayAccessibilityLabel(viewModel))
            .accessibilityHint("Choose another day")

            Button {
                step(viewModel, forward: true)
            } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel("Next school day")
        }
    }

    /// How much of the day the header says, widest first.
    private enum DayLineDetail {
        case full
        case milestone
        case dateOnly
    }

    static let milestoneStyle = LinearGradient(
        colors: [.pink, .orange, .purple],
        startPoint: .leading,
        endPoint: .trailing
    )

    private func dayLine(_ viewModel: AssistantAttendanceViewModel, detail: DayLineDetail) -> some View {
        HStack(spacing: 5) {
            if viewModel.isLocked {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .accessibilityLabel("Locked")
            }
            if let milestone = viewModel.milestone, viewModel.isToday || detail != .dateOnly {
                Text(milestone.title)
                    .font(.headline)
                    .foregroundStyle(Self.milestoneStyle)
            } else if viewModel.isToday {
                Text("Today")
                    .font(.headline)
            }
            let showsLabel = viewModel.isToday || (viewModel.milestone != nil && detail != .dateOnly)
            Text(viewModel.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                .font(showsLabel ? .subheadline : .headline)
                .foregroundStyle(showsLabel ? .secondary : .primary)
            if detail == .full, viewModel.milestone == nil, let number = viewModel.dayNumber {
                Text("· Day \(number)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .lineLimit(1)
        .fixedSize()
        .foregroundStyle(.primary)
    }

    /// "Tuesday, September 29, 2026, school day 37".
    private func dayAccessibilityLabel(_ viewModel: AssistantAttendanceViewModel) -> String {
        let date = viewModel.date.formatted(date: .complete, time: .omitted)
        switch viewModel.milestone {
        case .firstDay: return "\(date), the first day of school"
        case .hundredthDay: return "\(date), the 100th day of school"
        case nil: return viewModel.dayNumber.map { "\(date), school day \($0)" } ?? date
        }
    }

    /// A step through school days, the grid sliding in from that side.
    private func step(_ viewModel: AssistantAttendanceViewModel, forward: Bool) {
        stepEdge = forward ? .trailing : .leading
        withAnimation(.smooth(duration: 0.3)) {
            viewModel.step(forward: forward)
        }
    }

    /// A clearly sideways swipe steps a day; anything more vertical is left
    /// to scrolling, and a long press to the tile's menu.
    func daySwipe(_ viewModel: AssistantAttendanceViewModel) -> some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                guard let forward = AttendanceDaySwipe.step(for: value.translation) else { return }
                step(viewModel, forward: forward)
            }
    }
}
