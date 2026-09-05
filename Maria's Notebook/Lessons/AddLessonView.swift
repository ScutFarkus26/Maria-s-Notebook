import SwiftUI
import OSLog
import CoreData

struct AddLessonView: View {
    private static let logger = Logger.lessons

    // Optional defaults to prefill when adding from a filtered Albums view
    let defaultArea: String?
    let defaultSequence: String?
    let defaultSection: String?
    let onLessonCreated: ((CDLesson) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.managedObjectContext) private var managedObjectContext
    @Environment(SaveCoordinator.self) private var saveCoordinator

    private var repository: LessonRepository {
        LessonRepository(context: managedObjectContext, saveCoordinator: saveCoordinator)
    }

    @State private var name: String = ""
    @State private var area: String = ""
    @State private var sequence: String = ""
    @State private var section: String = ""
    @State private var writeUp: String = ""
    @State private var materials: String = ""
    @State private var purpose: String = ""
    @State private var ageRange: String = ""
    @State private var teacherNotes: String = ""
    @State private var showingBulkEntry: Bool = false

    @State private var source: LessonSource = .album
    @State private var personalKind: PersonalLessonKind = .personal
    @State private var lessonFormat: LessonFormat = .standard
    @State private var parentStoryID: UUID?

    init(
        defaultArea: String? = nil,
        defaultSequence: String? = nil,
        defaultSection: String? = nil,
        onLessonCreated: ((CDLesson) -> Void)? = nil
    ) {
        self.defaultArea = defaultArea?.trimmed()
        self.defaultSequence = defaultSequence?.trimmed()
        self.defaultSection = defaultSection?.trimmed()
        self.onLessonCreated = onLessonCreated
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            addLessonHeader
            addLessonForm
        }
        .padding(24)
        .frame(width: 520, height: 720)
        .sheet(isPresented: $showingBulkEntry) {
            BulkLessonsEntryView(
                defaultArea: area.trimmed().isEmpty ? defaultArea : area,
                defaultSequence: sequence.trimmed().isEmpty ? defaultSequence : sequence,
                onDone: { showingBulkEntry = false }
            )
#if os(macOS)
            .frame(minWidth: 720, minHeight: 560)
            .presentationSizingFitted()
#else
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
#endif
        }
        .onAppear {
            if area.trimmed().isEmpty, let d = defaultArea, !d.isEmpty { area = d }
            if sequence.trimmed().isEmpty, let g = defaultSequence, !g.isEmpty { sequence = g }
            if section.trimmed().isEmpty, let s = defaultSection, !s.isEmpty { section = s }
        }
        .saveErrorAlert()
    }

    private var addLessonHeader: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Add Lesson")
                .font(AppTheme.ScaledFont.titleLarge)

            HStack {
                Spacer()
                Button {
                    showingBulkEntry = true
                } label: {
                    Label("Bulk Entry…", systemImage: "square.grid.3x3")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var addLessonForm: some View {
        VStack {
        Form {
            Section("Basics") {
                    TextField("Lesson Name", text: $name)
                    TextField("Area", text: $area)
                    TextField("Sequence", text: $sequence)
                    TextField("Section", text: $section)
                    Picker("Source", selection: $source) {
                        ForEach(LessonSource.allCases) { s in
                            Text(s.label).tag(s)
                        }
                    }
                    if source == .personal {
                        Picker("Personal Type", selection: $personalKind) {
                            ForEach(PersonalLessonKind.allCases) { k in
                                Text(k.label).tag(k)
                            }
                        }
                    }
                    Picker("Format", selection: $lessonFormat) {
                        ForEach(LessonFormat.allCases) { f in
                            Label(f.label, systemImage: f.icon).tag(f)
                        }
                    }
                    if lessonFormat == .story {
                        let storyRaw = LessonFormat.story.rawValue
                        let storyLessons: [CDLesson] = {
                            let descriptor: NSFetchRequest<CDLesson> = NSFetchRequest(entityName: "Lesson")
        descriptor.predicate = NSPredicate(format: "lessonFormatRaw == %@", storyRaw as CVarArg)
                            return viewContext.safeFetch(descriptor)
                        }()
                        Picker("Parent Story", selection: $parentStoryID) {
                            Text("None (Root Story)").tag(nil as UUID?)
                            ForEach(storyLessons) { story in
                                Text(story.name).tag(story.id as UUID?)
                            }
                        }
                    }
                }

                Section("Montessori Details") {
                    TextField("Age Range (e.g., 6+, 3-6)", text: $ageRange)
                    VStack(alignment: .leading) {
                        Text("Purpose / Learning Objective")
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $purpose)
                            .frame(minHeight: 60)
                    }
                }

                Section("Materials") {
                    VStack(alignment: .leading) {
                        Text("Enter one material per line")
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $materials)
                            .frame(minHeight: 80)
                    }
                }

                Section("Write Up") {
                    TextEditor(text: $writeUp)
                        .frame(minHeight: 140)
                }

                Section("Teacher Notes") {
                    TextEditor(text: $teacherNotes)
                        .frame(minHeight: 80)
                }
            }
            .formStyle(.grouped)

            addLessonActionButtons
        }
    }

    private var addLessonActionButtons: some View {
        HStack {
            Spacer()

            Button("Cancel") {
                dismiss()
            }

            Button("Add") {
                addLesson()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(name.trimmed().isEmpty)
        }
    }

    private func addLesson() {
        let newLesson = repository.createLesson(
            name: name.trimmed(),
            area: area.trimmed(),
            sequence: sequence.trimmed(),
            section: section.trimmed(),
            writeUp: writeUp,
            source: source,
            personalKind: source == .personal ? personalKind : nil,
            materials: materials,
            purpose: purpose.trimmed(),
            ageRange: ageRange.trimmed(),
            teacherNotes: teacherNotes,
            lessonFormat: lessonFormat,
            parentStoryID: lessonFormat == .story ? parentStoryID?.uuidString : nil
        )

        let areaTrimmed: String = newLesson.area.trimmed()
        let groupTrimmed: String = newLesson.sequence.trimmed()
        if !areaTrimmed.isEmpty && !groupTrimmed.isEmpty {
            let isTrack: Bool = SequenceTrackService.isTrack(
                area: areaTrimmed, sequence: groupTrimmed, context: viewContext
            )
            if isTrack {
                do {
                    _ = try SequenceTrackService.getOrCreateTrack(
                        area: areaTrimmed,
                        sequence: groupTrimmed,
                        context: viewContext
                    )
                } catch {
                    let trackMsg = "Failed to create/update CDTrackEntity " +
                        "for \(areaTrimmed)/\(groupTrimmed): \(error)"
                    Self.logger.warning("\(trackMsg, privacy: .public)")
                }
            }
        }

        if repository.save(reason: "Adding lesson") {
            onLessonCreated?(newLesson)
            dismiss()
        }
    }
}

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct AddLessonViewPreview: View {
    var body: some View {
        AddLessonView()
    }
}

#Preview {
    AddLessonViewPreview()
}
