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
    #if DEBUG
    @Query private var lessonAssignments: [LessonAssignment]
    #endif
    @Query private var planItems: [WorkPlanItem]
    @Query private var allPracticeSessions: [PracticeSession]
    #if DEBUG
    @Query private var peerWorks: [WorkModel]
    #endif

    @State private var resolvedPresentationID: UUID? = nil
    @State private var relatedPresentation: Presentation? = nil
    @State private var showPresentationNotes: Bool = true
    @State private var showAddNoteSheet: Bool = false
    @State private var noteBeingEdited: Note? = nil
    @State private var showScheduleSheet: Bool = false
    @State private var showPlannedBanner: Bool = false
    @State private var showDeleteAlert: Bool = false
    @State private var showAddStepSheet: Bool = false
    @State private var stepBeingEdited: WorkStep? = nil
    @State private var showGroupPracticeSheet: Bool = false

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
    
    private var practiceSessions: [PracticeSession] {
        guard let work = work else { return [] }
        return allPracticeSessions
            .filter { $0.workItemIDs.contains(work.id.uuidString) }
            .sorted { $0.date > $1.date }
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
        #if DEBUG
        // Query for peer works - will filter by lessonID after work is loaded
        _peerWorks = Query()
        #endif
    }

    var body: some View {
        Group {
            if let work = work {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            headerSection()
                            
                            presentationContextSection()

                            if status == .complete { completionSection() }
                            if workKind == .report { stepsSection() }
                            practiceHistorySection()
                            notesSection()
                            calendarSection()
                        }.padding(28)
                    }
                    Divider()
                    HStack(spacing: 12) {
                        Button {
                            showDeleteAlert = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.red)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.red.opacity(0.1))
                                )
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            showGroupPracticeSheet = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "person.2.fill")
                                    .font(.system(size: 12, weight: .medium))
                                Text("Group Practice")
                                    .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.blue)
                            )
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Button {
                            close()
                        } label: {
                            Text("Cancel")
                                .font(.system(size: AppTheme.FontSize.body, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.primary.opacity(0.05))
                                )
                        }
                        .buttonStyle(.plain)

                        Button {
                            save()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Save")
                                    .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.accentColor)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(20)
                    .background(.bar)
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
                .sheet(isPresented: $showGroupPracticeSheet) {
                    GroupPracticeSheet(initialWorkItem: work) { _ in
                        // Practice session saved - will automatically show in history
                    }
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
                        "lessonAssignments": lessonAssignments.count,
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
        let fetchedWork = modelContext.safeFetchFirst(descriptor)
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
        VStack(spacing: 20) {
            // Hero section with student avatar and work kind badge
            VStack(spacing: 14) {
                // Student avatar circle
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [workKind.color.opacity(0.8), workKind.color],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)
                        .shadow(color: workKind.color.opacity(0.3), radius: 12, x: 0, y: 6)

                    Image(systemName: workKind.iconName)
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(.white)
                }

                // Student name
                Text(studentName())
                    .font(.system(size: AppTheme.FontSize.titleLarge, weight: .bold, design: .rounded))

                // Lesson info pill
                Label(lessonTitle(), systemImage: "book.closed.fill")
                    .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 8)

            // Work title field
            VStack(alignment: .leading, spacing: 6) {
                Text("Title")
                    .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                TextField("Work Title", text: $workTitle)
                    .font(.system(size: AppTheme.FontSize.body, weight: .medium, design: .rounded))
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.primary.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            }

            // Work kind segmented control
            VStack(alignment: .leading, spacing: 8) {
                Text("Type")
                    .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(WorkKind.allCases) { kind in
                        kindPill(kind)
                    }
                }
            }

            // Status pills
            VStack(alignment: .leading, spacing: 8) {
                Text("Status")
                    .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(WorkStatus.allCases) { s in
                        statusPill(s)
                    }

                    Spacer()

                    if status != .complete, likelyNextLesson != nil {
                        Button { showScheduleSheet = true } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "lock.open.fill")
                                Text("Unlock")
                                    .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                            }
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(Color.accentColor.opacity(0.12))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder private func kindPill(_ kind: WorkKind) -> some View {
        let isSelected = workKind == kind
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                workKind = kind
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: kind.iconName)
                    .font(.system(size: 12, weight: .semibold))
                Text(kind.shortLabel)
                    .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(isSelected ? .white : kind.color)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(isSelected ? kind.color : kind.color.opacity(0.12))
            )
            .overlay(
                Capsule()
                    .stroke(kind.color.opacity(isSelected ? 0 : 0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func statusPill(_ s: WorkStatus) -> some View {
        let isSelected = status == s
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                status = s
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: s.iconName)
                    .font(.system(size: 12, weight: .semibold))
                Text(s.displayName)
                    .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(isSelected ? .white : s.color)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(isSelected ? s.color : s.color.opacity(0.12))
            )
            .overlay(
                Capsule()
                    .stroke(s.color.opacity(isSelected ? 0 : 0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func completionSection() -> some View {
        DetailSectionCard(title: "Completion", icon: "checkmark.seal.fill", accentColor: .green) {
            VStack(alignment: .leading, spacing: 12) {
                // Outcome picker styled as pills
                Text("Outcome")
                    .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                FlowLayout(spacing: 8) {
                    ForEach(CompletionOutcome.allCases, id: \.self) { outcome in
                        let isSelected = completionOutcome == outcome
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                completionOutcome = outcome
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: outcome.iconName)
                                    .font(.system(size: 11, weight: .semibold))
                                Text(outcome.displayName)
                                    .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                            }
                            .foregroundStyle(isSelected ? .white : outcome.color)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(isSelected ? outcome.color : outcome.color.opacity(0.12))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Completion note
                TextField("Add a completion note...", text: $completionNote)
                    .font(.system(size: AppTheme.FontSize.body, design: .rounded))
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.primary.opacity(0.04))
                    )
            }
        }
    }

    @ViewBuilder private func stepsSection() -> some View {
        DetailSectionCard(
            title: "Steps",
            icon: "list.bullet.clipboard.fill",
            accentColor: .green,
            trailing: {
                Button { showAddStepSheet = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
            }
        ) {
            if let work = work {
                let orderedSteps = work.orderedSteps
                if orderedSteps.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "checklist")
                                .font(.system(size: 28))
                                .foregroundStyle(.tertiary)
                            Text("No steps yet")
                                .font(.system(size: AppTheme.FontSize.body, design: .rounded))
                                .foregroundStyle(.secondary)
                            Text("Add steps to track progress")
                                .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 16)
                        Spacer()
                    }
                } else {
                    VStack(spacing: 8) {
                        ForEach(orderedSteps) { step in
                            WorkStepRow(step: step) {
                                stepBeingEdited = step
                            }
                        }
                    }
                }

                // Progress indicator
                let progress = work.stepProgress
                if progress.total > 0 {
                    HStack(spacing: 10) {
                        ProgressView(value: Double(progress.completed), total: Double(progress.total))
                            .progressViewStyle(.linear)
                            .tint(.green)

                        Text("\(progress.completed)/\(progress.total)")
                            .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                }
            }
        }
    }

    @ViewBuilder private func calendarSection() -> some View {
        DetailSectionCard(title: "Schedule Check-In", icon: "calendar.badge.plus", accentColor: .blue) {
            HStack(spacing: 12) {
                DatePicker("", selection: $newPlanDate, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        addPlan()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text("Add")
                            .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Color.blue)
                    )
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
    }

    @ViewBuilder private func practiceHistorySection() -> some View {
        if !practiceSessions.isEmpty {
            DetailSectionCard(
                title: "Practice History",
                icon: "person.2.fill",
                accentColor: .blue
            ) {
                VStack(spacing: 12) {
                    ForEach(practiceSessions) { session in
                        PracticeSessionCard(session: session, displayMode: .standard)
                    }
                }
            }
        }
    }
    
    @ViewBuilder private func presentationContextSection() -> some View {
        if let presentation = relatedPresentation {
            DetailSectionCard(
                title: "From Presentation",
                icon: "calendar.badge.checkmark",
                accentColor: .indigo
            ) {
                VStack(spacing: 14) {
                    // Presentation date info
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.indigo.opacity(0.15))
                                .frame(width: 44, height: 44)
                            
                            Image(systemName: presentation.isPresented ? "calendar.badge.checkmark" : "calendar")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.indigo)
                        }
                        
                        VStack(alignment: .leading, spacing: 3) {
                            Text(presentation.isPresented ? "Presented" : presentation.isScheduled ? "Scheduled" : "Draft")
                                .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                            
                            if let date = presentation.presentedAt ?? presentation.scheduledFor {
                                Text(date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.indigo.opacity(0.05))
                    )
                    
                    // Presentation flags
                    if presentation.needsPractice || presentation.needsAnotherPresentation || !presentation.followUpWork.isEmpty {
                        VStack(spacing: 8) {
                            if presentation.needsPractice {
                                flagRow(icon: "arrow.counterclockwise", text: "Needs Practice", color: .orange)
                            }
                            
                            if presentation.needsAnotherPresentation {
                                flagRow(icon: "repeat", text: "Needs Re-presentation", color: .red)
                            }
                            
                            if !presentation.followUpWork.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "list.clipboard")
                                            .font(.system(size: 14, weight: .medium))
                                        Text("Follow-up Work")
                                            .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                                    }
                                    .foregroundStyle(.blue)
                                    
                                    Text(presentation.followUpWork)
                                        .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.blue.opacity(0.08))
                                )
                            }
                        }
                    }
                    
                    // Presentation notes
                    if !presentation.notes.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: "note.text")
                                    .font(.system(size: 14, weight: .medium))
                                Text("Presentation Notes")
                                    .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                            }
                            .foregroundStyle(.purple)
                            
                            Text(presentation.notes)
                                .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.purple.opacity(0.08))
                        )
                    }
                    
                    // Students in presentation (if multiple)
                    let students = presentation.fetchStudents(from: modelContext)
                    if students.count > 1 {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "person.2.fill")
                                    .font(.system(size: 14, weight: .medium))
                                Text("Also presented to:")
                                    .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                            }
                            .foregroundStyle(.green)
                            
                            ForEach(students.filter { $0.id.uuidString != work?.studentID }) { student in
                                Text("• \(StudentFormatter.displayName(for: student))")
                                    .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.green.opacity(0.08))
                        )
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func flagRow(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(color)
            
            Text(text)
                .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
            
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.08))
        )
    }
    
    @ViewBuilder private func notesSection() -> some View {
        DetailSectionCard(
            title: "Notes",
            icon: "note.text",
            accentColor: .purple,
            trailing: {
                Button { showAddNoteSheet = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.purple)
                }
                .buttonStyle(.plain)
            }
        ) {
            if workModelNotes.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "note.text")
                            .font(.system(size: 28))
                            .foregroundStyle(.tertiary)
                        Text("No notes yet")
                            .font(.system(size: AppTheme.FontSize.body, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text("Add notes to track progress")
                            .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 16)
                    Spacer()
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(workModelNotes.sorted(by: { $0.createdAt > $1.createdAt }), id: \.id) { note in
                        noteRow(note)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func noteRow(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(note.body)
                .font(.system(size: AppTheme.FontSize.body, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
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
    }

    private func categoryColor(for category: NoteCategory) -> Color {
        switch category {
        case .general: return .gray
        case .behavioral: return .orange
        case .academic: return .blue
        case .social: return .green
        case .emotional: return .pink
        case .health: return .red
        case .attendance: return .purple
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
        
        // Load the presentation that spawned this work
        relatedPresentation = work.fetchPresentation(from: modelContext)

        // Load the specific lesson
        if let lessonID = UUID(uuidString: work.lessonID) {
            let lessonDescriptor = FetchDescriptor<Lesson>(
                predicate: #Predicate<Lesson> { $0.id == lessonID }
            )
            relatedLesson = modelContext.safeFetchFirst(lessonDescriptor)

            // If we found the lesson, load lessons in the same subject/group for NextLessonResolver
            if let lesson = relatedLesson {
                let subject = lesson.subject.trimmed()
                let group = lesson.group.trimmed()
                // Only load related lessons if subject/group are non-empty
                if !subject.isEmpty && !group.isEmpty {
                    // Load all lessons and filter in memory (predicates don't support trimmingCharacters or caseInsensitiveCompare)
                    let allLessonsDescriptor = FetchDescriptor<Lesson>(
                        sortBy: [SortDescriptor(\.orderInGroup)]
                    )
                    let allLessons = modelContext.safeFetch(allLessonsDescriptor)
                    relatedLessons = allLessons.filter { l in
                        let lSubject = l.subject.trimmed()
                        let lGroup = l.group.trimmed()
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

}

// MARK: - Detail Section Card

/// Reusable card component for detail view sections
private struct DetailSectionCard<Content: View, Trailing: View>: View {
    let title: String
    let icon: String
    let accentColor: Color
    let trailing: () -> Trailing
    let content: () -> Content

    init(
        title: String,
        icon: String,
        accentColor: Color,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() },
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.accentColor = accentColor
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accentColor)

                Text(title)
                    .font(.system(size: AppTheme.FontSize.titleSmall, weight: .semibold, design: .rounded))

                Spacer()

                trailing()
            }

            content()
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.primary.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
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
