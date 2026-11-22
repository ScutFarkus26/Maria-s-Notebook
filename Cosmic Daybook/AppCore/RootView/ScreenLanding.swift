// ScreenLanding.swift
// Where a retired sidebar row opens inside the screen that took its place.

import Foundation

/// The view a retired destination lands on (Simplify the app, Phase 11).
/// Three-Year View and Progress Dashboard became views of the Class Grid
/// (Lesson Recall did too, until Recall was taken out on 2026-11-21); Stories and Procedures were
/// types in Resources until it was taken out on 2026-11-22; Parsha Calendar, the year list on
/// This Week's Parsha. A saved scene or a router jump to one
/// of them sets `AppRouter.screenLanding`, and the screen takes it once.
nonisolated enum ScreenLanding: Hashable, Sendable {
    case classGrid(ClassGridViewKind)
    case parshaYearList
}
