// DetailWindowClassroom.swift
// One detail window's part in a classroom switch.

import Foundation

/// One detail window's part in a classroom switch (bug hunt 2026-10-17 #31):
/// closing once the classroom it opened in is no longer showing, where its
/// record isn't, and, for a window that holds typing (an observation, a
/// topic, a meeting or report), counted in `OpenDetailWindows` while its host
/// is on screen, so a switch asks first. A student, lesson or album window
/// doesn't count: on the Mac children open in their own windows, so counting
/// every window asked on almost every switch (review c #12).
@Observable
final class DetailWindowClassroom {
    /// The classroom the host first showed in.
    private(set) var openedIn: ClassroomWorkspace?

    @ObservationIgnored private let countsAsEditor: Bool
    @ObservationIgnored private let registry: OpenDetailWindows
    /// This window's place in `registry`.
    @ObservationIgnored private let registration = UUID()

    init(countsAsEditor: Bool, registry: OpenDetailWindows = .shared) {
        self.countsAsEditor = countsAsEditor
        self.registry = registry
    }

    /// Whether the window belongs to a classroom no longer showing, so it closes.
    func isClosing(showing selection: ClassroomWorkspace) -> Bool {
        guard let openedIn else { return false }
        return openedIn != selection
    }

    /// The host came on screen while `selection` is showing.
    func hostAppeared(showing selection: ClassroomWorkspace) {
        if openedIn == nil { openedIn = selection }
        if countsAsEditor, !isClosing(showing: selection) {
            registry.opened(registration)
        }
    }

    /// The host left the screen: the window closed, or a restore took the store away.
    func hostDisappeared() {
        registry.closed(registration)
    }

    /// The classroom switched to `selection`. A window of the other classroom
    /// stops counting at once, before it has closed: one that doesn't close
    /// (a sheet still closing in it) mustn't keep asking (review c #4).
    func classroomChanged(to selection: ClassroomWorkspace) {
        if isClosing(showing: selection) {
            registry.closed(registration)
        }
    }
}
