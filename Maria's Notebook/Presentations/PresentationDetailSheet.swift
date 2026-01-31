import SwiftUI
import SwiftData

struct PresentationDetailSheet: View, Identifiable {
    let presentationID: UUID
    var onDone: (() -> Void)? = nil

    var id: UUID { presentationID }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    // Test student filtering
    @AppStorage("General.showTestStudents") private var showTestStudents: Bool = false
    @AppStorage("General.testStudentNames") private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    @Query private var lessons: [Lesson]
    @Query private var studentsRaw: [Student]

    // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
    // Filter out test students when setting is disabled
    private var students: [Student] {
        TestStudentsFilter.filterVisible(studentsRaw.uniqueByID, show: showTestStudents, namesRaw: testStudentNamesRaw)
    }

    @State private var presentation: Presentation? = nil
    @State private var unifiedNotes: [Note] = [] // Unified notes
    @State private var isLoading: Bool = true
    @State private var showAddNoteSheet: Bool = false
    @State private var noteBeingEdited: Note? = nil

    init(presentationID: UUID, onDone: (() -> Void)? = nil) {
        self.presentationID = presentationID
        self.onDone = onDone
    }

    // Use uniquingKeysWith to handle CloudKit sync duplicates
    private var lessonsByID: [UUID: Lesson] { Dictionary(lessons.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }) }
    private var studentsByID: [UUID: Student] { Dictionary(students.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }) }

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }()

    private func title(for p: Presentation) -> String {
        let snap = (p.lessonTitleSnapshot ?? "").trimmed()
        if !snap.isEmpty { return snap }
        if let lid = UUID(uuidString: p.lessonID), let l = lessonsByID[lid] {
            let t = l.name.trimmed()
            if !t.isEmpty { return t }
        }
        return "Lesson"
    }

    private func studentList(for p: Presentation) -> [Student] {
        p.studentIDs.compactMap { UUID(uuidString: $0) }.compactMap { studentsByID[$0] }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let p = presentation {
                // Header
                HStack {
                    Text("Presentation Info")
                        .font(.system(size: AppTheme.FontSize.titleSmall, weight: .semibold, design: .rounded))
                    Spacer()
                    Button(action: close) {
                        Text("Done")
                            .fontWeight(.semibold)
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)

                Divider().padding(.top, 8)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(title(for: p))
                                .font(.system(size: AppTheme.FontSize.titleMedium, weight: .heavy, design: .rounded))
                            HStack(spacing: 6) {
                                Image(systemName: "calendar")
                                    .foregroundStyle(.secondary)
                                Text(Self.dateFormatter.string(from: p.presentedAt))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // Students
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "person.2")
                                    .foregroundStyle(.secondary)
                                Text("Students")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                            }
                            let list = studentList(for: p)
                            if list.isEmpty {
                                Text("No students")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else {
                                FlowLayout(spacing: 8) {
                                    ForEach(list, id: \.id) { s in
                                        Text(StudentFormatter.displayName(for: s))
                                            .font(.caption.weight(.semibold))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(
                                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                    .fill(Color.primary.opacity(0.06))
                                            )
                                    }
                                }
                            }
                        }

                        // Notes
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "note.text")
                                    .foregroundStyle(.secondary)
                                Text("Notes")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Button {
                                    showAddNoteSheet = true
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(.accent)
                                }
                            }
                            if unifiedNotes.isEmpty {
                                Text("No notes for this presentation")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    // Show unified notes
                                    ForEach(unifiedNotes.sorted(by: { $0.createdAt > $1.createdAt }), id: \.id) { note in
                                        unifiedNoteRow(note)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 24)
                }
            } else {
                // Loading skeleton
                VStack(spacing: 0) {
                    HStack {
                        Text("Presentation Info")
                            .font(.system(size: AppTheme.FontSize.titleSmall, weight: .semibold, design: .rounded))
                        Spacer()
                        Button(action: close) {
                            Text("Done")
                                .fontWeight(.semibold)
                        }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(true)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 18)

                    Divider().padding(.top, 8)

                    VStack(spacing: 12) {
                        Text("Loading…")
                            .font(.system(size: AppTheme.FontSize.titleMedium, weight: .heavy, design: .rounded))
                        ProgressView()
                            .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 48)
                }
            }
        }
#if os(macOS)
        .frame(minWidth: 520, minHeight: 560)
        .presentationSizingFitted()
#else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
#endif
        .sheet(isPresented: $showAddNoteSheet) {
            if let presentation = presentation {
                UnifiedNoteEditor(
                    context: .presentation(presentation),
                    initialNote: nil,
                    onSave: { _ in
                        // Note is automatically saved via relationship
                        showAddNoteSheet = false
                        reloadNotes()
                    },
                    onCancel: {
                        showAddNoteSheet = false
                    }
                )
            }
        }
        .sheet(item: $noteBeingEdited) { note in
            if let presentation = presentation {
                UnifiedNoteEditor(
                    context: .presentation(presentation),
                    initialNote: note,
                    onSave: { _ in
                        noteBeingEdited = nil
                        reloadNotes()
                    },
                    onCancel: {
                        noteBeingEdited = nil
                    }
                )
            }
        }
        .task { @MainActor in
            isLoading = true
            let pDesc = FetchDescriptor<Presentation>(predicate: #Predicate { $0.id == presentationID })
            if let fetched = modelContext.safeFetchFirst(pDesc) {
                self.presentation = fetched
            } else {
                self.presentation = nil
            }
            reloadNotes()
            isLoading = false
        }
    }

    @ViewBuilder
    private func unifiedNoteRow(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Note body first (like WorkDetailView)
            Text(note.body)
                .font(.system(size: AppTheme.FontSize.body, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)

            // Display image if available
            if let imagePath = note.imagePath {
                AsyncCachedImage(filename: imagePath)
                    .frame(maxWidth: 300, maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            // Metadata row
            HStack(spacing: 8) {
                // Category badge with color
                if note.category != .general {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(categoryColor(for: note.category))
                            .frame(width: 6, height: 6)
                        Text(note.category.rawValue.capitalized)
                            .font(.system(size: AppTheme.FontSize.captionSmall, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(categoryColor(for: note.category).opacity(0.1))
                    )
                }

                Text(note.createdAt, style: .date)
                    .font(.system(size: AppTheme.FontSize.captionSmall, design: .rounded))
                    .foregroundStyle(.tertiary)

                Spacer()

                Button {
                    noteBeingEdited = note
                } label: {
                    Image(systemName: "pencil.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .contextMenu {
            Button {
                noteBeingEdited = note
            } label: {
                Label("Edit Note", systemImage: "pencil")
            }
        }
    }

    private func categoryColor(for category: NoteCategory) -> Color {
        switch category {
        case .general: return .gray
        case .behavioral: return .orange
        case .academic: return .blue
        case .social: return .green
        case .emotional: return .pink
        case .health: return .red
        case .attendance: return .teal
        }
    }
    
    @MainActor
    private func reloadNotes() {
        guard let presentation = presentation else { return }
        
        // Load unified Note objects from relationship
        // Refresh the presentation object to get updated relationships
        let presentationID = presentation.id
        if let refreshed = try? modelContext.fetch(
            FetchDescriptor<Presentation>(predicate: #Predicate<Presentation> { $0.id == presentationID })
        ).first {
            if let notes = refreshed.unifiedNotes {
                self.unifiedNotes = Array(notes)
            } else {
                self.unifiedNotes = []
            }
        } else {
            self.unifiedNotes = []
        }
    }

    private func close() {
        if let onDone { onDone() } else { dismiss() }
    }
}

#Preview {
    let container = ModelContainer.preview
    let ctx = container.mainContext
    let lesson = Lesson(name: "Decimal System", subject: "Math", group: "Number Work", subheading: "", writeUp: "")
    let student = Student(firstName: "Ada", lastName: "Lovelace", birthday: Date(), level: .upper)
    ctx.insert(lesson); ctx.insert(student)
    
    // Try to find a matching StudentLesson if available
    var legacyStudentLessonID: String? = nil
    let allStudentLessons = (try? ctx.fetch(FetchDescriptor<StudentLesson>())) ?? []
    if let matchingSL = allStudentLessons.first(where: { sl in
        sl.lessonID == lesson.id.uuidString && Set(sl.studentIDs) == Set([student.id.uuidString])
    }) {
        legacyStudentLessonID = matchingSL.id.uuidString
    }
    
    let p = Presentation(
        id: UUID(),
        createdAt: Date(),
        presentedAt: Date(),
        lessonID: lesson.id.uuidString,
        studentIDs: [student.id.uuidString],
        legacyStudentLessonID: legacyStudentLessonID,
        lessonTitleSnapshot: lesson.name,
        lessonSubtitleSnapshot: nil
    )
    ctx.insert(p)
    let note = Note(body: "Group was engaged.", scope: .all, presentation: p)
    ctx.insert(note)
    return PresentationDetailSheet(presentationID: p.id)
        .previewEnvironment(using: container)
}

