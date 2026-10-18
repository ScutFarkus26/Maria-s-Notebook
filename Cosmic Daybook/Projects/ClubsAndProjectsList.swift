// ClubsAndProjectsList.swift
// What the Clubs & Projects list shows: projects and book clubs, each kept as
// what it is, in one list.

import Foundation

/// The row picked in Clubs & Projects: a project or a book club.
enum ClubsSelection: Hashable {
    case project(UUID)
    case bookClub(UUID)

    private static let bookClubPrefix = "bookClub:"
    private static let projectPrefix = "project:"

    /// Read back from the scene's saved string. A bare UUID is a project: the
    /// Projects screen saved its selection that way before book clubs joined it.
    init?(stored: String) {
        if stored.hasPrefix(Self.bookClubPrefix) {
            guard let id = UUID(uuidString: String(stored.dropFirst(Self.bookClubPrefix.count))) else { return nil }
            self = .bookClub(id)
        } else if stored.hasPrefix(Self.projectPrefix) {
            guard let id = UUID(uuidString: String(stored.dropFirst(Self.projectPrefix.count))) else { return nil }
            self = .project(id)
        } else if let id = UUID(uuidString: stored) {
            self = .project(id)
        } else {
            return nil
        }
    }

    /// What the scene saves.
    var stored: String {
        switch self {
        case .project(let id): return Self.projectPrefix + id.uuidString
        case .bookClub(let id): return Self.bookClubPrefix + id.uuidString
        }
    }
}

/// One section of the Clubs & Projects list.
struct ClubsAndProjectsSection: Identifiable {
    enum Rows {
        case projects([CDProject])
        case bookClubs([CDBookClubSession])
    }

    let title: String
    let rows: Rows

    var id: String { title }

    var isEmpty: Bool {
        switch rows {
        case .projects(let projects): return projects.isEmpty
        case .bookClubs(let sessions): return sessions.isEmpty
        }
    }
}

/// Builds the Clubs & Projects list: projects by how they're going (Running,
/// Dormant, Completed), then book clubs by their status (Active, Planned,
/// Completed, Archived), both narrowed by the school-year lens and the search.
struct ClubsAndProjectsList {
    var projects: [CDProject]
    var bookClubs: [CDBookClubSession]
    /// The school-year lens; nil for All Years.
    var range: DateRange?
    var searchText = ""
    /// A book club's packet title, for its search and its name when it has none.
    var packetTitle: (CDBookClubSession) -> String? = { _ in nil }
    var now = Date()

    var shownProjects: [CDProject] {
        projects.filter { project in
            if let range, !project.overlaps(range, asOf: now) { return false }
            guard !searchText.isEmpty else { return true }
            return project.title.localizedCaseInsensitiveContains(searchText)
                || (project.bookTitle ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    var shownBookClubs: [CDBookClubSession] {
        bookClubs.filter { session in
            if let range, !session.overlaps(range) { return false }
            guard !searchText.isEmpty else { return true }
            return session.displayTitle.localizedCaseInsensitiveContains(searchText)
                || (packetTitle(session) ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    /// Every section that has a row, in reading order.
    var sections: [ClubsAndProjectsSection] {
        var running: [CDProject] = []
        var dormant: [CDProject] = []
        var closed: [CDProject] = []
        for project in shownProjects {
            switch ProjectActivity.status(of: project, asOf: now) {
            case .active: running.append(project)
            case .dormant: dormant.append(project)
            case .closed: closed.append(project)
            }
        }
        let projectSections = [("Running", running), ("Dormant", dormant), ("Completed", closed)]
            .map { ClubsAndProjectsSection(title: $0.0, rows: .projects($0.1)) }

        let byStatus = Dictionary(grouping: shownBookClubs, by: \.status)
        let clubSections = BookClubSessionStatus.allCases
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { status in
                let sessions = (byStatus[status] ?? []).sorted { lhs, rhs in
                    (lhs.startDate ?? lhs.createdAt ?? .distantPast) > (rhs.startDate ?? rhs.createdAt ?? .distantPast)
                }
                return ClubsAndProjectsSection(title: "\(status.displayName) Book Clubs", rows: .bookClubs(sessions))
            }

        return (projectSections + clubSections).filter { !$0.isEmpty }
    }
}
