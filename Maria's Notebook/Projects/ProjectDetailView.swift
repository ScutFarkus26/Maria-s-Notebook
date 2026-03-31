import SwiftUI
import CoreData

struct ProjectDetailView: View {
    let club: Project

    @Environment(\.managedObjectContext) private var modelContext
    @Environment(SaveCoordinator.self) private var saveCoordinator
    @Environment(\.dismiss) private var dismiss

    // Test student filtering
    @AppStorage(UserDefaultsKeys.generalShowTestStudents) private var showTestStudents: Bool = false
    @AppStorage(UserDefaultsKeys.generalTestStudentNames)
    private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    @FetchRequest(sortDescriptors: CDStudent.sortByName) private var studentsRaw: FetchedResults<CDStudent>
    // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
    // Filter out test students when setting is disabled
    private var students: [Student] {
        TestStudentsFilter.filterVisible(
            Array(studentsRaw).uniqueByID.filter(\.isEnrolled),
            show: showTestStudents,
            namesRaw: testStudentNamesRaw
        )
    }

    // Performance: Filter roles by projectID at query level
    @FetchRequest private var roles: FetchedResults<CDProjectRole>

    @State private var showNewSession: Bool = false
    @State private var showEditClub: Bool = false
    @State private var showManageRoles: Bool = false

    init(club: Project) {
        self.club = club
        // Performance: Filter roles by projectID at query level
        let projectIDString = (club.id ?? UUID()).uuidString
        _roles = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \CDProjectRole.createdAt, ascending: true)],
            predicate: NSPredicate(format: "projectID == %@", projectIDString)
        )
    }

    // Use uniquingKeysWith to handle CloudKit sync duplicates
    private var studentsByID: [UUID: Student] {
        Dictionary(
            students.compactMap { s -> (UUID, Student)? in guard let id = s.id else { return nil }; return (id, s) },
            uniquingKeysWith: { first, _ in first }
        )
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                // Overview
                SectionCard(title: "Overview", systemImage: SFSymbol.People.person3) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                        // Header with Book Title and Edit (if available)
                        if let bt = club.bookTitle, !bt.isEmpty {
                            HStack(alignment: .firstTextBaseline) {
                                Label(bt, systemImage: SFSymbol.Education.bookClosed)
                                    .font(.title3).fontWeight(.semibold)
                                Spacer()
                                Button {
                                    showEditClub = true
                                } label: {
                                    Label("Edit", systemImage: SFSymbol.Education.pencil)
                                }
                                .buttonStyle(.bordered)
                            }
                            // Members subheader (compact)
                            HStack(alignment: .firstTextBaseline) {
                                Label("Members", systemImage: SFSymbol.People.person2)
                                    .font(.headline)
                                Spacer()
                            }
                        } else {
                            // Fallback: Members header with Edit when no book title
                            HStack(alignment: .firstTextBaseline) {
                                Label("Members", systemImage: SFSymbol.People.person2)
                                    .font(.headline)
                                Spacer()
                                Button {
                                    showEditClub = true
                                } label: {
                                    Label("Edit", systemImage: SFSymbol.Education.pencil)
                                }
                                .buttonStyle(.bordered)
                            }
                        }

                        // Members as a single row (horizontal chips)
                        if club.memberStudentIDsArray.isEmpty {
                            Text("No members selected")
                                .foregroundStyle(.secondary)
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: AppTheme.Spacing.small) {
                                    ForEach(club.memberStudentIDsArray, id: \.self) { sid in
                                        if let s = studentsByID[uuidString: sid] {
                                            Chip(text: StudentFormatter.displayName(for: s))
                                        } else {
                                            Chip(text: "Unknown")
                                        }
                                    }
                                }
                            }
                        }

                        // Shared Assignments (only show if present)
                        let shared = ((club.sharedTemplates?.allObjects as? [CDProjectAssignmentTemplate]) ?? []).filter(\.isShared)
                        if !shared.isEmpty {
                            Divider().opacity(UIConstants.OpacityConstants.faint + 0.12)
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                                Label("Shared Assignments", systemImage: "square.and.pencil")
                                    .font(.headline)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: AppTheme.Spacing.small) {
                                        ForEach(shared, id: \.objectID) { tpl in
                                            Chip(text: tpl.title.isEmpty ? "Untitled" : tpl.title)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Template
                SectionCard(title: "Template", systemImage: SFSymbol.List.squareGrid) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                        // Roles: one-row chips with Manage button (not collapsible)
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
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
                                    HStack(spacing: AppTheme.Spacing.small) {
                                        ForEach(Array(roles), id: \.objectID) { role in
                                            Chip(text: role.title.isEmpty ? "Role" : role.title)
                                        }
                                    }
                                }
                            }
                        }

                        // Weeks (remain collapsible to save space)
                        DisclosureGroup {
                            ProjectWeeksEditorView(club: club, showHeader: false)
                                .padding(.top, AppTheme.Spacing.xsmall)
                        } label: {
                            Label("Weeks", systemImage: SFSymbol.Time.calendar)
                                .font(.headline)
                        }
                    }
                }

                // Sessions
                SectionCard(title: "Sessions", systemImage: SFSymbol.Time.calendar) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                        HStack {
                            Text("Upcoming & Past Sessions")
                                .font(.headline)
                            Spacer()
                            Button {
                                showNewSession = true
                            } label: {
                                Label("New Session", systemImage: SFSymbol.Time.calendarBadgePlus)
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        let sessionsArray = (club.sessions?.allObjects as? [CDProjectSession]) ?? []
                        if sessionsArray.isEmpty {
                            Text("No sessions yet")
                                .foregroundStyle(.secondary)
                                .padding(.top, AppTheme.Spacing.xsmall)
                        } else {
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                                let sorted = sessionsArray
                                    .sorted { ($0.meetingDate ?? .distantPast) > ($1.meetingDate ?? .distantPast) }
                                ForEach(sorted, id: \.objectID) { session in
                                    NavigationLink(destination: ProjectSessionDetailView(session: session)) {
                                        // Use subview to correctly query work count
                                        SessionRow(session: session)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.vertical, AppTheme.Spacing.xsmall)
                                    Divider().opacity(UIConstants.OpacityConstants.accent)
                                }
                            }
                        }
                    }
                }
            }
            .padding(AppTheme.Spacing.medium)
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
    @FetchRequest private var workModels: FetchedResults<CDWorkModel>

    init(session: ProjectSession) {
        self.session = session
        let sid = session.id?.uuidString ?? ""
        _workModels = FetchRequest(
            sortDescriptors: [],
            predicate: NSPredicate(format: "sourceContextID == %@", sid)
        )
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
                Text(DateFormatters.mediumDate.string(from: session.meetingDate ?? Date()))
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
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            HStack(spacing: AppTheme.Spacing.small) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.title3).fontWeight(.semibold)
                Spacer()
            }
            .padding(.bottom, AppTheme.Spacing.xxsmall)

            content
        }
        .padding(AppTheme.Spacing.compact + 2)
        .background(
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.large + 2, style: .continuous)
                .fill(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
        )
    }
}

private struct Chip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.subheadline)
            .padding(.vertical, AppTheme.Spacing.verySmall)
            .padding(.horizontal, AppTheme.Spacing.small + 2)
            .background(
                Capsule().fill(Color.primary.opacity(UIConstants.OpacityConstants.subtle))
            )
    }
}
