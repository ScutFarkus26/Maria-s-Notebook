import SwiftUI
import CoreData
#if os(iOS)
import UIKit
#endif

/// Root view for the Initiatives feature — Things-style project manager for
/// the teacher's personal admin (report cards, class trips, etc.).
struct InitiativesRootView: View {
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(SaveCoordinator.self) private var saveCoordinator
    @Environment(\.appRouter) private var appRouter

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \CDInitiative.completedAt, ascending: true),
            NSSortDescriptor(keyPath: \CDInitiative.deadline, ascending: true),
            NSSortDescriptor(keyPath: \CDInitiative.title, ascending: true)
        ]
    ) private var initiativesRaw: FetchedResults<CDInitiative>

    private var initiatives: [CDInitiative] { Array(initiativesRaw).uniqueByID }

    @SceneStorage("Initiatives.selectedID") private var selectedIDString: String = ""
    @State private var showNewSheet: Bool = false
    @State private var searchText: String = ""
    @State private var showCompleted: Bool = false
    @State private var initiativeToDelete: CDInitiative?
    @State private var showDeleteAlert: Bool = false

    private var selectedBinding: Binding<UUID?> {
        Binding {
            UUID(uuidString: selectedIDString)
        } set: { newValue in
            selectedIDString = newValue?.uuidString ?? ""
        }
    }

    private var selectedInitiative: CDInitiative? {
        initiatives.first { $0.id?.uuidString == selectedIDString }
    }

    private var filteredInitiatives: [CDInitiative] {
        let base = showCompleted ? initiatives : initiatives.filter { !$0.isCompleted }
        guard !searchText.isEmpty else { return base }
        return base.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    private var groupedByArea: [(area: String, items: [CDInitiative])] {
        let groups = Dictionary(grouping: filteredInitiatives) {
            ($0.area?.trimmed().isEmpty ?? true) ? "Other" : ($0.area!.trimmed())
        }
        return groups.keys.sorted().map { key in
            (area: key, items: groups[key] ?? [])
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ViewHeader(title: "Initiatives") {
                Button {
                    showNewSheet = true
                } label: {
                    Label("New Initiative", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            Divider()
            HStack(spacing: 0) {
                sidebar
                    .frame(width: 300)
                Divider()
                detailContent
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showNewSheet) {
            InitiativeEditorSheet(initiative: nil)
        }
        .alert("Delete Initiative?", isPresented: $showDeleteAlert, presenting: initiativeToDelete) { item in
            Button("Delete", role: .destructive) { delete(item) }
            Button("Cancel", role: .cancel) { initiativeToDelete = nil }
        } message: { item in
            Text("Delete \"\(item.title)\"? Linked todos will be unlinked but not deleted.")
        }
        .task {
            if selectedIDString.isEmpty, let first = filteredInitiatives.first {
                selectedIDString = first.id?.uuidString ?? ""
            }
            if let pendingID = appRouter.pendingInitiativeID {
                selectedIDString = pendingID
                appRouter.pendingInitiativeID = nil
            }
        }
        .onChange(of: appRouter.pendingInitiativeID) { _, newValue in
            if let pendingID = newValue {
                selectedIDString = pendingID
                appRouter.pendingInitiativeID = nil
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                Toggle(isOn: $showCompleted) {
                    Image(systemName: showCompleted ? "checkmark.circle.fill" : "checkmark.circle")
                }
                .toggleStyle(.button)
                .help("Show completed")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            List(selection: selectedBinding) {
                ForEach(groupedByArea, id: \.area) { group in
                    Section(group.area) {
                        ForEach(group.items, id: \.objectID) { item in
                            InitiativeSidebarRow(initiative: item)
                                .tag(item.id)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        initiativeToDelete = item
                                        showDeleteAlert = true
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .contextMenu {
                                    Button {
                                        toggleComplete(item)
                                    } label: {
                                        Label(
                                            item.isCompleted ? "Mark Active" : "Mark Complete",
                                            systemImage: item.isCompleted ? "arrow.uturn.backward.circle" : "checkmark.circle"
                                        )
                                    }
                                    Divider()
                                    Button(role: .destructive) {
                                        initiativeToDelete = item
                                        showDeleteAlert = true
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailContent: some View {
        if let initiative = selectedInitiative {
            InitiativeDetailView(initiative: initiative) {
                initiativeToDelete = initiative
                showDeleteAlert = true
            }
        } else {
            ContentUnavailableView(
                "No Initiative Selected",
                systemImage: "target",
                description: Text("Pick an initiative on the left, or create one to get started.")
            )
        }
    }

    // MARK: - Mutations

    private func toggleComplete(_ item: CDInitiative) {
        item.completedAt = item.isCompleted ? nil : Date()
        item.modifiedAt = Date()
        _ = saveCoordinator.save(modelContext, reason: "Toggle Initiative Complete")
        // Completed initiatives shouldn't fire reminders.
        if item.isCompleted {
            TodoNotificationService.shared.cancelNotifications(for: item, context: modelContext)
        } else {
            Task { @MainActor in
                try? await TodoNotificationService.shared.rescheduleNotifications(for: item, context: modelContext)
            }
        }
    }

    private func delete(_ item: CDInitiative) {
        // Tear down pending notifications first.
        TodoNotificationService.shared.cancelNotifications(for: item, context: modelContext)
        // Unlink any todos that point at this initiative.
        if let idString = item.id?.uuidString {
            let fetch: NSFetchRequest<CDTodoItemEntity> = NSFetchRequest(entityName: "TodoItem")
            fetch.predicate = NSPredicate(format: "initiativeID == %@", idString)
            if let todos = try? modelContext.fetch(fetch) {
                for todo in todos { todo.initiativeID = nil }
            }
        }
        modelContext.delete(item)
        if selectedIDString == item.id?.uuidString {
            selectedIDString = ""
        }
        initiativeToDelete = nil
        _ = saveCoordinator.save(modelContext, reason: "Delete Initiative")
    }
}

// MARK: - Sidebar row

struct InitiativeSidebarRow: View {
    @ObservedObject var initiative: CDInitiative

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: initiative.symbol ?? InitiativeSymbol.defaultValue.rawValue)
                .foregroundStyle(InitiativeColor.from(raw: initiative.colorRaw).swiftUIColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(initiative.title.isEmpty ? "Untitled" : initiative.title)
                    .strikethrough(initiative.isCompleted)
                    .foregroundStyle(initiative.isCompleted ? .secondary : .primary)
                if let deadline = initiative.deadline {
                    Text(deadline, format: .dateTime.month(.abbreviated).day().year())
                        .font(.caption2)
                        .foregroundStyle(initiative.isOverdue ? .red : .secondary)
                }
            }
            Spacer(minLength: 0)
            if let days = initiative.daysUntilDeadline, !initiative.isCompleted {
                deadlinePill(days: days)
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func deadlinePill(days: Int) -> some View {
        let label: String = {
            if days < 0 { return "\(-days)d over" }
            if days == 0 { return "today" }
            return "\(days)d"
        }()
        let color: Color = {
            if days < 0 { return .red }
            if days <= 3 { return .orange }
            return .secondary
        }()
        Text(label)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
