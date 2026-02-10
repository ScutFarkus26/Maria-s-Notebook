import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#endif

struct ProjectsRootView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var saveCoordinator: SaveCoordinator

    // MARK: - Data
    @Query(sort: [SortDescriptor(\Project.createdAt, order: .reverse)]) private var clubsRaw: [Project]
    private var clubs: [Project] { clubsRaw.uniqueByID }
    
    // OPTIMIZATION: Removed unfiltered queries - deletion logic uses targeted FetchDescriptor
    // when needed, avoiding loading all records into memory upfront

    // MARK: - State
    @SceneStorage("Projects.selectedClubID") private var selectedClubIDString: String = ""
    @State private var showNewSheet: Bool = false
    @State private var searchText: String = ""
    
    // Deletion State
    @State private var clubToDelete: Project?
    @State private var showDeleteAlert: Bool = false

    private var selectedClubID: Binding<UUID?> {
        Binding {
            UUID(uuidString: selectedClubIDString)
        } set: { newValue in
            selectedClubIDString = newValue?.uuidString ?? ""
        }
    }

    private var selectedClub: Project? {
        clubs.first { $0.id.uuidString == selectedClubIDString }
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
        VStack(spacing: 0) {
            ViewHeader(title: "Projects") {
                Button {
                    showNewSheet = true
                } label: {
                    Label("Add Project", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            Divider()
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
        .task {
            // Auto-select first if none selected on iPad
            #if os(iOS)
            if UIDevice.current.userInterfaceIdiom == .pad {
                if selectedClubIDString.isEmpty, let first = clubs.first {
                    selectedClubIDString = first.id.uuidString
                }
            }
            #else
            if selectedClubIDString.isEmpty, let first = clubs.first {
                selectedClubIDString = first.id.uuidString
            }
            #endif
        }
    }

    // MARK: - Sidebar

    private var projectsSidebar: some View {
        List(selection: selectedClubID) {
            ForEach(filteredClubs) { club in
                ProjectSidebarRow(
                    club: club,
                    isSelected: club.id.uuidString == selectedClubIDString,
                    lastSessionDate: lastSessionDate(for: club)
                )
                .tag(club.id)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        clubToDelete = club
                        showDeleteAlert = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.sidebar)
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
                description: Text("Select a project from the sidebar to view details.")
            )
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
        
        // Fetch work models only for these sessions
        let sessionIDs = Set(sessions.map { $0.id.uuidString })
        let allWorkModels = (try? modelContext.fetch(FetchDescriptor<WorkModel>())) ?? []
        let workModels = allWorkModels.filter {
            ($0.sourceContextType == .projectSession || $0.sourceContextType == .bookClubSession) &&
            sessionIDs.contains($0.sourceContextID ?? "")
        }

        for w in workModels {
            modelContext.delete(w)
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
        if selectedClubIDString == club.id.uuidString {
            selectedClubIDString = ""
        }
        
        _ = saveCoordinator.save(modelContext, reason: "Delete Project")
    }
}

// MARK: - Sidebar Row

/// A row component for displaying a project in a list view.
/// Shows the project's icon (colored circle with project icon), title, and member count.
/// Design matches SubjectListRow/StudentListRow for visual consistency across the app.
struct ProjectSidebarRow: View {
    let club: Project
    let isSelected: Bool
    let lastSessionDate: Date?

    private var projectColor: Color {
        // Use a consistent color for projects, or could be customized per project
        AppColors.color(forSubject: "Reading")
    }

    var body: some View {
        HStack(spacing: 12) {
            // Icon circle with project icon (matching SubjectListRow/StudentListRow avatar style)
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [projectColor.opacity(0.8), projectColor]),
                            center: .center,
                            startRadius: 8,
                            endRadius: 24
                        )
                    )
                    .frame(width: 40, height: 40)

                Image(systemName: "person.3.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }

            // Title and member count
            VStack(alignment: .leading, spacing: 2) {
                Text(club.title)
                    .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                // Member count as secondary text
                let memberCount = club.memberStudentIDs.count
                HStack(spacing: 4) {
                    Circle().fill(projectColor).frame(width: 6, height: 6)
                    Text("\(memberCount) \(memberCount == 1 ? "member" : "members")")
                        .font(.system(size: AppTheme.FontSize.captionSmall, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }
}

