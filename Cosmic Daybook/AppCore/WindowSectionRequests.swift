//
//  WindowSectionRequests.swift
//  Cosmic Daybook
//
//  The Go menu's section switches, asked for in one main window.
//

import SwiftUI

/// One main window's pending Lessons & Work lens, for that window's
/// workspace to open on.
///
/// RootView makes one per window and passes it down by environment. The Go
/// menu goes through the key window's `QuickCaptureActions`, which switch
/// that window's section and, for Lessons & Work, land the lens here; it used
/// to set the shared `AppRouter`, which every window observes, so with two
/// windows a background one could move instead of the key one.
/// `AppRouter.navigateTo` and `navigateToLessonsAndWork` stay for callers
/// with no window (Siri, notifications, a request made while the app is
/// still opening).
@Observable
final class WindowSectionRequests {
    private(set) var lessonsAndWork: AppRouter.LessonsAndWorkRequest?

    func ask(_ request: AppRouter.LessonsAndWorkRequest) {
        lessonsAndWork = request
    }

    /// Takes the pending lens once. Nothing pending writes nothing, so a
    /// workspace appearing doesn't wake the window's other observers.
    func consumeLessonsAndWork() -> AppRouter.LessonsAndWorkRequest? {
        guard let request = lessonsAndWork else { return nil }
        lessonsAndWork = nil
        return request
    }

    /// Where going to `item` takes a window, the same way
    /// `AppRouter.navigateTo` does: an aliased section opens its canonical
    /// one, and Lessons & Work opens on To Schedule.
    static func route(
        to item: RootView.NavigationItem
    ) -> (section: RootView.NavigationItem, lessonsAndWork: AppRouter.LessonsAndWorkRequest?) {
        if item == .planningAgenda {
            return (.planningAgenda, AppRouter.LessonsAndWorkRequest(scope: .toSchedule))
        }
        return (item.canonical, nil)
    }
}

extension EnvironmentValues {
    /// The enclosing main window's section requests. Nil outside a main
    /// window (a detail window, a preview), where only the router's apply.
    @Entry var windowSectionRequests: WindowSectionRequests?
}
