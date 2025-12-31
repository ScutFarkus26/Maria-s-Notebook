import SwiftUI
import SwiftData

struct BookClubsRootView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var saveCoordinator: SaveCoordinator

    // MARK: - Data
    @Query(sort: [SortDescriptor(\BookClub.createdAt, order: .reverse)]) private var clubs: [BookClub]
    
    // Queries needed for cascading deletes
    @Query private var allWeeks: [BookClubTemplateWeek]
    @Query private var allRoleAssignments: [BookClubWeekRoleAssignment]
    @Query private var allRoles: [BookClubRole]
    @Query private var allSessions: [BookClubSession]
    @Query private var allTemplates: [BookClubAssignmentTemplate]
    
    // NEW: Query work contracts to delete orphaned items
    @Query private var allWorkContracts: [WorkContract]
    
    // Legacy queries (optional, kept for safety)
    // Removed legacy queries per instructions

    // MARK: - State
    @SceneStorage("BookClubs.selectedClubID") private var selectedClubIDString: String = ""
    @State private var showNewSheet: Bool = false
    @State private var searchText: String = ""
    
    // Deletion State
    @State private var clubToDelete: BookClub?
    @State private var showDeleteAlert: Bool = false

    private var selectedClubID: UUID? {
        get { UUID(uuidString: selectedClubIDString) }
        nonmutating set { selectedClubIDString = newValue?.uuidString ?? "" }
    }

    private var selectedClub: BookClub? {
        clubs.first { $0.id == selectedClubID }
    }

    private var filteredClubs: [BookClub] {
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
                    BookClubDetailView(club: club)
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
            BookClubEditorSheet(club: nil)
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

    private func lastSessionDate(for club: BookClub) -> Date? {
        (club.sessions ?? []).map { $0.meetingDate }.max()
    }

    private func deleteClub(_ club: BookClub) {
        // Delete sessions and their related work contracts
        let sessions = allSessions.filter { $0.bookClubID == club.id }
        
        for s in sessions {
            // Find contracts linked to this session
            let sid = s.id.uuidString
            let contracts = allWorkContracts.filter { $0.sourceContextType == .bookClubSession && $0.sourceContextID == sid }
            
            for c in contracts {
                modelContext.delete(c)
            }
            modelContext.delete(s)
        }

        // Delete templates associated with this club
        let templates = allTemplates.filter { $0.bookClubID == club.id }
        for t in templates { modelContext.delete(t) }

        // Delete roles for this club
        let roles = allRoles.filter { $0.bookClubID == club.id }
        for r in roles { modelContext.delete(r) }

        // Delete template weeks and their related data
        let weeks = allWeeks.filter { $0.bookClubID == club.id }
        for w in weeks {
            // Role assignments for the week
            let assigns = allRoleAssignments.filter { $0.weekID == w.id }
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
        
        _ = saveCoordinator.save(modelContext, reason: "Delete Book Club")
    }
}

// MARK: - Sidebar Row

struct ProjectSidebarRow: View {
    let club: BookClub
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
                let dateStr = lastSessionDate.map { BookClubsRootView.df.string(from: $0) }
                
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

