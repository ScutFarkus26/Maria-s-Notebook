import SwiftUI
import SwiftData
import OSLog

/// Sheet for adding or editing a LessonExercise.
struct LessonExerciseEditorSheet: View {
    private static let logger = Logger.lessons

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let lesson: Lesson
    var existingExercise: LessonExercise?
    var onSave: () -> Void

    @State private var title: String = ""
    @State private var preparation: String = ""
    @State private var presentationSteps: String = ""
    @State private var notes: String = ""
    @State private var showDeleteAlert = false

    private var isEditing: Bool { existingExercise != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Exercise Details") {
                    TextField("Title (e.g., Exercise 1: Commutative Law)", text: $title)
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.verySmall) {
                        Text("Preparation")
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $preparation)
                            .frame(minHeight: 60)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.verySmall) {
                        Text("Enter one step per line")
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.tertiary)
                        TextEditor(text: $presentationSteps)
                            .frame(minHeight: 140)
                    }
                } header: {
                    Text("Presentation Steps")
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 60)
                }

                if isEditing {
                    Section {
                        Button("Delete Exercise", role: .destructive) {
                            showDeleteAlert = true
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "Edit Exercise" : "Add Exercise")
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
            .alert("Delete Exercise?", isPresented: $showDeleteAlert) {
                Button("Delete", role: .destructive) { deleteExercise() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This action cannot be undone.")
            }
        }
        .onAppear {
            if let exercise = existingExercise {
                title = exercise.title
                preparation = exercise.preparation
                presentationSteps = exercise.presentationSteps
                notes = exercise.notes
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 480)
        #endif
    }

    private func save() {
        let service = LessonExerciseService(context: modelContext)
        if let exercise = existingExercise {
            service.update(
                exercise,
                title: title.trimmed(),
                preparation: preparation,
                presentationSteps: presentationSteps,
                notes: notes
            )
        } else {
            service.createExercise(
                for: lesson,
                title: title.trimmed(),
                preparation: preparation,
                presentationSteps: presentationSteps,
                notes: notes
            )
        }
        onSave()
        dismiss()
    }

    private func deleteExercise() {
        guard let exercise = existingExercise else { return }
        let service = LessonExerciseService(context: modelContext)
        service.delete(exercise)
        onSave()
        dismiss()
    }
}
