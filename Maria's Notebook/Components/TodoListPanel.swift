import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import QuickLook
#if os(macOS)
import QuickLookUI
#endif

enum TodoFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case active = "Active"
    case completed = "Completed"
    case today = "Today"
    case thisWeek = "This Week"
    case someday = "Someday"
    case overdue = "Overdue"
    case highPriority = "High Priority"
    case hasSubtasks = "With Checklist"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .all: return "list.bullet"
        case .active: return "circle"
        case .completed: return "checkmark.circle.fill"
        case .today: return "calendar.badge.clock"
        case .thisWeek: return "calendar"
        case .someday: return "moon.zzz"
        case .overdue: return "exclamationmark.triangle.fill"
        case .highPriority: return "flag.fill"
        case .hasSubtasks: return "checklist"
        }
    }
    
    var color: Color {
        switch self {
        case .all: return .primary
        case .active: return .blue
        case .completed: return .green
        case .today: return .orange
        case .thisWeek: return .purple
        case .someday: return .brown
        case .overdue: return .red
        case .highPriority: return .red
        case .hasSubtasks: return .indigo
        }
    }
    
    var emptyMessage: String {
        switch self {
        case .all: return "Add a task to get started"
        case .active: return "All done! No active tasks"
        case .completed: return "No completed tasks yet"
        case .today: return "No tasks due today"
        case .thisWeek: return "No tasks due this week"
        case .someday: return "No someday tasks"
        case .overdue: return "You're all caught up!"
        case .highPriority: return "No high priority tasks"
        case .hasSubtasks: return "No tasks with checklists"
        }
    }
    
    func matches(_ todo: TodoItem) -> Bool {
        switch self {
        case .all:
            return true
        case .active:
            return !todo.isCompleted && !todo.isSomeday
        case .completed:
            return todo.isCompleted
        case .today:
            return todo.isScheduledForToday && !todo.isCompleted
        case .thisWeek:
            return todo.isDueThisWeek && !todo.isCompleted
        case .someday:
            return todo.isSomeday && !todo.isCompleted
        case .overdue:
            return todo.isOverdue
        case .highPriority:
            return todo.priority == .high && !todo.isCompleted
        case .hasSubtasks:
            return !todo.subtasks.isEmpty
        }
    }
}

struct TodoListPanel: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TodoItem.orderIndex) private var todos: [TodoItem]
    @Query(sort: \Student.firstName) private var studentsRaw: [Student]
    @AppStorage(UserDefaultsKeys.generalShowTestStudents) private var showTestStudents: Bool = false
    @AppStorage(UserDefaultsKeys.generalTestStudentNames) private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"
    @Environment(\.modelContext) private var modelContext

    private var students: [Student] {
        TestStudentsFilter.filterVisible(studentsRaw.uniqueByID, show: showTestStudents, namesRaw: testStudentNamesRaw)
    }

    @State private var newTodoTitle = ""
    @State private var editingTodo: TodoItem?
    @State private var selectedFilter: TodoFilter = .all
    @State private var isParsingWithAI = false
    @State private var showAnalytics = false
    @State private var showTemplates = false
    @State private var showExport = false
    @FocusState private var isAddingFocused: Bool
    
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
                        .foregroundStyle(.blue.opacity(0.7))

                    TextField("New To-Do", text: $newTodoTitle)
                        .textFieldStyle(.plain)
                        .font(AppTheme.ScaledFont.callout)
                        .focused($isAddingFocused)
                        .onSubmit {
                            addTodo()
                        }

                    if !newTodoTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button {
                            Task { await addTodoWithAI() }
                        } label: {
                            if isParsingWithAI {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.purple.opacity(0.7))
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
    
    private func addTodo() {
        let trimmed = newTodoTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let parseResult = TodoDateParser.parse(trimmed)
        let newTodo = TodoItem(
            title: parseResult.cleanTitle,
            orderIndex: todos.count,
            scheduledDate: parseResult.suggestedDate
        )
        modelContext.insert(newTodo)
        do {
            try modelContext.save()
        } catch {
            print("⚠️ [\(#function)] Failed to save new todo: \(error)")
        }
        newTodoTitle = ""
        isAddingFocused = true
    }
    
    private func addTodoWithAI() async {
        #if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            let trimmed = newTodoTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            
            isParsingWithAI = true
            defer { isParsingWithAI = false }
            
            do {
                let parsed = try await TodoSmartParserService.parseTodo(from: trimmed)
                
                // Parse priority
                let priority: TodoPriority = {
                    switch parsed.priority.lowercased() {
                    case "high": return .high
                    case "medium": return .medium
                    case "low": return .low
                    default: return .none
                    }
                }()
                
                // Parse due date
                let dueDate: Date? = {
                    guard !parsed.dueDate.isEmpty else { return nil }
                    let formatter = ISO8601DateFormatter()
                    return formatter.date(from: parsed.dueDate)
                }()
                
                // Parse recurrence
                let recurrence: RecurrencePattern = {
                    switch parsed.recurrence.lowercased() {
                    case "daily": return .daily
                    case "weekdays": return .weekdays
                    case "weekly": return .weekly
                    case "biweekly": return .biweekly
                    case "monthly": return .monthly
                    case "yearly": return .yearly
                    default: return .none
                    }
                }()
                
                let newTodo = TodoItem(
                    title: parsed.title.isEmpty ? trimmed : parsed.title,
                    orderIndex: todos.count,
                    dueDate: dueDate,
                    priority: priority,
                    recurrence: recurrence
                )

                modelContext.insert(newTodo)
                do {
                    try modelContext.save()
                } catch {
                    print("⚠️ [\(#function)] Failed to save new todo: \(error)")
                }
                newTodoTitle = ""
                isAddingFocused = true
            } catch {
                // Fall back to simple add if AI parsing fails
                addTodo()
            }
        } else {
            addTodo()
        }
        #else
        addTodo()
        #endif
    }
    
    private func toggleTodo(_ todo: TodoItem) {
        todo.isCompleted.toggle()
        if todo.isCompleted {
            todo.completedAt = Date()
            
            // Handle recurring todos
            if todo.recurrence != .none {
                let baseDate: Date
                let today = AppCalendar.startOfDay(Date())
                
                if todo.repeatAfterCompletion {
                    // "After completion" mode: calculate from today
                    baseDate = today
                } else {
                    baseDate = todo.dueDate ?? today
                }
                
                let nextDueDate: Date?
                if todo.recurrence == .custom, let interval = todo.customIntervalDays {
                    nextDueDate = Calendar.current.date(byAdding: .day, value: interval, to: baseDate)
                } else {
                    nextDueDate = todo.recurrence.nextDate(after: baseDate)
                }
                
                if let nextDueDate {
                    // Preserve the scheduledDate offset if both were set
                    var nextScheduled: Date?
                    if let scheduled = todo.scheduledDate, let due = todo.dueDate {
                        let offset = Calendar.current.dateComponents([.day], from: due, to: scheduled).day ?? 0
                        nextScheduled = Calendar.current.date(byAdding: .day, value: offset, to: nextDueDate)
                    } else if todo.scheduledDate != nil {
                        nextScheduled = nextDueDate
                    }
                    
                    let newTodo = TodoItem(
                        title: todo.title,
                        notes: todo.notes,
                        orderIndex: todos.count,
                        studentIDs: todo.studentIDs,
                        dueDate: nextDueDate,
                        scheduledDate: nextScheduled,
                        priority: todo.priority,
                        recurrence: todo.recurrence
                    )
                    newTodo.repeatAfterCompletion = todo.repeatAfterCompletion
                    newTodo.customIntervalDays = todo.customIntervalDays
                    newTodo.tags = todo.tags
                    modelContext.insert(newTodo)
                }
            }
        } else {
            todo.completedAt = nil
        }
        do {
            try modelContext.save()
        } catch {
            print("⚠️ [\(#function)] Failed to save todo completion: \(error)")
        }
    }

    private func deleteTodo(_ todo: TodoItem) {
        modelContext.delete(todo)
        do {
            try modelContext.save()
        } catch {
            print("⚠️ [\(#function)] Failed to delete todo: \(error)")
        }
    }
    
    private func moveTodos(from source: IndexSet, to destination: Int) {
        var reorderedTodos = todos
        reorderedTodos.move(fromOffsets: source, toOffset: destination)
        
        // Update orderIndex for all todos
        for (index, todo) in reorderedTodos.enumerated() {
            todo.orderIndex = index
        }

        do {
            try modelContext.save()
        } catch {
            print("⚠️ [\(#function)] Failed to update todo order: \(error)")
        }
    }
}

struct TodoRow: View {
    let todo: TodoItem
    let students: [Student]
    let onToggle: () -> Void
    let onDelete: () -> Void
    let onEdit: () -> Void
    
    private var assignedStudents: [Student] {
        students.filter { todo.studentIDs.contains($0.id.uuidString) }
    }
    
    private func formatDueDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInTomorrow(date) {
            return "Tomorrow"
        } else if calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            return formatter.string(from: date)
        }
    }
    
    private func priorityColor(_ priority: TodoPriority) -> Color {
        switch priority {
        case .none: return .gray
        case .low: return .blue
        case .medium: return .orange
        case .high: return .red
        }
    }
    
    private func formatTimeEstimate(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        
        if hours > 0 && mins > 0 {
            return "\(hours)h \(mins)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(mins)m"
        }
    }
    
    private func formatReminderBadge(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: date)
        } else if calendar.isDateInTomorrow(date) {
            return "Tomorrow"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
    
    private func formatTodoAsText(_ todo: TodoItem) -> String {
        var text = "📋 \(todo.title)\n"
        
        // Priority
        if todo.priority != .none {
            let priorityEmoji = todo.priority == .high ? "🔴" : todo.priority == .medium ? "🟠" : "🔵"
            text += "\(priorityEmoji) Priority: \(todo.priority.rawValue)\n"
        }
        
        // Due date
        if let dueDate = todo.dueDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            text += "📅 Due: \(formatter.string(from: dueDate))\n"
        }
        
        // Assigned students
        if !assignedStudents.isEmpty {
            let names = assignedStudents.map { $0.firstName }.joined(separator: ", ")
            text += "👥 Assigned to: \(names)\n"
        }
        
        // Reminder
        if let reminderDate = todo.reminderDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            text += "🔔 Reminder: \(formatter.string(from: reminderDate))\n"
        }
        
        // Time estimate
        if let estimated = todo.estimatedMinutes, estimated > 0 {
            text += "⏱️ Estimated time: \(formatTimeEstimate(estimated))\n"
        }
        
        // Mood
        if let mood = todo.mood {
            text += "\(mood.emoji) Mood: \(mood.rawValue)\n"
        }
        
        // Reflection
        if !todo.reflectionNotes.isEmpty {
            text += "💭 Reflection: \(todo.reflectionNotes)\n"
        }
        
        // Subtasks
        if !todo.subtasks.isEmpty {
            text += "\n✅ Subtasks (\(todo.subtasks.filter { $0.isCompleted }.count)/\(todo.subtasks.count)):\n"
            for subtask in todo.subtasks.sorted(by: { $0.orderIndex < $1.orderIndex }) {
                let checkbox = subtask.isCompleted ? "☑️" : "☐"
                text += "  \(checkbox) \(subtask.title)\n"
            }
        }
        
        // Notes
        if !todo.notes.isEmpty {
            text += "\n📝 Notes:\n\(todo.notes)\n"
        }
        
        return text
    }
    
    @State private var checkboxScale: CGFloat = 1.0

    var body: some View {
        HStack(spacing: 0) {
            // Priority left-edge bar
            if todo.priority != .none {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(priorityColor(todo.priority))
                    .frame(width: 3)
                    .padding(.vertical, 6)
                    .padding(.trailing, 9)
            } else {
                Spacer().frame(width: 12)
            }

            // Checkbox
            Button {
                adaptiveWithAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                    checkboxScale = 0.8
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    adaptiveWithAnimation(.spring(response: 0.35, dampingFraction: 0.5)) {
                        checkboxScale = 1.0
                        onToggle()
                    }
                }
            } label: {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(todo.isCompleted ? .secondary : .tertiary)
                    .contentTransition(.symbolEffect(.replace))
                    .scaleEffect(checkboxScale)
            }
            .buttonStyle(.plain)
            #if os(iOS)
            .sensoryFeedback(.success, trigger: todo.isCompleted)
            #endif

            Spacer().frame(width: 12)

            // Content
            VStack(alignment: .leading, spacing: 3) {
                Text(todo.title)
                    .font(AppTheme.ScaledFont.titleSmall)
                    .foregroundStyle(todo.isCompleted ? .secondary : .primary)
                    .strikethrough(todo.isCompleted, color: .secondary.opacity(0.5))

                if !todo.notes.isEmpty {
                    Text(todo.notes)
                        .font(AppTheme.ScaledFont.body)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    if !assignedStudents.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "person.fill")
                                .font(.system(size: 10))
                            Text(assignedStudents.map { $0.firstName }.joined(separator: ", "))
                                .font(AppTheme.ScaledFont.captionSemibold)
                        }
                        .foregroundStyle(.blue.opacity(0.7))
                    }

                    if todo.effectiveDate != nil || todo.isSomeday {
                        TodoDateChip(todo: todo)
                    }

                    if todo.recurrence != .none {
                        HStack(spacing: 3) {
                            Image(systemName: "repeat")
                                .font(.system(size: 10))
                            Text(todo.recurrence.shortLabel)
                                .font(AppTheme.ScaledFont.captionSemibold)
                        }
                        .foregroundStyle(.purple.opacity(0.7))
                    }

                    if let progressText = todo.subtasksProgressText {
                        HStack(spacing: 3) {
                            Image(systemName: "checklist")
                                .font(.system(size: 10))
                            Text(progressText)
                                .font(AppTheme.ScaledFont.captionSemibold)
                        }
                        .foregroundStyle(todo.allSubtasksCompleted ? .green.opacity(0.7) : .secondary.opacity(0.5))
                    }
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 8)
        }
        .padding(.trailing, 12)
        .padding(.vertical, 10)
        .opacity(todo.isCompleted ? 0.5 : 1.0)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }

            Button {
                onEdit()
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                onToggle()
            } label: {
                Label(todo.isCompleted ? "Incomplete" : "Complete",
                      systemImage: todo.isCompleted ? "arrow.uturn.backward" : "checkmark")
            }
            .tint(todo.isCompleted ? .orange : .green)

            Button {
                todo.scheduledDate = AppCalendar.startOfDay(Date())
                todo.isSomeday = false
            } label: {
                Label("Today", systemImage: "star.fill")
            }
            .tint(.orange)

            Button {
                todo.scheduledDate = AppCalendar.startOfDay(Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date())
                todo.isSomeday = false
            } label: {
                Label("Tomorrow", systemImage: "sunrise")
            }
            .tint(.orange.opacity(0.8))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onEdit()
        }
        .contextMenu {
            Button { onEdit() } label: {
                Label("Edit", systemImage: "pencil")
            }
            Divider()
            Menu("Move to...") {
                Button {
                    todo.scheduledDate = AppCalendar.startOfDay(Date())
                    todo.isSomeday = false
                } label: {
                    Label("Today", systemImage: "star.fill")
                }
                Button {
                    let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                    todo.scheduledDate = AppCalendar.startOfDay(tomorrow)
                    todo.isSomeday = false
                } label: {
                    Label("Tomorrow", systemImage: "sunrise")
                }
                Button {
                    let cal = Calendar.current
                    let weekday = cal.component(.weekday, from: Date())
                    let daysUntilMonday = weekday == 1 ? 1 : (9 - weekday)
                    let nextMon = cal.date(byAdding: .day, value: daysUntilMonday, to: Date()) ?? Date()
                    todo.scheduledDate = AppCalendar.startOfDay(nextMon)
                    todo.isSomeday = false
                } label: {
                    Label("Next Week", systemImage: "calendar.badge.plus")
                }
                Divider()
                Button {
                    todo.isSomeday = true
                    todo.scheduledDate = nil
                } label: {
                    Label("Someday", systemImage: "moon.zzz")
                }
                Button {
                    todo.scheduledDate = nil
                    todo.dueDate = nil
                    todo.isSomeday = false
                } label: {
                    Label("Remove Date", systemImage: "calendar.badge.minus")
                }
            }
            Divider()
            Button(role: .destructive) { onDelete() } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

struct TodoEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Student.firstName) private var studentsRaw: [Student]
    @AppStorage(UserDefaultsKeys.generalShowTestStudents) private var showTestStudents: Bool = false
    @AppStorage(UserDefaultsKeys.generalTestStudentNames) private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    private var students: [Student] {
        TestStudentsFilter.filterVisible(studentsRaw.uniqueByID, show: showTestStudents, namesRaw: testStudentNamesRaw)
    }

    let todo: TodoItem
    let onDone: (() -> Void)?
    
    @State private var title: String
    @State private var notes: String
    @State private var selectedStudentIDs: Set<String>
    @State private var isSuggestingStudents = false
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var scheduledDate: Date?
    @State private var deadlineDate: Date?
    @State private var isSomeday: Bool
    @State private var repeatAfterCompletion: Bool
    @State private var customIntervalDays: Int
    @State private var priority: TodoPriority
    @State private var recurrence: RecurrencePattern
    @State private var estimatedHours: Int
    @State private var estimatedMinutes: Int
    @State private var actualHours: Int
    @State private var actualMinutes: Int
    @State private var hasReminder: Bool
    @State private var reminderDate: Date
    @State private var isSchedulingNotification = false
    @State private var showingSaveAsTemplate = false
    @State private var templateName = ""
    @State private var selectedMood: TodoMood?
    @State private var reflectionNotes: String
    @State private var hasLocationReminder: Bool
    @State private var locationName: String
    @State private var locationLatitude: Double?
    @State private var locationLongitude: Double?
    @State private var notifyOnEntry: Bool
    @State private var notifyOnExit: Bool
    @State private var isShowingFileImporter = false
    @State private var previewingAttachmentURL: URL?
    @State private var isShowingMapPicker = false
    @FocusState private var isTitleFocused: Bool
    
    init(todo: TodoItem, onDone: (() -> Void)? = nil) {
        self.todo = todo
        self.onDone = onDone
        _title = State(initialValue: todo.title)
        _notes = State(initialValue: todo.notes)
        _selectedStudentIDs = State(initialValue: Set(todo.studentIDs))
        _hasDueDate = State(initialValue: todo.dueDate != nil)
        _dueDate = State(initialValue: todo.dueDate ?? AppCalendar.startOfDay(Date()))
        _scheduledDate = State(initialValue: todo.scheduledDate)
        _deadlineDate = State(initialValue: todo.dueDate)
        _isSomeday = State(initialValue: todo.isSomeday)
        _repeatAfterCompletion = State(initialValue: todo.repeatAfterCompletion)
        _customIntervalDays = State(initialValue: todo.customIntervalDays ?? 7)
        _priority = State(initialValue: todo.priority)
        _recurrence = State(initialValue: todo.recurrence)
        
        // Parse time estimates
        let estTotal = todo.estimatedMinutes ?? 0
        _estimatedHours = State(initialValue: estTotal / 60)
        _estimatedMinutes = State(initialValue: estTotal % 60)
        
        let actTotal = todo.actualMinutes ?? 0
        _actualHours = State(initialValue: actTotal / 60)
        _actualMinutes = State(initialValue: actTotal % 60)
        
        // Parse reminder
        _hasReminder = State(initialValue: todo.reminderDate != nil)
        _reminderDate = State(initialValue: todo.reminderDate ?? Date().addingTimeInterval(3600)) // Default to 1 hour from now
        
        // Parse mood and reflection
        _selectedMood = State(initialValue: todo.mood)
        _reflectionNotes = State(initialValue: todo.reflectionNotes)
        
        // Parse location reminder
        _hasLocationReminder = State(initialValue: todo.hasLocationReminder)
        _locationName = State(initialValue: todo.locationName ?? "")
        _locationLatitude = State(initialValue: todo.locationLatitude)
        _locationLongitude = State(initialValue: todo.locationLongitude)
        _notifyOnEntry = State(initialValue: todo.notifyOnEntry)
        _notifyOnExit = State(initialValue: todo.notifyOnExit)
    }
    
    private var selectedStudents: [Student] {
        students.filter { selectedStudentIDs.contains($0.id.uuidString) }
    }
    
    var body: some View {
        Group {
            #if os(macOS)
            macOSLayout
            #else
            iOSLayout
            #endif
        }
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
        .sheet(item: $previewingAttachmentURL) { url in
            AttachmentPreviewSheet(url: url)
        }
    }
    
    // MARK: - macOS Layout
    #if os(macOS)
    private var macOSLayout: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Edit Task")
                    .font(AppTheme.ScaledFont.header)
                    .foregroundStyle(.primary)
                Spacer()
                HStack(spacing: 12) {
                    Menu {
                        ShareLink(item: formatTodoForSharing()) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        
                        Button {
                            showingSaveAsTemplate = true
                        } label: {
                            Label("Save as Template", systemImage: "doc.badge.plus")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    
                    Button("Cancel") { closeEditor() }
                        .keyboardShortcut(.cancelAction)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    Button("Save") { save() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(!canSave)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Title Section
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Title")
                            .font(AppTheme.ScaledFont.captionSemibold)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                        
                        TextField("Task title", text: $title)
                            .textFieldStyle(.roundedBorder)
                            .focused($isTitleFocused)
                            .font(AppTheme.ScaledFont.callout)
                    }
                    
                    Divider()
                    
                    // Students Section
                    studentSection
                    
                    Divider()
                    
                    // Due Date Section
                    dueDateSection
                    
                    Divider()
                    
                    // Priority Section
                    prioritySection
                    
                    Divider()
                    
                    // Recurrence Section
                    recurrenceSection
                    
                    Divider()
                    
                    // Subtasks Section
                    subtasksSection
                    
                    Divider()
                    
                    // Work Integration Section
                    workIntegrationSection
                    
                    Divider()
                    
                    // Attachments Section
                    attachmentsSection
                    
                    Divider()
                    
                    // Time Estimate Section
                    timeEstimateSection
                    
                    Divider()
                    
                    // Reminder Section
                    reminderSection
                    
                    Divider()
                    
                    // Mood & Reflection Section
                    moodReflectionSection
                    
                    Divider()
                    
                    // Location Reminder Section
                    locationReminderSection
                    
                    Divider()
                    
                    // Notes Section
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Notes")
                            .font(AppTheme.ScaledFont.captionSemibold)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                        
                        TextEditor(text: $notes)
                            .font(AppTheme.ScaledFont.body)
                            .frame(minHeight: 120)
                            .padding(8)
                            .background(Color.primary.opacity(0.04))
                            .cornerRadius(8)
                            .scrollContentBackground(.hidden)
                    }
                }
                .padding(28)
            }
            .background(Color(NSColor.textBackgroundColor))
        }
        .frame(minWidth: 500, minHeight: 550)
        .task {
            do {
                try await Task.sleep(for: .milliseconds(200))
            } catch {
                print("⚠️ [\(#function)] Failed to sleep: \(error)")
            }
            isTitleFocused = true
        }
        .alert("Save as Template", isPresented: $showingSaveAsTemplate) {
            TextField("Template name", text: $templateName)
            Button("Cancel", role: .cancel) {
                templateName = ""
            }
            Button("Save") {
                saveAsTemplate()
            }
        } message: {
            Text("Enter a name for this template")
        }
    }
    #endif
    
    // MARK: - iOS Layout
    #if !os(macOS)
    private var iOSLayout: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Title Section
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Title")
                            .font(AppTheme.ScaledFont.captionSemibold)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                        
                        TextField("Task title", text: $title)
                            .textFieldStyle(.roundedBorder)
                            .focused($isTitleFocused)
                            .font(AppTheme.ScaledFont.callout)
                    }
                    
                    Divider()
                    
                    // Students Section
                    studentSection
                    
                    Divider()
                    
                    // Due Date Section
                    dueDateSection
                    
                    Divider()
                    
                    // Priority Section
                    prioritySection
                    
                    Divider()
                    
                    // Recurrence Section
                    recurrenceSection
                    
                    Divider()
                    
                    // Subtasks Section
                    subtasksSection
                    
                    Divider()
                    
                    // Work Integration Section
                    workIntegrationSection
                    
                    Divider()
                    
                    // Attachments Section
                    attachmentsSection
                    
                    Divider()
                    
                    // Time Estimate Section
                    timeEstimateSection
                    
                    Divider()
                    
                    // Reminder Section
                    reminderSection
                    
                    Divider()
                    
                    // Mood & Reflection Section
                    moodReflectionSection
                    
                    Divider()
                    
                    // Location Reminder Section
                    locationReminderSection
                    
                    Divider()
                    
                    // Notes Section
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Notes")
                            .font(AppTheme.ScaledFont.captionSemibold)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                        
                        TextEditor(text: $notes)
                            .font(AppTheme.ScaledFont.body)
                            .frame(minHeight: 120)
                            .padding(8)
                            .background(Color.primary.opacity(0.04))
                            .cornerRadius(8)
                            .scrollContentBackground(.hidden)
                    }
                }
                .padding(20)
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { closeEditor() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        ShareLink(item: formatTodoForSharing()) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        
                        Button {
                            showingSaveAsTemplate = true
                        } label: {
                            Label("Save as Template", systemImage: "doc.badge.plus")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .task {
                do {
                    try await Task.sleep(for: .milliseconds(300))
                } catch {
                    print("⚠️ [\(#function)] Failed to sleep: \(error)")
                }
                isTitleFocused = true
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .alert("Save as Template", isPresented: $showingSaveAsTemplate) {
            TextField("Template name", text: $templateName)
            Button("Cancel", role: .cancel) {
                templateName = ""
            }
            Button("Save") {
                saveAsTemplate()
            }
        } message: {
            Text("Enter a name for this template")
        }
    }
    #endif
    
    // MARK: - Student Section
    @ViewBuilder
    private var studentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            studentSectionHeader
            
            if students.isEmpty {
                emptyStudentsView
            } else {
                selectedStudentsChips
                availableStudentsList
            }
        }
    }
    
    @ViewBuilder
    private var studentSectionHeader: some View {
        HStack {
            Text("Assigned To")
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            
            Spacer()
            
            suggestButton
        }
    }
    
    @ViewBuilder
    private var suggestButton: some View {
        Button {
            Task { await suggestStudents() }
        } label: {
            HStack(spacing: 4) {
                if isSuggestingStudents {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12))
                    Text("Suggest")
                        .font(AppTheme.ScaledFont.captionSemibold)
                }
            }
            .foregroundStyle(.purple)
        }
        .buttonStyle(.plain)
        .disabled(isSuggestingStudents || students.isEmpty || title.isEmpty)
    }
    
    @ViewBuilder
    private var emptyStudentsView: some View {
        Text("No students available")
            .foregroundStyle(.secondary)
            .font(.subheadline)
            .padding(.vertical, 8)
    }
    
    @ViewBuilder
    private var selectedStudentsChips: some View {
        if !selectedStudents.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(selectedStudents) { student in
                        TodoStudentChip(student: student) {
                            _ = adaptiveWithAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                selectedStudentIDs.remove(student.id.uuidString)
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
    
    @ViewBuilder
    private var availableStudentsList: some View {
        let available = students.filter { !selectedStudentIDs.contains($0.id.uuidString) }
        if !available.isEmpty {
            VStack(spacing: 6) {
                ForEach(available) { student in
                    Button {
                        adaptiveWithAnimation(Animation.spring(response: 0.25, dampingFraction: 0.85)) {
                            _ = selectedStudentIDs.insert(student.id.uuidString)
                        }
                    } label: {
                        HStack {
                            Text(student.fullName)
                                .font(AppTheme.ScaledFont.body)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "plus.circle")
                                .foregroundStyle(.blue)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    // MARK: - Due Date Section
    @ViewBuilder
    private var dueDateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Schedule")
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            HStack {
                Text("When")
                    .font(AppTheme.ScaledFont.body)
                Spacer()
                TodoSchedulePickerButton(
                    scheduledDate: $scheduledDate,
                    dueDate: $deadlineDate,
                    isSomeday: $isSomeday
                )
            }

            Picker("Repeats", selection: $recurrence) {
                ForEach(RecurrencePattern.allCases, id: \.self) { pattern in
                    Text(pattern.rawValue).tag(pattern)
                }
            }
            .pickerStyle(.menu)

            if recurrence != .none {
                Toggle("Repeat after completion", isOn: $repeatAfterCompletion)
                    .font(AppTheme.ScaledFont.body)
                if recurrence == .custom {
                    Stepper("Every \(customIntervalDays) days", value: $customIntervalDays, in: 1...365)
                        .font(AppTheme.ScaledFont.body)
                }
            }
        }
    }
    
    // MARK: - Priority Section
    @ViewBuilder
    private var prioritySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Priority")
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            
            HStack(spacing: 8) {
                ForEach(TodoPriority.allCases, id: \.self) { priorityLevel in
                    Button {
                        adaptiveWithAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            priority = priorityLevel
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: priorityLevel.icon)
                                .font(.system(size: 12))
                            Text(priorityLevel.rawValue)
                                .font(AppTheme.ScaledFont.body)
                                .fontWeight(priority == priorityLevel ? .semibold : .regular)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(priority == priorityLevel ? colorForPriority(priorityLevel).opacity(0.15) : Color.secondary.opacity(0.1))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(priority == priorityLevel ? colorForPriority(priorityLevel).opacity(0.4) : Color.clear, lineWidth: 1.5)
                        }
                        .foregroundStyle(priority == priorityLevel ? colorForPriority(priorityLevel) : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    private func colorForPriority(_ priority: TodoPriority) -> Color {
        switch priority {
        case .none: return .gray
        case .low: return .blue
        case .medium: return .orange
        case .high: return .red
        }
    }
    
    // MARK: - Recurrence Section
    @ViewBuilder
    private var recurrenceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Repeat")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                
                Spacer()
                
                if recurrence != .none {
                    Image(systemName: recurrence.icon)
                        .font(.system(size: 12))
                        .foregroundStyle(.purple)
                }
            }
            
            Menu {
                ForEach(RecurrencePattern.allCases, id: \.self) { pattern in
                    Button {
                        adaptiveWithAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            recurrence = pattern
                        }
                    } label: {
                        HStack {
                            Text(pattern.description)
                            if recurrence == pattern {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Text(recurrence.description)
                        .font(AppTheme.ScaledFont.body)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(!hasDueDate)
            .opacity(hasDueDate ? 1.0 : 0.5)
            
            if !hasDueDate {
                Text("Set a due date to enable recurrence")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    // MARK: - Subtasks Section
    @ViewBuilder
    private var subtasksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Checklist")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                
                Spacer()
                
                if !todo.subtasks.isEmpty {
                    Text(todo.subtasksProgressText ?? "")
                        .font(AppTheme.ScaledFont.captionSemibold)
                        .foregroundStyle(.secondary)
                }
                
                Button {
                    addSubtask()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
            
            if todo.subtasks.isEmpty {
                Text("No checklist items")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                    .padding(.vertical, 8)
            } else {
                let sortedSubtasks = todo.subtasks.sorted(by: { $0.orderIndex < $1.orderIndex })
                VStack(spacing: 6) {
                    ForEach(sortedSubtasks) { subtask in
                        SubtaskRow(
                            subtask: subtask,
                            onToggle: { toggleSubtask(subtask) },
                            onDelete: { deleteSubtask(subtask) },
                            onUpdate: { newTitle in updateSubtask(subtask, title: newTitle) }
                        )
                    }
                    .onMove { source, destination in
                        reorderSubtasks(from: source, to: destination)
                    }
                }
            }
        }
    }
    
    // MARK: - Work Integration Section
    @ViewBuilder
    private var workIntegrationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Work Integration")
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            
            if todo.linkedWorkItemID != nil {
                HStack(spacing: 10) {
                    Image(systemName: "link.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.indigo)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Linked to Work Item")
                            .font(AppTheme.ScaledFont.bodySemibold)
                        Text("This todo is connected to a work item")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button {
                        todo.linkedWorkItemID = nil
                        if let context = todo.modelContext {
                            do {
                                try context.save()
                            } catch {
                                print("⚠️ [\(#function)] Failed to save todo: \(error)")
                            }
                        }
                    } label: {
                        Text("Unlink")
                            .font(AppTheme.ScaledFont.captionSemibold)
                            .foregroundStyle(AppColors.destructive)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(Color.indigo.opacity(0.1))
                .cornerRadius(8)
            } else {
                Button {
                    createWorkItemFromTodo()
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16))
                        Text("Create Work Item")
                            .font(AppTheme.ScaledFont.bodySemibold)
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(.indigo)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                Text("Convert this todo into a work item for tracking")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    // MARK: - Attachments Section
    @ViewBuilder
    private var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Attachments")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                
                Spacer()
                
                Button {
                    isShowingFileImporter = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.brown)
                }
                .buttonStyle(.plain)
            }
            
            if todo.attachmentPaths.isEmpty {
                Text("No attachments")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(todo.attachmentPaths.enumerated()), id: \.offset) { index, path in
                        HStack(spacing: 10) {
                            Image(systemName: fileIcon(for: path))
                                .font(.system(size: 20))
                                .foregroundStyle(.brown)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(fileName(from: path))
                                    .font(AppTheme.ScaledFont.body)
                                    .lineLimit(1)
                                Text(fileSize(for: path))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Button {
                                removeAttachment(at: index)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.red.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(10)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(8)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            let url = URL(fileURLWithPath: path)
                            if FileManager.default.fileExists(atPath: path) {
                                previewingAttachmentURL = url
                            }
                        }
                    }
                }
            }
            
            Text("Tap + to attach files or images")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Time Estimate Section
    @ViewBuilder
    private var timeEstimateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Time Tracking")
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            
            VStack(spacing: 16) {
                // Estimated Time
                VStack(alignment: .leading, spacing: 8) {
                    Text("Estimated Time")
                        .font(AppTheme.ScaledFont.bodySemibold)
                        .foregroundStyle(.primary)
                    
                    HStack(spacing: 12) {
                        // Hours picker
                        HStack(spacing: 8) {
                            #if os(macOS)
                            Picker("", selection: $estimatedHours) {
                                ForEach(0..<24) { hour in
                                    Text("\(hour)").tag(hour)
                                }
                            }
                            .frame(width: 60)
                            #else
                            Picker("Hours", selection: $estimatedHours) {
                                ForEach(0..<24) { hour in
                                    Text("\(hour) hr").tag(hour)
                                }
                            }
                            .pickerStyle(.menu)
                            #endif
                            
                            Text("hours")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        
                        // Minutes picker
                        HStack(spacing: 8) {
                            #if os(macOS)
                            Picker("", selection: $estimatedMinutes) {
                                ForEach([0, 15, 30, 45], id: \.self) { minute in
                                    Text("\(minute)").tag(minute)
                                }
                            }
                            .frame(width: 60)
                            #else
                            Picker("Minutes", selection: $estimatedMinutes) {
                                ForEach([0, 15, 30, 45], id: \.self) { minute in
                                    Text("\(minute) min").tag(minute)
                                }
                            }
                            .pickerStyle(.menu)
                            #endif
                            
                            Text("min")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        // Clear button
                        if estimatedHours > 0 || estimatedMinutes > 0 {
                            Button {
                                estimatedHours = 0
                                estimatedMinutes = 0
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(12)
                .background(Color.blue.opacity(0.08))
                .cornerRadius(10)
                
                // Actual Time
                VStack(alignment: .leading, spacing: 8) {
                    Text("Actual Time")
                        .font(AppTheme.ScaledFont.bodySemibold)
                        .foregroundStyle(.primary)
                    
                    HStack(spacing: 12) {
                        // Hours picker
                        HStack(spacing: 8) {
                            #if os(macOS)
                            Picker("", selection: $actualHours) {
                                ForEach(0..<24) { hour in
                                    Text("\(hour)").tag(hour)
                                }
                            }
                            .frame(width: 60)
                            #else
                            Picker("Hours", selection: $actualHours) {
                                ForEach(0..<24) { hour in
                                    Text("\(hour) hr").tag(hour)
                                }
                            }
                            .pickerStyle(.menu)
                            #endif
                            
                            Text("hours")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        
                        // Minutes picker
                        HStack(spacing: 8) {
                            #if os(macOS)
                            Picker("", selection: $actualMinutes) {
                                ForEach([0, 15, 30, 45], id: \.self) { minute in
                                    Text("\(minute)").tag(minute)
                                }
                            }
                            .frame(width: 60)
                            #else
                            Picker("Minutes", selection: $actualMinutes) {
                                ForEach([0, 15, 30, 45], id: \.self) { minute in
                                    Text("\(minute) min").tag(minute)
                                }
                            }
                            .pickerStyle(.menu)
                            #endif
                            
                            Text("min")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        // Clear button
                        if actualHours > 0 || actualMinutes > 0 {
                            Button {
                                actualHours = 0
                                actualMinutes = 0
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(12)
                .background(Color.green.opacity(0.08))
                .cornerRadius(10)
                
                // Time variance display
                if estimatedHours > 0 || estimatedMinutes > 0 || actualHours > 0 || actualMinutes > 0 {
                    let estimatedTotal = estimatedHours * 60 + estimatedMinutes
                    let actualTotal = actualHours * 60 + actualMinutes
                    let variance = actualTotal - estimatedTotal
                    
                    HStack(spacing: 8) {
                        Image(systemName: variance > 0 ? "exclamationmark.triangle.fill" : variance < 0 ? "checkmark.circle.fill" : "equal.circle.fill")
                            .foregroundStyle(variance > 0 ? .orange : variance < 0 ? .green : .blue)
                        
                        if variance == 0 && actualTotal > 0 {
                            Text("On track")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if variance > 0 {
                            Text("Over by \(formatMinutes(variance))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if variance < 0 {
                            Text("Under by \(formatMinutes(abs(variance)))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
    }
    
    private func formatMinutes(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        
        if hours > 0 && mins > 0 {
            return "\(hours)h \(mins)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(mins)m"
        }
    }
    
    // MARK: - Reminder Section
    @ViewBuilder
    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Reminder")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                
                Spacer()
                
                Toggle("", isOn: $hasReminder)
                    .labelsHidden()
            }
            
            if hasReminder {
                VStack(spacing: 12) {
                    DatePicker(
                        "Remind me at",
                        selection: $reminderDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.compact)
                    
                    if isSchedulingNotification {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Scheduling notification...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    // Show reminder info
                    HStack(spacing: 8) {
                        Image(systemName: "bell.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption)
                        Text(formatReminderDate(reminderDate))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(10)
                    .background(Color.yellow.opacity(0.1))
                    .cornerRadius(8)
                }
            } else {
                Text("No reminder set")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
        }
    }
    
    private func formatReminderDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "'Today at' h:mm a"
        } else if calendar.isDateInTomorrow(date) {
            formatter.dateFormat = "'Tomorrow at' h:mm a"
        } else if calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) {
            formatter.dateFormat = "EEEE 'at' h:mm a"
        } else {
            formatter.dateFormat = "MMM d 'at' h:mm a"
        }
        
        return formatter.string(from: date)
    }
    
    // MARK: - Mood & Reflection Section
    @ViewBuilder
    private var moodReflectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mood & Reflection")
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            
            // Mood selection
            VStack(alignment: .leading, spacing: 8) {
                Text("How are you feeling about this task?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 8) {
                    ForEach(TodoMood.allCases, id: \.self) { mood in
                        Button {
                            if selectedMood == mood {
                                selectedMood = nil // Deselect if already selected
                            } else {
                                selectedMood = mood
                            }
                        } label: {
                            VStack(spacing: 4) {
                                Text(mood.emoji)
                                    .font(.title2)
                                Text(mood.rawValue)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                selectedMood == mood
                                    ? mood.color.opacity(0.2)
                                    : Color.primary.opacity(0.04)
                            )
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(
                                        selectedMood == mood ? mood.color : Color.clear,
                                        lineWidth: 2
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            // Reflection notes
            VStack(alignment: .leading, spacing: 8) {
                Text("Reflection Notes")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                TextEditor(text: $reflectionNotes)
                    .font(AppTheme.ScaledFont.body)
                    .frame(minHeight: 80)
                    .padding(8)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(8)
                    .scrollContentBackground(.hidden)
                
                Text("Personal thoughts, lessons learned, or context")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    // MARK: - Location Reminder Section
    @ViewBuilder
    private var locationReminderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Location Reminder")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                
                Spacer()
                
                Toggle("", isOn: $hasLocationReminder)
                    .labelsHidden()
            }
            
            if hasLocationReminder {
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        TextField("Location name (e.g., School, Home)", text: $locationName)
                            .textFieldStyle(.roundedBorder)
                        
                        Button {
                            isShowingMapPicker = true
                        } label: {
                            Image(systemName: "map")
                                .font(.system(size: 16))
                                .padding(8)
                                .background(Color.blue.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                    
                    if let lat = locationLatitude, let lon = locationLongitude {
                        HStack(spacing: 6) {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundStyle(.red)
                            Text(String(format: "%.4f, %.4f", lat, lon))
                                .font(AppTheme.ScaledFont.caption)
                                .foregroundStyle(.secondary)
                            
                            Spacer()
                            
                            Button {
                                locationLatitude = nil
                                locationLongitude = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    HStack {
                        Toggle("Notify on arrival", isOn: $notifyOnEntry)
                        Spacer()
                    }
                    
                    HStack {
                        Toggle("Notify on departure", isOn: $notifyOnExit)
                        Spacer()
                    }
                }
                .padding(12)
                .background(Color.blue.opacity(0.08))
                .cornerRadius(10)
            } else {
                Text("Set a location-based reminder for this task")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
        }
        .sheet(isPresented: $isShowingMapPicker) {
            TodoLocationPickerView(
                locationName: $locationName,
                latitude: $locationLatitude,
                longitude: $locationLongitude
            )
        }
    }
    
    private func fileIcon(for path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "heic", "gif":
            return "photo"
        case "pdf":
            return "doc.fill"
        case "doc", "docx":
            return "doc.text.fill"
        case "txt":
            return "doc.plaintext"
        default:
            return "doc.fill"
        }
    }
    
    private func fileName(from path: String) -> String {
        (path as NSString).lastPathComponent
    }


    private func fileSize(for path: String) -> String {
        let attrs: [FileAttributeKey: Any]
        do {
            attrs = try FileManager.default.attributesOfItem(atPath: path)
        } catch {
            print("⚠️ [\(#function)] Failed to get file attributes: \(error)")
            return "Unknown size"
        }
        guard let size = attrs[.size] as? Int64 else {
            return "Unknown size"
        }
        
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
    
    private func removeAttachment(at index: Int) {
        guard index < todo.attachmentPaths.count else { return }
        todo.attachmentPaths.remove(at: index)
        if let context = todo.modelContext {
            do {
                try context.save()
            } catch {
                print("⚠️ [\(#function)] Failed to save todo: \(error)")
            }
        }
    }
    
    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
            let attachmentsDir = documentsDir.appendingPathComponent("TodoAttachments", isDirectory: true)
            
            try? FileManager.default.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)
            
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }
                
                let destURL = attachmentsDir.appendingPathComponent(url.lastPathComponent)
                do {
                    if FileManager.default.fileExists(atPath: destURL.path) {
                        try FileManager.default.removeItem(at: destURL)
                    }
                    try FileManager.default.copyItem(at: url, to: destURL)
                    todo.attachmentPaths.append(destURL.path)
                } catch {
                    print("⚠️ [\(#function)] Failed to copy attachment: \(error)")
                }
            }
            
            if let context = todo.modelContext {
                do {
                    try context.save()
                } catch {
                    print("⚠️ [\(#function)] Failed to save attachments: \(error)")
                }
            }
        case .failure(let error):
            print("⚠️ [\(#function)] File import failed: \(error)")
        }
    }
    
    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private func createWorkItemFromTodo() {
        guard let context = todo.modelContext else { return }
        
        // Create a new work model from this todo
        let work = WorkModel()
        work.title = todo.title
        work.setLegacyNoteText(todo.notes, in: context)
        work.dueAt = todo.dueDate
        
        // Assign to first student if available
        if let firstStudentID = todo.studentIDs.first {
            work.studentID = firstStudentID
        }
        
        context.insert(work)
        
        // Link the work to this todo
        todo.linkedWorkItemID = work.id.uuidString

        do {
            try context.save()
        } catch {
            print("⚠️ [\(#function)] Failed to link work item: \(error)")
        }
    }

    private func addSubtask() {
        let newSubtask = TodoSubtask(
            title: "",
            orderIndex: todo.subtasks.count
        )
        todo.subtasks.append(newSubtask)
        if let context = todo.modelContext {
            do {
                try context.save()
            } catch {
                print("⚠️ [\(#function)] Failed to save subtask: \(error)")
            }
        }
    }
    
    private func toggleSubtask(_ subtask: TodoSubtask) {
        subtask.isCompleted.toggle()
        if subtask.isCompleted {
            subtask.completedAt = Date()
        } else {
            subtask.completedAt = nil
        }
        if let context = todo.modelContext {
            do {
                try context.save()
            } catch {
                print("⚠️ [\(#function)] Failed to toggle subtask: \(error)")
            }
        }
    }
    
    private func deleteSubtask(_ subtask: TodoSubtask) {
        if let context = todo.modelContext {
            context.delete(subtask)
            do {
                try context.save()
            } catch {
                print("⚠️ [\(#function)] Failed to delete subtask: \(error)")
            }
        }
    }
    
    private func updateSubtask(_ subtask: TodoSubtask, title: String) {
        subtask.title = title
        if let context = todo.modelContext {
            do {
                try context.save()
            } catch {
                print("⚠️ [\(#function)] Failed to update subtask: \(error)")
            }
        }
    }

    private func reorderSubtasks(from source: IndexSet, to destination: Int) {
        var sorted = todo.subtasks.sorted(by: { $0.orderIndex < $1.orderIndex })
        sorted.move(fromOffsets: source, toOffset: destination)
        for (index, subtask) in sorted.enumerated() {
            subtask.orderIndex = index
        }
        if let context = todo.modelContext {
            do {
                try context.save()
            } catch {
                print("⚠️ [\(#function)] Failed to reorder subtasks: \(error)")
            }
        }
    }
    
    private func suggestStudents() async {
        #if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            isSuggestingStudents = true
            defer { isSuggestingStudents = false }
            
            let combinedText = "\(title) \(notes)"
            
            do {
                let extractedNames = try await TodoStudentSuggestionService.extractStudentNames(
                    from: combinedText,
                    availableStudents: students
                )
                
                let matchedStudents = TodoStudentSuggestionService.matchStudents(
                    extractedNames: extractedNames,
                    from: students
                )
                
                // Add matched students to selection
                for student in matchedStudents {
                    _ = adaptiveWithAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        selectedStudentIDs.insert(student.id.uuidString)
                    }
                }
            } catch {
                // Silently fail - Apple Intelligence might not be available
            }
        }
        #endif
    }
    
    private func formatTodoForSharing() -> String {
        var text = "📋 \(title.trimmingCharacters(in: .whitespacesAndNewlines))\n"
        
        // Priority
        if priority != .none {
            let priorityEmoji = priority == .high ? "🔴" : priority == .medium ? "🟠" : "🔵"
            text += "\(priorityEmoji) Priority: \(priority.rawValue)\n"
        }
        
        // Due date
        if hasDueDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            text += "📅 Due: \(formatter.string(from: dueDate))\n"
        }
        
        // Assigned students
        if !selectedStudentIDs.isEmpty {
            let assignedStudents = students.filter { selectedStudentIDs.contains($0.id.uuidString) }
            let names = assignedStudents.map { $0.firstName }.joined(separator: ", ")
            text += "👥 Assigned to: \(names)\n"
        }
        
        // Reminder
        if hasReminder {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            text += "🔔 Reminder: \(formatter.string(from: reminderDate))\n"
        }
        
        // Time estimate
        let totalEstimated = estimatedHours * 60 + estimatedMinutes
        if totalEstimated > 0 {
            let hours = totalEstimated / 60
            let mins = totalEstimated % 60
            if hours > 0 && mins > 0 {
                text += "⏱️ Estimated time: \(hours)h \(mins)m\n"
            } else if hours > 0 {
                text += "⏱️ Estimated time: \(hours)h\n"
            } else {
                text += "⏱️ Estimated time: \(mins)m\n"
            }
        }
        
        // Mood
        if let mood = selectedMood {
            text += "\(mood.emoji) Mood: \(mood.rawValue)\n"
        }
        
        // Reflection
        let trimmedReflection = reflectionNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedReflection.isEmpty {
            text += "💭 Reflection: \(trimmedReflection)\n"
        }
        
        // Subtasks
        if !todo.subtasks.isEmpty {
            text += "\n✅ Subtasks (\(todo.subtasks.filter { $0.isCompleted }.count)/\(todo.subtasks.count)):\n"
            for subtask in todo.subtasks.sorted(by: { $0.orderIndex < $1.orderIndex }) {
                let checkbox = subtask.isCompleted ? "☑️" : "☐"
                text += "  \(checkbox) \(subtask.title)\n"
            }
        }
        
        // Notes
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNotes.isEmpty {
            text += "\n📝 Notes:\n\(trimmedNotes)\n"
        }
        
        return text
    }
    
    private func saveAsTemplate() {
        guard !templateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let context = todo.modelContext else {
            templateName = ""
            return
        }
        
        let trimmedName = templateName.trimmingCharacters(in: .whitespacesAndNewlines)
        let totalEstimated = estimatedHours * 60 + estimatedMinutes
        let selectedNames = students
            .filter { selectedStudentIDs.contains($0.id.uuidString) }
            .map(\.fullName)
        let syncedTemplateTags = TodoTagHelper.syncStudentTags(
            existingTags: todo.tags,
            studentNames: selectedNames
        )
        
        let template = TodoTemplate(
            name: trimmedName,
            title: title,
            notes: notes,
            priority: priority,
            defaultEstimatedMinutes: totalEstimated > 0 ? totalEstimated : nil,
            defaultStudentIDs: Array(selectedStudentIDs),
            tags: syncedTemplateTags
        )

        context.insert(template)
        do {
            try context.save()
        } catch {
            print("⚠️ [\(#function)] Failed to save template: \(error)")
        }

        templateName = ""
    }
    
    private func save() {
        todo.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        todo.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        todo.studentIDs = Array(selectedStudentIDs)
        let selectedNames = students
            .filter { selectedStudentIDs.contains($0.id.uuidString) }
            .map(\.fullName)
        todo.tags = TodoTagHelper.syncStudentTags(
            existingTags: todo.tags,
            studentNames: selectedNames
        )
        todo.scheduledDate = scheduledDate
        todo.dueDate = deadlineDate
        todo.isSomeday = isSomeday
        todo.priority = priority
        todo.recurrence = recurrence
        todo.repeatAfterCompletion = recurrence != .none ? repeatAfterCompletion : false
        todo.customIntervalDays = recurrence == .custom ? customIntervalDays : nil
        
        // Save time estimates
        let totalEstimated = estimatedHours * 60 + estimatedMinutes
        let totalActual = actualHours * 60 + actualMinutes
        todo.estimatedMinutes = totalEstimated > 0 ? totalEstimated : nil
        todo.actualMinutes = totalActual > 0 ? totalActual : nil
        
        // Save mood and reflection
        todo.mood = selectedMood
        todo.reflectionNotes = reflectionNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Save location reminder
        if hasLocationReminder && !locationName.isEmpty {
            todo.locationName = locationName.trimmingCharacters(in: .whitespacesAndNewlines)
            todo.notifyOnEntry = notifyOnEntry
            todo.notifyOnExit = notifyOnExit
            // Note: Actual coordinates would be set via location picker in full implementation
        } else {
            todo.locationName = nil
            todo.locationLatitude = nil
            todo.locationLongitude = nil
        }
        
        // Handle reminder notification
        Task {
            if hasReminder {
                isSchedulingNotification = true
                do {
                    try await TodoNotificationService.shared.scheduleNotification(for: todo, at: reminderDate)
                } catch {
                    print("Error scheduling notification: \(error)")
                }
                isSchedulingNotification = false
            } else {
                // Cancel notification if reminder was disabled
                TodoNotificationService.shared.cancelNotification(for: todo)
            }


            if let context = todo.modelContext {
                do {
                    try context.save()
                } catch {
                    print("⚠️ [\(#function)] Failed to save todo: \(error)")
                }
            }

            closeEditor()
        }
    }

    private func closeEditor() {
        if let onDone {
            onDone()
        } else {
            dismiss()
        }
    }
}
// MARK: - Subtask Row
private struct SubtaskRow: View {
    let subtask: TodoSubtask
    let onToggle: () -> Void
    let onDelete: () -> Void
    let onUpdate: (String) -> Void
    
    @State private var editingTitle: String
    @FocusState private var isFocused: Bool
    
    init(subtask: TodoSubtask, onToggle: @escaping () -> Void, onDelete: @escaping () -> Void, onUpdate: @escaping (String) -> Void) {
        self.subtask = subtask
        self.onToggle = onToggle
        self.onDelete = onDelete
        self.onUpdate = onUpdate
        _editingTitle = State(initialValue: subtask.title)
    }
    
    var body: some View {
        HStack(spacing: 10) {
            Button {
                onToggle()
            } label: {
                Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(subtask.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)
            
            TextField("Subtask", text: $editingTitle)
                .textFieldStyle(.plain)
                .font(AppTheme.ScaledFont.body)
                .foregroundStyle(subtask.isCompleted ? .secondary : .primary)
                .strikethrough(subtask.isCompleted)
                .focused($isFocused)
                .onSubmit {
                    saveTitle()
                }
                .onChange(of: isFocused) { _, newValue in
                    if !newValue {
                        saveTitle()
                    }
                }
            
            Button {
                onDelete()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.02))
        .cornerRadius(8)
        .task {
            if subtask.title.isEmpty {
                do {
                    try await Task.sleep(for: .milliseconds(100))
                } catch {
                    print("⚠️ [\(#function)] Failed to sleep: \(error)")
                }
                isFocused = true
            }
        }
    }
    
    private func saveTitle() {
        let trimmed = editingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != subtask.title {
            onUpdate(trimmed)
        } else if trimmed.isEmpty {
            onDelete()
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

// MARK: - Todo Student Chip
private struct TodoStudentChip: View {
    let student: Student
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 6) {
            Text(student.firstName)
                .font(AppTheme.ScaledFont.bodySemibold)
            
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.15))
        .foregroundStyle(Color.accentColor)
        .clipShape(Capsule())
    }
}
// MARK: - URL Identifiable Conformance

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

// MARK: - Attachment Preview Sheet

private struct AttachmentPreviewSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            QuickLookPreview(url: url)
                .navigationTitle(url.lastPathComponent)
                #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

#if os(iOS)
private struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL
    
    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }
    
    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator { Coordinator(url: url) }
    
    class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem {
            url as NSURL
        }
    }
}
#else
private struct QuickLookPreview: NSViewRepresentable {
    let url: URL
    
    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)!
        view.previewItem = url as NSURL
        return view
    }
    
    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        nsView.previewItem = url as NSURL
    }
}
#endif
