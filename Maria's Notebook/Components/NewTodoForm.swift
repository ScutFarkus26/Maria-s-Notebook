// NewTodoForm.swift
// Elegant full-screen todo list view inspired by Things and Bear

import OSLog
import SwiftUI
import CoreData

// MARK: - New Todo Form

struct NewTodoForm: View {
    private static let logger = Logger.todos
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(sortDescriptors: CDStudent.sortByName)private var allStudentsRaw: FetchedResults<CDStudent>
    @AppStorage(UserDefaultsKeys.generalShowTestStudents) private var showTestStudents: Bool = false
    @AppStorage(UserDefaultsKeys.generalTestStudentNames)
    private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    private var allStudents: [CDStudent] {
        TestStudentsFilter.filterVisible(
            Array(allStudentsRaw).uniqueByID.filter(\.isEnrolled), show: showTestStudents, namesRaw: testStudentNamesRaw
        )
    }

    /// Optional initial title from the command bar
    private let initialTitle: String

    init(initialTitle: String = "") {
        self.initialTitle = initialTitle
        _title = State(initialValue: initialTitle)
    }

    @State private var title: String
    @State private var notes = ""
    @State private var dueDate: Date?
    @State private var scheduledDate: Date?
    @State private var isSomeday = false
    @State private var priority: TodoPriority = .none
    @State private var recurrence: RecurrencePattern = .none
    @State private var repeatAfterCompletion = false
    @State private var customIntervalDays = 7
    @State private var selectedTags: [String] = []
    @State private var selectedStudentIDs: Set<UUID> = []
    @State private var subtaskTitles: [String] = []
    @State private var newSubtaskTitle = ""
    @State private var estimatedHours = 0
    @State private var estimatedMinutes = 0
    @State private var isCreatingTodo = false

    var body: some View {
        Form {
            // Title & Notes
            Section {
                TextField("What do you need to do?", text: $title)
                    .font(AppTheme.ScaledFont.titleSmall)

                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
                    .font(AppTheme.ScaledFont.body)
            }

            // Students
            if !allStudents.isEmpty {
                Section("Students") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(allStudents) { student in
                                let sid = student.id ?? UUID()
                                let isSelected = selectedStudentIDs.contains(sid)
                                Button {
                                    if isSelected {
                                        selectedStudentIDs.remove(sid)
                                    } else {
                                        selectedStudentIDs.insert(sid)
                                    }
                                } label: {
                                    Text(student.firstName)
                                        .font(AppTheme.ScaledFont.caption)
                                        .fontWeight(isSelected ? .semibold : .regular)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(isSelected ? Color.accentColor : Color.secondary.opacity(UIConstants.OpacityConstants.light))
                                        .foregroundStyle(isSelected ? .white : .primary)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            // CDSchedule
            Section("Schedule") {
                HStack {
                    Text("When")
                    Spacer()
                    TodoSchedulePickerButton(
                        scheduledDate: $scheduledDate,
                        dueDate: $dueDate,
                        isSomeday: $isSomeday
                    )
                }

                Picker("Repeats", selection: $recurrence) {
                    ForEach(RecurrencePattern.allCases, id: \.self) { pattern in
                        Text(pattern.rawValue).tag(pattern)
                    }
                }

                if recurrence != .none {
                    Toggle("Repeat after completion", isOn: $repeatAfterCompletion)
                    if recurrence == .custom {
                        Stepper("Every \(customIntervalDays) days", value: $customIntervalDays, in: 1...365)
                    }
                }
            }

            // Priority
            Section {
                Picker("Priority", selection: $priority) {
                    ForEach(TodoPriority.allCases, id: \.self) { p in
                        HStack {
                            Circle().fill(p.color).frame(width: 8, height: 8)
                            Text(p.rawValue)
                        }
                        .tag(p)
                    }
                }
            }

            // Subtasks / Checklist
            Section("Checklist") {
                ForEach(subtaskTitles.indices, id: \.self) { index in
                    HStack(spacing: 10) {
                        Image(systemName: "circle")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                        Text(subtaskTitles[index])
                            .font(AppTheme.ScaledFont.body)
                        Spacer()
                        Button {
                            subtaskTitles.remove(at: index)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.red.opacity(UIConstants.OpacityConstants.prominent))
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 10) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.accentColor)
                    TextField("Add subtask", text: $newSubtaskTitle)
                        .font(AppTheme.ScaledFont.body)
                        .onSubmit {
                            addSubtask()
                        }
                }
            }

            // Time Estimate
            Section("Time Estimate") {
                HStack {
                    Picker("Hours", selection: $estimatedHours) {
                        ForEach(0..<13) { h in Text("\(h)h").tag(h) }
                    }
                    .pickerStyle(.menu)
                    Picker("Minutes", selection: $estimatedMinutes) {
                        ForEach([0, 5, 10, 15, 20, 30, 45], id: \.self) { m in Text("\(m)m").tag(m) }
                    }
                    .pickerStyle(.menu)
                }
            }

            // Tags
            Section("Tags") {
                TagPicker(selectedTags: $selectedTags)
            }

            // Create
            Section {
                Button {
                    createTodo()
                } label: {
                    HStack {
                        Spacer()
                        if isCreatingTodo {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Label("Create Todo", systemImage: "plus.circle.fill")
                            .font(AppTheme.ScaledFont.calloutSemibold)
                        Spacer()
                    }
                }
                .disabled(title.trimmed().isEmpty || isCreatingTodo)
            }
        }
    }

    private func addSubtask() {
        let trimmed = newSubtaskTitle.trimmed()
        guard !trimmed.isEmpty else { return }
        subtaskTitles.append(trimmed)
        newSubtaskTitle = ""
    }

    private func createTodo() {
        isCreatingTodo = true
        defer { isCreatingTodo = false }

        let resolvedStudentIDs = resolveStudentIDs()
        let resolvedStudentNames = allStudents
            .filter { resolvedStudentIDs.contains($0.id ?? UUID()) }
            .map(\.fullName)
        let resolvedTags = TodoTagHelper.syncStudentTags(
            existingTags: selectedTags,
            studentNames: resolvedStudentNames
        )

        let todo = CDTodoItem(context: viewContext)
        todo.title = title.trimmed()
        todo.notes = notes.trimmed()
        todo.studentIDsArray = resolvedStudentIDs.map(\.uuidString)
        todo.dueDate = dueDate
        todo.scheduledDate = scheduledDate
        todo.priority = priority
        todo.recurrence = recurrence
        todo.isSomeday = isSomeday
        todo.repeatAfterCompletion = repeatAfterCompletion
        if recurrence == .custom {
            todo.customIntervalDays = Int64(customIntervalDays)
        }

        todo.tagsArray = resolvedTags

        let totalEstimated = estimatedHours * 60 + estimatedMinutes
        if totalEstimated > 0 {
            todo.estimatedMinutes = Int64(totalEstimated)
        }

        // Create subtasks
        for (index, subtaskTitle) in subtaskTitles.enumerated() {
            let subtask = CDTodoSubtask(context: viewContext)
            subtask.title = subtaskTitle
            subtask.orderIndex = Int64(index)
            subtask.todo = todo
        }

        do {
            try viewContext.save()
        } catch {
            Self.logger.error("[\(#function)] Failed to create todo: \(error)")
        }
        dismiss()
    }

    private func resolveStudentIDs() -> Set<UUID> {
        // Use only manually-selected students. AI suggestions are available
        // via the "Suggest" button in the edit sheet after creation.
        selectedStudentIDs
    }
}
