// CommandBarSheet.swift
// Natural language command bar for quick record keeping

import SwiftUI
import CoreData

struct CommandBarSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dependencies) private var dependencies

    // Callbacks to RootView for opening sheets
    var onPresentation: (UUID) -> Void
    var onWorkItem: (UUID?, Set<UUID>) -> Void
    var onPractice: ((UUID?, Set<UUID>) -> Void)?
    var onNote: (UUID?, String) -> Void
    var onTodo: (String) -> Void

    // MARK: - Data

    @FetchRequest(sortDescriptors: CDStudent.sortByName)private var allStudents: FetchedResults<CDStudent>
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDLesson.subject, ascending: true), NSSortDescriptor(keyPath: \CDLesson.name, ascending: true)]) private var allLessons: FetchedResults<CDLesson>

    @AppStorage(UserDefaultsKeys.generalShowTestStudents) private var showTestStudents: Bool = false
    @AppStorage(UserDefaultsKeys.generalTestStudentNames)
    private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    private var students: [CDStudent] {
        TestStudentsFilter.filterVisible(
            Array(allStudents).uniqueByID.filter(\.isEnrolled), show: showTestStudents, namesRaw: testStudentNamesRaw
        )
    }

    // MARK: - State

    @State private var viewModel = CommandBarViewModel()
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                inputSection
                Divider()
                contentSection
            }
            .navigationTitle("Command Bar")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 400)
        .presentationSizingFitted()
        #else
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
        .onAppear {
            isTextFieldFocused = true
        }
        .onChange(of: viewModel.speechService.transcript) { _, newValue in
            if !newValue.isEmpty {
                viewModel.inputText = newValue
            }
        }
    }

    // MARK: - Input Section

    private var inputSection: some View {
        HStack(spacing: 12) {
            TextField("Type or speak a command...", text: $viewModel.inputText, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.plain)
                .focused($isTextFieldFocused)
                .onSubmit {
                    submitCommand()
                }

            // Mic button
            Button {
                viewModel.speechService.toggleRecording()
            } label: {
                Image(systemName: viewModel.speechService.isRecording ? "mic.fill" : "mic")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(viewModel.speechService.isRecording ? .red : .secondary)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(viewModel.speechService.isRecording
                                  ? Color.red.opacity(UIConstants.OpacityConstants.accent)
                                  : Color.secondary.opacity(UIConstants.OpacityConstants.light))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(viewModel.speechService.isRecording ? "Stop recording" : "Start voice input")

            // Submit button
            if !viewModel.inputText.trimmed().isEmpty {
                Button {
                    submitCommand()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Submit command")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Content Section

    @ViewBuilder
    private var contentSection: some View {
        if viewModel.isProcessing {
            processingView
        } else if let command = viewModel.parsedCommand {
            resultView(command)
        } else if let error = viewModel.errorMessage {
            errorView(error)
        } else {
            examplesView
        }
    }

    // MARK: - Examples

    private var examplesView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !viewModel.recentCommands.isEmpty {
                    Text("Recent")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    ForEach(viewModel.recentCommands, id: \.self) { command in
                        Button {
                            viewModel.inputText = command
                            submitCommand()
                        } label: {
                            HStack {
                                Image(systemName: "clock.arrow.circlepath")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24)
                                Text(command)
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(2)
                                Spacer()
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(Color.secondary.opacity(UIConstants.OpacityConstants.veryFaint), in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("Examples")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                ForEach(CommandBarViewModel.exampleCommands, id: \.self) { example in
                    Button {
                        viewModel.inputText = example
                        submitCommand()
                    } label: {
                        HStack {
                            Image(systemName: "text.quote")
                                .foregroundStyle(.secondary)
                                .frame(width: 24)
                            Text(example)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color.secondary.opacity(UIConstants.OpacityConstants.veryFaint), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
    }

    // MARK: - Processing

    private var processingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("Understanding...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Result

    private func resultView(_ command: ParsedCommand) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                // Intent card
                intentCard(command)

                // Entities
                if !command.rawStudentNames.isEmpty {
                    entityRow(
                        icon: "person.fill",
                        label: "Students",
                        values: command.rawStudentNames,
                        color: .blue
                    )
                }

                if let lesson = command.rawLessonName {
                    entityRow(
                        icon: "book.fill",
                        label: "Lesson",
                        values: [lesson],
                        color: .orange
                    )
                }

                if !command.freeText.isEmpty {
                    freeTextRow(command.freeText)
                }

                // Open form button
                Button {
                    executeCommand(command)
                } label: {
                    HStack {
                        Image(systemName: command.intent.icon)
                        Text("Open \(command.intent.displayName) Form")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(command.intent.pieMenuAction.color, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)

                // Try again
                Button {
                    viewModel.reset()
                    isTextFieldFocused = true
                } label: {
                    Text("Try Again")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 16)
        }
    }

    // MARK: - Actions

    private func submitCommand() {
        guard !viewModel.inputText.trimmed().isEmpty else { return }

        // Stop recording if active
        if viewModel.speechService.isRecording {
            viewModel.speechService.stopRecording()
        }

        let studentData = students.compactMap { s -> StudentData? in
            guard let id = s.id else { return nil }
            return StudentData(id: id, firstName: s.firstName, lastName: s.lastName, nickname: s.nickname)
        }
        let lessonData = allLessons.compactMap { l -> LessonData? in
            guard let id = l.id else { return nil }
            return LessonData(id: id, name: l.name, subject: l.subject, group: l.group)
        }

        Task {
            await viewModel.submit(
                students: studentData,
                lessons: lessonData,
                mcpClient: dependencies.mcpClient
            )
        }
    }

    private func executeCommand(_ command: ParsedCommand) {
        viewModel.addToRecent(viewModel.inputText.trimmed())
        let action = viewModel.buildAction(from: command, modelContext: viewContext)

        switch action {
        case .openPresentation(let draftID):
            onPresentation(draftID)
        case .openWorkItem(let lessonID, let studentIDs):
            onWorkItem(lessonID, studentIDs)
        case .openPractice(let lessonID, let studentIDs):
            onPractice?(lessonID, studentIDs)
        case .openNote(let studentID, let bodyText):
            onNote(studentID, bodyText)
        case .openTodo(let titleText):
            onTodo(titleText)
        }
    }
}

// MARK: - Helper Views

extension CommandBarSheet {

    private func intentCard(_ command: ParsedCommand) -> some View {
        HStack(spacing: 12) {
            Image(systemName: command.intent.icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(command.intent.pieMenuAction.color)
                .frame(width: 44, height: 44)
                .background(
                    command.intent.pieMenuAction.color.opacity(UIConstants.OpacityConstants.medium),
                    in: RoundedRectangle(cornerRadius: 10)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(command.intent.displayName)
                    .font(.headline)
                Text("Confidence: \(Int(command.confidence * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(16)
        .background(Color.secondary.opacity(UIConstants.OpacityConstants.veryFaint), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }

    private func entityRow(icon: String, label: String, values: [String], color: Color) -> some View {
        HStack(alignment: .top) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                FlowLayout(spacing: 6) {
                    ForEach(values, id: \.self) { value in
                        Text(value)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(color.opacity(UIConstants.OpacityConstants.medium), in: Capsule())
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func freeTextRow(_ text: String) -> some View {
        HStack(alignment: .top) {
            Image(systemName: "text.alignleft")
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text("Text")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(text)
                    .font(.body)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "questionmark.circle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Try Again") {
                viewModel.reset()
                isTextFieldFocused = true
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
