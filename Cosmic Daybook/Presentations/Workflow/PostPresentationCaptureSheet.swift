import SwiftUI

/// A brief, optional reflection after the presentation itself has already been recorded.
/// It reuses the same editable Capture What Happened proposal used by free-form capture.
struct PostPresentationCaptureSheet: View {
    let students: [CDStudent]
    let lesson: CDLesson
    let presentationID: UUID
    let presentedAt: Date
    var onUndoPresentation: (() -> String?)?
    var onDetailsSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(SaveCoordinator.self) private var saveCoordinator

    @State private var captureViewModel = CommandBarViewModel()
    @State private var observationText = ""
    @State private var errorAlertTitle = "Couldn’t Save Details"
    @State private var saveErrorMessage: String?
    @State private var showDiscardConfirmation = false
    @State private var isSaving = false
    @FocusState private var observationFieldFocused: Bool

    private var lessonID: UUID? { lesson.id }

    private var hasSupplementalDraft: Bool {
        if !observationText.trimmed().isEmpty { return true }
        guard let proposal = captureViewModel.captureProposal else { return false }
        if !proposal.groupObservation.trimmed().isEmpty { return true }
        return proposal.studentEntries.contains {
            !$0.observation.trimmed().isEmpty || $0.followUp != .none
        }
    }

    private var detailValidationMessage: String? {
        if let message = captureViewModel.captureValidationMessage {
            return message
        }
        guard let proposal = captureViewModel.captureProposal else { return nil }
        let hasReviewedDetail = !proposal.groupObservation.trimmed().isEmpty
            || proposal.studentEntries.contains {
                !$0.observation.trimmed().isEmpty || $0.followUp != .none
            }
        return hasReviewedDetail
            ? nil
            : "Add an observation, or choose Continue to Follow-Up."
    }

    var body: some View {
        NavigationStack {
            Group {
                if captureViewModel.isProcessing {
                    organizingView
                } else if captureViewModel.captureProposal != nil {
                    reviewView
                } else {
                    initialCaptureView
                }
            }
            .navigationTitle("What Happened?")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(hasSupplementalDraft ? "Skip Reflection" : "Continue") {
                        closeRequested()
                    }
                }

                if let onUndoPresentation {
                    ToolbarItem(placement: .secondaryAction) {
                        Button("Undo Presentation", role: .destructive) {
                            if let message = onUndoPresentation() {
                                errorAlertTitle = "Couldn’t Undo Presentation"
                                saveErrorMessage = message
                            } else {
                                dismiss()
                            }
                        }
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 600, minHeight: 500, idealHeight: 640)
        .presentationSizingFitted()
        #else
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
        .interactiveDismissDisabled(hasSupplementalDraft)
        .onAppear {
            observationFieldFocused = true
        }
        .onChange(of: captureViewModel.speechService.transcript) { _, transcript in
            if !transcript.isEmpty {
                observationText = transcript
            }
        }
        .onDisappear {
            if captureViewModel.speechService.isRecording {
                captureViewModel.speechService.stopRecording()
            }
        }
        .confirmationDialog(
            "Discard Unsaved Details?",
            isPresented: $showDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard Details", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text(
                "The presentation is already recorded. "
                    + "Only these unsaved observations will be discarded."
            )
        }
        .alert(errorAlertTitle, isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("OK") { saveErrorMessage = nil }
        } message: {
            Text(saveErrorMessage ?? "The presentation details could not be saved.")
        }
    }
}

private extension PostPresentationCaptureSheet {
    private var initialCaptureView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                presentationRecordedHeader

                VStack(alignment: .leading, spacing: 8) {
                    Text("What did you observe?")
                        .font(.headline)

                    TextField(
                        "Type or speak naturally. You can leave this blank.",
                        text: $observationText,
                        axis: .vertical
                    )
                    .lineLimit(4...8)
                    .textFieldStyle(.roundedBorder)
                    .focused($observationFieldFocused)

                    Text("The lesson, children, and date are already known.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    Button {
                        captureViewModel.speechService.toggleRecording(
                            requiresOnDeviceRecognition: true
                        )
                    } label: {
                        Label(
                            captureViewModel.speechService.isRecording ? "Stop" : "Speak",
                            systemImage: captureViewModel.speechService.isRecording ? "stop.circle.fill" : "mic.fill"
                        )
                    }
                    .buttonStyle(.bordered)

                    Button("Organize and Review") {
                        organizeAndReview()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(observationText.trimmed().isEmpty)
                }

                if let speechError = captureViewModel.speechService.error {
                    Label(speechError, systemImage: "lock.trianglebadge.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Add Individual Observations Manually") {
                    captureViewModel.captureProposal = manualProposal(sharedObservation: observationText)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Divider()

                Button(
                    hasSupplementalDraft
                        ? "Skip Reflection and Continue"
                        : "Continue to Follow-Up"
                ) {
                    closeRequested()
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.bordered)
            }
            .padding(16)
        }
    }

    private var presentationRecordedHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Presentation recorded", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(AppColors.success)

            Text(lesson.name)
                .font(.title3.weight(.semibold))

            HStack(spacing: 8) {
                Text(presentedAt.formatted(date: .abbreviated, time: .omitted))
                Text("\u{2022}")
                Text(students.count == 1 ? "1 child" : "\(students.count) children")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            Color.green.opacity(UIConstants.OpacityConstants.veryFaint),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

    private var organizingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("Organizing your observation…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Nothing is being saved yet.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var reviewView: some View {
        if captureViewModel.captureProposal != nil {
            CaptureProposalReviewView(
                proposal: Binding(
                    get: { captureViewModel.captureProposal ?? manualProposal(sharedObservation: observationText) },
                    set: { captureViewModel.captureProposal = $0 }
                ),
                students: students,
                lessons: [lesson],
                mode: .recordedPresentation(lessonName: lesson.name, presentedAt: presentedAt),
                validationMessage: detailValidationMessage,
                saveTitle: "Save Observation",
                isSaving: isSaving,
                onSave: saveDetails,
                onStartOver: {
                    captureViewModel.reset()
                    observationFieldFocused = true
                }
            )
        }
    }
}

private extension PostPresentationCaptureSheet {
    private func organizeAndReview() {
        let trimmed = observationText.trimmed()
        guard !trimmed.isEmpty, let lessonID else { return }

        let names = students.map { StudentFormatter.displayName(for: $0) }.joined(separator: ", ")
        captureViewModel.inputText = "I presented \(lesson.name) to \(names). \(trimmed)"

        let studentData = students.compactMap { student -> StudentData? in
            guard let id = student.id else { return nil }
            return StudentData(
                id: id,
                firstName: student.firstName,
                lastName: student.lastName,
                nickname: student.nickname
            )
        }
        let lessonData = [LessonData(id: lessonID, name: lesson.name, area: lesson.area, sequence: lesson.sequence)]

        Task { @MainActor in
            await captureViewModel.submit(students: studentData, lessons: lessonData, mcpClient: nil)
            normalizeProposalAfterOrganization(originalWords: trimmed)
        }
    }

    private func normalizeProposalAfterOrganization(originalWords: String) {
        var proposal = captureViewModel.captureProposal ?? manualProposal(sharedObservation: originalWords)
        proposal.rawText = originalWords
        proposal.recordsPresentation = true
        proposal.lessonID = lesson.id
        proposal.lessonName = lesson.name
        proposal.unresolvedStudentNames = []

        let existingByID = Dictionary(
            proposal.studentEntries.map { ($0.studentID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        proposal.studentEntries = students.compactMap { student -> StudentCaptureProposal? in
            guard let id = student.id else { return nil }
            var entry = existingByID[id] ?? StudentCaptureProposal(
                studentID: id,
                studentName: StudentFormatter.displayName(for: student)
            )
            // Reflection and planning are separate moments. AI may organize the
            // guide's words, but the following screen owns every planning choice.
            entry.followUp = .none
            entry.followUpDetail = ""
            return entry
        }

        let organizedSomething = !proposal.groupObservation.trimmed().isEmpty
            || proposal.studentEntries.contains { !$0.observation.trimmed().isEmpty }
        if !organizedSomething {
            proposal.groupObservation = originalWords
        }

        captureViewModel.captureProposal = proposal
        captureViewModel.inputText = originalWords
    }

    private func manualProposal(sharedObservation: String) -> CaptureProposal {
        CaptureProposal(
            rawText: sharedObservation.trimmed(),
            recordsPresentation: true,
            lessonID: lesson.id,
            lessonName: lesson.name,
            groupObservation: sharedObservation.trimmed(),
            studentEntries: students.compactMap { student in
                guard let id = student.id else { return nil }
                return StudentCaptureProposal(
                    studentID: id,
                    studentName: StudentFormatter.displayName(for: student)
                )
            },
            unresolvedStudentNames: [],
            source: .deterministic
        )
    }

    private func saveDetails() {
        guard !isSaving else { return }
        isSaving = true
        do {
            _ = try captureViewModel.saveCaptureProposal(
                context: viewContext,
                saveCoordinator: saveCoordinator,
                presentedAt: presentedAt,
                recordedPresentationID: presentationID
            )
            onDetailsSaved()
            ToastService.shared.showSuccess("Presentation observation saved")
            dismiss()
        } catch {
            isSaving = false
            errorAlertTitle = "Couldn’t Save Details"
            saveErrorMessage = error.localizedDescription
        }
    }

    private func closeRequested() {
        if hasSupplementalDraft {
            showDiscardConfirmation = true
        } else {
            dismiss()
        }
    }
}
