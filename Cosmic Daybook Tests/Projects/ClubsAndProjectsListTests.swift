import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Simplify the app, Phase 6: Projects and book clubs in one Clubs & Projects
/// list, each kept as what it is.
@Suite("Clubs & Projects: one list (simplify phase 6)")
@MainActor
struct ClubsAndProjectsListTests {

    private let now = Date(timeIntervalSince1970: 1_790_000_000) // 2026-09-21

    private func project(_ title: String, in context: NSManagedObjectContext) -> CDProject {
        let project = CDProject(context: context)
        project.title = title
        project.createdAt = now.addingTimeInterval(-86_400)
        project.isActive = true
        return project
    }

    private func bookClub(
        _ name: String,
        status: BookClubSessionStatus,
        packetID: UUID? = nil,
        in context: NSManagedObjectContext
    ) -> CDBookClubSession {
        let session = CDBookClubSession(context: context)
        session.displayName = name
        session.status = status
        session.startDate = now.addingTimeInterval(-86_400)
        session.packetID = packetID?.uuidString ?? ""
        return session
    }

    private func titles(_ section: ClubsAndProjectsSection) -> [String] {
        switch section.rows {
        case .projects(let projects): return projects.map(\.title)
        case .bookClubs(let sessions): return sessions.map(\.displayTitle)
        }
    }

    @Test("Projects and book clubs share one list, projects first, clubs by status")
    func oneListHoldsBoth() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let garden = project("Garden Project", in: context)
        let finished = project("Bridge Building", in: context)
        finished.isActive = false
        _ = bookClub("Charlotte's Web Club", status: .active, in: context)
        _ = bookClub("Hatchet Club", status: .planned, in: context)
        _ = bookClub("Holes Club", status: .archived, in: context)

        let list = ClubsAndProjectsList(
            projects: [garden, finished],
            bookClubs: try context.fetch(CDFetchRequest(CDBookClubSession.self)),
            range: nil,
            now: now
        )
        let sections = list.sections

        #expect(sections.map(\.title) == [
            "Running", "Completed", "Active Book Clubs", "Planned Book Clubs", "Archived Book Clubs"
        ])
        #expect(titles(sections[0]) == ["Garden Project"])
        #expect(titles(sections[1]) == ["Bridge Building"])
        #expect(titles(sections[2]) == ["Charlotte's Web Club"])
        #expect(titles(sections[3]) == ["Hatchet Club"])
        #expect(titles(sections[4]) == ["Holes Club"])
    }

    @Test("Search finds a club by its packet's title and a project by its own")
    func searchCoversBoth() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let packetID = UUID()
        let garden = project("Garden Project", in: context)
        let club = bookClub("", status: .active, packetID: packetID, in: context)

        var list = ClubsAndProjectsList(
            projects: [garden],
            bookClubs: [club],
            range: nil,
            searchText: "hatchet",
            packetTitle: { $0.packetUUID == packetID ? "Hatchet" : nil },
            now: now
        )
        #expect(list.shownBookClubs.count == 1)
        #expect(list.shownProjects.isEmpty)

        list.searchText = "garden"
        #expect(list.shownProjects.count == 1)
        #expect(list.shownBookClubs.isEmpty)
    }

    @Test("A club outside the school year being viewed is left out; one with no dates stays")
    func yearLensNarrowsClubs() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let lastYear = bookClub("Old Club", status: .completed, in: context)
        lastYear.startDate = now.addingTimeInterval(-400 * 86_400)
        lastYear.endDate = now.addingTimeInterval(-300 * 86_400)
        let undated = bookClub("New Club", status: .planned, in: context)
        undated.startDate = nil
        undated.createdAt = nil
        let range = DateRange(start: now.addingTimeInterval(-30 * 86_400), end: now.addingTimeInterval(300 * 86_400))

        #expect(!lastYear.overlaps(range))
        #expect(undated.overlaps(range))
        let list = ClubsAndProjectsList(projects: [], bookClubs: [lastYear, undated], range: range, now: now)
        #expect(list.shownBookClubs.map(\.displayTitle) == ["New Club"])
    }

    @Test("The picked row is saved as a string; a bare id saved by the old Projects screen is a project")
    func selectionRoundTrips() throws {
        let id = UUID()
        #expect(ClubsSelection(stored: ClubsSelection.project(id).stored) == .project(id))
        #expect(ClubsSelection(stored: ClubsSelection.bookClub(id).stored) == .bookClub(id))
        #expect(ClubsSelection(stored: id.uuidString) == .project(id))
        #expect(ClubsSelection(stored: "") == nil)
        #expect(ClubsSelection(stored: "bookClub:not-an-id") == nil)
    }
}
