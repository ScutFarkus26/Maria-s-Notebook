import SwiftUI
import SwiftData

/// Main view for managing classroom procedures
struct ProceduresListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Procedure.title) private var procedures: [Procedure]

    @State private var searchText = ""
    @State private var selectedCategory: ProcedureCategory?
    @State private var showingAddSheet = false
    @State private var selectedProcedure: Procedure?
    @State private var procedureToEdit: Procedure?

    private var filteredProcedures: [Procedure] {
        ProcedureService.fetchProcedures(
            in: modelContext,
            category: selectedCategory,
            searchText: searchText
        )
    }

    private var groupedProcedures: [(category: ProcedureCategory, procedures: [Procedure])] {
        ProcedureService.fetchProceduresGroupedByCategory(
            in: modelContext,
            searchText: searchText
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            ViewHeader(title: "Procedures") {
                HStack(spacing: 12) {
                    // Category filter
                    Menu {
                        Button("All Categories") {
                            selectedCategory = nil
                        }
                        Divider()
                        ForEach(ProcedureCategory.allCases) { category in
                            Button {
                                selectedCategory = category
                            } label: {
                                Label(category.rawValue, systemImage: category.icon)
                            }
                        }
                    } label: {
                        Label(
                            selectedCategory?.rawValue ?? "All",
                            systemImage: selectedCategory?.icon ?? "square.grid.2x2"
                        )
                        .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    // Add button
                    Button {
                        showingAddSheet = true
                    } label: {
                        Label("Add Procedure", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Search bar
                    searchBar

                    // Procedures list
                    if procedures.isEmpty {
                        emptyState
                    } else if filteredProcedures.isEmpty {
                        noResultsState
                    } else if selectedCategory != nil {
                        // Single category view
                        proceduresList(filteredProcedures)
                    } else {
                        // Grouped by category
                        groupedProceduresView
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            ProcedureEditorSheet(procedure: nil)
        }
        .sheet(item: $selectedProcedure) { procedure in
            ProcedureDetailView(procedure: procedure) { editProcedure in
                selectedProcedure = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    procedureToEdit = editProcedure
                }
            }
        }
        .sheet(item: $procedureToEdit) { procedure in
            ProcedureEditorSheet(procedure: procedure)
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search procedures...", text: $searchText)
                .textFieldStyle(.plain)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08))
        )
    }

    // MARK: - Grouped Procedures View

    private var groupedProceduresView: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(groupedProcedures, id: \.category) { group in
                VStack(alignment: .leading, spacing: 12) {
                    // Category header
                    HStack(spacing: 10) {
                        Image(systemName: group.category.icon)
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.category.rawValue)
                                .font(.title2)
                                .fontWeight(.bold)
                            Text(group.category.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(group.procedures.count)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)

                    proceduresList(group.procedures)
                }
            }
        }
    }

    // MARK: - Procedures List

    private func proceduresList(_ items: [Procedure]) -> some View {
        VStack(spacing: 8) {
            ForEach(items) { procedure in
                ProcedureRow(procedure: procedure)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedProcedure = procedure
                    }
                    .contextMenu {
                        Button {
                            selectedProcedure = procedure
                        } label: {
                            Label("View", systemImage: "eye")
                        }

                        Button {
                            procedureToEdit = procedure
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }

                        Divider()

                        Button(role: .destructive) {
                            ProcedureService.deleteProcedure(procedure, in: modelContext)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
    }

    // MARK: - Empty States

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Procedures Yet")
                .font(.title2.weight(.semibold))

            Text("Document your classroom routines, safety procedures, and special schedules.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            Button {
                showingAddSheet = true
            } label: {
                Label("Add First Procedure", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var noResultsState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)

            Text("No procedures found")
                .font(.headline)

            Text("Try adjusting your search or filter.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

#Preview {
    ProceduresListView()
        .previewEnvironment()
}
