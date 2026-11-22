// NotebookLink.swift
// The app's own address for one item, `cosmicdaybook://<kind>/<id>`, so a
// link elsewhere (a Tide to-do's `link:` field) can open a child, a lesson or
// a follow-up in the main window.
//
// A link only opens: it never changes data. Anything malformed, of a kind
// this doesn't know, or naming an id that isn't in this notebook opens
// nothing and is logged. The main window receives it beside Handoff
// (`HandoffContinuationModifier`), and once the window's screen is up the
// screen looks the id up (`RootView.openLinkInThisWindow`) and opens it
// through the same route a Handoff takes.

import CoreData
import Foundation

nonisolated enum NotebookLink {
    /// The URL scheme, as registered under `CFBundleURLTypes` in both
    /// Info.plists.
    static let scheme = "cosmicdaybook"

    /// What an address names, before it is looked up in the notebook.
    enum Target: Equatable, Sendable {
        case student(UUID)
        case lesson(UUID)
        /// A todo, a goal or a flagged observation: the three kinds Claude's
        /// tools call a follow-up (`resolve_follow_up`).
        case followUp(UUID)

        /// The address's host for each kind.
        var host: String {
            switch self {
            case .student: "student"
            case .lesson: "lesson"
            case .followUp: "follow-up"
            }
        }
    }

    /// Where a looked-up link opens in a main window.
    enum Landing: Equatable {
        /// The route a Handoff takes: a child's page, a lesson.
        case handoff(Handoff.Destination)
        /// A section of the window.
        case section(RootView.NavigationItem)
    }

    // MARK: Addresses

    /// What `url` names, `cosmicdaybook://<kind>/<uuid>`, or nil unless
    /// every part is as that: this scheme, a known kind, one path part that
    /// is a UUID, and nothing else (no user, port, query or fragment).
    static func target(from url: URL) -> Target? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == scheme,
              parts.user == nil, parts.password == nil, parts.port == nil,
              parts.query == nil, parts.fragment == nil,
              let host = parts.host?.lowercased()
        else { return nil }

        let path = parts.path
        guard path.hasPrefix("/") else { return nil }
        let rest = path.dropFirst()
        guard !rest.isEmpty, !rest.contains("/"),
              let id = UUID(uuidString: String(rest))
        else { return nil }

        switch host {
        case "student": return .student(id)
        case "lesson": return .lesson(id)
        case "follow-up": return .followUp(id)
        default: return nil
        }
    }

    // MARK: Looking up

    /// Where `target` opens in a window showing `context`'s notebook, or nil
    /// when the id isn't there (another classroom's, deleted, not yet synced).
    ///
    /// A follow-up has no page of its own, so it opens where it is shown: a
    /// goal on its child's page; a flagged observation about one child on
    /// that child's page; a todo, or an observation about several children or
    /// the whole class, on Today. Today shows the todos due or overdue and
    /// this week's watched items, so an undated todo or an older note lands
    /// there without being on screen: there is no page that lists them all.
    @MainActor
    static func landing(for target: Target, in context: NSManagedObjectContext) -> Landing? {
        switch target {
        case .student(let id):
            return studentExists(id, in: context) ? .handoff(.student(id)) : nil
        case .lesson(let id):
            return context.object(CDLesson.self, id: id) != nil ? .handoff(.lesson(id)) : nil
        case .followUp(let id):
            return followUpLanding(id, in: context)
        }
    }

    @MainActor
    private static func followUpLanding(_ id: UUID, in context: NSManagedObjectContext) -> Landing? {
        if context.object(CDTodoItem.self, id: id) != nil {
            return .section(.today)
        }
        if let goal = context.object(CDStudentFocusItem.self, id: id) {
            guard let studentID = goal.studentIDUUID, studentExists(studentID, in: context) else {
                return .section(.today)
            }
            return .handoff(.student(studentID))
        }
        if let note = context.object(CDNote.self, id: id) {
            if let only = note.scope.studentIDs, only.count == 1, let studentID = only.first,
               studentExists(studentID, in: context) {
                return .handoff(.student(studentID))
            }
            return .section(.today)
        }
        return nil
    }

    @MainActor
    private static func studentExists(_ id: UUID, in context: NSManagedObjectContext) -> Bool {
        context.object(CDStudent.self, id: id) != nil
    }
}
