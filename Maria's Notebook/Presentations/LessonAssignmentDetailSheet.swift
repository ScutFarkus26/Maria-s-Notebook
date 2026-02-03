//
//  LessonAssignmentDetailSheet.swift
//  Maria's Notebook
//
//  Detail view for a presented LessonAssignment.
//  Phase 5 migration: This sheet reads from LessonAssignment instead of Presentation.
//

import SwiftUI
import SwiftData

struct LessonAssignmentDetailSheet: View, Identifiable {
    let assignmentID: UUID
    var onDone: (() -> Void)? = nil

    var id: UUID { assignmentID }

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

    @State private var assignment: LessonAssignment? = nil
    @State private var unifiedNotes: [Note] = []
    @State private var isLoading: Bool = true
    @State private var showAddNoteSheet: Bool = false
    @State private var noteBeingEdited: Note? = nil

    init(assignmentID: UUID, onDone: (() -> Void)? = nil) {
        self.assignmentID = assignmentID
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

    private func title(for la: LessonAssignment) -> String {
        let snap = (la.lessonTitleSnapshot ?? "").trimmed()
        if !snap.isEmpty { return snap }
        if let lid = la.lessonIDUUID, let l = lessonsByID[lid] {
            let t = l.name.trimmed()
            if !t.isEmpty { return t }
        }
        return "Lesson"
    }

    private func studentList(for la: LessonAssignment) -> [Student] {
        la.studentUUIDs.compactMap { studentsByID[$0] }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let la = assignment {
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
                            Text(title(for: la))
                                .font(.system(size: AppTheme.FontSize.titleMedium, weight: .heavy, design: .rounded))
                            if let presentedAt = la.presentedAt {
                                HStack(spacing: 6) {
                                    Image(systemName: "calendar")
                                        .foregroundStyle(.secondary)
                                    Text(Self.dateFormatter.string(from: presentedAt))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        // State badge
                        HStack(spacing: 8) {
                            Image(systemName: stateBadgeIcon(for: la.state))
                                .foregroundStyle(stateBadgeColor(for: la.state))
                            Text(la.stateDescription)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
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
                            let list = studentList(for: la)
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

                        // Planning flags (if any are set)
                        if la.needsPractice || la.needsAnotherPresentation || !la.followUpWork.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Image(systemName: "flag")
                                        .foregroundStyle(.orange)
                                    Text("Follow-Up")
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                }

                                if la.needsPractice {
                                    Label("Needs Practice", systemImage: "arrow.triangle.2.circlepath")
                                        .font(.subheadline)
                                        .foregroundStyle(.orange)
                                }

                                if la.needsAnotherPresentation {
                                    Label("Needs Another Presentation", systemImage: "arrow.counterclockwise")
                                        .font(.subheadline)
                                        .foregroundStyle(.orange)
                                }

                                if !la.followUpWork.isEmpty {
                                    Text(la.followUpWork)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .padding(10)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color.orange.opacity(0.1))
                                        )
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

                        // General notes field (if any)
                        if !la.notes.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Image(systemName: "doc.text")
                                        .foregroundStyle(.secondary)
                                    Text("Assignment Notes")
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                }
                                Text(la.notes)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
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
                        Text("Loading...")
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
            if let assignment = assignment {
                UnifiedNoteEditor(
                    context: .presentation(assignment),
                    initialNote: nil,
                    onSave: { _ in
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
            if let assignment = assignment {
                UnifiedNoteEditor(
                    context: .presentation(assignment),
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
            let targetID = assignmentID
            let descriptor = FetchDescriptor<LessonAssignment>(predicate: #Predicate { $0.id == targetID })
            if let fetched = modelContext.safeFetchFirst(descriptor) {
                self.assignment = fetched
            } else {
                self.assignment = nil
            }
            reloadNotes()
            isLoading = false
        }
    }

    // MARK: - State Badge Helpers

    private func stateBadgeIcon(for state: LessonAssignmentState) -> String {
        switch state {
        case .draft: return "doc"
        case .scheduled: return "calendar"
        case .presented: return "checkmark.circle.fill"
        }
    }

    private func stateBadgeColor(for state: LessonAssignmentState) -> Color {
        switch state {
        case .draft: return .gray
        case .scheduled: return .blue
        case .presented: return .green
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
        guard let assignment = assignment else { return }

        // Load unified Note objects from relationship
        // Refresh the assignment object to get updated relationships
        let targetID = assignment.id
        var descriptor = FetchDescriptor<LessonAssignment>(predicate: #Predicate<LessonAssignment> { $0.id == targetID })
        descriptor.fetchLimit = 1
        if let refreshed = try? modelContext.fetch(descriptor).first {
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

    let la = LessonAssignment(
        lesson: lesson,
        students: [student],
        state: .presented,
        scheduledFor: nil
    )
    la.presentedAt = Date()
    la.lessonTitleSnapshot = lesson.name
    ctx.insert(la)

    let note = Note(body: "Group was engaged.", scope: .all, lessonAssignment: la)
    ctx.insert(note)

    return LessonAssignmentDetailSheet(assignmentID: la.id)
        .previewEnvironment(using: container)
}
