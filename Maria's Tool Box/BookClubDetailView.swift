import SwiftUI
import SwiftData

struct BookClubDetailView: View {
    let club: BookClub

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var saveCoordinator: SaveCoordinator
    @Environment(\.dismiss) private var dismiss

    @Query(sort: [SortDescriptor(\Student.firstName), SortDescriptor(\Student.lastName)]) private var students: [Student]
    @Query(sort: [SortDescriptor(\BookClubRole.createdAt, order: .forward)]) private var allRoles: [BookClubRole]
    @Query(sort: [SortDescriptor<BookClubTemplateWeek>(\.weekIndex, order: .forward)]) private var allWeeks: [BookClubTemplateWeek]
    @Query(sort: [SortDescriptor<BookClubChoiceItem>(\.createdAt, order: .forward)]) private var allChoiceItems: [BookClubChoiceItem]
    @Query(sort: [SortDescriptor(\BookClubChoiceSet.createdAt, order: .forward)]) private var allChoiceSets: [BookClubChoiceSet]
    @Query(sort: [SortDescriptor(\BookClubWeekRoleAssignment.createdAt, order: .forward)]) private var allRoleAssignments: [BookClubWeekRoleAssignment]
    @Query(sort: [SortDescriptor(\BookClubSession.createdAt, order: .forward)]) private var allSessions: [BookClubSession]
    @Query(sort: [SortDescriptor(\BookClubAssignmentTemplate.createdAt, order: .forward)]) private var allTemplates: [BookClubAssignmentTemplate]

    private var roles: [BookClubRole] { allRoles.filter { $0.bookClubID == club.id } }

    @State private var showNewSession: Bool = false
    @State private var showEditClub: Bool = false
    @State private var showManageRoles: Bool = false
    @State private var showDeleteConfirm: Bool = false

    private var studentsByID: [UUID: Student] { Dictionary(uniqueKeysWithValues: students.map { ($0.id, $0) }) }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Overview
                SectionCard(title: "Overview", systemImage: "person.3") {
                    VStack(alignment: .leading, spacing: 12) {
                        // Header with Book Title and Edit (if available)
                        if let bt = club.bookTitle, !bt.isEmpty {
                            HStack(alignment: .firstTextBaseline) {
                                Label(bt, systemImage: "book.closed")
                                    .font(.title3).fontWeight(.semibold)
                                Spacer()
                                Button {
                                    showEditClub = true
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .buttonStyle(.bordered)
                            }
                            // Members subheader (compact)
                            HStack(alignment: .firstTextBaseline) {
                                Label("Members", systemImage: "person.2")
                                    .font(.headline)
                                Spacer()
                            }
                        } else {
                            // Fallback: Members header with Edit when no book title
                            HStack(alignment: .firstTextBaseline) {
                                Label("Members", systemImage: "person.2")
                                    .font(.headline)
                                Spacer()
                                Button {
                                    showEditClub = true
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .buttonStyle(.bordered)
                            }
                        }

                        // Members as a single row (horizontal chips)
                        if club.memberStudentIDs.isEmpty {
                            Text("No members selected")
                                .foregroundStyle(.secondary)
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(club.memberStudentIDs, id: \.self) { sid in
                                        if let uuid = UUID(uuidString: sid), let s = studentsByID[uuid] {
                                            Chip(text: StudentFormatter.displayName(for: s))
                                        } else {
                                            Chip(text: "Unknown")
                                        }
                                    }
                                }
                            }
                        }

                        // Shared Assignments (only show if present)
                        let shared = club.sharedTemplates.filter { $0.isShared }
                        if !shared.isEmpty {
                            Divider().opacity(0.2)
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Shared Assignments", systemImage: "square.and.pencil")
                                    .font(.headline)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(shared) { tpl in
                                            Chip(text: tpl.title.isEmpty ? "Untitled" : tpl.title)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Template
                SectionCard(title: "Template", systemImage: "square.grid.2x2") {
                    VStack(alignment: .leading, spacing: 12) {
                        // Roles: one-row chips with Manage button (not collapsible)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .center) {
                                Label("Roles", systemImage: "person.badge.key")
                                    .font(.headline)
                                Spacer()
                                Button {
                                    showManageRoles = true
                                } label: {
                                    Label("Manage", systemImage: "slider.horizontal.3")
                                }
                                .buttonStyle(.bordered)
                            }
                            if roles.isEmpty {
                                Text("No roles yet")
                                    .foregroundStyle(.secondary)
                            } else {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(roles, id: \.id) { role in
                                            Chip(text: role.title.isEmpty ? "Role" : role.title)
                                        }
                                    }
                                }
                            }
                        }

                        // Weeks (remain collapsible to save space)
                        DisclosureGroup {
                            BookClubWeeksEditorView(club: club, showHeader: false)
                                .padding(.top, 4)
                        } label: {
                            Label("Weeks", systemImage: "calendar")
                                .font(.headline)
                        }
                    }
                }

                // Sessions
                SectionCard(title: "Sessions", systemImage: "calendar") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Upcoming & Past Sessions")
                                .font(.headline)
                            Spacer()
                            Button {
                                showNewSession = true
                            } label: {
                                Label("New Session", systemImage: "calendar.badge.plus")
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        if club.sessions.isEmpty {
                            Text("No sessions yet")
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(club.sessions.sorted(by: { $0.meetingDate > $1.meetingDate })) { session in
                                    NavigationLink(destination: BookClubSessionDetailView(session: session)) {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(Self.df.string(from: session.meetingDate))
                                                    .font(.headline)
                                                if let ch = session.chapterOrPages, !ch.isEmpty {
                                                    Text(ch).font(.subheadline).foregroundStyle(.secondary)
                                                }
                                            }
                                            Spacer()
                                            Text("\(session.deliverables.count) deliverables")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.vertical, 4)
                                    Divider().opacity(0.15)
                                }
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle(club.title)
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete Project", systemImage: "trash")
                }
            }
        }
        .sheet(isPresented: $showNewSession) {
            NewBookClubSessionSheet(club: club)
        }
        .sheet(isPresented: $showEditClub) {
            BookClubEditorSheet(club: club)
        }
        .sheet(isPresented: $showManageRoles) {
            NavigationStack { BookClubRolesEditorView(club: club) }
            #if os(macOS)
            .frame(minWidth: 520, minHeight: 360)
            #endif
        }
        .alert("Delete this project?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { deleteClub() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will remove all sessions, deliverables, roles, template weeks, and shared assignments for this project. This action cannot be undone.")
        }
    }

    private func deleteClub() {
        // Delete sessions and their deliverables
        let sessions = allSessions.filter { $0.bookClubID == club.id }
        for s in sessions {
            for d in s.deliverables { modelContext.delete(d) }
            modelContext.delete(s)
        }

        // Delete templates associated with this club
        let templates = allTemplates.filter { $0.bookClubID == club.id }
        for t in templates { modelContext.delete(t) }

        // Delete roles for this club
        let rolesToDelete = allRoles.filter { $0.bookClubID == club.id }
        for r in rolesToDelete { modelContext.delete(r) }

        // Delete template weeks and their related data
        let weeks = allWeeks.filter { $0.bookClubID == club.id }
        for w in weeks {
            let assigns = allRoleAssignments.filter { $0.weekID == w.id }
            for a in assigns { modelContext.delete(a) }
            if let setID = w.questionChoiceSetID {
                let items = allChoiceItems.filter { $0.setID == setID }
                for item in items { modelContext.delete(item) }
                if let set = allChoiceSets.first(where: { $0.id == setID }) { modelContext.delete(set) }
            }
            modelContext.delete(w)
        }

        // Safety: delete any remaining choice sets/items for this club
        let sets = allChoiceSets.filter { $0.bookClubID == club.id }
        for set in sets {
            let items = allChoiceItems.filter { $0.setID == set.id }
            for item in items { modelContext.delete(item) }
            modelContext.delete(set)
        }

        // Finally, delete the club itself
        modelContext.delete(club)
        _ = saveCoordinator.save(modelContext, reason: "Delete Book Club from detail view")
        dismiss()
    }

    private static let df: DateFormatter = {
        let df = DateFormatter(); df.dateStyle = .medium; return df
    }()
}

private struct SectionCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.title3).fontWeight(.semibold)
                Spacer()
            }
            .padding(.bottom, 2)

            content
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }
}

private struct Chip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.subheadline)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                Capsule().fill(Color.primary.opacity(0.06))
            )
    }
}

#if DEBUG
struct BookClubRolesEditorView_Placeholder: View {
    let club: BookClub
    var body: some View { EmptyView() }
}

struct BookClubWeeksEditorView_Placeholder: View {
    let club: BookClub
    var body: some View { EmptyView() }
}
#endif
