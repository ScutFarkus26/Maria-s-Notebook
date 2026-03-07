import SwiftUI
import SwiftData
import OSLog

// Sheet for adding or editing a SampleWork and its template steps.
// swiftlint:disable:next type_body_length
struct SampleWorkEditorSheet: View {
    private static let logger = Logger.lessons

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let lesson: Lesson
    var existingSampleWork: SampleWork?
    var onSave: () -> Void

    @State private var title: String = ""
    @State private var workKind: WorkKind = .practiceLesson
    @State private var notes: String = ""
    @State private var draftSteps: [DraftStep] = []
    @State private var showDeleteAlert = false

    struct DraftStep: Identifiable {
        var id = UUID()
        var title: String = ""
        var instructions: String = ""
    }

    private var isEditing: Bool { existingSampleWork != nil }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Template Section
                Section {
                    TextField(text: $title, prompt: Text("Skyscraper Drawers")) {
                        Text("Title")
                    }

                    // Work kind picker
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.verySmall) {
                        Text("Work Type")
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 0) {
                            kindButton(.practiceLesson, "Practice")
                            kindButton(.followUpAssignment, "Follow-Up")
                            kindButton(.research, "Project")
                            kindButton(.report, "Report")
                        }
                        .background(
                            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium)
                                .stroke(Color.primary.opacity(UIConstants.OpacityConstants.light))
                        )
                    }
                } header: {
                    Text("Work Template")
                }

                // MARK: - Notes Section
                Section {
                    TextEditor(text: $notes)
                        .frame(minHeight: 60)
                } header: {
                    Text("Notes")
                }

                // MARK: - Steps Section
                Section {
                    ForEach(Array(draftSteps.enumerated()), id: \.element.id) { index, step in
                        stepRow(index: index, step: step)
                    }
                    .onMove(perform: moveSteps)

                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            draftSteps.append(DraftStep())
                        }
                    } label: {
                        Label("Add Step", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text("Steps")
                } footer: {
                    if !draftSteps.isEmpty {
                        Text("Steps define the progression students work through (e.g., Set 1, Set 2, Set 3).")
                    }
                }

                // MARK: - Delete Section
                if isEditing {
                    Section {
                        Button("Delete Sample Work", role: .destructive) {
                            showDeleteAlert = true
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "Edit Sample Work" : "Add Sample Work")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmed().isEmpty)
                }
            }
            .alert("Delete Sample Work?", isPresented: $showDeleteAlert) {
                Button("Delete", role: .destructive) { deleteSampleWork() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will delete this work template and all its steps. This action cannot be undone.")
            }
        }
        .onAppear {
            if let sw = existingSampleWork {
                title = sw.title
                workKind = sw.workKind ?? .practiceLesson
                notes = sw.notes
                draftSteps = sw.orderedSteps.map { step in
                    DraftStep(id: step.id, title: step.title, instructions: step.instructions)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 520)
        #endif
    }

    // MARK: - Kind Button

    @ViewBuilder
    private func kindButton(_ kind: WorkKind, _ label: String) -> some View {
        Button(label) {
            workKind = kind
        }
        .padding(.horizontal, AppTheme.Spacing.compact)
        .padding(.vertical, AppTheme.Spacing.small)
        .background(workKind == kind ? Color.accentColor.opacity(UIConstants.OpacityConstants.light) : Color.clear)
        .foregroundStyle(workKind == kind ? Color.accentColor : .primary)
        .font(.subheadline)
    }

    // MARK: - Step Row

    @ViewBuilder
    // swiftlint:disable:next function_body_length
    private func stepRow(index: Int, step: DraftStep) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // Step number
            Text("\(index + 1).")
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
                .padding(.top, 8)

            // Title & instructions
            VStack(alignment: .leading, spacing: 4) {
                TextField(text: stepTitleBinding(for: step.id), prompt: Text("Set \(index + 1)")) {
                    EmptyView()
                }
                .font(AppTheme.ScaledFont.body)
                .labelsHidden()

                TextField(text: stepInstructionsBinding(for: step.id), prompt: Text("Instructions (optional)")) {
                    EmptyView()
                }
                .font(AppTheme.ScaledFont.caption)
                .foregroundStyle(.secondary)
                .labelsHidden()
            }

            // Move up/down buttons
            if draftSteps.count > 1 {
                VStack(spacing: 2) {
                    Button {
                        moveStepUp(index: index)
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(index > 0 ? .secondary : .quaternary)
                    }
                    .buttonStyle(.plain)
                    .disabled(index == 0)

                    Button {
                        moveStepDown(index: index)
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(index < draftSteps.count - 1 ? .secondary : .quaternary)
                    }
                    .buttonStyle(.plain)
                    .disabled(index >= draftSteps.count - 1)
                }
                .padding(.top, 6)
            }

            // Delete button
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    draftSteps.removeAll { $0.id == step.id }
                }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
    }

    // Binding helpers for step fields (needed because ForEach with enumerated doesn't give $bindings)
    private func stepTitleBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { draftSteps.first(where: { $0.id == id })?.title ?? "" },
            set: { newValue in
                if let idx = draftSteps.firstIndex(where: { $0.id == id }) {
                    draftSteps[idx].title = newValue
                }
            }
        )
    }

    private func stepInstructionsBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { draftSteps.first(where: { $0.id == id })?.instructions ?? "" },
            set: { newValue in
                if let idx = draftSteps.firstIndex(where: { $0.id == id }) {
                    draftSteps[idx].instructions = newValue
                }
            }
        )
    }

    // MARK: - Step Management

    private func moveStepUp(index: Int) {
        guard index > 0 else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            draftSteps.swapAt(index, index - 1)
        }
    }

    private func moveStepDown(index: Int) {
        guard index < draftSteps.count - 1 else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            draftSteps.swapAt(index, index + 1)
        }
    }

    private func moveSteps(from source: IndexSet, to destination: Int) {
        draftSteps.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: - Save

    private func save() {
        let service = SampleWorkService(context: modelContext)

        if let existing = existingSampleWork {
            // Update existing sample work
            service.update(existing, title: title.trimmed(), workKind: workKind, notes: notes)

            // Reconcile steps: delete removed, update existing, add new
            let existingStepIDs = Set(existing.orderedSteps.map { $0.id })
            let draftStepIDs = Set(draftSteps.map { $0.id })

            // Delete steps that were removed
            for step in existing.orderedSteps where !draftStepIDs.contains(step.id) {
                service.deleteStep(step)
            }

            // Update or create steps
            for (index, draft) in draftSteps.enumerated() {
                if existingStepIDs.contains(draft.id),
                   let step = existing.orderedSteps.first(where: { $0.id == draft.id }) {
                    service.updateStep(step, title: draft.title.trimmed(), instructions: draft.instructions)
                    step.orderIndex = index
                } else {
                    let newStep = service.createStep(for: existing, title: draft.title.trimmed(),
                                                     instructions: draft.instructions)
                    newStep.orderIndex = index
                }
            }
        } else {
            // Create new sample work
            let sw = service.createSampleWork(for: lesson, title: title.trimmed(),
                                               workKind: workKind, notes: notes)
            for (index, draft) in draftSteps.enumerated() {
                let step = service.createStep(for: sw, title: draft.title.trimmed(),
                                               instructions: draft.instructions)
                step.orderIndex = index
            }
        }

        onSave()
        dismiss()
    }

    // MARK: - Delete

    private func deleteSampleWork() {
        guard let existing = existingSampleWork else { return }
        let service = SampleWorkService(context: modelContext)
        service.delete(existing)
        onSave()
        dismiss()
    }
}
