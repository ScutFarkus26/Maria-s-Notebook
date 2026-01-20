import SwiftUI
import SwiftData
import Foundation

/// Unified detail view for viewing and editing work items
/// Replaces: WorkModelDetailSheet, WorkDetailWindowContainer, WorkDetailContainerView
struct WorkDetailView: View {
    let workID: UUID
    var onDone: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var saveCoordinator: SaveCoordinator

    @State private var work: WorkModel? = nil

    // OPTIMIZATION: Load only related lessons and students instead of all
    @State private var relatedLesson: Lesson? = nil
    @State private var relatedLessons: [Lesson] = [] // For NextLessonResolver - same subject/group
    @State private var relatedStudent: Student? = nil

    @State private var workModelNotes: [Note] = [] // Unified notes - loaded via relationship
    @Query private var presentations: [Presentation]
    @Query private var planItems: [WorkPlanItem]
    @Query private var peerWorks: [WorkModel]

    @State private var resolvedPresentationID: UUID? = nil
    @State private var showPresentationNotes: Bool = true
    @State private var showAddNoteSheet: Bool = false
    @State private var noteBeingEdited: Note? = nil
    @State private var showScheduleSheet: Bool = false
    @State private var showPlannedBanner: Bool = false
    @State private var showDeleteAlert: Bool = false
    @State private var showAddStepSheet: Bool = false
    @State private var stepBeingEdited: WorkStep? = nil

    @State private var status: WorkStatus
    @State private var workKind: WorkKind
    @State private var workTitle: String = ""
    @State private var completionOutcome: CompletionOutcome? = nil
    @State private var completionNote: String = ""

    @State private var newPlanDate: Date = Date()
    @State private var newPlanReason: WorkPlanItem.Reason = .progressCheck
    @State private var newPlanNote: String = ""

    private var scheduleDates: WorkScheduleDates {
        guard let work = work else {
            return WorkScheduleDates(primaryDate: nil, primaryKind: nil, secondaryDate: nil, secondaryKind: nil)
        }
        let workIDString = work.id.uuidString
        let items = planItems.filter { $0.workID == workIDString }
        return WorkScheduleDateLogic.compute(forPlanItems: items)
    }

    private var likelyNextLesson: Lesson? {
        guard let work = work,
              let currentLessonID = UUID(uuidString: work.lessonID),
              relatedLessons.first(where: { $0.id == currentLessonID }) != nil else { return nil }
        return NextLessonResolver.resolveNextLesson(from: currentLessonID, lessons: relatedLessons)
    }

    init(workID: UUID, onDone: (() -> Void)? = nil) {
        self.workID = workID
        self.onDone = onDone
        // Initialize with default values - will be updated when work is loaded
        _status = State(initialValue: .active)
        _workTitle = State(initialValue: "")
        _completionOutcome = State(initialValue: nil)
        _completionNote = State(initialValue: "")
        _workKind = State(initialValue: .practiceLesson)

        let workIDString = workID.uuidString
        _planItems = Query(filter: #Predicate<WorkPlanItem> { $0.workID == workIDString })
        // Query for peer works - will filter by lessonID after work is loaded
        _peerWorks = Query()
    }

    var body: some View {
        Group {
            if let work = work {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            headerSection()
                            Divider()
                            if status == .complete { completionSection(); Divider() }
                            if workKind == .report { stepsSection(); Divider() }
                            calendarSection()
                            Divider()
                            notesSection()

                            Button(role: .destructive) { showDeleteAlert = true } label: {
                                Label("Delete Work", systemImage: "trash")
                            }.frame(maxWidth: .infinity).padding(.top, 20)
                        }.padding(24)
                    }
                    Divider()
                    HStack {
                        Button("Cancel") { close() }
                        Spacer()
                        Button("Save") { save() }.buttonStyle(.borderedProminent)
                    }.padding(16).background(.bar)
                }
                .sheet(isPresented: $showScheduleSheet) {
                    WorkModelScheduleNextLessonSheet(work: work) { showPlannedBanner = true }
                }
                .sheet(isPresented: $showAddNoteSheet) {
                    UnifiedNoteEditor(
                        context: .work(work),
                        initialNote: nil,
                        onSave: { _ in
                            // Note is automatically saved via relationship
                            showAddNoteSheet = false
                            loadWorkNotes() // Reload notes
                        },
                        onCancel: {
                            showAddNoteSheet = false
                        }
                    )
                }
                .sheet(item: $noteBeingEdited) { note in
                    UnifiedNoteEditor(
                        context: .work(work),
                        initialNote: note,
                        onSave: { _ in
                            noteBeingEdited = nil
                            loadWorkNotes() // Reload notes
                        },
                        onCancel: {
                            noteBeingEdited = nil
                        }
                    )
                }
                .alert("Delete?", isPresented: $showDeleteAlert) {
                    Button("Delete", role: .destructive) { deleteWork() }
                }
                .sheet(isPresented: $showAddStepSheet) {
                    WorkStepEditorSheet(work: work, existingStep: nil) {
                        // Step was added - force refresh
                    }
                }
                .sheet(item: $stepBeingEdited) { step in
                    WorkStepEditorSheet(work: work, existingStep: step) {
                        stepBeingEdited = nil
                    }
                }
            } else {
                ContentUnavailableView("Work not found", systemImage: "doc.questionmark")
                    #if os(macOS)
                    .frame(minWidth: 400, minHeight: 200)
                    #endif
            }
        }
        .onAppear {
            loadWork()
            if work != nil {
                #if DEBUG
                PerformanceLogger.logScreenLoad(
                    screenName: "WorkDetailView",
                    itemCounts: [
                        "lessons": relatedLessons.count,
                        "students": relatedStudent != nil ? 1 : 0,
                        "workModelNotes": workModelNotes.count,
                        "presentations": presentations.count,
                        "planItems": planItems.count,
                        "peerWorks": peerWorks.count
                    ]
                )
                #endif
                resolvedPresentationID = resolvePresentationID()
                reloadPresentationNotes()
            }
        }
    }

    private func loadWork() {
        let descriptor = FetchDescriptor<WorkModel>(predicate: #Predicate { $0.id == workID })
        let fetchedWork = try? modelContext.fetch(descriptor).first
        work = fetchedWork

        if let fetchedWork = fetchedWork {
            status = fetchedWork.status
            workTitle = fetchedWork.title
            workKind = fetchedWork.kind ?? .practiceLesson
            completionOutcome = fetchedWork.completionOutcome
            // Note: WorkModel doesn't have completionNote field, so we'll leave it empty
            completionNote = ""

            // Load related data immediately after work is loaded
            // Pass the work directly since @State hasn't updated yet
            loadRelatedData(for: fetchedWork)
            loadWorkNotes(for: fetchedWork)
        }
    }

    @ViewBuilder
    private func headerSection() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Row 1: Student name + Work title
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(studentName())
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .layoutPriority(1)
                TextField("Work Title", text: $workTitle)
                    .font(.title3)
                    .padding(8)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(8)
            }

            // Row 2: Lesson info
            Label(lessonTitle(), systemImage: "book.closed")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Row 3: Work kind buttons
            HStack(spacing: 0) {
                kindBtn(.practiceLesson, "Practice")
                kindBtn(.followUpAssignment, "Follow-Up")
                kindBtn(.research, "Project")
                kindBtn(.report, "Report")
            }
            .background(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1)))

            // Row 4: Status buttons
            HStack(spacing: 12) {
                HStack(spacing: 0) {
                    statusBtn(.active, "Active")
                    statusBtn(.review, "Review")
                    statusBtn(.complete, "Complete")
                }
                .background(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1)))

                if status != .complete, likelyNextLesson != nil {
                    Button { showScheduleSheet = true } label: {
                        Image(systemName: "lock.open.fill")
                            .padding(8)
                            .background(Color.accentColor.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
            }
        }
    }

    @ViewBuilder private func kindBtn(_ kind: WorkKind, _ label: String) -> some View {
        Button(label) {
            workKind = kind
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(workKind == kind ? Color.accentColor.opacity(0.1) : Color.clear)
        .foregroundStyle(workKind == kind ? Color.accentColor : .primary)
    }

    @ViewBuilder private func statusBtn(_ s: WorkStatus, _ label: String) -> some View {
        Button(label) {
            status = s
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(status == s ? Color.accentColor.opacity(0.1) : Color.clear)
        .foregroundStyle(status == s ? Color.accentColor : .primary)
    }

    @ViewBuilder private func completionSection() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Outcome", selection: $completionOutcome) {
                Text("Select...").tag(nil as CompletionOutcome?)
                ForEach(CompletionOutcome.allCases, id: \.self) { Text(labelForOutcome($0)).tag($0 as CompletionOutcome?) }
            }
            TextField("Notes", text: $completionNote).textFieldStyle(.roundedBorder)
        }
    }

    @ViewBuilder private func stepsSection() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Steps").font(.headline)
                Spacer()
                Button {
                    showAddStepSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }

            if let work = work {
                let orderedSteps = work.orderedSteps
                if orderedSteps.isEmpty {
                    Text("No steps yet. Add steps to this report.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .italic()
                } else {
                    ForEach(orderedSteps) { step in
                        WorkStepRow(step: step) {
                            stepBeingEdited = step
                        }
                    }
                }

                // Progress indicator
                let progress = work.stepProgress
                if progress.total > 0 {
                    HStack {
                        Spacer()
                        Text("\(progress.completed)/\(progress.total) steps complete")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder private func calendarSection() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Calendar").font(.headline)
            HStack {
                DatePicker("", selection: $newPlanDate, displayedComponents: .date).labelsHidden()
                Button("Add") { addPlan() }.buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder private func notesSection() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("Notes").font(.headline); Spacer(); Button("+") { showAddNoteSheet = true } }

            // Show unified notes
            ForEach(workModelNotes.sorted(by: { $0.createdAt > $1.createdAt }), id: \.id) { note in
                noteRow(note)
            }

            if workModelNotes.isEmpty {
                Text("No notes yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .italic()
            }
        }
    }

    @ViewBuilder
    private func noteRow(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.body)
                .font(.body)
            HStack {
                if note.category != .general {
                    Text(note.category.rawValue.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.secondary.opacity(0.1))
                        )
                }
                Text(note.createdAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(8)
        .contextMenu {
            Button {
                noteBeingEdited = note
            } label: {
                Label("Edit Note", systemImage: "pencil")
            }
        }
    }


    private func save() {
        guard let work = work else { return }
        work.status = status
        work.title = workTitle
        work.kind = workKind
        work.completionOutcome = completionOutcome
        // Note: WorkModel doesn't have completionNote field, so we skip it
        saveCoordinator.save(modelContext, reason: "Saving work model")
        close()
    }

    private func close() { onDone?() ?? dismiss() }

    private func deleteWork() {
        guard let work = work else { return }
        modelContext.delete(work)
        saveCoordinator.save(modelContext, reason: "Deleting work model")
        close()
    }

    private func addPlan() {
        guard let work = work else { return }
        let item = WorkPlanItem(workID: work.id, scheduledDate: newPlanDate, reason: newPlanReason)
        modelContext.insert(item)
        saveCoordinator.save(modelContext, reason: "Adding plan item")
    }

    /// OPTIMIZATION: Load only related lessons and students on demand
    private func loadRelatedData(for workModel: WorkModel? = nil) {
        guard let work = workModel ?? self.work else { return }

        // Load the specific student first (most important for display)
        if let studentID = UUID(uuidString: work.studentID) {
            let allStudentsDescriptor = FetchDescriptor<Student>()
            let allStudents = modelContext.safeFetch(allStudentsDescriptor)
            relatedStudent = allStudents.first { $0.id == studentID }
        }

        // Load the specific lesson
        if let lessonID = UUID(uuidString: work.lessonID) {
            let lessonDescriptor = FetchDescriptor<Lesson>(
                predicate: #Predicate<Lesson> { $0.id == lessonID }
            )
            relatedLesson = modelContext.safeFetchFirst(lessonDescriptor)

            // If we found the lesson, load lessons in the same subject/group for NextLessonResolver
            if let lesson = relatedLesson {
                let subject = lesson.subject.trimmingCharacters(in: .whitespacesAndNewlines)
                let group = lesson.group.trimmingCharacters(in: .whitespacesAndNewlines)
                // Only load related lessons if subject/group are non-empty
                if !subject.isEmpty && !group.isEmpty {
                    // Load all lessons and filter in memory (predicates don't support trimmingCharacters or caseInsensitiveCompare)
                    let allLessonsDescriptor = FetchDescriptor<Lesson>(
                        sortBy: [SortDescriptor(\.orderInGroup)]
                    )
                    let allLessons = modelContext.safeFetch(allLessonsDescriptor)
                    relatedLessons = allLessons.filter { l in
                        let lSubject = l.subject.trimmingCharacters(in: .whitespacesAndNewlines)
                        let lGroup = l.group.trimmingCharacters(in: .whitespacesAndNewlines)
                        return lSubject.caseInsensitiveCompare(subject) == .orderedSame &&
                               lGroup.caseInsensitiveCompare(group) == .orderedSame
                    }
                }
            }
        }
    }

    private func studentName() -> String {
        relatedStudent?.firstName ?? "Student"
    }

    private func lessonTitle() -> String {
        return relatedLesson?.name ?? "Lesson"
    }

    private func resolvePresentationID() -> UUID? {
        guard let work = work, let pid = work.presentationID else { return nil }
        return UUID(uuidString: pid)
    }

    private func reloadPresentationNotes() { /* Logic for ScopedNotes */ }

    /// Load work notes via relationships
    private func loadWorkNotes(for workModel: WorkModel? = nil) {
        guard let work = workModel ?? self.work else { return }
        // Load notes via relationships
        workModelNotes = Array(work.unifiedNotes ?? [])
    }

    private func labelForOutcome(_ o: CompletionOutcome) -> String {
        switch o {
        case .mastered: return "Mastered"
        case .needsMorePractice: return "Keep Practicing"
        default: return o.rawValue.capitalized
        }
    }
}

// MARK: - Sheet Presentation Extension

extension View {
    /// Present work detail as a sheet with platform-adaptive sizing
    func workDetailSheet(workID: Binding<UUID?>, onDone: (() -> Void)? = nil) -> some View {
        self.sheet(isPresented: Binding(
            get: { workID.wrappedValue != nil },
            set: { if !$0 { workID.wrappedValue = nil } }
        )) {
            if let id = workID.wrappedValue {
                WorkDetailView(workID: id, onDone: {
                    workID.wrappedValue = nil
                    onDone?()
                })
                #if os(macOS)
                .frame(minWidth: 720, minHeight: 640)
                .presentationSizingFitted()
                #else
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                #endif
            }
        }
    }
}

// MARK: - Helpers

private struct NextLessonResolver {
    static func resolveNextLesson(from currentID: UUID, lessons: [Lesson]) -> Lesson? {
        guard let current = lessons.first(where: { $0.id == currentID }) else { return nil }
        let candidates = lessons.filter { $0.subject == current.subject && $0.group == current.group }
            .sorted { $0.orderInGroup < $1.orderInGroup }
        if let idx = candidates.firstIndex(where: { $0.id == current.id }), idx + 1 < candidates.count {
            return candidates[idx + 1]
        }
        return nil
    }
}

struct WorkModelScheduleNextLessonSheet: View {
    let work: WorkModel
    var onCreated: () -> Void
    @Environment(\.dismiss) var dismiss
    var body: some View {
        Button("Tap to Unlock") { onCreated(); dismiss() }.padding()
    }
}
