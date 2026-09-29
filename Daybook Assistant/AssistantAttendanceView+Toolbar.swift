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
            .accessibilityHint("Your guide, your name, and leaving the classroom")
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
            .accessibilityLabel("Previous school day")

            Button {
                showingDatePicker = true
            } label: {
                // One line: "Today  Tue, Sep 29", or just the date on
                // another day.
                HStack(spacing: 5) {
                    if viewModel.isLocked {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .accessibilityLabel("Locked")
                    }
                    if viewModel.isToday {
                        Text("Today")
                            .font(.headline)
                    }
                    Text(viewModel.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                        .font(viewModel.isToday ? .subheadline : .headline)
                        .foregroundStyle(viewModel.isToday ? .secondary : .primary)
                }
                .lineLimit(1)
                .foregroundStyle(.primary)
            }
            .accessibilityLabel(viewModel.date.formatted(date: .complete, time: .omitted))
            .accessibilityHint("Choose another day")

            Button {
                step(viewModel, forward: true)
            } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel("Next school day")
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
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) > 80, abs(dx) > abs(dy) * 2 else { return }
                step(viewModel, forward: dx < 0)
            }
    }
}
