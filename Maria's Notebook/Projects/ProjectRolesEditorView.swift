import SwiftUI
import SwiftData

struct ProjectRolesEditorView: View {
    let club: Project

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var saveCoordinator: SaveCoordinator
    @Environment(\.dismiss) private var dismiss

    // FIX: Use explicit generic SortDescriptor so SwiftData compiles reliably.
    @Query(sort: [SortDescriptor<ProjectRole>(\.createdAt, order: .forward)])
    private var allRoles: [ProjectRole]

    @State private var showEditor: Bool = false
    @State private var editingRole: ProjectRole? = nil

    private var roles: [ProjectRole] {
        allRoles.filter { $0.projectID == club.id.uuidString }
    }

    var body: some View {
        Group {
            if roles.isEmpty {
                VStack(spacing: 12) {
                    ContentUnavailableView(
                        "No Roles",
                        systemImage: "person.2",
                        description: Text("Create roles like Director, Illustrator, etc.")
                    )
                    Button {
                        editingRole = nil
                        showEditor = true
                    } label: {
                        Label("Add Role", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding()
            } else {
                List {
                    ForEach(roles, id: \.id) { role in
                        Button {
                            editingRole = role
                            showEditor = true
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(role.title.isEmpty ? "Untitled" : role.title)
                                        .font(.body.weight(.semibold))
                                    let firstLine = role.summary.split(separator: "\n").first.map(String.init) ?? role.summary
                                    if !firstLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        Text(firstLine)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote)
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu { Button("Delete", role: .destructive) { delete(role) } }
                    }
                    .onDelete(perform: deleteAtOffsets)
                }
                #if os(iOS)
                .listStyle(.insetGrouped)
                #else
                .listStyle(.inset)
                #endif
            }
        }
        .navigationTitle("Roles")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editingRole = nil
                    showEditor = true
                } label: {
                    Label("Add Role", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            NavigationStack {
                ProjectRoleEditorSheet(club: club, role: editingRole) {
                    showEditor = false
                }
            }
            .frame(minWidth: 520, minHeight: 340)
        }
    }

    private func delete(_ role: ProjectRole) {
        modelContext.delete(role)
        _ = saveCoordinator.save(modelContext, reason: "Delete project role")
    }

    private func deleteAtOffsets(_ offsets: IndexSet) {
        for i in offsets {
            if roles.indices.contains(i) {
                let role = roles[i]
                delete(role)
            }
        }
    }
}

private struct ProjectRoleEditorSheet: View {
    let club: Project
    let role: ProjectRole?
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var saveCoordinator: SaveCoordinator

    @State private var title: String = ""
    @State private var summary: String = ""
    @State private var instructions: String = ""

    init(club: Project, role: ProjectRole?, onDone: @escaping () -> Void) {
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
            let newRole = ProjectRole(
                projectID: club.id,
                title: trimmedTitle,
                summary: summary,
                instructions: instructions
            )
            modelContext.insert(newRole)
        }

        _ = saveCoordinator.save(modelContext, reason: "Save project role")
        onDone()
        dismiss()
    }
}
