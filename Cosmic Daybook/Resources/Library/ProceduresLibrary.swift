import SwiftUI
import CoreData

/// Resources › Procedures: classroom routines written in the notebook, shown
/// as pages and grouped by category. A page opens the procedure, whose Edit
/// opens the procedure editor from the detail itself (on a phone the detail
/// is a sheet, which can't hand the editor to a sheet on the list below it);
/// a card's context menu opens the editor from here.
struct ProceduresLibrary: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDProcedure.title, ascending: true)],
        animation: .default
    )
    private var procedures: FetchedResults<CDProcedure>

    @State private var searchText = ""
    @State private var selectedCategory: ProcedureCategory?
    @State private var isShowingAddSheet = false
    @State private var procedureToEdit: CDProcedure?

    private var filteredProcedures: [CDProcedure] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return procedures.filter { procedure in
            if let selectedCategory, procedure.category != selectedCategory { return false }
            guard !query.isEmpty else { return true }
            return procedure.title.lowercased().contains(query)
                || procedure.summary.lowercased().contains(query)
                || procedure.content.lowercased().contains(query)
        }
    }

    /// One section per category, in the categories' own order; one untitled
    /// section once a category is picked.
    private var sections: [PDFLibrarySection<CDProcedure>] {
        let shown = filteredProcedures
        if selectedCategory != nil {
            return [PDFLibrarySection(title: nil, items: shown)]
        }
        let grouped = Dictionary(grouping: shown, by: \.category)
        return ProcedureCategory.allCases.compactMap { category in
            guard let items = grouped[category], !items.isEmpty else { return nil }
            return PDFLibrarySection(
                title: category.rawValue,
                systemImage: category.icon,
                subtitle: category.description,
                items: items
            )
        }
    }

    var body: some View {
        PDFLibraryListView(
            items: Array(procedures),
            sections: sections,
            logger: .app_,
            importPDF: nil,
            header: { headerBar },
            card: { procedure, isSelected in
                ProcedurePageCard(procedure: procedure, isSelected: isSelected)
                    .contextMenu {
                        Button {
                            procedureToEdit = procedure
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Divider()
                        Button(role: .destructive) {
                            ProcedureService.deleteProcedure(procedure, in: viewContext)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            },
            detail: { procedure, close in
                ProcedureDetailView(procedure: procedure, onClose: close)
            },
            emptyState: { emptyState }
        )
        .sheet(isPresented: $isShowingAddSheet) {
            ProcedureEditorSheet(procedure: nil)
        }
        .sheet(item: $procedureToEdit) { procedure in
            ProcedureEditorSheet(procedure: procedure)
        }
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            LibrarySearchField(prompt: "Search procedures", text: $searchText)
            categoryMenu
            Spacer(minLength: 0)
            Button {
                isShowingAddSheet = true
            } label: {
                Label("Add Procedure", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var categoryMenu: some View {
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
                selectedCategory?.rawValue ?? "All Categories",
                systemImage: selectedCategory?.icon ?? "square.grid.2x2"
            )
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .fixedSize()
        .help("Show one category of procedures")
    }

    private var emptyState: some View {
        PDFLibraryEmptyState(
            systemImage: "doc.text",
            isLibraryEmpty: procedures.isEmpty,
            emptyTitle: "No procedures yet",
            filteredTitle: "No procedures match your filters",
            hint: "Write down your classroom routines, safety procedures and special schedules. "
                + "Use Add Procedure to start one.",
            clearFilters: {
                searchText = ""
                selectedCategory = nil
            },
            footer: { EmptyView() }
        )
    }
}

/// A procedure as a written page in the Procedures grid: its icon, title,
/// summary and the first lines of what it says.
struct ProcedurePageCard: View {
    @ObservedObject var procedure: CDProcedure
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image.safeSymbol(procedure.displayIcon)
                    .font(.system(size: 16))
                    .foregroundStyle(.accent)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium, style: .continuous)
                            .fill(Color.accentColor.opacity(UIConstants.OpacityConstants.medium))
                    )
                Text(procedure.category.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(procedure.title.isEmpty ? "Untitled Procedure" : procedure.title)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            if !procedure.summary.isEmpty {
                Text(procedure.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(preview)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .topLeading)

            Spacer(minLength: 0)

            Text("Updated \((procedure.modifiedAt ?? Date()).formatted(.relative(presentation: .named)))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
        .surface(
            UIConstants.CornerRadius.tile,
            fill: Color.secondary.opacity(0.08),
            stroke: isSelected ? Color.accentColor : Color.clear,
            lineWidth: 2,
            style: .continuous
        )
        .contentShape(Rectangle())
    }

    /// The page's opening words, without Markdown's heading and list marks.
    private var preview: String {
        let lines = procedure.content
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "#*-> ").union(.whitespaces)) }
            .filter { !$0.isEmpty }
        return lines.isEmpty ? "Nothing written yet." : lines.prefix(4).joined(separator: "\n")
    }
}
