import OSLog
import SwiftUI
import CoreData
#if os(iOS)
import UIKit
#endif

struct ProjectsRootView: View {
    private static let logger = Logger.projects
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(SaveCoordinator.self) private var saveCoordinator
    @Environment(\.dependencies) private var dependencies

    // MARK: - Data
    @FetchRequest(fetchRequest: {
        let request = CDFetchRequest(CDProject.self)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDProject.createdAt, ascending: false)]
        // Prefetch sessions so lastSessionDate(for:) reads each club's relationship
        // from the row cache instead of faulting it per sidebar row (N+1).
        request.relationshipKeyPathsForPrefetching = ["sessions"]
        return request
    }())
    private var clubsRaw: FetchedResults<CDProject>
    private var clubs: [CDProject] { Array(clubsRaw).uniqueByID }

    /// Only to tell a member who is still in the class from one who has left:
    /// the member id list keeps every child ever added.
    private var enrolledMemberIDs: Set<String> {
        Set(dependencies.roster.enrolled.compactMap { $0.id?.uuidString })
    }

    // OPTIMIZATION: Removed unfiltered queries - deletion logic uses targeted FetchDescriptor
    // when needed, avoiding loading all records into memory upfront

    // MARK: - State
    @SceneStorage("Projects.selectedClubID") private var selectedClubIDString: String = ""
    @State private var showNewSheet: Bool = false
    @State private var searchText: String = ""
    
    // Deletion State
    @State private var clubToDelete: CDProject?
    @State private var showDeleteAlert: Bool = false

    private var selectedClubID: Binding<UUID?> {
        Binding {
            UUID(uuidString: selectedClubIDString)
        } set: { newValue in
            selectedClubIDString = newValue?.uuidString ?? ""
        }
    }

    private var selectedClub: CDProject? {
        clubs.first { $0.id?.uuidString == selectedClubIDString }
    }

    private var filteredClubs: [CDProject] {
        var result = clubs

        // School-year lens: scope to projects active in the selected year
        // (no-op when the lens is "All years").
        if let range = dependencies.schoolYearStore.activeRange {
            result = result.filter { $0.overlaps(range) }
        }

        if !searchText.isEmpty {
            result = result.filter { club in
                club.title.localizedCaseInsensitiveContains(searchText) ||
                (club.bookTitle ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }
        return result
    }

    /// The rows grouped the way the guide reads them: what is running now,
    /// what has gone quiet, and what is finished.
    private var clubSections: [(title: String, clubs: [CDProject])] {
        var active: [CDProject] = []
        var dormant: [CDProject] = []
        var closed: [CDProject] = []
        for club in filteredClubs {
            switch ProjectActivity.status(of: club) {
            case .active: active.append(club)
            case .dormant: dormant.append(club)
            case .closed: closed.append(club)
            }
        }
        return [("Running", active), ("Dormant", dormant), ("Completed", closed)]
            .filter { !$0.1.isEmpty }
            .map { (title: $0.0, clubs: $0.1) }
    }

    private func enrolledMemberCount(of club: CDProject) -> Int {
        let enrolled = enrolledMemberIDs
        return club.memberStudentIDsArray.filter { enrolled.contains($0) }.count
    }

    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            #if os(iOS)
            ViewHeader(title: "Projects") {
                Button {
                    showNewSheet = true
                } label: {
                    Label("Add Project", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            Divider()
            #endif
            HStack(spacing: 0) {
                // MARK: Sidebar
                projectsSidebar
                    .frame(width: 280)

                Divider()

                // MARK: Detail Area
                projectDetailContent
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Projects")
        .sheet(isPresented: $showNewSheet) {
            ProjectEditorSheet(club: nil)
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
            // Auto-select first if none selected on iPad
            #if os(iOS)
            if UIDevice.current.userInterfaceIdiom == .pad {
                if selectedClubIDString.isEmpty, let first = clubs.first {
                    selectedClubIDString = first.id?.uuidString ?? ""
                }
            }
            #else
            if selectedClubIDString.isEmpty, let first = clubs.first {
                selectedClubIDString = first.id?.uuidString ?? ""
            }
            #endif
        }
    }

    // MARK: - Sidebar

    private var projectsSidebar: some View {
        List(selection: selectedClubID) {
            ForEach(clubSections, id: \.title) { section in
                Section(section.title) {
                    ForEach(section.clubs, id: \.objectID) { club in
                        clubRow(for: club)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            // The school-year lens can empty this list on a notebook that does
            // hold projects, so say where they went rather than leaving the
            // guide looking at nothing. (Dormant projects are sectioned off
            // below the running ones, never hidden.)
            if filteredClubs.isEmpty && !clubs.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "None This Year" : "No Match",
                    systemImage: SFSymbol.People.person3Fill,
                    description: Text(
                        searchText.isEmpty
                            ? "Every project falls outside the school year you are viewing. "
                                + "Switch the year lens to All Years to see them."
                            : "No project matches “\(searchText)”."
                    )
                )
            }
        }
        .searchable(text: $searchText)
        .navigationTitle("Projects")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showNewSheet = true
                } label: {
                    Label("Add Project", systemImage: "plus")
                }
            }
        }
    }

    // The tag must be a non-optional UUID: List(selection: Binding<UUID?>) only
    // matches tags of exactly UUID, so tagging with the optional `club.id`
    // makes every row silently unselectable.
    @ViewBuilder
    private func clubRow(for club: CDProject) -> some View {
        let row = ProjectSidebarRow(
            club: club,
            isSelected: club.id?.uuidString == selectedClubIDString,
            lastSessionDate: lastSessionDate(for: club),
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
            row.tag(id)
        } else {
            row.selectionDisabled()
        }
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var projectDetailContent: some View {
        if let club = selectedClub {
            ProjectDetailView(club: club)
                .id(club.id)
        } else {
            ContentUnavailableView(
                "No Selection",
                systemImage: "book",
                description: Text("Select a project to view students, lessons, progress, and next steps.")
            )
        }
    }

    // MARK: - Helpers

    private func lastSessionDate(for club: CDProject) -> Date? {
        ((club.sessions?.allObjects as? [CDProjectSession]) ?? []).compactMap(\.meetingDate).max()
    }

    private func deleteClub(_ club: CDProject) {
        // OPTIMIZATION: Use targeted filtering instead of loading all records upfront
        // SwiftData predicates can't compare captured UUID values, so we fetch and filter
        // This is still more efficient than the original which loaded everything into @Query properties
        
        let clubID = club.id ?? UUID()

        // Delete sessions and their related work contracts
        // Fetch all sessions (can't use predicate with captured UUID), then filter
        let clubIDString = clubID.uuidString
        let allSessions: [CDProjectSession]
        do {
            allSessions = try modelContext.fetch(CDFetchRequest(CDProjectSession.self))
        } catch {
            Self.logger.warning("Failed to fetch project sessions: \(error)")
            allSessions = []
        }
        let sessions = allSessions.filter { $0.projectID == clubIDString }

        // Fetch work models only for these sessions
        let sessionIDs = Set(sessions.compactMap { $0.id?.uuidString })
        let allWorkModels: [CDWorkModel]
        do {
            allWorkModels = try modelContext.fetch(CDFetchRequest(CDWorkModel.self))
        } catch {
            Self.logger.warning("Failed to fetch work models: \(error)")
            allWorkModels = []
        }
        let workModels = allWorkModels.filter {
            ($0.sourceContextType == .projectSession || $0.sourceContextType == .bookClubSession) &&
            sessionIDs.contains($0.sourceContextID ?? "")
        }

        // Through the service, so check-ins keyed only by workID string,
        // completion records and passenger rows on linked copies go too.
        if !workModels.isEmpty {
            do {
                try WorkDeletionService(context: modelContext).delete(workModels) { true }
            } catch {
                Self.logger.error("Failed to delete club work: \(error)")
            }
        }
        for s in sessions {
            modelContext.delete(s)
        }

        // Delete roles for this club
        let allRoles: [CDProjectRole]
        do {
            allRoles = try modelContext.fetch(CDFetchRequest(CDProjectRole.self))
        } catch {
            Self.logger.warning("Failed to fetch project roles: \(error)")
            allRoles = []
        }
        let roles = allRoles.filter { $0.projectID == clubIDString }
        for r in roles { modelContext.delete(r) }

        // Finally, delete the club itself
        modelContext.delete(club)
        
        // Clear selection if needed
        if selectedClubIDString == club.id?.uuidString {
            selectedClubIDString = ""
        }
        
        saveCoordinator.save(modelContext, reason: "Delete Project")
    }
}
