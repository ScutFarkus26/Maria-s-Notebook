// swiftlint:disable file_length
//
//  LessonAssignmentDetailSheet.swift
//  Maria's Notebook
//
//  Detail view for a presented CDLessonAssignment.
//  Phase 5 migration: This sheet reads from CDLessonAssignment instead of Presentation.
//

import SwiftUI
import CoreData
import OSLog

// swiftlint:disable:next type_body_length
struct LessonAssignmentDetailSheet: View, Identifiable {
    static let logger = Logger.presentations
    let assignmentID: UUID
    var onDone: (() -> Void)?

    var id: UUID { assignmentID }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) var viewContext

    // Test student filtering
    @AppStorage(UserDefaultsKeys.generalShowTestStudents) private var showTestStudents: Bool = false
    @AppStorage(UserDefaultsKeys.generalTestStudentNames)
    private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    @FetchRequest(sortDescriptors: []) private var lessons: FetchedResults<CDLesson>
    @FetchRequest(sortDescriptors: []) private var studentsRaw: FetchedResults<CDStudent>

    // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
    // Filter out test students when setting is disabled
    private var students: [CDStudent] {
        TestStudentsFilter.filterVisible(
            Array(studentsRaw).uniqueByID.filter(\.isEnrolled), show: showTestStudents,
            namesRaw: testStudentNamesRaw
        )
    }

    @State var assignment: CDLessonAssignment?
    @State var unifiedNotes: [CDNote] = []
    @State private var isLoading: Bool = true
    @State private var showAddNoteSheet: Bool = false
    @State var noteBeingEdited: CDNote?
    @State private var showingEditSheet = false

    init(assignmentID: UUID, onDone: (() -> Void)? = nil) {
        self.assignmentID = assignmentID
        self.onDone = onDone
    }

    // Use uniquingKeysWith to handle CloudKit sync duplicates
    private var lessonsByID: [UUID: CDLesson] {
        Dictionary(lessons.compactMap { guard let id = $0.id else { return nil }; return (id, $0) }, uniquingKeysWith: { first, _ in first })
    }
    private var studentsByID: [UUID: CDStudent] {
        Dictionary(students.compactMap { guard let id = $0.id else { return nil }; return (id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func title(for la: CDLessonAssignment) -> String {
        let snap = (la.lessonTitleSnapshot ?? "").trimmed()
        if !snap.isEmpty { return snap }
        if let lid = la.lessonIDUUID, let l = lessonsByID[lid] {
            let t = l.name.trimmed()
            if !t.isEmpty { return t }
        }
        return "Lesson"
    }

    private func studentList(for la: CDLessonAssignment) -> [CDStudent] {
        la.studentUUIDs.compactMap { studentsByID[$0] }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let la = assignment {
                // Header
                HStack {
                    Text("Presentation Info")
                        .font(AppTheme.ScaledFont.titleSmall)
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
                                .font(AppTheme.ScaledFont.titleMedium)
                            if let presentedAt = la.presentedAt {
                                HStack(spacing: 6) {
                                    Image(systemName: SFSymbol.Time.calendar)
                                        .foregroundStyle(.secondary)
                                    Text(DateFormatters.mediumDateTime.string(from: presentedAt))
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
                                                    .fill(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
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
                                        .foregroundStyle(AppColors.warning)
                                    Text("Follow-Up")
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                }

                                if la.needsPractice {
                                    Label("Needs Practice", systemImage: "arrow.triangle.2.circlepath")
                                        .font(.subheadline)
                                        .foregroundStyle(AppColors.warning)
                                }

                                if la.needsAnotherPresentation {
                                    Label(
                                        "Needs Another Presentation",
                                        systemImage: SFSymbol.Action.arrowCounterclockwise
                                    )
                                        .font(.subheadline)
                                        .foregroundStyle(AppColors.warning)
                                }

                                if !la.followUpWork.isEmpty {
                                    Text(la.followUpWork)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .padding(10)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color.orange.opacity(UIConstants.OpacityConstants.light))
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
                                    ForEach(
                                        unifiedNotes.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) },
                                        id: \.objectID
                                    ) { note in
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
                            .font(AppTheme.ScaledFont.titleSmall)
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
                            .font(AppTheme.ScaledFont.titleMedium)
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
            if let assignment {
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
            if let assignment {
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
            let descriptor = { let r = NSFetchRequest<CDLessonAssignment>(entityName: "LessonAssignment"); r.predicate = NSPredicate(format: "id == %@", targetID as CVarArg); r.fetchLimit = 1; return r }()
            if let fetched = viewContext.safeFetchFirst(descriptor) {
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
    private func updatePresentation(
        status: UnifiedPostPresentationSheet.PresentationStatus,
        entries: [UnifiedPostPresentationSheet.StudentEntry],
        groupObservation: String
    ) {
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
            try viewContext.save()
        } catch {
            Self.logger.warning("Failed to save presentation updates: \(error)")
        }
        
        // Reload the assignment to reflect changes
        let targetID = assignmentID
        let descriptor = { let r = NSFetchRequest<CDLessonAssignment>(entityName: "LessonAssignment"); r.predicate = NSPredicate(format: "id == %@", targetID as CVarArg); r.fetchLimit = 1; return r }()
        if let refreshed = viewContext.safeFetchFirst(descriptor) {
            self.assignment = refreshed
        }
        reloadNotes()
    }

    private func close() {
        if let onDone { onDone() } else { dismiss() }
    }
}

#Preview {
    let ctx = CoreDataStack.preview.viewContext

    let lesson = CDLesson(context: ctx)
    lesson.name = "Decimal System"
    lesson.subject = "Math"
    lesson.group = "Number Work"

    let student = CDStudent(context: ctx)
    student.firstName = "Ada"
    student.lastName = "Lovelace"
    student.birthday = Date()
    student.level = .upper

    let la = CDLessonAssignment(context: ctx)
    la.state = .presented
    la.presentedAt = Date()
    la.lessonTitleSnapshot = lesson.name
    la.lessonIDUUID = lesson.id
    la.studentIDs = [student.id?.uuidString ?? UUID().uuidString]

    return LessonAssignmentDetailSheet(assignmentID: la.id ?? UUID())
        .previewEnvironment()
}
