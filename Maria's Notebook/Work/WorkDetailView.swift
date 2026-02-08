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

    @StateObject private var viewModel: WorkDetailViewModel
    #if DEBUG
    @Query private var lessonAssignments: [LessonAssignment]
    #endif
    @Query private var planItems: [WorkPlanItem]
    @Query private var allPracticeSessions: [PracticeSession]
    @Query(sort: \Lesson.sortIndex) private var allLessons: [Lesson]
    @Query private var studentLessons: [StudentLesson]
    #if DEBUG
    @Query private var peerWorks: [WorkModel]
    #endif

    private var scheduleDates: WorkScheduleDates {
        viewModel.scheduleDates(planItems: planItems)
    }

    private var likelyNextLesson: Lesson? {
        viewModel.likelyNextLesson(allLessons: allLessons)
    }
    
    private var practiceSessions: [PracticeSession] {
        viewModel.practiceSessions(allSessions: allPracticeSessions)
    }

    init(workID: UUID, onDone: (() -> Void)? = nil) {
        self.workID = workID
        self.onDone = onDone
        _viewModel = StateObject(wrappedValue: WorkDetailViewModel(workID: workID))

        let workIDString = workID.uuidString
        _planItems = Query(filter: #Predicate<WorkPlanItem> { $0.workID == workIDString })
        #if DEBUG
        // Query for peer works - will filter by lessonID after work is loaded
        _peerWorks = Query()
        #endif
    }

    var body: some View {
        Group {
            if let work = viewModel.work {
                mainContent(work: work)
            } else {
                ContentUnavailableView("Work not found", systemImage: "doc.questionmark")
                    #if os(macOS)
                    .frame(minWidth: 400, minHeight: 200)
                    #endif
            }
        }
        .onAppear {
            viewModel.loadWork(modelContext: modelContext, saveCoordinator: saveCoordinator)
            if viewModel.work != nil {
                #if DEBUG
                PerformanceLogger.logScreenLoad(
                    screenName: "WorkDetailView",
                    itemCounts: [
                        "lessons": viewModel.relatedLessons.count,
                        "students": viewModel.relatedStudent != nil ? 1 : 0,
                        "workModelNotes": viewModel.workModelNotes.count,
                        "lessonAssignments": lessonAssignments.count,
                        "planItems": planItems.count,
                        "peerWorks": peerWorks.count
                    ]
                )
                #endif
            }
        }
    }
    
    @State private var selectedPracticeSession: PracticeSession? = nil
    
    @ViewBuilder
    private func mainContent(work: WorkModel) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerSection()
                    
                    presentationContextSection()

                    if viewModel.status == .complete { completionSection() }
                    if viewModel.workKind == .report { stepsSection() }
                    if !practiceSessions.isEmpty { practiceOverviewSection() }
                    practiceHistorySection()
                    notesSection()
                    calendarSection()
                }.padding(28)
            }
            .sheet(item: $selectedPracticeSession) { session in
                practiceSessionDetailSheet(session: session)
            }
            Divider()
            HStack(spacing: 12) {
                        Button {
                            viewModel.showDeleteAlert = true
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
                            viewModel.showPracticeSessionSheet = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "person.2.fill")
                                    .font(.system(size: 12, weight: .medium))
                                Text("Add Practice")
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
        .sheet(isPresented: $viewModel.showScheduleSheet) {
                    WorkModelScheduleNextLessonSheet(work: work) { viewModel.showPlannedBanner = true }
                }
                .sheet(isPresented: $viewModel.showAddNoteSheet) {
                    UnifiedNoteEditor(
                        context: .work(work),
                        initialNote: nil,
                        onSave: { _ in
                            // Note is automatically saved via relationship
                            viewModel.showAddNoteSheet = false
                        },
                        onCancel: {
                            viewModel.showAddNoteSheet = false
                        }
                    )
                }
                .sheet(item: $viewModel.noteBeingEdited) { note in
                    UnifiedNoteEditor(
                        context: .work(work),
                        initialNote: note,
                        onSave: { _ in
                            viewModel.noteBeingEdited = nil
                        },
                        onCancel: {
                            viewModel.noteBeingEdited = nil
                        }
                    )
                }
                .sheet(isPresented: $viewModel.showPracticeSessionSheet) {
                    PracticeSessionSheet(initialWorkItem: work) { _ in
                        // Practice session saved - will automatically show in history
                    }
                }
                .alert("Delete?", isPresented: $viewModel.showDeleteAlert) {
                    Button("Delete", role: .destructive) { deleteWork() }
                }
                .alert("Unlock Next Lesson?", isPresented: $viewModel.showUnlockNextLessonAlert) {
                    Button("Unlock") {
                        unlockNextLesson()
                    }
                    Button("Not Yet", role: .cancel) { }
                } message: {
                    if let nextLesson = viewModel.nextLessonToUnlock {
                        Text("Ready to unlock \(nextLesson.name) for \(viewModel.relatedStudent?.firstName ?? "this student")?")
                    }
                }
                .sheet(isPresented: $viewModel.showAddStepSheet) {
                    WorkStepEditorSheet(work: work, existingStep: nil) {
                        // Step was added - force refresh
                    }
                }
            .sheet(item: $viewModel.stepBeingEdited) { step in
                WorkStepEditorSheet(work: work, existingStep: step) {
                    viewModel.stepBeingEdited = nil
                }
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
                                colors: [viewModel.workKind.color.opacity(0.8), viewModel.workKind.color],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)
                        .shadow(color: viewModel.workKind.color.opacity(0.3), radius: 12, x: 0, y: 6)

                    Image(systemName: viewModel.workKind.iconName)
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
                TextField("Work Title", text: $viewModel.workTitle)
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

                    if viewModel.status != .complete, likelyNextLesson != nil {
                        Button { viewModel.showScheduleSheet = true } label: {
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
        let isSelected = viewModel.workKind == kind
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                viewModel.workKind = kind
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
        let isSelected = viewModel.status == s
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                viewModel.status = s
                
                // When marking as complete with good outcome, offer to unlock next lesson
                if s == .complete, 
                   let outcome = viewModel.completionOutcome,
                   outcome == .mastered || outcome == .needsReview,
                   let work = viewModel.work,
                   let lessonID = UUID(uuidString: work.lessonID),
                   let studentID = UUID(uuidString: work.studentID) {
                    checkAndOfferUnlock(lessonID: lessonID, studentID: studentID)
                }
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
                        let isSelected = viewModel.completionOutcome == outcome
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                viewModel.completionOutcome = outcome
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
                TextField("Add a completion note...", text: $viewModel.completionNote)
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
                Button { viewModel.showAddStepSheet = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
            }
        ) {
            if let work = viewModel.work {
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
                                viewModel.stepBeingEdited = step
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
                DatePicker("", selection: $viewModel.newPlanDate, displayedComponents: .date)
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

    @ViewBuilder private func practiceOverviewSection() -> some View {
        let stats = calculatePracticeStats()

        DetailSectionCard(
            title: "Practice Overview",
            icon: "chart.bar.fill",
            accentColor: .green
        ) {
            VStack(spacing: 16) {
                // Top row: Sessions and Time
                HStack(spacing: 16) {
                    statBox(
                        value: "\(stats.totalSessions)",
                        label: stats.totalSessions == 1 ? "Session" : "Sessions",
                        icon: "calendar",
                        color: .blue
                    )

                    if let totalTime = stats.totalDuration {
                        statBox(
                            value: totalTime,
                            label: "Practice Time",
                            icon: "clock",
                            color: .purple
                        )
                    }
                }

                // Quality metrics row
                if stats.avgQuality != nil || stats.avgIndependence != nil {
                    HStack(spacing: 16) {
                        if let avgQuality = stats.avgQuality {
                            qualityMetricBox(
                                level: avgQuality,
                                label: "Avg Quality",
                                icon: "star.fill",
                                color: .blue
                            )
                        }

                        if let avgIndependence = stats.avgIndependence {
                            qualityMetricBox(
                                level: avgIndependence,
                                label: "Avg Independence",
                                icon: "figure.walk",
                                color: .green
                            )
                        }
                    }
                }

                // Behavior highlights
                if !stats.topBehaviors.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recent Observations")
                            .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)

                        FlowLayout(spacing: 6) {
                            ForEach(stats.topBehaviors, id: \.self) { behavior in
                                behaviorPill(behavior)
                            }
                        }
                    }
                }

                // Action items
                if stats.needsReteaching > 0 || stats.upcomingCheckIns > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Action Items")
                            .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            if stats.needsReteaching > 0 {
                                actionItemBox(
                                    count: stats.needsReteaching,
                                    label: "Needs Reteaching",
                                    icon: "arrow.counterclockwise",
                                    color: .orange
                                )
                            }

                            if stats.upcomingCheckIns > 0 {
                                actionItemBox(
                                    count: stats.upcomingCheckIns,
                                    label: "Check-ins Scheduled",
                                    icon: "calendar.badge.clock",
                                    color: .blue
                                )
                            }
                        }
                    }
                }
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
                        PracticeSessionCard(session: session, displayMode: .standard) {
                            selectedPracticeSession = session
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func practiceSessionDetailSheet(session: PracticeSession) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    PracticeSessionCard(session: session, displayMode: .expanded)
                }
                .padding(20)
            }
            .navigationTitle("Practice Session")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        selectedPracticeSession = nil
                    }
                }
            }
        }
    }
    
    @ViewBuilder private func presentationContextSection() -> some View {
        if let presentation = viewModel.relatedPresentation {
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
                            
                            ForEach(students.filter { $0.id.uuidString != viewModel.work?.studentID }) { student in
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
                Button { viewModel.showAddNoteSheet = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.purple)
                }
                .buttonStyle(.plain)
            }
        ) {
            if viewModel.workModelNotes.isEmpty {
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
                    ForEach(viewModel.workModelNotes.sorted(by: { $0.createdAt > $1.createdAt }), id: \.id) { note in
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
                    viewModel.noteBeingEdited = note
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


    // MARK: - Practice Overview Helpers

    private struct PracticeStats {
        var totalSessions: Int = 0
        var totalDuration: String? = nil
        var avgQuality: Double? = nil
        var avgIndependence: Double? = nil
        var topBehaviors: [String] = []
        var needsReteaching: Int = 0
        var upcomingCheckIns: Int = 0
    }

    private func calculatePracticeStats() -> PracticeStats {
        var stats = PracticeStats()

        stats.totalSessions = practiceSessions.count

        // Calculate total duration
        let totalSeconds = practiceSessions.compactMap { $0.duration }.reduce(0, +)
        if totalSeconds > 0 {
            let minutes = Int(totalSeconds / 60)
            if minutes < 60 {
                stats.totalDuration = "\(minutes) min"
            } else {
                let hours = Double(minutes) / 60.0
                stats.totalDuration = String(format: "%.1f hrs", hours)
            }
        }

        // Calculate average quality
        let qualityScores = practiceSessions.compactMap { $0.practiceQuality }
        if !qualityScores.isEmpty {
            stats.avgQuality = Double(qualityScores.reduce(0, +)) / Double(qualityScores.count)
        }

        // Calculate average independence
        let independenceScores = practiceSessions.compactMap { $0.independenceLevel }
        if !independenceScores.isEmpty {
            stats.avgIndependence = Double(independenceScores.reduce(0, +)) / Double(independenceScores.count)
        }

        // Collect all behaviors
        var behaviorCounts: [String: Int] = [:]
        for session in practiceSessions {
            for behavior in session.activeBehaviors {
                behaviorCounts[behavior, default: 0] += 1
            }
        }

        // Get top 3 behaviors
        stats.topBehaviors = behaviorCounts
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { $0.key }

        // Count action items
        stats.needsReteaching = practiceSessions.filter { $0.needsReteaching }.count
        stats.upcomingCheckIns = practiceSessions.filter { $0.checkInScheduledFor != nil }.count

        return stats
    }

    @ViewBuilder
    private func statBox(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)

                Text(value)
                    .font(.system(size: AppTheme.FontSize.titleMedium, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }

            Text(label)
                .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.08))
        )
    }

    @ViewBuilder
    private func qualityMetricBox(level: Double, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)

            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { index in
                    Circle()
                        .fill(color.opacity(level >= Double(index) ? 1.0 : 0.2))
                        .frame(width: 8, height: 8)
                }
            }

            Text(label)
                .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.08))
        )
    }

    @ViewBuilder
    private func behaviorPill(_ behavior: String) -> some View {
        let color = behaviorColor(for: behavior)

        Text(behavior)
            .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(color.opacity(0.15))
            )
    }

    private func behaviorColor(for behavior: String) -> Color {
        switch behavior {
        case "Breakthrough!": return .green
        case "Struggled": return .orange
        case "Needs reteaching": return .red
        case "Ready for check-in", "Ready for assessment": return .blue
        case "Asked for help": return .purple
        case "Helped peer": return .teal
        default: return .gray
        }
    }

    @ViewBuilder
    private func actionItemBox(count: Int, label: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(count)")
                    .font(.system(size: AppTheme.FontSize.body, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(label)
                    .font(.system(size: AppTheme.FontSize.captionSmall, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(0.1))
        )
    }

    private func save() {
        viewModel.save(modelContext: modelContext, saveCoordinator: saveCoordinator)
        close()
    }

    private func close() { onDone?() ?? dismiss() }

    private func deleteWork() {
        viewModel.deleteWork(modelContext: modelContext, saveCoordinator: saveCoordinator) {
            close()
        }
    }
    
    private func checkAndOfferUnlock(lessonID: UUID, studentID: UUID) {
        // Find current lesson
        guard let currentLesson = allLessons.first(where: { $0.id == lessonID }) else { return }
        
        // Find next lesson using PlanNextLessonService
        guard let nextLesson = PlanNextLessonService.findNextLesson(after: currentLesson, in: allLessons) else {
            return // No next lesson available
        }
        
        // Check if already unlocked
        let existingSLs = studentLessons.filter { sl in
            sl.resolvedLessonID == nextLesson.id &&
            sl.resolvedStudentIDs.contains(studentID)
        }
        
        // If already manually unlocked, don't show prompt
        if existingSLs.contains(where: { $0.manuallyUnblocked }) {
            return
        }
        
        // Show unlock prompt
        viewModel.nextLessonToUnlock = nextLesson
        viewModel.showUnlockNextLessonAlert = true
    }
    
    private func unlockNextLesson() {
        guard let work = viewModel.work,
              let lessonID = UUID(uuidString: work.lessonID),
              let studentID = UUID(uuidString: work.studentID) else { return }
        
        _ = UnlockNextLessonService.unlockNextLesson(
            after: lessonID,
            for: studentID,
            modelContext: modelContext,
            lessons: allLessons,
            studentLessons: studentLessons
        )
        
        saveCoordinator.save(modelContext, reason: "Unlocking next lesson")
    }

    private func addPlan() {
        guard let work = viewModel.work else { return }
        let item = WorkPlanItem(workID: work.id, scheduledDate: viewModel.newPlanDate, reason: viewModel.newPlanReason)
        modelContext.insert(item)
        saveCoordinator.save(modelContext, reason: "Adding plan item")
    }

    private func studentName() -> String {
        viewModel.relatedStudent?.firstName ?? "Student"
    }

    private func lessonTitle() -> String {
        return viewModel.relatedLesson?.name ?? "Lesson"
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
