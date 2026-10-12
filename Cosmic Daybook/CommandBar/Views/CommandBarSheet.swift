// CommandBarSheet.swift
// Natural language command bar for quick record keeping

import SwiftUI
import CoreData
import OSLog

struct CommandBarSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dependencies) private var dependencies
    @Environment(SaveCoordinator.self) private var saveCoordinator

    // Callbacks to RootView for opening sheets
    var onWorkItem: (UUID?, Set<UUID>) -> Void
    var onPractice: ((UUID?, Set<UUID>) -> Void)?
    var onTodo: (String) -> Void

    // MARK: - Data

    /// The workspace's catalog in this sheet's own order — area, then lesson name.
    private var allLessons: [CDLesson] {
        dependencies.lessonCatalog.all.sorted { lhs, rhs in
            lhs.area == rhs.area
                ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                : lhs.area.localizedStandardCompare(rhs.area) == .orderedAscending
        }
    }

    @TestStudentVisibility private var testStudents

    private var students: [CDStudent] {
        TestStudentsFilter.filterVisible(
            dependencies.roster.enrolled, show: testStudents.show, namesRaw: testStudents.namesRaw
        )
    }

    // MARK: - State

    @State private var viewModel = CommandBarViewModel()
    @Environment(\.isSampleClassroom) private var isSampleClassroom
    @State private var saveErrorMessage: String?
    @FocusState private var isTextFieldFocused: Bool
    /// Set just before the sheet closes on purpose (Save, a form opening,
    /// Discard), so the discard question doesn't ask about words being kept.
    @State private var isClosing = false
    /// Save or Discard: the sheet dismisses itself once `isClosing` is drawn.
    /// A form opening doesn't set it: RootView swaps the sheet for the form,
    /// and a dismiss here would close the form.
    @State private var isDismissRequested = false
    /// A form to open once `isClosing` is drawn: RootView swaps this sheet for
    /// it, which the Mac counts as a programmatic dismiss, so it waits for the
    /// redraw like Save does (review 2026-10-11 (c) #6).
    @State private var pendingAction: CommandAction?
    @State private var isConfirmingCancel = false

    /// Words that closing now would throw away: typed, or organized and not
    /// yet saved (bug hunt 2026-10-11 #47).
    private var hasWordsToLose: Bool {
        !isClosing && (viewModel.captureProposal != nil || !viewModel.inputText.trimmed().isEmpty)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                inputSection
                Divider()
                contentSection
            }
            .navigationTitle("Capture What Happened")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasWordsToLose {
                            isConfirmingCancel = true
                        } else {
                            close()
                        }
                    }
                }
            }
            .confirmationDialog(Self.discardTitle, isPresented: $isConfirmingCancel, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { close() }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text(discardMessage)
            }
        }
        // A swipe down or a click outside asks first too. On the Mac this also
        // fires for a programmatic dismiss, which `isClosing` lets through.
        .dismissalConfirmationDialog(Self.discardTitle, shouldPresent: hasWordsToLose) {
            Button("Discard", role: .destructive) {}
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text(discardMessage)
        }
        // Dismissed only once the view has redrawn with `isClosing` set, so
        // the question above is already off when the sheet goes.
        .onChange(of: isDismissRequested) { _, requested in
            if requested { dismiss() }
        }
        .onChange(of: pendingAction) { _, action in
            if let action { openForm(action) }
        }
        #if os(macOS)
        // Fixed, not min-sized: `contentSection` swaps wholesale (examples →
        // spinner → review) and a fitted sheet re-sizes its window inside the
        // same layout pass that measures the sheet's toolbar. That trips
        // "NSToolbarItemViewer's min/max size is nan" (2026-09-10). A constant
        // frame keeps every state inside one stable window.
        .frame(width: 560, height: 500)
        .presentationSizingFitted()
        #else
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
        .onAppear {
            viewModel.isSampleClassroom = isSampleClassroom
            isTextFieldFocused = true
        }
        // Closing mid-dictation would otherwise leave the microphone tap and
        // the recognition task running with nowhere to show the transcript.
        .onDisappear {
            viewModel.speechService.stopRecording()
        }
        .alert("Couldn't Save", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("OK") { saveErrorMessage = nil }
        } message: {
            Text(saveErrorMessage ?? "Couldn't save what you wrote. Nothing was changed. Try again.")
        }
    }

    // MARK: - Input Section

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            inputRow
            // Why dictation didn't start (permission off, not available) or
            // why it stopped; without it a tap on the mic just did nothing.
            if let speechError = viewModel.speechService.error {
                Text(speechError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var inputRow: some View {
        HStack(spacing: 12) {
            TextField("What happened? Type or speak naturally…", text: $viewModel.inputText, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.plain)
                .focused($isTextFieldFocused)
                .onSubmit {
                    submitCommand()
                }

            // Mic button
            Button {
                viewModel.toggleDictation()
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
                .accessibilityLabel("Organize classroom capture")
            }
        }
    }

    // MARK: - Content Section

    @ViewBuilder
    private var contentSection: some View {
        if viewModel.isProcessing {
            processingView
        } else if viewModel.captureProposal != nil {
            captureReviewView
        } else if let command = viewModel.parsedCommand {
            resultView(command)
        } else if let error = viewModel.errorMessage {
            errorView(error)
        } else {
            examplesView
        }
    }

    // MARK: - Capture Review

    @ViewBuilder
    private var captureReviewView: some View {
        if viewModel.captureProposal != nil {
            CaptureProposalReviewView(
                proposal: Binding(
                    get: { viewModel.captureProposal ?? Self.emptyCaptureProposal },
                    set: { viewModel.captureProposal = $0 }
                ),
                students: students,
                lessons: allLessons.uniqueByID,
                validationMessage: viewModel.captureValidationMessage,
                saveTitle: "Save",
                onSave: saveReviewedCapture,
                onStartOver: {
                    viewModel.reset()
                    isTextFieldFocused = true
                }
            )
        }
    }

    private static let emptyCaptureProposal = CaptureProposal(
        rawText: "",
        recordsPresentation: false,
        lessonID: nil,
        lessonName: nil,
        groupObservation: "",
        studentEntries: [],
        unresolvedStudentNames: [],
        source: .deterministic
    )

    private func saveReviewedCapture() {
        do {
            let receipt = try viewModel.saveCaptureProposal(
                context: viewContext,
                saveCoordinator: saveCoordinator
            )
            let recordCount = (receipt.presentationID == nil ? 0 : 1) + receipt.noteCount + receipt.workCount
            dependencies.toastService.showSuccess(
                recordCount == 1 ? "Saved" : "Saved \(recordCount) entries"
            )
            close()
        } catch let error as CaptureSaveError {
            saveErrorMessage = error.errorDescription
        } catch {
            Logger.notes.error("Command bar save failed: \(error.localizedDescription, privacy: .public)")
            saveErrorMessage = CaptureSaveError.saveFailed.errorDescription
        }
    }

    // MARK: - Actions

    private func submitCommand() {
        let speech = viewModel.speechService
        guard !viewModel.inputText.trimmed().isEmpty || speech.isRecording || speech.isFinishing else { return }

        let studentData = students.compactMap { s -> StudentData? in
            guard let id = s.id else { return nil }
            return StudentData(id: id, firstName: s.firstName, lastName: s.lastName, nickname: s.nickname)
        }
        let lessonData = allLessons.compactMap { l -> LessonData? in
            guard let id = l.id else { return nil }
            return LessonData(id: id, name: l.name, area: l.area, sequence: l.sequence)
        }

        // Sending while dictating: the last words she said come in first.
        // A second Return while it waits is ignored.
        Task {
            await viewModel.send(students: studentData, lessons: lessonData)
        }
    }

    private func executeCommand(_ command: ParsedCommand) {
        viewModel.addToRecent(viewModel.inputText.trimmed())
        guard let action = viewModel.buildAction(from: command) else { return }

        // The form that opens takes the words with it.
        isClosing = true
        pendingAction = action
    }

    private func openForm(_ action: CommandAction) {
        switch action {
        case .openWorkItem(let lessonID, let studentIDs):
            onWorkItem(lessonID, studentIDs)
        case .openPractice(let lessonID, let studentIDs):
            onPractice?(lessonID, studentIDs)
        case .openTodo(let titleText):
            onTodo(titleText)
        }
    }

    private func close() {
        isClosing = true
        isDismissRequested = true
    }

    private static let discardTitle = "Discard what you wrote?"

    private var discardMessage: String {
        viewModel.captureProposal == nil
            ? "It isn't saved yet."
            : "Nothing here is saved yet. What you wrote stays in Recent, so you can start again from it."
    }
}

// MARK: - Content States

extension CommandBarSheet {
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
                            .background(
                            Color.secondary.opacity(UIConstants.OpacityConstants.veryFaint),
                            in: RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium)
                        )
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
                        .background(
                            Color.secondary.opacity(UIConstants.OpacityConstants.veryFaint),
                            in: RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium)
                        )
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
            Text("Organizing what happened…")
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
                    .background(command.intent.pieMenuAction.color,
                                in: RoundedRectangle(cornerRadius: UIConstants.CornerRadius.large))
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
                    in: RoundedRectangle(cornerRadius: UIConstants.CornerRadius.control)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(command.intent.displayName)
                    .font(.headline)
                Text("Review in the form before saving")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(16)
        .background(
            Color.secondary.opacity(UIConstants.OpacityConstants.veryFaint),
            in: RoundedRectangle(cornerRadius: UIConstants.CornerRadius.large)
        )
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
