import SwiftUI
import SwiftData

struct ProjectsRootView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var saveCoordinator: SaveCoordinator

    // MARK: - Data
    @Query(sort: [SortDescriptor(\Project.createdAt, order: .reverse)]) private var clubs: [Project]
    
    // OPTIMIZATION: Removed unfiltered queries - deletion logic uses targeted FetchDescriptor
    // when needed, avoiding loading all records into memory upfront

    // MARK: - State
    @SceneStorage("Projects.selectedClubID") private var selectedClubIDString: String = ""
    @State private var showNewSheet: Bool = false
    @State private var searchText: String = ""
    
    // Deletion State
    @State private var clubToDelete: Project?
    @State private var showDeleteAlert: Bool = false

    private var selectedClubID: UUID? {
        get { UUID(uuidString: selectedClubIDString) }
        nonmutating set { selectedClubIDString = newValue?.uuidString ?? "" }
    }

    private var selectedClub: Project? {
        clubs.first { $0.id == selectedClubID }
    }

    private var filteredClubs: [Project] {
        if searchText.isEmpty { return clubs }
        return clubs.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    static let df: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df
    }()

    // MARK: - Body
    var body: some View {
        HStack(spacing: 0) {
            // MARK: Sidebar
            VStack(alignment: .leading, spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Projects")
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .foregroundStyle(.primary)
                        Spacer()
                        Button {
                            showNewSheet = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Search
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(8)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(16)

                // List with Swipe Actions
                List {
                    ForEach(filteredClubs) { club in
                        ProjectSidebarRow(
                            club: club,
                            isSelected: club.id == selectedClubID,
                            lastSessionDate: lastSessionDate(for: club)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedClubIDString = club.id.uuidString
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                clubToDelete = club
                                showDeleteAlert = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.gray.opacity(0.05))
            }
            .frame(width: 260)
            .background(Color.gray.opacity(0.05))
            
            Divider()
            
            // MARK: Detail Area
            ZStack {
                if let club = selectedClub {
                    ProjectDetailView(club: club)
                        .id(club.id) // Force recreation when selection changes
                } else {
                    ContentUnavailableView(
                        "No Selection",
                        systemImage: "book",
                        description: Text("Select a project from the sidebar to view details.")
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
            Text("Are you sure you want to delete \"\(club.title)\"? This will permanently remove all sessions, deliverables, and assignments associated with this project.")
        }
        .onAppear {
            if selectedClubIDString.isEmpty, let first = clubs.first {
                selectedClubIDString = first.id.uuidString
            }
        }
    }

    // MARK: - Helpers

    private func lastSessionDate(for club: Project) -> Date? {
        (club.sessions ?? []).map { $0.meetingDate }.max()
    }

    private func deleteClub(_ club: Project) {
        // OPTIMIZATION: Use targeted filtering instead of loading all records upfront
        // SwiftData predicates can't compare captured UUID values, so we fetch and filter
        // This is still more efficient than the original which loaded everything into @Query properties
        
        let clubID = club.id
        
        // Delete sessions and their related work contracts
        // Fetch all sessions (can't use predicate with captured UUID), then filter
        let clubIDString = clubID.uuidString
        let allSessions = (try? modelContext.fetch(FetchDescriptor<ProjectSession>())) ?? []
        let sessions = allSessions.filter { $0.projectID == clubIDString }
        
        // Fetch contracts only for these sessions
        let sessionIDs = Set(sessions.map { $0.id.uuidString })
        let allContracts = (try? modelContext.fetch(FetchDescriptor<WorkContract>())) ?? []
        let contracts = allContracts.filter {
            ($0.sourceContextType == .projectSession || $0.sourceContextType == .bookClubSession) &&
            sessionIDs.contains($0.sourceContextID ?? "")
        }
        
        for c in contracts {
            modelContext.delete(c)
        }
        for s in sessions {
            modelContext.delete(s)
        }

        // Delete templates associated with this club
        let allTemplates = (try? modelContext.fetch(FetchDescriptor<ProjectAssignmentTemplate>())) ?? []
        let templates = allTemplates.filter { $0.projectID == clubIDString }
        for t in templates { modelContext.delete(t) }

        // Delete roles for this club
        let allRoles = (try? modelContext.fetch(FetchDescriptor<ProjectRole>())) ?? []
        let roles = allRoles.filter { $0.projectID == clubIDString }
        for r in roles { modelContext.delete(r) }

        // Delete template weeks and their related data
        let allWeeks = (try? modelContext.fetch(FetchDescriptor<ProjectTemplateWeek>())) ?? []
        let weeks = allWeeks.filter { $0.projectID == clubIDString }
        for w in weeks {
            // Role assignments for the week
            let allAssigns = (try? modelContext.fetch(FetchDescriptor<ProjectWeekRoleAssignment>())) ?? []
            let assigns = allAssigns.filter { $0.weekID == w.id.uuidString }
            for a in assigns { modelContext.delete(a) }
            
            modelContext.delete(w)
        }

        // Removed legacy cleanup block per instructions

        // Finally, delete the club itself
        modelContext.delete(club)
        
        // Clear selection if needed
        if selectedClubID == club.id {
            selectedClubIDString = ""
        }
        
        _ = saveCoordinator.save(modelContext, reason: "Delete Project")
    }
}

// MARK: - Sidebar Row

struct ProjectSidebarRow: View {
    let club: Project
    let isSelected: Bool
    let lastSessionDate: Date?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "book.closed.fill")
                .font(.title3)
                .foregroundStyle(isSelected ? .white : AppColors.color(forSubject: "Reading"))
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(club.title)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(1)
                
                let memberCount = club.memberStudentIDs.count
                let dateStr = lastSessionDate.map { ProjectsRootView.df.string(from: $0) }
                
                Text("\(memberCount) member\(memberCount == 1 ? "" : "s")\(dateStr != nil ? " • " + dateStr! : "")")
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
    }
}

