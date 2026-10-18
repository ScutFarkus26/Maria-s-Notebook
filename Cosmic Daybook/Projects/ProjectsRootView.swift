import SwiftUI
import CoreData
#if os(iOS)
import UIKit
#endif

/// Clubs & Projects: projects and book clubs in one list, each opening its
/// own detail. Projects make work for their members; a book club reads a
/// packet (kept in Resources › Packets) on a schedule with rotating leaders.
/// Both keep their own records. The Book Club sidebar row opens this screen
/// too (`BookClubRootView`).
struct ProjectsRootView: View {
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(SaveCoordinator.self) private var saveCoordinator
    @Environment(\.dependencies) private var dependencies
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    private var isCompact: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    // MARK: - Data
    @FetchRequest(fetchRequest: {
        let request = CDFetchRequest(CDProject.self)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDProject.createdAt, ascending: false)]
        // Prefetch sessions so each row's activity (the year lens and the
        // Running/Dormant sections, `ProjectActivity.lastActivity`) reads the
        // club's relationship from the row cache instead of faulting it per
        // sidebar row (N+1).
        request.relationshipKeyPathsForPrefetching = ["sessions"]
        return request
    }())
    private var clubsRaw: FetchedResults<CDProject>
    private var clubs: [CDProject] { Array(clubsRaw).uniqueByID }

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDBookClubSession.createdAt, ascending: false)],
        animation: .default
    )
    private var bookClubs: FetchedResults<CDBookClubSession>

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDBookClubPacket.title, ascending: true)])
    private var packets: FetchedResults<CDBookClubPacket>

    /// Only to tell a member who is still in the class from one who has left:
    /// the member id list keeps every child ever added.
    private var enrolledMemberIDs: Set<String> {
        Set(dependencies.roster.enrolled.compactMap { $0.id?.uuidString })
    }

    // MARK: - State
    /// The picked row (`ClubsSelection.stored`). The key is the Projects
    /// screen's, so the project picked there stays picked.
    @SceneStorage("Projects.selectedClubID") private var selectionString: String = ""
    @State private var showNewProjectSheet = false
    @State private var showNewBookClubSheet = false
    @State private var searchText: String = ""

    // Deletion State
    @State private var clubToDelete: CDProject?
    @State private var showDeleteAlert: Bool = false

    private var selection: Binding<ClubsSelection?> {
        Binding {
            ClubsSelection(stored: selectionString)
        } set: { newValue in
            selectionString = newValue?.stored ?? ""
        }
    }

    private var packetTitles: [UUID: String] {
        var titles: [UUID: String] = [:]
        for packet in packets {
            if let id = packet.id, titles[id] == nil { titles[id] = packet.title }
        }
        return titles
    }

    private var list: ClubsAndProjectsList {
        let titles = packetTitles
        return ClubsAndProjectsList(
            projects: clubs,
            bookClubs: Array(bookClubs).uniqueByID,
            range: dependencies.schoolYearStore.activeRange,
            searchText: searchText,
            packetTitle: { session in session.packetUUID.flatMap { titles[$0] } }
        )
    }

    private func enrolledMemberCount(of club: CDProject) -> Int {
        let enrolled = enrolledMemberIDs
        return club.memberStudentIDsArray.filter { enrolled.contains($0) }.count
    }

    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            if isCompact {
                // A phone has no room for the list beside the detail: the list
                // fills the screen, under the navigation title and its + menu,
                // and a project or club pushes over it.
                sidebar
                    .navigationDestination(item: selection) { picked in
                        detail(for: picked)
                    }
            } else {
                #if os(iOS)
                ViewHeader(title: "Clubs & Projects") {
                    addMenu
                        .buttonStyle(.borderedProminent)
                }
                Divider()
                #endif
                HStack(spacing: 0) {
                    sidebar
                        .frame(width: 300)
                    Divider()
                    detail(for: ClubsSelection(stored: selectionString))
                        .id(selectionString)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Clubs & Projects")
        .sheet(isPresented: $showNewProjectSheet) {
            ProjectEditorSheet(club: nil)
        }
        .sheet(isPresented: $showNewBookClubSheet) {
            BookClubSessionEditorSheet(prefilledPacket: nil)
                .frame(minWidth: 560, minHeight: 600)
        }
        .alert("Delete Project?", isPresented: $showDeleteAlert, presenting: clubToDelete) { club in
            Button("Delete", role: .destructive) {
                deleteClub(club)
            }
            Button("Cancel", role: .cancel) {
                clubToDelete = nil
            }
        } message: { club in
            Text(
                """
                Are you sure you want to delete "\(club.title)"? \
                This will permanently remove all check-ins, \
                follow-ups, and assignments associated with \
                this project.
                """
            )
        }
        .task {
            // Pick the first row on iPad and Mac, where the detail sits beside the list.
            #if os(iOS)
            guard UIDevice.current.userInterfaceIdiom == .pad else { return }
            #endif
            if selectionString.isEmpty, let first = clubs.first?.id {
                selectionString = ClubsSelection.project(first).stored
            }
        }
    }

    // MARK: - Sidebar

    private var addMenu: some View {
        Menu {
            Button("New Project", systemImage: "person.3") {
                showNewProjectSheet = true
            }
            Button("New Book Club", systemImage: "books.vertical") {
                showNewBookClubSheet = true
            }
        } label: {
            Label("Add", systemImage: "plus")
        }
        .menuStyle(.button)
        .fixedSize()
    }

    private var sidebar: some View {
        let list = self.list
        return List(selection: selection) {
            ForEach(list.sections) { section in
                Section(section.title) {
                    switch section.rows {
                    case .projects(let projects):
                        ForEach(projects, id: \.objectID) { club in
                            projectRow(for: club)
                        }
                    case .bookClubs(let sessions):
                        ForEach(sessions, id: \.objectID) { session in
                            bookClubRow(for: session)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if list.sections.isEmpty {
                ClubsAndProjectsEmptyState(
                    hasAnything: !clubs.isEmpty || !bookClubs.isEmpty,
                    searchText: searchText
                )
            }
        }
        .searchable(text: $searchText)
        .navigationTitle("Clubs & Projects")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                addMenu
            }
        }
    }

    // The tag must be a non-optional `ClubsSelection`: List(selection:) only
    // matches tags of exactly that type, so an optional tag makes every row
    // silently unselectable.
    @ViewBuilder
    private func projectRow(for club: CDProject) -> some View {
        let row = ProjectSidebarRow(
            club: club,
            status: ProjectActivity.status(of: club),
            memberCount: enrolledMemberCount(of: club)
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                clubToDelete = club
                showDeleteAlert = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        if let id = club.id {
            row.tag(ClubsSelection.project(id))
        } else {
            row.selectionDisabled()
        }
    }

    @ViewBuilder
    private func bookClubRow(for session: CDBookClubSession) -> some View {
        let viewModel = BookClubSessionsViewModel()
        let row = BookClubSessionRowView(
            session: session,
            packet: viewModel.packet(for: session, in: modelContext),
            roster: viewModel.roster(for: session, in: modelContext),
            nextMeeting: viewModel.nextMeeting(for: session)
        )
        if let id = session.id {
            row.tag(ClubsSelection.bookClub(id))
        } else {
            row.selectionDisabled()
        }
    }

    // MARK: - Detail

    private func detail(for picked: ClubsSelection?) -> ClubsAndProjectsDetail {
        ClubsAndProjectsDetail(
            selection: picked,
            projects: clubs,
            bookClubs: Array(bookClubs),
            onClose: { selectionString = "" }
        )
    }

    // MARK: - Helpers

    private func deleteClub(_ club: CDProject) {
        let wasSelected = club.id.map { selectionString == ClubsSelection.project($0).stored } ?? false
        ProjectDeletion.delete(club, in: modelContext)
        if wasSelected {
            selectionString = ""
        }
        saveCoordinator.save(modelContext, reason: "Delete Project")
    }
}
