import SwiftUI
import SwiftData

struct BookClubRolesEditorView: View {
    let club: BookClub

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var saveCoordinator: SaveCoordinator

    @Query private var roles: [BookClubRole]

    @State private var showEditor: Bool = false
    @State private var editingRole: BookClubRole? = nil

    init(club: BookClub) {
        self.club = club
        let clubID = club.id
        _roles = Query(
            filter: #Predicate<BookClubRole> { $0.bookClubID == clubID },
            sort: [SortDescriptor<BookClubRole>(\.title, order: .forward)]
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Roles")
                    .font(.headline)
                Spacer()
                Button { editingRole = nil; showEditor = true } label: { Label("Add Role", systemImage: "plus") }
            }
            if roles.isEmpty {
                ContentUnavailableView("No Roles", systemImage: "person.2", description: Text("Create roles like Director, Illustrator, etc."))
            } else {
                List {
                    ForEach(roles, id: \.id) { role in
                        Button {
                            editingRole = role; showEditor = true
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(role.title.isEmpty ? "Untitled" : role.title)
                                    .font(.headline)
                                let firstLine = role.summary.split(separator: "\n").first.map(String.init) ?? role.summary
                                if !firstLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text(firstLine)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Delete", role: .destructive) { delete(role) }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            BookClubRoleEditorSheet(club: club, role: editingRole) { showEditor = false }
        }
    }

    private func delete(_ role: BookClubRole) {
        modelContext.delete(role)
        _ = saveCoordinator.save(modelContext, reason: "Delete book club role")
    }
}

struct BookClubRoleEditorSheet: View {
    let club: BookClub
    let role: BookClubRole?
    var onDone: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var saveCoordinator: SaveCoordinator

    @State private var title: String = ""
    @State private var summary: String = ""
    @State private var instructions: String = ""

    init(club: BookClub, role: BookClubRole?, onDone: @escaping () -> Void) {
        self.club = club
        self.role = role
        self.onDone = onDone
        _title = State(initialValue: role?.title ?? "")
        _summary = State(initialValue: role?.summary ?? "")
        _instructions = State(initialValue: role?.instructions ?? "")
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(role == nil ? "New Role" : "Edit Role")
                    .font(.title3).fontWeight(.semibold)

                TextField("Title (e.g., The Director)", text: $title)
                    .textFieldStyle(.roundedBorder)
                TextField("Summary (one-liner)", text: $summary)
                    .textFieldStyle(.roundedBorder)
                TextField("Instructions", text: $instructions, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(6...12)
            }
            .padding(16)
            .navigationTitle(role == nil ? "New Role" : "Edit Role")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    #if os(macOS)
        .frame(minWidth: 520, minHeight: 360)
        .presentationSizing(.fitted)
    #else
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    #endif
    }

    private func cancel() { onDone(); dismiss() }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        if let role {
            role.title = trimmedTitle
            role.summary = summary
            role.instructions = instructions
        } else {
            let newRole = BookClubRole(bookClubID: club.id, title: trimmedTitle, summary: summary, instructions: instructions)
            modelContext.insert(newRole)
        }
        _ = saveCoordinator.save(modelContext, reason: "Save book club role")
        onDone(); dismiss()
    }
}

