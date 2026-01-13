import SwiftUI
import SwiftData

struct PresentationDetailSheet: View, Identifiable {
    let presentationID: UUID
    var onDone: (() -> Void)? = nil

    var id: UUID { presentationID }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var lessons: [Lesson]
    @Query private var students: [Student]

    @State private var presentation: Presentation? = nil
    @State private var notes: [ScopedNote] = [] // Legacy notes
    @State private var unifiedNotes: [Note] = [] // New unified notes
    @State private var isLoading: Bool = true
    @State private var showAddNoteSheet: Bool = false
    @State private var noteBeingEdited: Note? = nil
    @State private var scopedNoteBeingEdited: ScopedNote? = nil

    init(presentationID: UUID, onDone: (() -> Void)? = nil) {
        self.presentationID = presentationID
        self.onDone = onDone
    }

    private var lessonsByID: [UUID: Lesson] { Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) }) }
    private var studentsByID: [UUID: Student] { Dictionary(uniqueKeysWithValues: students.map { ($0.id, $0) }) }

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }()

    private func title(for p: Presentation) -> String {
        let snap = (p.lessonTitleSnapshot ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !snap.isEmpty { return snap }
        if let lid = UUID(uuidString: p.lessonID), let l = lessonsByID[lid] {
            let t = l.name.trimmingCharacters(in: .whitespacesAndNewlines)
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
                                ChipFlowLayout(spacing: 8) {
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
                            if unifiedNotes.isEmpty && notes.isEmpty {
                                Text("No notes for this presentation")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    // Show new unified notes first
                                    ForEach(unifiedNotes.sorted(by: { $0.createdAt > $1.createdAt }), id: \.id) { note in
                                        unifiedNoteRow(note)
                                    }
                                    // Show legacy ScopedNote objects
                                    ForEach(notes.sorted(by: { $0.createdAt > $1.createdAt }), id: \.id) { note in
                                        noteRow(note)
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
        .sheet(item: $scopedNoteBeingEdited) { scopedNote in
            LegacyNoteEditor(
                title: "Edit Note",
                text: scopedNote.body,
                onSave: { newText in
                    scopedNote.body = newText
                    try? modelContext.save()
                    scopedNoteBeingEdited = nil
                    reloadNotes()
                },
                onCancel: {
                    scopedNoteBeingEdited = nil
                }
            )
        }
        .task { @MainActor in
            #if DEBUG
            let t0 = Date()
            #endif
            isLoading = true
            do {
                let pDesc = FetchDescriptor<Presentation>(predicate: #Predicate { $0.id == presentationID })
                if let fetched = try? modelContext.fetch(pDesc).first {
                    self.presentation = fetched
                } else {
                    self.presentation = nil
                }
                reloadNotes()
            }
            isLoading = false
            #if DEBUG
            let dt = Date().timeIntervalSince(t0) * 1000
            print("[DEBUG] PresentationDetailSheet fetch took \(Int(dt)) ms for \(presentationID.uuidString)")
            #endif
        }
    }

    @ViewBuilder
    private func unifiedNoteRow(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if note.category != .general {
                    Text(note.category.rawValue.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.secondary.opacity(0.1))
                        )
                }
                Spacer()
                Text(Self.dateFormatter.string(from: note.updatedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(note.body)
                .font(.body)
                .foregroundStyle(.primary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .contextMenu {
            Button {
                noteBeingEdited = note
            } label: {
                Label("Edit Note", systemImage: "pencil")
            }
        }
    }
    
    @ViewBuilder
    private func noteRow(_ note: ScopedNote) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(scopeText(for: note.scope))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .overlay(
                        Capsule().stroke(Color.primary.opacity(0.12))
                    )
                Spacer()
                Text(Self.dateFormatter.string(from: note.updatedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(note.body)
                .font(.body)
                .foregroundStyle(.primary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .contextMenu {
            Button {
                scopedNoteBeingEdited = note
            } label: {
                Label("Edit Note", systemImage: "pencil")
            }
        }
    }
    
    @MainActor
    private func reloadNotes() {
        guard let presentation = presentation else { return }
        let pid = presentation.id.uuidString
        
        // Load legacy ScopedNote objects
        let sort: [SortDescriptor<ScopedNote>] = [
            SortDescriptor(\ScopedNote.updatedAt, order: .reverse),
            SortDescriptor(\ScopedNote.createdAt, order: .reverse)
        ]
        let nDesc = FetchDescriptor<ScopedNote>(predicate: #Predicate { $0.presentationID == pid }, sortBy: sort)
        self.notes = (try? modelContext.fetch(nDesc)) ?? []
        
        // Load new unified Note objects from relationship
        // Refresh the presentation object to get updated relationships
        let presentationID = presentation.id
        if let refreshed = try? modelContext.fetch(
            FetchDescriptor<Presentation>(predicate: #Predicate<Presentation> { $0.id == presentationID })
        ).first {
            if let notes = refreshed.notes {
                self.unifiedNotes = Array(notes)
            } else {
                self.unifiedNotes = []
            }
        } else {
            self.unifiedNotes = []
        }
    }

    private func scopeText(for scope: ScopedNote.Scope) -> String {
        switch scope {
        case .all: return "All"
        case .student(_): return "Student"
        case .students(let ids): return ids.isEmpty ? "Group" : "\(ids.count) students"
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
    print("Presentation link set: legacyStudentLessonID=\(p.legacyStudentLessonID ?? "nil")")
    let note = ScopedNote(body: "Group was engaged.", scope: .all, presentation: p)
    ctx.insert(note)
    return PresentationDetailSheet(presentationID: p.id)
        .previewEnvironment(using: container)
}

// Simple flow layout for chips
struct ChipFlowLayout<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder var content: Content

    init(spacing: CGFloat = 8, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        GeometryReader { geometry in
            self.generateContent(in: geometry)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 0)
    }

    private func generateContent(in g: GeometryProxy) -> some View {
        var width = CGFloat.zero
        var height = CGFloat.zero
        return ZStack(alignment: .topLeading) {
            content
                .alignmentGuide(.leading, computeValue: { d in
                    if (abs(width - d.width) > g.size.width) {
                        width = 0
                        height -= d.height + spacing
                    }
                    let result = width
                    if content is EmptyView { width = 0 } else { width -= d.width + spacing }
                    return result
                })
                .alignmentGuide(.top, computeValue: { d in
                    let result = height
                    if content is EmptyView { height = 0 } else { height = height }
                    return result
                })
        }
    }
}
