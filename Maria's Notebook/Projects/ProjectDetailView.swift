import SwiftUI
import SwiftData

struct ProjectDetailView: View {
    let club: Project

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var saveCoordinator: SaveCoordinator
    @Environment(\.dismiss) private var dismiss

    // Test student filtering
    @AppStorage("General.showTestStudents") private var showTestStudents: Bool = false
    @AppStorage("General.testStudentNames") private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    @Query(sort: [SortDescriptor(\Student.firstName), SortDescriptor(\Student.lastName)]) private var studentsRaw: [Student]
    // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
    // Filter out test students when setting is disabled
    private var students: [Student] {
        TestStudentsFilter.filterVisible(studentsRaw.uniqueByID, show: showTestStudents, namesRaw: testStudentNamesRaw)
    }

    // Performance: Filter roles by projectID at query level
    @Query(sort: [SortDescriptor(\ProjectRole.createdAt, order: .forward)]) private var roles: [ProjectRole]

    @State private var showNewSession: Bool = false
    @State private var showEditClub: Bool = false
    @State private var showManageRoles: Bool = false

    init(club: Project) {
        self.club = club
        // Performance: Filter roles by projectID at query level
        let projectIDString = club.id.uuidString
        _roles = Query(
            filter: #Predicate<ProjectRole> { $0.projectID == projectIDString },
            sort: [SortDescriptor(\.createdAt, order: .forward)]
        )
    }

    // Use uniquingKeysWith to handle CloudKit sync duplicates
    private var studentsByID: [UUID: Student] { Dictionary(students.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }) }
    
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
                        let shared = (club.sharedTemplates ?? []).filter { $0.isShared }
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
                            ProjectWeeksEditorView(club: club, showHeader: false)
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

                        if (club.sessions ?? []).isEmpty {
                            Text("No sessions yet")
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach((club.sessions ?? []).sorted(by: { $0.meetingDate > $1.meetingDate })) { session in
                                    NavigationLink(destination: ProjectSessionDetailView(session: session)) {
                                        // Use subview to correctly query work count
                                        SessionRow(session: session)
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
        .sheet(isPresented: $showNewSession) {
            NewProjectSessionSheet(club: club)
        }
        .sheet(isPresented: $showEditClub) {
            ProjectEditorSheet(club: club)
        }
        .sheet(isPresented: $showManageRoles) {
            NavigationStack { ProjectRolesEditorView(club: club) }
            #if os(macOS)
            .frame(minWidth: 520, minHeight: 360)
            #endif
        }
    }
}

// Helper view to show session details + work count
private struct SessionRow: View {
    let session: ProjectSession
    @Query private var workModels: [WorkModel]
    
    init(session: ProjectSession) {
        self.session = session
        let sid = session.id.uuidString
        _workModels = Query(filter: #Predicate<WorkModel> { $0.sourceContextID == sid })
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(df.string(from: session.meetingDate))
                    .font(.headline)
                if let ch = session.chapterOrPages, !ch.isEmpty {
                    Text(ch).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("\(workModels.count) work items")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    private let df: DateFormatter = {
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
