// AttendanceExpandedView+DayEvents.swift
// The band's row of the day's comings and goings: pickups to come,
// departures and returns.

import SwiftUI

extension AttendanceExpandedView {

    /// "Dalia S leaves 2:30", "Maya S left 12:30", "Etty K back 12:40", in
    /// the order they happen.
    var dayEvents: [AttendanceDayEvent] {
        viewModel.rows.flatMap { row -> [AttendanceDayEvent] in
            let name = row.student.shortName
            var events: [AttendanceDayEvent] = []
            if let leaves = AttendanceRules.pendingPickup(row) {
                events.append(AttendanceDayEvent(id: "\(row.id)-leaving", time: leaves,
                                       text: "\(name) leaves \(AttendanceClock.string(leaves))", kind: .leaving))
            }
            if row.status == .leftEarly, let left = row.leftAt {
                events.append(AttendanceDayEvent(id: "\(row.id)-left", time: left,
                                       text: "\(name) left \(AttendanceClock.string(left))", kind: .left))
            }
            if AttendanceRules.tripText(row) != nil, let back = row.returnedAt {
                events.append(AttendanceDayEvent(id: "\(row.id)-back", time: back,
                                       text: "\(name) back \(AttendanceClock.string(back))", kind: .back))
            }
            return events
        }
        .sorted { $0.time < $1.time }
    }

    var dayEventsRow: some View {
        HStack(spacing: AppTheme.Spacing.small) {
            Text(viewModel.isToday ? "Today" : "That day")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(dayEvents) { event in
                        Label(event.text, systemImage: Self.symbol(for: event.kind))
                            .font(.caption.weight(.medium))
                            .monospacedDigit()
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Self.tint(for: event.kind).opacity(0.14), in: Capsule())
                            .foregroundStyle(Self.tint(for: event.kind))
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }

    private static func symbol(for kind: AttendanceDayEvent.Kind) -> String {
        switch kind {
        case .leaving: return "figure.walk.departure"
        case .left: return "arrow.right"
        case .back: return "arrow.uturn.backward"
        }
    }

    private static func tint(for kind: AttendanceDayEvent.Kind) -> Color {
        switch kind {
        case .leaving: return .purple
        case .left: return .secondary
        case .back: return .green
        }
    }
}

/// One pickup, departure or return on the day on screen.
struct AttendanceDayEvent: Identifiable {
    enum Kind { case leaving, left, back }

    let id: String
    let time: Date
    let text: String
    let kind: Kind
}
