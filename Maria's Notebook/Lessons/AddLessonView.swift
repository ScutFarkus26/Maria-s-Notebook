import SwiftUI
import SwiftData
import OSLog

struct AddLessonView: View {
    private static let logger = Logger.lessons

    // Optional defaults to prefill when adding from a filtered Albums view
    let defaultSubject: String?
    let defaultGroup: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SaveCoordinator.self) private var saveCoordinator

    private var repository: LessonRepository {
        LessonRepository(context: modelContext, saveCoordinator: saveCoordinator)
    }

    @State private var name: String = ""
    @State private var subject: String = ""
    @State private var group: String = ""
    @State private var subheading: String = ""
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

    init(defaultSubject: String? = nil, defaultGroup: String? = nil) {
        self.defaultSubject = defaultSubject?.trimmed()
        self.defaultGroup = defaultGroup?.trimmed()
    }

    var body: some View {
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

            Form {
                Section("Basics") {
                    TextField("Lesson Name", text: $name)
                    TextField("Subject", text: $subject)
                    TextField("Group", text: $group)
                    TextField("Subheading", text: $subheading)
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
                        let storyLessons: [Lesson] = {
                            let descriptor = FetchDescriptor<Lesson>(
                                predicate: #Predicate { $0.lessonFormatRaw == storyRaw }
                            )
                            return modelContext.safeFetch(descriptor)
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

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button("Add") {
                    let newLesson = repository.createLesson(
                        name: name.trimmed(),
                        subject: subject.trimmed(),
                        group: group.trimmed(),
                        subheading: subheading.trimmed(),
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

                    // Automatically create/update Track object if lesson belongs to a track
                    let subjectTrimmed = newLesson.subject.trimmed()
                    let groupTrimmed = newLesson.group.trimmed()
                    if !subjectTrimmed.isEmpty && !groupTrimmed.isEmpty {
                        let isTrack = GroupTrackService.isTrack(
                            subject: subjectTrimmed, group: groupTrimmed, modelContext: modelContext
                        )
                        if isTrack {
                            do {
                                _ = try GroupTrackService.getOrCreateTrack(
                                    subject: subjectTrimmed,
                                    group: groupTrimmed,
                                    modelContext: modelContext
                                )
                            } catch {
                                // swiftlint:disable:next line_length
                                Self.logger.warning("Failed to create/update Track for \(subjectTrimmed)/\(groupTrimmed): \(error)")
                            }
                        }
                    }

                    if repository.save(reason: "Adding lesson") {
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmed().isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520, height: 720)
        .sheet(isPresented: $showingBulkEntry) {
            BulkLessonsEntryView(
                defaultSubject: subject.trimmed().isEmpty ? defaultSubject : subject,
                defaultGroup: group.trimmed().isEmpty ? defaultGroup : group,
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
            if subject.trimmed().isEmpty, let d = defaultSubject, !d.isEmpty { subject = d }
            if group.trimmed().isEmpty, let g = defaultGroup, !g.isEmpty { group = g }
        }
        .saveErrorAlert()
    }
}

#Preview {
    AddLessonView()
}
