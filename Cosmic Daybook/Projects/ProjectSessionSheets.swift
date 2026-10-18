import OSLog
import SwiftUI
import CoreData

// MARK: - Project Lesson Picker Sheet

/// Chooses the lesson a project's piece of work belongs to, with the shared
/// `LessonLinkPicker`.
struct ProjectLessonPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// The lesson the work has now, ticked in the list.
    let chosenLessonID: UUID?
    var onChosen: (UUID) -> Void

    var body: some View {
        NavigationStack {
            LessonLinkPicker(chosen: chosenLessonID) { lessonID in
                onChosen(lessonID)
                dismiss()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #else
        .frame(minWidth: 420, minHeight: 480)
        #endif
    }
}

// MARK: - Add Work Offer Sheet

struct AddWorkOfferSheet: View {
    let session: CDProjectSession

    private static let logger = Logger.projects

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(SaveCoordinator.self) private var saveCoordinator

    @State private var title: String = ""
    @State private var instructions: String = ""
    @State private var dueDate: Date

    init(session: CDProjectSession) {
        self.session = session
        dueDate = session.meetingDate ?? Date()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Work Offer")
                .font(.title3).fontWeight(.semibold)

            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 4) {
                Text("Instructions (optional)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $instructions)
                    .frame(minHeight: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium)
                            .stroke(Color.secondary.opacity(UIConstants.OpacityConstants.moderate))
                    )
            }

            DatePicker("Due Date", selection: $dueDate, displayedComponents: .date)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") { addWork() }
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
    #if os(macOS)
        .frame(minWidth: 400)
        .presentationSizingFitted()
    #else
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    #endif
    }

    private func addWork() {
        let service = SessionWorkAssignmentService(context: modelContext)
        do {
            try service.createOfferedWork(
                session: session,
                title: title,
                instructions: instructions,
                dueDate: dueDate
            )
            saveCoordinator.save(modelContext, reason: "Add work offer to session")
        } catch {
            Self.logger.error("Failed to add work offer: \(error.localizedDescription, privacy: .public)")
        }
        dismiss()
    }
}
