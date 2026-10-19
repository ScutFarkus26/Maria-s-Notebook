// ScreenLanding.swift
// Where a retired sidebar row opens inside the screen that took its place.

import Foundation

/// The view a retired destination lands on (Simplify the app, Phase 11).
/// Three-Year View, Progress Dashboard and Lesson Recall became views of the
/// Class Grid; Stories and Procedures, types in Resources; Parsha Calendar,
/// the year list on This Week's Parsha. A saved scene or a router jump to one
/// of them sets `AppRouter.screenLanding`, and the screen takes it once.
nonisolated enum ScreenLanding: Hashable, Sendable {
    case classGrid(ClassGridViewKind)
    case resources(LibraryKind)
    case parshaYearList
}
