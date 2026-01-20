import SwiftUI
import SwiftData

struct WorkStepEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let work: WorkModel
    var existingStep: WorkStep?
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
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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

    private func save() {
        let service = WorkStepService(context: modelContext)

        if let step = existingStep {
            try? service.update(step, title: title, instructions: instructions, notes: notes)
        } else {
            _ = try? service.createStep(for: work, title: title, instructions: instructions, notes: notes)
        }

        onSave()
        dismiss()
    }

    private func deleteStep() {
        guard let step = existingStep else { return }
        let service = WorkStepService(context: modelContext)
        try? service.delete(step, from: work)
        onSave()
        dismiss()
    }
}
