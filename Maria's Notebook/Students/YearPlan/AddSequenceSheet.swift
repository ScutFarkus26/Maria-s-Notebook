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
            formContent
                .navigationTitle("Add Lesson Sequence")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { formToolbar }
                .task {
                    viewModel.loadAreasAndSequences(context: viewContext)
                }
                .onChange(of: viewModel.selectionMode) { _, _ in
                    viewModel.selectedArea = nil
                    viewModel.selectedSequence = nil
                    viewModel.selectedLesson = nil
                }
                .onChange(of: viewModel.selectedArea) { _, _ in
                    viewModel.selectedSequence = nil
                    viewModel.selectedLesson = nil
                }
                .onChange(of: viewModel.selectedSequence) { _, newSequence in
                    if let area = viewModel.selectedArea, let sequence = newSequence {
                        viewModel.selectSequence(
                            area: area, sequence: sequence,
                            student: student, context: viewContext
                        )
                    }
                }
                .onChange(of: viewModel.selectedLesson) { _, _ in
                    refreshPreview()
                }
                .onChange(of: viewModel.startDate) { _, _ in
                    refreshPreview()
                }
                .onChange(of: viewModel.spacingDays) { _, _ in
                    refreshPreview()
                }
        }
    }

    private var formContent: some View {
        Form {
            lessonSection
            startDateSection
            spacingSection
            overflowWarningSection
            if !viewModel.previewItems.isEmpty {
                previewSection
            }
        }
    }

    @ViewBuilder
    private var overflowWarningSection: some View {
        if viewModel.showsOverflowWarning {
            let count: Int = viewModel.overflowCount
            let noun: String = count == 1 ? "lesson" : "lessons"
            let verb: String = count == 1 ? "extends" : "extend"
            Section {
                Label(
                    "\(count) \(noun) \(verb) past the school year end.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
    }

    @ToolbarContentBuilder
    private var formToolbar: some ToolbarContent {
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

    private func refreshPreview() {
        Task { await viewModel.computePreview(student: student, context: viewContext) }
    }

    // MARK: - Sections

    private var lessonSection: some View {
        Section {
            Picker("Selection Mode", selection: $viewModel.selectionMode) {
                ForEach(AddSequenceViewModel.SelectionMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if viewModel.selectionMode == .sequence {
                groupPickerContent
            } else {
                lessonPickerContent
            }
        } header: {
            Text(viewModel.selectionMode == .sequence ? "Curriculum Group" : "Starting Lesson")
        }
    }

    @ViewBuilder
    private var groupPickerContent: some View {
        Picker("Area", selection: $viewModel.selectedArea) {
            Text("Select a area").tag(nil as String?)
            ForEach(viewModel.areas, id: \.self) { area in
                Text(area).tag(area as String?)
            }
        }

        if viewModel.selectedArea != nil {
            Picker("Sequence", selection: $viewModel.selectedSequence) {
                Text("Select a sequence").tag(nil as String?)
                ForEach(viewModel.availableSequences, id: \.self) { sequence in
                    Text(sequence).tag(sequence as String?)
                }
            }
        }

        if let lesson = viewModel.selectedLesson, viewModel.selectedSequence != nil {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.allLessonsPresentedInSequence
                         ? "All lessons presented — restarting from:"
                         : "Starting at:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(lesson.name)
                        .font(.body)
                }
                Spacer()
                Circle()
                    .fill(AppColors.color(forArea: lesson.area))
                    .frame(width: 8, height: 8)
            }
        }
    }

    private var lessonPickerContent: some View {
        NavigationLink {
            LessonSearchPicker(selectedLesson: $viewModel.selectedLesson)
        } label: {
            if let lesson = viewModel.selectedLesson {
                VStack(alignment: .leading, spacing: 2) {
                    Text(lesson.name)
                        .font(.body)
                    Text("\(lesson.area) \u{00B7} \(lesson.sequence)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Choose a lesson...")
                    .foregroundStyle(.secondary)
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
                        .fill(AppColors.color(forArea: item.area))
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
