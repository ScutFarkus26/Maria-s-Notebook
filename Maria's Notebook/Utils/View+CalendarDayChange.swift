// View+CalendarDayChange.swift
// Reusable calendar-day rollover observation for "Today"-style screens.

import SwiftUI

/// Invokes an action when the calendar day rolls over while the view is alive.
///
/// Foundation posts `.NSCalendarDayChanged` at midnight (and once on wake if
/// the device slept through it), but delivery timing is not guaranteed and a
/// suspended app runs no code at midnight, so the action is also invoked when
/// the scene becomes active. Handlers must therefore be idempotent: compare
/// against the day last rendered and only react when it actually changed.
private struct CalendarDayChangeModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    let action: @MainActor () -> Void

    func body(content: Content) -> some View {
        content
            .task {
                // The notification arrives on an arbitrary thread and
                // Notification is not Sendable — map each element to Void so
                // this MainActor task only ever receives a Sendable value.
                let dayChanges = NotificationCenter.default
                    .notifications(named: .NSCalendarDayChanged)
                    .map { _ in () }
                for await _ in dayChanges {
                    action()
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    action()
                }
            }
    }
}

extension View {
    /// Runs `action` on the main actor when the calendar day changes —
    /// midnight rollover, wake from sleep, or resume from suspension.
    /// `action` is also called on scene activation as a safety net, so it
    /// must be idempotent.
    func onCalendarDayChange(perform action: @escaping @MainActor () -> Void) -> some View {
        modifier(CalendarDayChangeModifier(action: action))
    }
}
