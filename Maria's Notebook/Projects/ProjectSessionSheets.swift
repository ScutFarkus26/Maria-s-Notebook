import OSLog
import SwiftUI
import CoreData

// MARK: - CDProject CDLesson Picker Sheet

/// A minimal wrapper that reuses LessonPickerViewModel to choose a single lesson
struct ProjectLessonPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var modelContext

    let viewModel: LessonPickerViewModel
    var onChosen: (UUID?) -> Void

    @State private var search: String = ""
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDLesson.name, ascending: true)]) private var lessons: FetchedResults<CDLesson>

    init(viewModel: LessonPickerViewModel, onChosen: @escaping (UUID?) -> Void) {
        self.viewModel = viewModel
        self.onChosen = onChosen
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose CDLesson")
                .font(.title3).fontWeight(.semibold)
            TextField("Search…", text: $search)
                .textFieldStyle(.roundedBorder)
            List {
                ForEach(filteredLessons, id: \.objectID) { l in
                    Button {
                        onChosen(l.id)
                        dismiss()
                    } label: {
                        HStack {
                            Text(l.name)
                            Spacer()
                            if viewModel.selectedLessonID == l.id { Image(systemName: "checkmark") }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
            }
        }
        .padding(16)
    #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    #endif
    }

    private var filteredLessons: [CDLesson] {
        let q = search.trimmed()
        let all = Array(lessons)
        if q.isEmpty { return all }
        return all.filter { l in
            l.name.localizedCaseInsensitiveContains(q) ||
            l.subject.localizedCaseInsensitiveContains(q) ||
            l.group.localizedCaseInsensitiveContains(q)
        }
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
        _dueDate = State(initialValue: session.meetingDate ?? Date())
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
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(UIConstants.OpacityConstants.moderate)))
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
