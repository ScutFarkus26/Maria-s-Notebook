import SwiftUI

/// App-wide search view with results grouped by entity type.
struct AppSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var results: [SearchResult] = []
    @State private var selectedTypes: Set<SearchableEntityType>? = nil

    private let searchIndex = SearchIndexService.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                Divider()
                if !searchIndex.isReady {
                    ContentUnavailableView("Building index…", systemImage: "magnifyingglass")
                } else if searchText.isEmpty {
                    ContentUnavailableView("Search everything", systemImage: "magnifyingglass",
                        description: Text("Notes, lessons, students, todos, and work items"))
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    resultsList
                }
            }
            .navigationTitle("Search")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 400)
        #else
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search…", text: $searchText)
                .textFieldStyle(.plain)
                .onChange(of: searchText) { _, query in
                    performSearch(query: query)
                }
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    results = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var resultsList: some View {
        let grouped = Dictionary(grouping: results) { $0.entityType }
        let orderedTypes: [SearchableEntityType] = [.student, .lesson, .note, .work, .todo]

        return List {
            ForEach(orderedTypes, id: \.self) { type in
                if let items = grouped[type], !items.isEmpty {
                    Section(type.sectionTitle) {
                        ForEach(items) { result in
                            HStack(spacing: 10) {
                                Image(systemName: type.iconName)
                                    .foregroundStyle(type.iconColor)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.title)
                                        .font(.body)
                                        .lineLimit(1)
                                    if !result.snippet.isEmpty {
                                        Text(result.snippet)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private func performSearch(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            results = []
            return
        }
        results = searchIndex.search(query: trimmed, entityTypes: selectedTypes, limit: 50)
    }
}

// MARK: - Entity Type Display

extension SearchableEntityType {
    var sectionTitle: String {
        switch self {
        case .student: return "Students"
        case .lesson: return "Lessons"
        case .note: return "Notes"
        case .todo: return "Todos"
        case .work: return "Work"
        }
    }

    var iconName: String {
        switch self {
        case .student: return "person.fill"
        case .lesson: return "book.fill"
        case .note: return "note.text"
        case .todo: return "checklist"
        case .work: return "hammer.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .student: return .blue
        case .lesson: return .purple
        case .note: return .orange
        case .todo: return .green
        case .work: return .indigo
        }
    }
}
