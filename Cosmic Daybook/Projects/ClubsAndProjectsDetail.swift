import SwiftUI
import CoreData

/// What Clubs & Projects shows for the picked row: the project's own detail
/// or the book club's, beside the list (or pushed over it on a phone).
struct ClubsAndProjectsDetail: View {
    let selection: ClubsSelection?
    let projects: [CDProject]
    let bookClubs: [CDBookClubSession]
    /// Clears the pick, when a book club is closed or deleted.
    let onClose: () -> Void

    var body: some View {
        switch selection {
        case .project(let id):
            if let club = projects.first(where: { $0.id == id }) {
                ProjectDetailView(club: club)
            } else {
                placeholder
            }
        case .bookClub(let id):
            if let session = bookClubs.first(where: { $0.id == id }) {
                BookClubSessionDetailView(session: session, onClose: onClose, onDelete: onClose)
            } else {
                placeholder
            }
        case nil:
            placeholder
        }
    }

    private var placeholder: some View {
        ContentUnavailableView(
            "No Selection",
            systemImage: "book",
            description: Text("Select a project or a book club to see its students, readings and next steps.")
        )
    }
}

/// The Clubs & Projects list when it shows nothing: an empty notebook, or a
/// year lens or search that hides every row.
struct ClubsAndProjectsEmptyState: View {
    /// True when the notebook holds a project or club the list is hiding.
    let hasAnything: Bool
    let searchText: String

    var body: some View {
        if !hasAnything {
            ContentUnavailableView(
                "No Projects or Clubs Yet",
                systemImage: SFSymbol.People.person3Fill,
                description: Text("Use Add to start a project or a book club.")
            )
        } else {
            // The school-year lens can empty this list on a notebook that does
            // hold projects, so say where they went rather than leaving the
            // guide looking at nothing.
            ContentUnavailableView(
                searchText.isEmpty ? "None This Year" : "No Match",
                systemImage: SFSymbol.People.person3Fill,
                description: Text(
                    searchText.isEmpty
                        ? "Every project and club falls outside the school year you're viewing. "
                            + "Choose All Years to see them."
                        : "Nothing matches “\(searchText)”."
                )
            )
        }
    }
}
