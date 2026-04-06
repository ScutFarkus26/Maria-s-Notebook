import SwiftUI
import CoreData

struct AddSequenceSheet: View {
    let student: CDStudent
    let onComplete: () -> Void

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = AddSequenceViewModel()

    var body: some View {
        NavigationStack {
            Form {
                lessonSection
                startDateSection
                spacingSection

                if viewModel.showsOverflowWarning {
                    Section {
                        Label(
                            "\(viewModel.overflowCount) lesson\(viewModel.overflowCount == 1 ? "" : "s") extend\(viewModel.overflowCount == 1 ? "s" : "") past the school year end.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                }

                if !viewModel.previewItems.isEmpty {
                    previewSection
                }
            }
            .navigationTitle("Add Lesson Sequence")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Schedule All") {
                        viewModel.scheduleAll(student: student, context: viewContext)
                        onComplete()
                        dismiss()
                    }
                    .disabled(viewModel.previewItems.isEmpty)
                }
            }
            .onChange(of: viewModel.selectedLesson) { _, _ in
                Task { await viewModel.computePreview(context: viewContext) }
            }
            .onChange(of: viewModel.startDate) { _, _ in
                Task { await viewModel.computePreview(context: viewContext) }
            }
            .onChange(of: viewModel.spacingDays) { _, _ in
                Task { await viewModel.computePreview(context: viewContext) }
            }
        }
    }

    // MARK: - Sections

    private var lessonSection: some View {
        Section("Starting Lesson") {
            NavigationLink {
                LessonSearchPicker(selectedLesson: $viewModel.selectedLesson)
            } label: {
                if let lesson = viewModel.selectedLesson {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lesson.name)
                            .font(.body)
                        Text("\(lesson.subject) \u{00B7} \(lesson.group)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Choose a lesson...")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var startDateSection: some View {
        Section("Start Date") {
            DatePicker(
                "First lesson on",
                selection: $viewModel.startDate,
                displayedComponents: .date
            )
        }
    }

    private var spacingSection: some View {
        Section("Spacing") {
            Stepper(
                "Every \(viewModel.spacingDays) school day\(viewModel.spacingDays == 1 ? "" : "s")",
                value: $viewModel.spacingDays,
                in: 1...10
            )
        }
    }

    private var previewSection: some View {
        Section("Sequence Preview (\(viewModel.previewItems.count) lessons)") {
            ForEach(viewModel.previewItems) { item in
                HStack {
                    Circle()
                        .fill(AppColors.color(forSubject: item.subject))
                        .frame(width: 8, height: 8)
                    Text(item.lessonName)
                        .font(.body)
                        .strikethrough(item.alreadyExists)
                        .foregroundStyle(item.alreadyExists ? .secondary : .primary)
                    Spacer()
                    if item.alreadyExists {
                        Text("Exists")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Text(item.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
