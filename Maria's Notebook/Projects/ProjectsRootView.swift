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

    // MARK: - Data
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDProject.createdAt, ascending: false)]) private var clubsRaw: FetchedResults<CDProject>
    private var clubs: [Project] { Array(clubsRaw).uniqueByID }
    
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
        clubs.first { $0.id?.uuidString == selectedClubIDString }
    }

    private var filteredClubs: [Project] {
        if searchText.isEmpty { return clubs }
        return clubs.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

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
            Text(
                """
                Are you sure you want to delete "\(club.title)"? \
                This will permanently remove all sessions, \
                deliverables, and assignments associated with \
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
            ForEach(filteredClubs, id: \.objectID) { club in
                ProjectSidebarRow(
                    club: club,
                    isSelected: club.id?.uuidString == selectedClubIDString,
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
        ((club.sessions?.allObjects as? [CDProjectSession]) ?? []).compactMap(\.meetingDate).max()
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func deleteClub(_ club: Project) {
        // OPTIMIZATION: Use targeted filtering instead of loading all records upfront
        // SwiftData predicates can't compare captured UUID values, so we fetch and filter
        // This is still more efficient than the original which loaded everything into @Query properties
        
        let clubID = club.id ?? UUID()

        // Delete sessions and their related work contracts
        // Fetch all sessions (can't use predicate with captured UUID), then filter
        let clubIDString = clubID.uuidString
        let allSessions: [ProjectSession]
        do {
            allSessions = try modelContext.fetch(CDFetchRequest(CDProjectSession.self))
        } catch {
            Self.logger.warning("Failed to fetch project sessions: \(error)")
            allSessions = []
        }
        let sessions = allSessions.filter { $0.projectID == clubIDString }

        // Fetch work models only for these sessions
        let sessionIDs = Set(sessions.compactMap { $0.id?.uuidString })
        let allWorkModels: [WorkModel]
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

        for w in workModels {
            modelContext.delete(w)
        }
        for s in sessions {
            modelContext.delete(s)
        }

        // Delete templates associated with this club
        let allTemplates: [ProjectAssignmentTemplate]
        do {
            allTemplates = try modelContext.fetch(CDFetchRequest(CDProjectAssignmentTemplate.self))
        } catch {
            Self.logger.warning("Failed to fetch project templates: \(error)")
            allTemplates = []
        }
        let templates = allTemplates.filter { $0.projectID == clubIDString }
        for t in templates { modelContext.delete(t) }

        // Delete roles for this club
        let allRoles: [ProjectRole]
        do {
            allRoles = try modelContext.fetch(CDFetchRequest(CDProjectRole.self))
        } catch {
            Self.logger.warning("Failed to fetch project roles: \(error)")
            allRoles = []
        }
        let roles = allRoles.filter { $0.projectID == clubIDString }
        for r in roles { modelContext.delete(r) }

        // Delete template weeks and their related data
        let allWeeks: [ProjectTemplateWeek]
        do {
            allWeeks = try modelContext.fetch(CDFetchRequest(CDProjectTemplateWeek.self))
        } catch {
            Self.logger.warning("Failed to fetch project template weeks: \(error)")
            allWeeks = []
        }
        let weeks = allWeeks.filter { $0.projectID == clubIDString }
        for w in weeks {
            // Role assignments for the week
            let allAssigns: [ProjectWeekRoleAssignment]
            do {
                allAssigns = try modelContext.fetch(CDFetchRequest(CDProjectWeekRoleAssignment.self))
            } catch {
                Self.logger.warning("Failed to fetch week role assignments: \(error)")
                allAssigns = []
            }
            let assigns = allAssigns.filter { $0.weekID == w.id?.uuidString }
            for a in assigns { modelContext.delete(a) }

            modelContext.delete(w)
        }

        // Removed legacy cleanup block per instructions

        // Finally, delete the club itself
        modelContext.delete(club)
        
        // Clear selection if needed
        if selectedClubIDString == club.id?.uuidString {
            selectedClubIDString = ""
        }
        
        saveCoordinator.save(modelContext, reason: "Delete Project")
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
        HStack(spacing: AppTheme.Spacing.compact) {
            // Icon circle with project icon (matching SubjectListRow/StudentListRow avatar style)
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                projectColor.opacity(UIConstants.OpacityConstants.faint + 0.72),
                                projectColor
                            ]),
                            center: .center,
                            startRadius: 8,
                            endRadius: 24
                        )
                    )
                    .frame(width: 40, height: 40)

                Image(systemName: SFSymbol.People.person3Fill)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }

            // Title and member count
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
                Text(club.title)
                    .font(AppTheme.ScaledFont.bodySemibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                // Member count as secondary text
                let memberCount = club.memberStudentIDsArray.count
                HStack(spacing: AppTheme.Spacing.xsmall) {
                    Circle().fill(projectColor).frame(width: 6, height: 6)
                    Text("\(memberCount) \(memberCount == 1 ? "member" : "members")")
                        .font(AppTheme.ScaledFont.captionSmallSemibold)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, AppTheme.Spacing.verySmall)
        .padding(.horizontal, AppTheme.Spacing.small)
        .contentShape(Rectangle())
    }
}
