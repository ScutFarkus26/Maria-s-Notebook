import SwiftUI
import SwiftData
import Foundation

/// Unified detail view for viewing and editing work items
/// Replaces: WorkModelDetailSheet, WorkDetailWindowContainer, WorkDetailContainerView
struct WorkDetailView: View {
    let workID: UUID
    var onDone: (() -> Void)? = nil
    var showRepresentButton: Bool = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SaveCoordinator.self) private var saveCoordinator

    @State private var viewModel: WorkDetailViewModel
    @State private var showingRepresentSheet: Bool = false
    #if DEBUG
    @Query private var lessonAssignments: [LessonAssignment]
    #endif
    @Query private var checkIns: [WorkCheckIn]
    @Query private var allPracticeSessions: [PracticeSession]
    @Query(sort: \Lesson.sortIndex) private var allLessons: [Lesson]
    @Query private var allLessonAssignments: [LessonAssignment]
    #if DEBUG
    @Query private var peerWorks: [WorkModel]
    #endif

    private var scheduleDates: WorkScheduleDates {
        viewModel.scheduleDates(checkIns: checkIns)
    }

    private var likelyNextLesson: Lesson? {
        viewModel.likelyNextLesson(allLessons: allLessons)
    }
    
    private var practiceSessions: [PracticeSession] {
        viewModel.practiceSessions(allSessions: allPracticeSessions)
    }

    private var unlockInfo: (lessonID: UUID, studentID: UUID)? {
        guard viewModel.status == .complete,
              let outcome = viewModel.completionOutcome,
              outcome == .mastered || outcome == .needsReview,
              let work = viewModel.work,
              let lessonID = UUID(uuidString: work.lessonID),
              let studentID = UUID(uuidString: work.studentID) else {
            return nil
        }
        return (lessonID, studentID)
    }

    private var representSheetInfo: (student: Student, lessonID: UUID)? {
        guard let student = viewModel.relatedStudent,
              let work = viewModel.work,
              let lessonID = UUID(uuidString: work.lessonID) else {
            return nil
        }
        return (student, lessonID)
    }

    private var unlockNextLessonInfo: (lessonID: UUID, studentID: UUID)? {
        guard let work = viewModel.work,
              let lessonID = UUID(uuidString: work.lessonID),
              let studentID = UUID(uuidString: work.studentID) else {
            return nil
        }
        return (lessonID, studentID)
    }

    init(workID: UUID, onDone: (() -> Void)? = nil, showRepresentButton: Bool = false) {
        self.workID = workID
        self.onDone = onDone
        self.showRepresentButton = showRepresentButton
        _viewModel = State(wrappedValue: WorkDetailViewModel(workID: workID))

        let workIDString = workID.uuidString
        let scheduledStatus = WorkCheckInStatus.scheduled.rawValue
        _checkIns = Query(filter: #Predicate<WorkCheckIn> { 
            $0.workID == workIDString && $0.statusRaw == scheduledStatus 
        })
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
                        "checkIns": checkIns.count,
                        "peerWorks": peerWorks.count
                    ]
                )
                #endif
            }
        }
    }
    
    @State private var selectedPracticeSession: PracticeSession?
    
    @ViewBuilder
    private func mainContent(work: WorkModel) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerSection()
                    
                    presentationContextSection()
                    
                    nextPresentationStatusSection

                    if viewModel.status == .complete { completionSection() }
                    if viewModel.workKind == .report { stepsSection() }
                    if !practiceSessions.isEmpty { practiceOverviewSection() }
                    practiceHistorySection()
                    notesSection()
                    calendarSection()
                }.padding(AppTheme.Spacing.xlarge)
            }
            .sheet(item: $selectedPracticeSession) { session in
                practiceSessionDetailSheet(session: session)
            }
            Divider()
            VStack(spacing: 12) {
                // Top row: Action buttons
                HStack(spacing: 12) {
                    IconActionButton(
                        icon: "trash",
                        color: .red,
                        backgroundColor: Color.red.opacity(UIConstants.OpacityConstants.light)
                    ) {
                        viewModel.showDeleteAlert = true
                    }

                    RoundedActionButton(
                        title: "Add Practice",
                        icon: "person.2.fill",
                        color: .blue
                    ) {
                        viewModel.showPracticeSessionSheet = true
                    }

                    if showRepresentButton {
                        RoundedActionButton(
                            title: "Re-present",
                            icon: "arrow.clockwise",
                            color: .purple
                        ) {
                            showingRepresentSheet = true
                        }
                    }

                    Spacer()
                }

                // Bottom row: Cancel and Save buttons
                SaveCancelButtons(onCancel: close, onSave: save)
            }
            .padding(AppTheme.Spacing.large)
            .background(.bar)
        }
        .sheet(isPresented: $showingRepresentSheet) {
            if let info = representSheetInfo {
                AddLessonToInboxSheet(student: info.student, preselectedLessonID: info.lessonID)
            }
        }
        .sheet(isPresented: $viewModel.showScheduleSheet) {
                    WorkModelScheduleNextLessonSheet(work: work) { viewModel.showPlannedBanner = true }
                }
                .sheet(isPresented: $viewModel.showAddNoteSheet) {
                    UnifiedNoteEditor(
                        context: .work(work),
                        initialNote: nil,
                        onSave: { _ in
                            // Reload notes after saving
                            viewModel.loadWork(modelContext: modelContext, saveCoordinator: saveCoordinator)
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
                            // Reload notes after saving
                            viewModel.loadWork(modelContext: modelContext, saveCoordinator: saveCoordinator)
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
                        .shadow(AppTheme.ShadowStyle.medium)

                    Image(systemName: viewModel.workKind.iconName)
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(.white)
                }

                // Student name
                Text(studentName())
                    .font(AppTheme.ScaledFont.titleLarge)

                // Lesson info pill
                Label(lessonTitle(), systemImage: "book.closed.fill")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, AppTheme.Spacing.compact)
                    .padding(.vertical, AppTheme.Spacing.small)
                    .background(Capsule().fill(Color.primary.opacity(UIConstants.OpacityConstants.subtle)))
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 8)

            // Work title field
            VStack(alignment: .leading, spacing: 6) {
                Text("Title")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)
                TextField("Work Title", text: $viewModel.workTitle)
                    .font(AppTheme.ScaledFont.bodySemibold)
                    .padding(AppTheme.Spacing.compact)
                    .background(
                        RoundedRectangle(cornerRadius: UIConstants.CornerRadius.large)
                            .fill(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: UIConstants.CornerRadius.large)
                            .stroke(Color.primary.opacity(UIConstants.OpacityConstants.faint), lineWidth: UIConstants.StrokeWidth.thin)
                    )
            }

            // Work kind segmented control
            VStack(alignment: .leading, spacing: 8) {
                Text("Type")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(WorkKind.allCases) { kind in
                        SelectablePillButton(
                            item: kind,
                            isSelected: viewModel.workKind == kind,
                            color: kind.color,
                            icon: kind.iconName,
                            label: kind.shortLabel
                        ) {
                            adaptiveWithAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                viewModel.workKind = kind
                            }
                        }
                    }
                }
            }

            // Status pills
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    Text("Status")
                        .font(AppTheme.ScaledFont.captionSemibold)
                        .foregroundStyle(.secondary)
                    #if os(macOS)
                    Text("")
                        .help("Active = in progress, Review = checking work, Complete = finished")
                    #endif
                }

                HStack(spacing: 8) {
                    ForEach(WorkStatus.allCases) { s in
                        SelectablePillButton(
                            item: s,
                            isSelected: viewModel.status == s,
                            color: s.color,
                            icon: s.iconName,
                            label: s.displayName
                        ) {
                            adaptiveWithAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                viewModel.status = s

                                // When marking as complete with good outcome, offer to unlock next lesson
                                if let info = unlockInfo {
                                    checkAndOfferUnlock(lessonID: info.lessonID, studentID: info.studentID)
                                }
                            }
                            if s == .complete {
                                HapticService.shared.notification(.success)
                            } else {
                                HapticService.shared.selection()
                            }
                        }
                    }

                    Spacer()

                    if viewModel.status != .complete, likelyNextLesson != nil {
                        Button { viewModel.showScheduleSheet = true } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "lock.open.fill")
                                Text("Unlock")
                                    .font(AppTheme.ScaledFont.captionSemibold)
                            }
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, AppTheme.Spacing.compact)
                            .padding(.vertical, AppTheme.Spacing.small)
                            .background(
                                Capsule()
                                    .fill(Color.accentColor.opacity(UIConstants.OpacityConstants.medium))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Check-in style
            VStack(alignment: .leading, spacing: 8) {
                Text("Check-In Style")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(CheckInStyle.allCases) { style in
                        SelectablePillButton(
                            item: style,
                            isSelected: viewModel.checkInStyle == style,
                            color: style.color,
                            icon: style.iconName,
                            label: style.displayName
                        ) {
                            adaptiveWithAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                viewModel.checkInStyle = style
                            }
                        }
                    }
                }

                Text(viewModel.checkInStyle.shortDescription)
                    .font(AppTheme.ScaledFont.captionSmall)
                    .foregroundStyle(.tertiary)
            }
        }
    }



    @ViewBuilder private func completionSection() -> some View {
        DetailSectionCard(title: "Completion", icon: "checkmark.seal.fill", accentColor: .green) {
            VStack(alignment: .leading, spacing: 12) {
                // Outcome picker styled as pills
                Text("Outcome")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)

                FlowLayout(spacing: 8) {
                    ForEach(CompletionOutcome.allCases, id: \.self) { outcome in
                        SelectablePillButton(
                            item: outcome,
                            isSelected: viewModel.completionOutcome == outcome,
                            color: outcome.color,
                            icon: outcome.iconName,
                            label: outcome.displayName
                        ) {
                            adaptiveWithAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                viewModel.completionOutcome = outcome
                            }
                        }
                    }
                }

                // Completion note
                TextField("Add a completion note...", text: $viewModel.completionNote)
                    .font(AppTheme.ScaledFont.body)
                    .padding(AppTheme.Spacing.compact)
                    .background(
                        RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium)
                            .fill(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
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
                .accessibilityLabel("Add step")
                .buttonStyle(.plain)
            }
        ) {
            if let work = viewModel.work {
                let orderedSteps = work.orderedSteps
                if orderedSteps.isEmpty {
                    EmptyStateView(
                        icon: "checklist",
                        title: "No steps yet",
                        subtitle: "Add steps to track progress"
                    )
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
                            .font(AppTheme.ScaledFont.captionSemibold)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                }
            }
        }
    }

    @ViewBuilder private func calendarSection() -> some View {
        DetailSectionCard(title: "Scheduled Check-Ins", icon: "calendar.badge.checkmark", accentColor: .blue) {
            VStack(alignment: .leading, spacing: 16) {
                // Display existing check-ins
                if !checkIns.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(checkIns.sorted(by: { $0.date < $1.date })) { item in
                            checkInRow(item)
                        }
                    }
                    .padding(.bottom, 8)
                }
                
                Divider()
                
                // Add new check-in section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Schedule New Check-In")
                        .font(AppTheme.ScaledFont.captionSemibold)
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 12) {
                        DatePicker("", selection: $viewModel.newPlanDate, displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.compact)
                        
                        Menu {
                            // Phase 6: Simple string-based purposes
                            Button {
                                viewModel.newPlanPurpose = "progressCheck"
                            } label: {
                                HStack {
                                    Image(systemName: "checkmark.circle")
                                    Text("Progress Check")
                                }
                            }
                            Button {
                                viewModel.newPlanPurpose = "assessment"
                            } label: {
                                HStack {
                                    Image(systemName: "chart.bar")
                                    Text("Assessment")
                                }
                            }
                            Button {
                                viewModel.newPlanPurpose = "dueDate"
                            } label: {
                                HStack {
                                    Image(systemName: "calendar.badge.exclamationmark")
                                    Text("Due Date")
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle")
                                    .font(.system(size: 12, weight: .medium))
                                Text(viewModel.newPlanPurpose.isEmpty ? "Progress Check" : viewModel.newPlanPurpose)
                                    .font(AppTheme.ScaledFont.captionSemibold)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.primary.opacity(UIConstants.OpacityConstants.subtle))
                            )
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            adaptiveWithAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                addPlan()
                            }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(.blue)
                        }
                        .accessibilityLabel("Add plan")
                        .buttonStyle(.plain)
                    }
                    
                    // Optional note field
                    TextField("Add a note (optional)", text: $viewModel.newPlanNote)
                        .font(AppTheme.ScaledFont.caption)
                        .padding(AppTheme.Spacing.small)
                        .background(
                            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.small)
                                .fill(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
                        )
                }
            }
        }
    }
    
    @ViewBuilder
    private func checkInRow(_ item: WorkCheckIn) -> some View {
        WorkCheckInRow(
            checkIn: item,
            onEditNote: { checkIn in
                // TODO: Implement note editing for check-ins
            },
            onSetStatus: { id, status in
                // Update the check-in status
                if let checkIn = checkIns.first(where: { $0.id == id }) {
                    checkIn.status = status
                    saveCoordinator.save(modelContext, reason: "Update check-in status")
                }
            },
            onDelete: { deleteCheckIn($0) }
        )
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
                    MetricStatBox(
                        value: "\(stats.totalSessions)",
                        label: stats.totalSessions == 1 ? "Session" : "Sessions",
                        icon: "calendar",
                        color: .blue
                    )

                    if let totalTime = stats.totalDuration {
                        MetricStatBox(
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
                            QualityMetricBox(
                                level: avgQuality,
                                label: "Avg Quality",
                                icon: "star.fill",
                                color: .blue
                            )
                        }

                        if let avgIndependence = stats.avgIndependence {
                            QualityMetricBox(
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
                            .font(AppTheme.ScaledFont.captionSemibold)
                            .foregroundStyle(.secondary)

                        FlowLayout(spacing: 6) {
                            ForEach(stats.topBehaviors, id: \.self) { behavior in
                                BehaviorPill(behavior: behavior)
                            }
                        }
                    }
                }

                // Action items
                if stats.needsReteaching > 0 || stats.upcomingCheckIns > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Action Items")
                            .font(AppTheme.ScaledFont.captionSemibold)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            if stats.needsReteaching > 0 {
                                ActionItemBox(
                                    count: stats.needsReteaching,
                                    label: "Needs Reteaching",
                                    icon: "arrow.counterclockwise",
                                    color: .orange
                                )
                            }

                            if stats.upcomingCheckIns > 0 {
                                ActionItemBox(
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
                VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                    PracticeSessionCard(session: session, displayMode: .expanded)
                }
                .padding(AppTheme.Spacing.large)
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
    
    @ViewBuilder 
    private var nextPresentationStatusSection: some View {
        if let status = presentationStatus, !status.isNotFound {
            presentationStatusCard(status: status)
        }
    }

    private var presentationStatus: WorkPresentationStatusService.PresentationStatus? {
        guard let work = viewModel.work else { return nil }
        return WorkPresentationStatusService.findNextPresentationStatus(
            for: work,
            modelContext: modelContext
        )
    }
    
    @ViewBuilder private func presentationStatusCard(status: WorkPresentationStatusService.PresentationStatus) -> some View {
        
        DetailSectionCard(
            title: "Next Presentation",
            icon: status.iconName,
            accentColor: status.color
        ) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(status.color.opacity(UIConstants.OpacityConstants.light))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: status.iconName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(status.color)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(status.displayText)
                        .font(AppTheme.ScaledFont.bodySemibold)
                    
                    // Additional context based on status
                    switch status {
                    case .scheduled(let date):
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.secondary)
                    case .inInbox(let students):
                        if students.count > 1 {
                            Text("Ready to present with \(students.count) students")
                                .font(AppTheme.ScaledFont.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Ready to present")
                                .font(AppTheme.ScaledFont.caption)
                                .foregroundStyle(.secondary)
                        }
                    case .withOtherStudents(let students):
                        Text("Waiting area with \(students.count) other \(students.count == 1 ? "student" : "students")")
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.secondary)
                    case .notFound:
                        EmptyView()
                    }
                }
                
                Spacer()
            }
            .padding(AppTheme.Spacing.compact)
            .background(
                RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium)
                    .fill(status.color.opacity(UIConstants.OpacityConstants.veryFaint))
            )
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
                                .fill(Color.indigo.opacity(UIConstants.OpacityConstants.light))
                                .frame(width: 44, height: 44)
                            
                            Image(systemName: presentation.isPresented ? "calendar.badge.checkmark" : "calendar")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.indigo)
                        }
                        
                        VStack(alignment: .leading, spacing: 3) {
                            Text(presentation.isPresented ? "Presented" : presentation.isScheduled ? "Scheduled" : "Draft")
                                .font(AppTheme.ScaledFont.bodySemibold)
                            
                            if let date = presentation.presentedAt ?? presentation.scheduledFor {
                                Text(date.formatted(date: .abbreviated, time: .omitted))
                                    .font(AppTheme.ScaledFont.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(AppTheme.Spacing.compact)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.indigo.opacity(UIConstants.OpacityConstants.veryFaint))
                    )
                    
                    // Presentation flags
                    if presentation.needsPractice || presentation.needsAnotherPresentation || !presentation.followUpWork.isEmpty {
                        VStack(spacing: 8) {
                            if presentation.needsPractice {
                                FlagRow(icon: "arrow.counterclockwise", text: "Needs Practice", color: .orange)
                            }

                            if presentation.needsAnotherPresentation {
                                FlagRow(icon: "repeat", text: "Needs Re-presentation", color: .red)
                            }
                            
                            if !presentation.followUpWork.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "list.clipboard")
                                            .font(.system(size: 14, weight: .medium))
                                        Text("Follow-up Work")
                                            .font(AppTheme.ScaledFont.captionSemibold)
                                    }
                                    .foregroundStyle(.blue)
                                    
                                    Text(presentation.followUpWork)
                                        .font(AppTheme.ScaledFont.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(AppTheme.Spacing.small)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: UIConstants.CornerRadius.small)
                                        .fill(Color.blue.opacity(UIConstants.OpacityConstants.faint))
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
                                    .font(AppTheme.ScaledFont.captionSemibold)
                            }
                            .foregroundStyle(.purple)
                            
                            Text(presentation.notes)
                                .font(AppTheme.ScaledFont.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(AppTheme.Spacing.small)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.small)
                                .fill(Color.purple.opacity(UIConstants.OpacityConstants.faint))
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
                                    .font(AppTheme.ScaledFont.captionSemibold)
                            }
                            .foregroundStyle(AppColors.success)

                            ForEach(students.filter { $0.id.uuidString != viewModel.work?.studentID }) { student in
                                Text("• \(StudentFormatter.displayName(for: student))")
                                    .font(AppTheme.ScaledFont.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(AppTheme.Spacing.small)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.small)
                                .fill(Color.green.opacity(UIConstants.OpacityConstants.faint))
                        )
                    }
                }
            }
        }
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
                .accessibilityLabel("Add note")
                .buttonStyle(.plain)
            }
        ) {
            if viewModel.workModelNotes.isEmpty {
                EmptyStateView(
                    icon: "note.text",
                    title: "No notes yet",
                    subtitle: "Add notes to track progress"
                )
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
        NoteRowView(note: note, onEdit: { viewModel.noteBeingEdited = note }, onDelete: { deleteNote(note) })
    }


    // MARK: - Practice Overview Helpers

    private func calculatePracticeStats() -> PracticeStats {
        PracticeStatsCalculator.calculate(from: practiceSessions)
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
        let existingLAs = allLessonAssignments.filter { la in
            la.lessonIDUUID == nextLesson.id &&
            la.studentUUIDs.contains(studentID)
        }
        
        // If already manually unlocked, don't show prompt
        if existingLAs.contains(where: { $0.manuallyUnblocked }) {
            return
        }
        
        // Show unlock prompt
        viewModel.nextLessonToUnlock = nextLesson
        viewModel.showUnlockNextLessonAlert = true
    }
    
    private func unlockNextLesson() {
        guard let info = unlockNextLessonInfo else { return }

        _ = UnlockNextLessonService.unlockNextLesson(
            after: info.lessonID,
            for: info.studentID,
            modelContext: modelContext,
            lessons: allLessons,
            lessonAssignments: allLessonAssignments
        )

        saveCoordinator.save(modelContext, reason: "Unlocking next lesson")
    }

    private func addPlan() {
        guard let work = viewModel.work else { return }
        let note = viewModel.newPlanNote.trimmed().isEmpty ? nil : viewModel.newPlanNote.trimmed()
        
        // PHASE 6: Create WorkCheckIn only (WorkPlanItem removed)
        let checkIn = WorkCheckIn(
            workID: work.id,
            date: viewModel.newPlanDate,
            status: .scheduled,
            purpose: viewModel.newPlanPurpose
        )
        modelContext.insert(checkIn)
        if let note {
            _ = checkIn.setLegacyNoteText(note, in: modelContext)
        }

        saveCoordinator.save(modelContext, reason: "Adding check-in")
        
        // Reset form fields
        viewModel.newPlanDate = Date()
        viewModel.newPlanPurpose = "progressCheck"
        viewModel.newPlanNote = ""
    }
    
    private func deleteCheckIn(_ item: WorkCheckIn) {
        modelContext.delete(item)
        saveCoordinator.save(modelContext, reason: "Deleting check-in")
    }
    
    private func deleteNote(_ note: Note) {
        modelContext.delete(note)
        saveCoordinator.save(modelContext, reason: "Deleting note")
        
        // Reload the work to refresh the notes list
        viewModel.loadWork(modelContext: modelContext, saveCoordinator: saveCoordinator)
    }

    private func studentName() -> String {
        viewModel.relatedStudent?.firstName ?? "Student"
    }

    private func lessonTitle() -> String {
        return viewModel.relatedLesson?.name ?? "Lesson"
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
