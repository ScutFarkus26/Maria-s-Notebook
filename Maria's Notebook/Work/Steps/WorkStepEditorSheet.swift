import OSLog
import SwiftUI
import CoreData

struct WorkStepEditorSheet: View {
    private static let logger = Logger.work

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var modelContext

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

    private func save() {
        let service = CDWorkStepServiceImpl(context: modelContext)

        do {
            if let step = existingStep {
                try service.update(step, title: title, instructions: instructions, notes: notes)
            } else {
                _ = try service.createStep(for: work, title: title, instructions: instructions, notes: notes)
            }
        } catch {
            Self.logger.warning("Failed to save work step: \(error)")
        }

        onSave()
        dismiss()
    }

    private func deleteStep() {
        guard let step = existingStep else { return }
        let service = CDWorkStepServiceImpl(context: modelContext)
        do {
            try service.delete(step, from: work)
        } catch {
            Self.logger.warning("Failed to delete work step: \(error)")
        }
        onSave()
        dismiss()
    }
}
