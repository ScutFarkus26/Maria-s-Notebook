//
//  LessonAssignmentDetailSheet.swift
//  Maria's Notebook
//
//  Detail view for a presented LessonAssignment.
//  Phase 5 migration: This sheet reads from LessonAssignment instead of Presentation.
//

import SwiftUI
import SwiftData
import OSLog

struct LessonAssignmentDetailSheet: View, Identifiable {
    private static let logger = Logger.presentations
    let assignmentID: UUID
    var onDone: (() -> Void)? = nil

    var id: UUID { assignmentID }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    // Test student filtering
    @AppStorage(UserDefaultsKeys.generalShowTestStudents) private var showTestStudents: Bool = false
    @AppStorage(UserDefaultsKeys.generalTestStudentNames) private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    @Query private var lessons: [Lesson]
    @Query private var studentsRaw: [Student]

    // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
    // Filter out test students when setting is disabled
    private var students: [Student] {
        TestStudentsFilter.filterVisible(studentsRaw.uniqueByID, show: showTestStudents, namesRaw: testStudentNamesRaw)
    }

    @State private var assignment: LessonAssignment?
    @State private var unifiedNotes: [Note] = []
    @State private var isLoading: Bool = true
    @State private var showAddNoteSheet: Bool = false
    @State private var noteBeingEdited: Note?
    @State private var showingEditSheet = false

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
                    Button("Edit") {
                        showingEditSheet = true
                    }
                    .buttonStyle(.bordered)
                    .disabled(studentList(for: la).isEmpty)
                    
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
                                    Image(systemName: SFSymbol.Time.calendar)
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
                                    Label("Needs Another Presentation", systemImage: SFSymbol.Action.arrowCounterclockwise)
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
                        
                        // Work Items Summary
                        workSummarySection(for: la)

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
        .sheet(isPresented: $showingEditSheet) {
            editPresentationSheet
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
    
    // MARK: - Work Summary Section
    
    @ViewBuilder
    private func workSummarySection(for presentation: LessonAssignment) -> some View {
        let workItems = presentation.fetchRelatedWork(from: modelContext)
        
        if !workItems.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "folder.badge.gearshape")
                        .foregroundStyle(.blue)
                    Text("Related Work")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    // Completion stats
                    let stats = presentation.workCompletionStats(from: modelContext)
                    if stats.total > 0 {
                        HStack(spacing: 4) {
                            Text("\(stats.completed)/\(stats.total)")
                                .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                        }
                        .foregroundStyle(stats.completed == stats.total ? .green : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill((stats.completed == stats.total ? Color.green : Color.secondary).opacity(0.1))
                        )
                    }
                }
                
                VStack(spacing: 8) {
                    ForEach(workItems) { work in
                        WorkItemCompactRow(work: work, modelContext: modelContext)
                    }
                }
                
                // Practice sessions for this presentation's work
                let practiceSessions = presentation.fetchRelatedPracticeSessions(from: modelContext)
                if !practiceSessions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 14, weight: .medium))
                            Text("Practice Sessions (\(practiceSessions.count))")
                                .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(.purple)
                        
                        ForEach(practiceSessions.prefix(3)) { session in
                            PracticeSessionCompactRow(session: session)
                        }
                        
                        if practiceSessions.count > 3 {
                            Text("+ \(practiceSessions.count - 3) more sessions")
                                .font(.system(size: AppTheme.FontSize.captionSmall, design: .rounded))
                                .foregroundStyle(.tertiary)
                                .padding(.leading, 8)
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.purple.opacity(0.05))
                    )
                }
            }
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
                // Tag badges
                if !note.tags.isEmpty {
                    ForEach(note.tags.prefix(2), id: \.self) { tag in
                        TagBadge(tag: tag, compact: true)
                    }
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
                Label("Edit Note", systemImage: SFSymbol.Education.pencil)
            }
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
        do {
            if let refreshed = try modelContext.fetch(descriptor).first {
                if let notes = refreshed.unifiedNotes {
                    self.unifiedNotes = Array(notes)
                } else {
                    self.unifiedNotes = []
                }
            } else {
                self.unifiedNotes = []
            }
        } catch {
            Self.logger.warning("Failed to fetch refreshed assignment: \(error)")
            self.unifiedNotes = []
        }
    }
    
    @ViewBuilder
    private var editPresentationSheet: some View {
        if let la = assignment, let lessonIDString = la.lessonIDUUID {
            UnifiedPresentationWorkflowSheet(
                students: studentList(for: la),
                lessonName: title(for: la),
                lessonID: lessonIDString,
                onComplete: {
                    // Work items are created by the workflow sheet
                    showingEditSheet = false
                    reloadNotes()
                },
                onCancel: {
                    showingEditSheet = false
                }
            )
        }
    }
    
    @MainActor
    private func updatePresentation(status: UnifiedPostPresentationSheet.PresentationStatus, entries: [UnifiedPostPresentationSheet.StudentEntry], groupObservation: String) {
        guard let la = assignment else { return }
        
        // Update presentation state
        switch status {
        case .justPresented:
            la.state = .presented
            la.presentedAt = Date()
            la.needsAnotherPresentation = false
        case .previouslyPresented:
            la.state = .presented
            la.needsAnotherPresentation = false
        case .needsAnother:
            la.state = .scheduled
            la.needsAnotherPresentation = true
        }
        
        // Update notes with group observation
        if !groupObservation.isEmpty {
            if la.notes.isEmpty {
                la.notes = groupObservation
            } else {
                la.notes += "\n\n" + groupObservation
            }
        }
        
        // Save changes
        do {
            try modelContext.save()
        } catch {
            Self.logger.warning("Failed to save presentation updates: \(error)")
        }
        
        // Reload the assignment to reflect changes
        let targetID = assignmentID
        let descriptor = FetchDescriptor<LessonAssignment>(predicate: #Predicate { $0.id == targetID })
        if let refreshed = modelContext.safeFetchFirst(descriptor) {
            self.assignment = refreshed
        }
        reloadNotes()
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
