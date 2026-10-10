import SwiftUI
import CoreData

struct WorkStepEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(SaveCoordinator.self) private var saveCoordinator

    let work: CDWorkModel
    var existingStep: CDWorkStep?
    var onSave: () -> Void

    @State private var title: String = ""
    @State private var instructions: String = ""
    @State private var notes: String = ""

    private var isEditing: Bool { existingStep != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Step Details") {
                    TextField("Title", text: $title)
                    TextField("Instructions", text: $instructions, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }

                if isEditing {
                    Section {
                        Button("Delete Step", role: .destructive) {
                            deleteStep()
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Step" : "Add Step")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmed().isEmpty)
                }
            }
        }
        .onAppear {
            if let step = existingStep {
                title = step.title
                instructions = step.instructions
                notes = step.notes
            }
        }
    }

    /// Saves the step on its own Save, through `SaveCoordinator`. It used to
    /// only change the context, so the step waited for some other screen's
    /// save, and Cancel on the work page didn't take it back either. A failed
    /// save takes back just this sheet's change and keeps the sheet open.
    private func save() {
        let service = CDWorkStepServiceImpl(context: modelContext)
        persist(reason: "Save work step", failure: "Couldn't save this step. Try again.") {
            if let step = existingStep {
                try service.update(step, title: title, instructions: instructions, notes: notes)
            } else {
                _ = try service.createStep(for: work, title: title, instructions: instructions, notes: notes)
            }
        }
    }

    private func deleteStep() {
        guard let step = existingStep else { return }
        let service = CDWorkStepServiceImpl(context: modelContext)
        persist(reason: "Delete work step", failure: "Couldn't delete this step. Try again.") {
            try service.delete(step, from: work)
        }
    }

    /// Runs one edit and saves it; on success tells the caller and closes,
    /// on failure undoes only this edit, says so, and stays open.
    private func persist(reason: String, failure message: String, _ edit: () throws -> Void) {
        guard saveCoordinator.saveEdit(in: modelContext, reason: reason, edit) else {
            ToastService.shared.showError(message)
            return
        }
        onSave()
        dismiss()
    }
}
