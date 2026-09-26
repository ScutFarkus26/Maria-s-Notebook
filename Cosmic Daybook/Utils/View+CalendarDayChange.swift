// View+CalendarDayChange.swift
// Reusable calendar-day rollover observation for "Today"-style screens.

import SwiftUI

/// Invokes an action when the calendar day rolls over while the view is alive.
///
/// Foundation posts `.NSCalendarDayChanged` at midnight (and once on wake if
/// the device slept through it), but delivery timing is not guaranteed and a
/// suspended app runs no code at midnight, so a scene activation also runs the
/// action — when `CalendarDayActivationGate` finds the day, the school calendar
/// or the counter epoch moved since the view last caught up (on appear, or when
/// the action last ran). Handlers must still be idempotent: the notification and
/// an activation can both fire for one rollover.
private struct CalendarDayChangeModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    let action: @MainActor () -> Void
    @State private var gate = CalendarDayActivationGate()

    func body(content: Content) -> some View {
        content
            .onAppear {
                // Every caller loads itself on appear.
                gate.record(.current())
            }
            .task {
                // The notification arrives on an arbitrary thread and
                // Notification is not Sendable — map each element to Void so
                // this MainActor task only ever receives a Sendable value.
                let dayChanges = NotificationCenter.default
                    .notifications(named: .NSCalendarDayChanged)
                    .map { _ in () }
                for await _ in dayChanges {
                    gate.record(.current())
                    action()
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active, gate.activationIsDue(.current()) {
                    action()
                }
            }
    }
}

extension View {
    /// Runs `action` on the main actor when the calendar day changes —
    /// midnight rollover, wake from sleep, or resume from suspension.
    /// A scene activation runs it only when the day, the school calendar or the
    /// counter epoch moved since the view appeared or the action last ran, so
    /// load on appear yourself, and keep `action` idempotent.
    func onCalendarDayChange(perform action: @escaping @MainActor () -> Void) -> some View {
        modifier(CalendarDayChangeModifier(action: action))
    }
}
