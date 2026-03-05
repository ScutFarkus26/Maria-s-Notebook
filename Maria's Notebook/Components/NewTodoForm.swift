// NewTodoForm.swift
// Elegant full-screen todo list view inspired by Things and Bear

import SwiftUI
import SwiftData

// MARK: - New Todo Form

struct NewTodoForm: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: Student.sortByName) private var allStudentsRaw: [Student]
    @AppStorage(UserDefaultsKeys.generalShowTestStudents) private var showTestStudents: Bool = false
    @AppStorage(UserDefaultsKeys.generalTestStudentNames) private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    private var allStudents: [Student] {
        TestStudentsFilter.filterVisible(allStudentsRaw.uniqueByID, show: showTestStudents, namesRaw: testStudentNamesRaw)
    }

    @State private var title = ""
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
                                let isSelected = selectedStudentIDs.contains(student.id)
                                Button {
                                    if isSelected {
                                        selectedStudentIDs.remove(student.id)
                                    } else {
                                        selectedStudentIDs.insert(student.id)
                                    }
                                } label: {
                                    Text(student.firstName)
                                        .font(AppTheme.ScaledFont.caption)
                                        .fontWeight(isSelected ? .semibold : .regular)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.1))
                                        .foregroundStyle(isSelected ? .white : .primary)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            // Schedule
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
                                .foregroundStyle(.red.opacity(0.7))
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
                    Task { await createTodo() }
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
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreatingTodo)
            }
        }
    }

    private func addSubtask() {
        let trimmed = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        subtaskTitles.append(trimmed)
        newSubtaskTitle = ""
    }

    private func createTodo() async {
        isCreatingTodo = true
        defer { isCreatingTodo = false }

        let resolvedStudentIDs = await resolveStudentIDs()
        let resolvedStudentNames = allStudents
            .filter { resolvedStudentIDs.contains($0.id) }
            .map(\.fullName)
        let resolvedTags = TodoTagHelper.syncStudentTags(
            existingTags: selectedTags,
            studentNames: resolvedStudentNames
        )

        let todo = TodoItem(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            studentIDs: resolvedStudentIDs.map(\.uuidString),
            dueDate: dueDate,
            scheduledDate: scheduledDate,
            priority: priority,
            recurrence: recurrence
        )
        todo.isSomeday = isSomeday
        todo.repeatAfterCompletion = repeatAfterCompletion
        if recurrence == .custom {
            todo.customIntervalDays = customIntervalDays
        }

        todo.tags = resolvedTags

        let totalEstimated = estimatedHours * 60 + estimatedMinutes
        if totalEstimated > 0 {
            todo.estimatedMinutes = totalEstimated
        }

        modelContext.insert(todo)

        // Create subtasks
        for (index, subtaskTitle) in subtaskTitles.enumerated() {
            let subtask = TodoSubtask(title: subtaskTitle, orderIndex: index)
            subtask.todo = todo
            modelContext.insert(subtask)
        }

        do {
            try modelContext.save()
        } catch {
            print("⚠️ [\(#function)] Failed to create todo: \(error)")
        }
        dismiss()
    }

    private func resolveStudentIDs() async -> Set<UUID> {
        var resolved = selectedStudentIDs
        #if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            let combinedText = "\(title) \(notes)".trimmingCharacters(in: .whitespacesAndNewlines)
            guard combinedText.isEmpty == false else { return resolved }

            do {
                let extractedNames = try await TodoStudentSuggestionService.extractStudentNames(
                    from: combinedText,
                    availableStudents: allStudents
                )
                let matchedStudents = TodoStudentSuggestionService.matchStudents(
                    extractedNames: extractedNames,
                    from: allStudents
                )
                resolved.formUnion(matchedStudents.map(\.id))
            } catch {
                // Fall back to manual student selection if extraction fails.
            }
        }
        #endif
        return resolved
    }
}
