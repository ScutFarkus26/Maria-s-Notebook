import SwiftUI
import SwiftData

struct BookClubDetailView: View {
    let club: BookClub

    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\Student.firstName), SortDescriptor(\Student.lastName)]) private var students: [Student]

    @State private var showNewSession: Bool = false
    @State private var showEditClub: Bool = false

    private var studentsByID: [UUID: Student] { Dictionary(uniqueKeysWithValues: students.map { ($0.id, $0) }) }
    
    private enum Tab {
        case overview, template, sessions
    }
    
    @State private var selectedTab: Tab = .overview

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            
            // Pill row tabs
            HStack(spacing: 12) {
                TabButton(title: "Overview", isSelected: selectedTab == .overview) {
                    selectedTab = .overview
                }
                TabButton(title: "Template", isSelected: selectedTab == .template) {
                    selectedTab = .template
                }
                TabButton(title: "Sessions", isSelected: selectedTab == .sessions) {
                    selectedTab = .sessions
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch selectedTab {
                    case .overview:
                        // Members
                        GroupBox("Members") {
                            if club.memberStudentIDs.isEmpty {
                                Text("No members selected")
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(club.memberStudentIDs, id: \.self) { sid in
                                        if let uuid = UUID(uuidString: sid), let s = studentsByID[uuid] {
                                            Text(StudentFormatter.displayName(for: s))
                                        } else {
                                            Text("Unknown student")
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Shared templates
                        GroupBox("Shared Assignments") {
                            if club.sharedTemplates.isEmpty {
                                Text("No shared templates")
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(club.sharedTemplates.filter { $0.isShared }) { tpl in
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(tpl.title.isEmpty ? "Untitled" : tpl.title)
                                                .font(.headline)
                                            if !tpl.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                                Text(tpl.instructions)
                                                    .font(.subheadline)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        .padding(.vertical, 4)
                                    }
                                }
                            }
                        }
                        
                    case .template:
                        GroupBox("Roles") {
                            BookClubRolesEditorView(club: club)
                                .padding(.vertical, 4)
                        }
                        GroupBox("Weeks") {
                            BookClubWeeksEditorView(club: club)
                                .padding(.vertical, 4)
                        }
                        
                    case .sessions:
                        GroupBox("Sessions") {
                            if club.sessions.isEmpty {
                                Text("No sessions yet")
                                    .foregroundStyle(.secondary)
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
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle(club.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                switch selectedTab {
                case .overview:
                    Button {
                        showEditClub = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                case .sessions:
                    Button {
                        showNewSession = true
                    } label: {
                        Label("New Session", systemImage: "calendar.badge.plus")
                    }
                case .template:
                    EmptyView()
                }
            }
        }
        .sheet(isPresented: $showNewSession) {
            NewBookClubSessionSheet(club: club)
        }
        .sheet(isPresented: $showEditClub) {
            BookClubEditorSheet(club: club)
        }
    }

    private static let df: DateFormatter = {
        let df = DateFormatter(); df.dateStyle = .medium; return df
    }()
}
private struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.vertical, 6)
                .padding(.horizontal, 14)
                .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
                .foregroundColor(isSelected ? Color.accentColor : Color.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
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

