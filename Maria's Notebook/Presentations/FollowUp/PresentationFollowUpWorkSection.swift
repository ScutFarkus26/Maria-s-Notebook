import CoreData
import SwiftUI

/// Captures the child's work after a presentation without changing the guide's
/// separate observation and planning follow-up.
@MainActor
struct PresentationFollowUpWorkSection: View {
    let presentationID: UUID
    let lesson: CDLesson
    let scopedRows: [CDLessonPresentation]
    let students: [CDStudent]
    let linkedWork: [CDWorkModel]
    @Binding var hasUnsavedDraft: Bool
    let onOpenWork: () -> Void

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(SaveCoordinator.self) private var saveCoordinator

    @State private var draftTitle: String
    @State private var draftKind: WorkKind
    @State private var selectedSampleWorkID: UUID?
    @State private var errorMessage: String?
    @State private var restoredDraft: Bool
    @FocusState private var isTitleFocused: Bool

    init(
        presentationID: UUID,
        lesson: CDLesson,
        scopedRows: [CDLessonPresentation],
        students: [CDStudent],
        linkedWork: [CDWorkModel],
        hasUnsavedDraft: Binding<Bool>,
        onOpenWork: @escaping () -> Void
    ) {
        self.presentationID = presentationID
        self.lesson = lesson
        self.scopedRows = scopedRows
        self.students = students
        self.linkedWork = linkedWork
        _hasUnsavedDraft = hasUnsavedDraft
        self.onOpenWork = onOpenWork
        let studentIDs = scopedRows.map(\.studentID)
        let savedDraft = PresentationFollowUpWorkDraftStore.load(
            presentationID: presentationID,
            studentIDs: studentIDs
        )
        draftTitle = savedDraft?.title ?? ""
        draftKind = savedDraft?.kind ?? lesson.defaultWorkKind ?? .followUpAssignment
        selectedSampleWorkID = savedDraft?.sampleWorkID
        restoredDraft = savedDraft != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading
            workEditor

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Could not add work. \(errorMessage)")
            }

            if !workSummaries.isEmpty {
                Divider()
                openWorkSummary
            }
        }
        .padding(16)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
        .onChange(of: lesson.objectID) { _, _ in
            resetDraft()
        }
        .onChange(of: draftTitle) { _, _ in
            synchronizeDraftState()
            persistDraft()
        }
        .onChange(of: draftKind) { _, _ in persistDraft() }
        .onChange(of: selectedSampleWorkID) { _, _ in persistDraft() }
        .onChange(of: draftScopeKey) { _, _ in loadDraftForCurrentScope() }
        .onAppear(perform: synchronizeDraftState)
    }
}

private extension PresentationFollowUpWorkSection {
    var heading: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Child’s Follow-Up Work", systemImage: "pencil.and.list.clipboard")
                .font(.headline)

            Text("What work did you invite or agree they will do? This is optional and separate from your follow-up as the guide.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(scopeDescription)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    var workEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Work invitation (optional)")
                .font(.subheadline.weight(.semibold))

            TextField(
                "Practice, symbolize four sentences, or write a biography…",
                text: $draftTitle
            )
            .textFieldStyle(.roundedBorder)
            .focused($isTitleFocused)
            .onSubmit(addWork)
            .accessibilityLabel("Child’s follow-up work")
            .accessibilityHint("Enter the work in your own words.")

            if restoredDraft {
                Label("Restored unfinished invitation", systemImage: "arrow.counterclockwise")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    workKindPicker
                    suggestionMenu
                    Spacer(minLength: 8)
                    addWorkButton
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        workKindPicker
                        suggestionMenu
                    }
                    addWorkButton
                }
            }

            if let selectedSampleWork {
                HStack(spacing: 6) {
                    Label("Using \(selectedSampleWork.title)", systemImage: "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Remove Template", systemImage: "xmark.circle.fill") {
                        selectedSampleWorkID = nil
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityHint("Keeps the work title but does not copy the template steps.")
                }
            }

            Text("Add Work creates an active item in Children Working for each child in the current scope. It does not schedule a date or change your guide follow-up.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    var workKindPicker: some View {
        Picker("Type", selection: $draftKind) {
            ForEach(WorkKind.allCases) { kind in
                Label(kind.displayName, systemImage: kind.iconName)
                    .tag(kind)
            }
        }
        .pickerStyle(.menu)
        .fixedSize()
        .accessibilityHint("Classifies the work in Children Working.")
    }

    var suggestionMenu: some View {
        Menu {
            Button {
                applySuggestion(
                    title: "Practice \(lesson.name)",
                    kind: .practiceLesson
                )
            } label: {
                Label("Practice \(lesson.name)", systemImage: WorkKind.practiceLesson.iconName)
            }

            if !lesson.suggestedFollowUpWorkItems.isEmpty {
                Divider()
                Section("Lesson Suggestions") {
                    ForEach(Array(lesson.suggestedFollowUpWorkItems.enumerated()), id: \.offset) { _, title in
                        Button(title) {
                            applySuggestion(
                                title: title,
                                kind: lesson.defaultWorkKind ?? .followUpAssignment
                            )
                        }
                    }
                }
            }

            if !lesson.orderedSampleWorks.isEmpty {
                Divider()
                Section("Saved Templates") {
                    ForEach(lesson.orderedSampleWorks, id: \.objectID) { sampleWork in
                        Button {
                            applySuggestion(
                                title: sampleWork.title,
                                kind: sampleWork.workKind ?? .followUpAssignment,
                                sampleWorkID: sampleWork.id
                            )
                        } label: {
                            Label(sampleWork.title, systemImage: "doc.on.doc")
                        }
                    }
                }
            }
        } label: {
            Label("Suggestions", systemImage: "text.badge.plus")
        }
        .fixedSize()
        .accessibilityHint("Fills the field with a lesson suggestion or saved template that you can edit.")
    }

    var addWorkButton: some View {
        Button(action: addWork) {
            Label("Add Work", systemImage: "plus.circle.fill")
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
        .disabled(!canAddWork)
        .accessibilityHint("Adds this work to Children Working. \(scopeDescription).")
    }

    var openWorkSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Already Added", systemImage: "tray.full")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(currentOpenWork.count) \(currentOpenWork.count == 1 ? "item" : "items")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Review Work", systemImage: "arrow.up.right.square") {
                    onOpenWork()
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }

            ForEach(workSummaries) { summary in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: summary.kind.iconName)
                        .foregroundStyle(summary.kind.color)
                        .accessibilityHidden(true)
                    Text(summary.title)
                        .font(.subheadline)
                    Spacer(minLength: 8)
                    Text(summary.audience)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

private extension PresentationFollowUpWorkSection {
    var canAddWork: Bool {
        lesson.id != nil && !scopedRows.isEmpty && !draftTitle.trimmed().isEmpty
    }

    var selectedSampleWork: CDSampleWorkEntity? {
        guard let selectedSampleWorkID else { return nil }
        return lesson.orderedSampleWorks.first { $0.id == selectedSampleWorkID }
    }

    var scopedStudentIDs: Set<String> {
        Set(scopedRows.compactMap { row in
            UUID(uuidString: row.studentID)?.uuidString
        })
    }

    var currentOpenWork: [CDWorkModel] {
        linkedWork.filter { work in
            work.presentationID == presentationID.uuidString
                && work.lessonID == lesson.id?.uuidString
                && scopedStudentIDs.contains(work.studentID)
                && work.status != .complete
        }.uniqueByID
    }

    var scopeDescription: String {
        let names = scopedStudentIDs.compactMap(studentName(for:)).sorted()
        guard names.count == scopedStudentIDs.count else {
            return scopedStudentIDs.isEmpty
                ? "No children selected"
                : "For \(scopedStudentIDs.count) \(scopedStudentIDs.count == 1 ? "child" : "children")"
        }
        switch names.count {
        case 0:
            return "No children selected"
        case 1:
            return "For \(names[0])"
        case 2:
            return "For \(names.joined(separator: " and "))"
        default:
            return "For \(names.count) children"
        }
    }

    var workSummaries: [WorkSummary] {
        let groups = Dictionary(grouping: currentOpenWork) { work in
            WorkSummary.Key(title: work.title, kind: work.kind ?? .followUpAssignment)
        }

        return groups.map { key, work in
            let names = Set(work.compactMap { studentName(for: $0.studentID) }).sorted()
            let audience: String
            if names.count <= 2 {
                audience = names.joined(separator: " and ")
            } else {
                audience = "\(names.count) children"
            }
            return WorkSummary(
                key: key,
                audience: audience,
                newestDate: work.compactMap(\.createdAt).max() ?? .distantPast
            )
        }
        .sorted { lhs, rhs in
            if lhs.newestDate != rhs.newestDate {
                return lhs.newestDate > rhs.newestDate
            }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    func studentName(for studentID: String) -> String? {
        guard let id = UUID(uuidString: studentID),
              let student = students.first(where: { $0.id == id }) else {
            return nil
        }
        return StudentFormatter.displayName(for: student)
    }

    func applySuggestion(
        title: String,
        kind: WorkKind,
        sampleWorkID: UUID? = nil
    ) {
        draftTitle = title
        draftKind = kind
        selectedSampleWorkID = sampleWorkID
        errorMessage = nil
        isTitleFocused = true
        restoredDraft = false
        synchronizeDraftState()
        persistDraft()
    }

    func addWork() {
        guard canAddWork, let lessonID = lesson.id else { return }

        do {
            let result = try PresentationFollowUpWorkService(context: viewContext).createWork(
                title: draftTitle,
                kind: draftKind,
                for: scopedRows,
                presentationID: presentationID,
                lessonID: lessonID,
                sampleWorkID: selectedSampleWorkID,
                persist: {
                    saveCoordinator.save(
                        viewContext,
                        reason: "Adding presentation follow-up work"
                    )
                }
            )

            if result.created.isEmpty {
                ToastService.shared.showInfo("That work is already in Children Working")
            } else {
                let count = result.created.count
                ToastService.shared.showSuccess(
                    count == 1 ? "Work added to Children Working" : "Work added for \(count) children"
                )
            }
            resetDraft()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resetDraft() {
        PresentationFollowUpWorkDraftStore.clear(
            presentationID: presentationID,
            studentIDs: draftStudentIDs
        )
        draftTitle = ""
        draftKind = lesson.defaultWorkKind ?? .followUpAssignment
        selectedSampleWorkID = nil
        errorMessage = nil
        restoredDraft = false
        hasUnsavedDraft = false
    }

    func synchronizeDraftState() {
        hasUnsavedDraft = !draftTitle.trimmed().isEmpty
    }

    var draftStudentIDs: [String] {
        scopedRows.map(\.studentID)
    }

    var draftScopeKey: String {
        draftStudentIDs.sorted().joined(separator: ",")
    }

    func persistDraft() {
        PresentationFollowUpWorkDraftStore.save(
            presentationID: presentationID,
            studentIDs: draftStudentIDs,
            title: draftTitle,
            kind: draftKind,
            sampleWorkID: selectedSampleWorkID
        )
    }

    func loadDraftForCurrentScope() {
        let saved = PresentationFollowUpWorkDraftStore.load(
            presentationID: presentationID,
            studentIDs: draftStudentIDs
        )
        draftTitle = saved?.title ?? ""
        draftKind = saved?.kind ?? lesson.defaultWorkKind ?? .followUpAssignment
        selectedSampleWorkID = saved?.sampleWorkID
        restoredDraft = saved != nil
        synchronizeDraftState()
    }

    struct WorkSummary: Identifiable {
        struct Key: Hashable {
            let title: String
            let kind: WorkKind
        }

        let key: Key
        let audience: String
        let newestDate: Date

        var id: Key { key }
        var title: String { key.title }
        var kind: WorkKind { key.kind }
    }
}
