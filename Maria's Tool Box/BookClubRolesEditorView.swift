import SwiftUI
import SwiftData

struct BookClubRolesEditorView: View {
    let club: BookClub

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var saveCoordinator: SaveCoordinator

    // FIX: Use explicit generic SortDescriptor so SwiftData compiles reliably.
    @Query(sort: [SortDescriptor<BookClubRole>(\.createdAt, order: .forward)])
    private var allRoles: [BookClubRole]

    @State private var showEditor: Bool = false
    @State private var editingRole: BookClubRole? = nil

    private var roles: [BookClubRole] {
        allRoles.filter { $0.bookClubID == club.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Roles")
                    .font(.headline)
                Spacer()
                Button {
                    editingRole = nil
                    showEditor = true
                } label: {
                    Label("Add Role", systemImage: "plus")
                }
            }

            if roles.isEmpty {
                // FIX: Proper ContentUnavailableView call (your file had a truncated/invalid call).
                ContentUnavailableView(
                    "No Roles",
                    systemImage: "person.2",
                    description: Text("Create roles like Director, Illustrator, etc.")
                )
                .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                List {
                    ForEach(roles, id: \.id) { role in
                        Button {
                            editingRole = role
                            showEditor = true
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
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Delete", role: .destructive) { delete(role) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            }
        }
        .sheet(isPresented: $showEditor) {
            // FIX: Always show Save/Cancel without resizing on macOS.
            NavigationStack {
                BookClubRoleEditorSheet(club: club, role: editingRole) {
                    showEditor = false
                }
            }
            .frame(minWidth: 520, minHeight: 340)
        }
    }

    private func delete(_ role: BookClubRole) {
        modelContext.delete(role)
        _ = saveCoordinator.save(modelContext, reason: "Delete book club role")
    }
}

private struct BookClubRoleEditorSheet: View {
    let club: BookClub
    let role: BookClubRole?
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
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
        VStack(alignment: .leading, spacing: 12) {
            Text(role == nil ? "New Role" : "Edit Role")
                .font(.title3)
                .fontWeight(.semibold)

            TextField("Title (e.g., The Director)", text: $title)
                .textFieldStyle(.roundedBorder)

            TextField("Summary (one-liner)", text: $summary)
                .textFieldStyle(.roundedBorder)

            TextField("Instructions", text: $instructions, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(6...12)

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Cancel") { cancel() }
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .navigationTitle(role == nil ? "Add Role" : "Edit Role")
    }

    private func cancel() {
        onDone()
        dismiss()
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        if let role {
            role.title = trimmedTitle
            role.summary = summary
            role.instructions = instructions
        } else {
            // IMPORTANT: Associates role with this club so it shows in the filtered list.
            let newRole = BookClubRole(
                bookClubID: club.id,
                title: trimmedTitle,
                summary: summary,
                instructions: instructions
            )
            modelContext.insert(newRole)
        }

        _ = saveCoordinator.save(modelContext, reason: "Save book club role")
        onDone()
        dismiss()
    }
}
