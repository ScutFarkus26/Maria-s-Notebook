import SwiftUI
import SwiftData

struct TodoListPanel: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TodoItem.orderIndex) var todos: [TodoItem]
    @Query(sort: \Student.firstName) private var studentsRaw: [Student]
    @AppStorage(UserDefaultsKeys.generalShowTestStudents) private var showTestStudents: Bool = false
    @AppStorage(UserDefaultsKeys.generalTestStudentNames)
    private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"
    @Environment(\.modelContext) var modelContext

    private var students: [Student] {
        TestStudentsFilter.filterVisible(
            studentsRaw.uniqueByID.filter(\.isEnrolled),
            show: showTestStudents,
            namesRaw: testStudentNamesRaw
        )
    }

    @State var newTodoTitle = ""
    @State private var editingTodo: TodoItem?
    @State private var selectedFilter: TodoFilter = .all
    @State var isParsingWithAI = false
    @State private var showAnalytics = false
    @State private var showTemplates = false
    @State private var showExport = false
    @FocusState var isAddingFocused: Bool

    private var filteredTodos: [TodoItem] {
        todos.filter { todo in
            selectedFilter.matches(todo)
        }
    }

    private var emptyStateMessage: String {
        selectedFilter.emptyMessage
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 12) {
                    Text("To-Do")
                        .font(AppTheme.ScaledFont.titleXLarge)

                    Spacer()

                    HStack(spacing: 4) {
                        Button {
                            showTemplates = true
                        } label: {
                            Image(systemName: "doc.text")
                                .font(.system(size: 15))
                                .foregroundStyle(.tertiary)
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.plain)

                        Button {
                            showAnalytics = true
                        } label: {
                            Image(systemName: "chart.bar")
                                .font(.system(size: 15))
                                .foregroundStyle(.tertiary)
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.plain)

                        Button {
                            showExport = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 15))
                                .foregroundStyle(.tertiary)
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.quaternary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()

                // Filters
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(TodoFilter.allCases) { filter in
                            TodoFilterChip(
                                filter: filter,
                                isSelected: selectedFilter == filter,
                                count: todos.filter { filter.matches($0) }.count
                            ) {
                                adaptiveWithAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    selectedFilter = filter
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }

                Divider()

                if let editingTodo {
                    VStack(spacing: 0) {
                        HStack {
                            Text("Edit Todo")
                                .font(AppTheme.ScaledFont.body.weight(.semibold))
                            Spacer()
                            Button("Done") {
                                self.editingTodo = nil
                            }
                            .buttonStyle(.plain)
                        }
                        .padding()

                        Divider()

                        TodoEditSheet(todo: editingTodo, onDone: {
                            self.editingTodo = nil
                        })
                    }
                } else {
                    // Todo list
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            if filteredTodos.isEmpty {
                                VStack(spacing: 16) {
                                    Image(systemName: selectedFilter.icon)
                                        .font(.system(size: 56, weight: .ultraLight))
                                        .foregroundStyle(.quaternary)
                                    Text(emptyStateMessage)
                                        .font(AppTheme.ScaledFont.calloutSemibold)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(48)
                            } else {
                                ForEach(Array(filteredTodos.enumerated()), id: \.element.id) { index, todo in
                                    VStack(spacing: 0) {
                                        TodoRow(
                                            todo: todo,
                                            students: students,
                                            onToggle: { toggleTodo(todo) },
                                            onDelete: { deleteTodo(todo) },
                                            onEdit: { editingTodo = todo }
                                        )

                                        if index < filteredTodos.count - 1 {
                                            Divider()
                                                .padding(.leading, 48)
                                        }
                                    }
                                }
                                .onMove(perform: moveTodos)
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                }

                Divider()

                // Things-style quick-add bar
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.blue.opacity(UIConstants.OpacityConstants.prominent))

                    TextField("New To-Do", text: $newTodoTitle)
                        .textFieldStyle(.plain)
                        .font(AppTheme.ScaledFont.callout)
                        .focused($isAddingFocused)
                        .onSubmit {
                            addTodo()
                        }

                    if !newTodoTitle.trimmed().isEmpty {
                        Button {
                            Task { await addTodoWithAI() }
                        } label: {
                            if isParsingWithAI {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.purple.opacity(UIConstants.OpacityConstants.prominent))
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isParsingWithAI)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
            }
            .frame(width: 360)
        }
#if !os(macOS)
        .sheet(item: $editingTodo) { todo in
            TodoEditSheet(todo: todo)
        }
#endif
        .sheet(isPresented: $showAnalytics) {
            TodoAnalyticsView(todos: todos)
        }
        .sheet(isPresented: $showTemplates) {
            TodoTemplatesView()
        }
        .sheet(isPresented: $showExport) {
            TodoExportView(todos: filteredTodos)
        }
    }
}

// MARK: - Todo Filter Chip
private struct TodoFilterChip: View {
    let filter: TodoFilter
    let isSelected: Bool
    let count: Int
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: filter.icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isSelected ? .white : filter.color)
                Text(filter.rawValue)
                    .font(AppTheme.ScaledFont.caption)
                    .fontWeight(isSelected ? .semibold : .medium)
                if count > 0 && !isSelected {
                    Text("\(count)")
                        .font(AppTheme.ScaledFont.captionSmallSemibold)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                Capsule(style: .continuous)
                    .fill(isSelected ? filter.color : Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
            }
            .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}
