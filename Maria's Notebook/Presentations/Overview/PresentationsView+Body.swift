import Combine
import OSLog
import SwiftUI
import CoreData

// MARK: - Body & Layout

extension PresentationsView {

    var body: some View {
        presentationsMainContent
        .task {
            if let embeddedSearchText {
                filterState.updateSearchText(embeddedSearchText)
            }
            updateViewModel()

            if startDateRaw != 0 {
                startDate = Date(timeIntervalSinceReferenceDate: startDateRaw)
            } else {
                let earliestDate = lessonAssignmentsForChangeDetection
                    .compactMap(\.scheduledFor)
                    .min()
                    .map { calendar.startOfDay(for: $0) }

                let today = calendar.startOfDay(for: Date())

                if let earliest = earliestDate {
                    startDate = min(earliest, today)
                } else {
                    await loadNonSchoolDates()
                    startDate = AgendaSchoolDayRules.computeInitialStartDate(
                        calendar: calendar,
                        isNonSchoolDay: isNonSchool
                    )
                }
                startDateRaw = startDate.timeIntervalSinceReferenceDate
            }

            // Load non-school dates for the current startDate
            await loadNonSchoolDates()

            syncInboxOrderWithCurrentBase()
            syncRecentWindowWithMissWindow()
            revealFocusedPresentationIfNeeded()
        }
        .onChange(of: startDate) { _, new in
            Task { @MainActor in
                startDateRaw = new.timeIntervalSinceReferenceDate
                await loadNonSchoolDates()
            }
        }
        .onChange(of: viewModelDependencies) { old, new in
            if old.lessonAssignmentKeys != new.lessonAssignmentKeys {
                syncInboxOrderWithCurrentBase()
                revealFocusedPresentationIfNeeded()
            }

            if old.missWindowRaw != new.missWindowRaw {
                syncRecentWindowWithMissWindow()
            }

            // Debounce the heavy fetch path: a CloudKit import that
            // touches several entities can fire multiple @FetchRequest
            // updates back-to-back. Collapse them into a single reload
            // 200ms after the last change.
            dependencyDebounceTask?.cancel()
            dependencyDebounceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                updateViewModel()
            }
        }
        // Memory pressure drops the view model's cached object graph. If this
        // screen is on-screen when that happens, refetch immediately so the user
        // never sees the list blank out; an off-screen instance refills from its
        // own `.task` the next time it appears.
        .onReceive(NotificationCenter.default.publisher(for: .memoryPressureDetected)) { _ in
            updateViewModel()
        }
        .onChange(of: embeddedSearchText) { _, newValue in
            guard let newValue else { return }
            filterState.updateSearchText(newValue)
        }
        .onChange(of: focusedPresentationID) { _, _ in
            revealFocusedPresentationIfNeeded()
        }
        #if os(macOS)
        .onChange(of: coordinator.activeSheet?.id) { _, _ in
            openPresentationWindowIfNeeded()
        }
        #endif
        .sheet(item: activeModalSheet) { sheet in
            switch sheet {
            case .lessonAssignmentDetail(let la):
                PresentationDetailView(lessonAssignment: la) {
                    coordinator.dismissSheet()
                }
                #if os(macOS)
                .presentationSizingFitted()
                #else
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                #endif

            case .schedulePresentationFor(let lesson):
                SchedulePresentationSheet(
                    lesson: lesson,
                    onPlan: { _ in coordinator.dismissSheet() },
                    onCancel: { coordinator.dismissSheet() }
                )

            case .consolidatePresentations:
                ConsolidatePresentationsSheet(onDismiss: { coordinator.dismissSheet() })
                #if os(macOS)
                .presentationSizingFitted()
                #else
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                #endif

            case .postPresentation, .unifiedWorkflow, .lessonAssignmentHistory:
                Text("Sheet not yet implemented")
            }
        }
    }

    private var activeModalSheet: Binding<PresentationsCoordinator.Sheet?> {
        Binding {
            #if os(macOS)
            if case .lessonAssignmentDetail = coordinator.activeSheet {
                return nil
            }
            #endif
            return coordinator.activeSheet
        } set: { newValue in
            coordinator.activeSheet = newValue
        }
    }

    #if os(macOS)
    private func openPresentationWindowIfNeeded() {
        guard case .lessonAssignmentDetail(let lessonAssignment) = coordinator.activeSheet,
              let id = lessonAssignment.id else {
            return
        }
        openWindow(id: "PresentationDetailWindow", value: id)
        coordinator.dismissSheet()
    }
    #endif

    @ViewBuilder
    private var presentationsMainContent: some View {
        if isEmbedded {
            embeddedPlanContent
        } else {
            VStack(spacing: 0) {
                screenHeader
                    .background(.regularMaterial)
                Divider()

                if workspaceMode == .followUp {
                    FollowingPresentationsView(
                        style: .full,
                        studentID: coordinator.selectedStudentFilter,
                        searchText: filterState.debouncedSearchText,
                        searchTokens: filterState.committedFilters,
                        onOpen: { coordinator.showLessonAssignmentDetail($0) }
                    )
                } else if horizontalSizeClass == .compact {
                    compactLayout
                } else {
                    regularLayout
                }
            }
        }
    }

    private var embeddedPlanContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: AppTheme.Spacing.compact) {
                Label("Ready and Scheduled", systemImage: "calendar")
                    .font(.headline)
                Spacer()
                Button(action: triggerSuggestNext) {
                    Label("Suggest Next", systemImage: "sparkles")
                }
                .disabled(viewModel.readyLessons.isEmpty)
            }
            .padding(.horizontal, AppTheme.Spacing.medium)
            .padding(.vertical, AppTheme.Spacing.small)

            Divider()

            // The unified Upcoming workspace uses the same explicit Ready /
            // Scheduled / Students destinations at every window size. This
            // makes a deep link deterministic on Mac as well as iPhone: a
            // scheduled assignment can select Scheduled and reveal its card.
            embeddedCompactPlanContent
        }
    }

    private var embeddedCompactPlanContent: some View {
        VStack(spacing: 0) {
            Picker("Upcoming View", selection: $compactTab) {
                Label("Ready", systemImage: "tray.full").tag(PresentationsCompactTab.ready)
                Label("Scheduled", systemImage: "calendar").tag(PresentationsCompactTab.week)
                Label("Students", systemImage: "person.2").tag(PresentationsCompactTab.students)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, AppTheme.Spacing.medium)
            .padding(.vertical, AppTheme.Spacing.small)

            Divider()

            if compactTab == .week {
                calendarStripView
            } else if compactTab == .students {
                StudentsNeedingLessonsView(
                    viewModel: viewModel,
                    coordinator: coordinator,
                    filterState: filterState,
                    lessonAssignments: Array(lessonAssignmentsForChangeDetection),
                    showAboutCard: true
                )
            } else {
                ReadyToPresentSection(
                    viewModel: viewModel,
                    blockingResults: viewModel.blockingResults,
                    getBlockingWork: getBlockingWork,
                    filteredSnapshot: filteredSnapshot,
                    coordinator: coordinator,
                    filterState: filterState,
                    suggestedLessonID: suggestedLessonID ?? focusedPresentationID
                )
            }
        }
    }

    // MARK: - Layout Helpers

    private var compactLayout: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $compactTab) {
                ForEach(PresentationsCompactTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.systemImage).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, AppTheme.Spacing.medium)
            .padding(.vertical, AppTheme.Spacing.small)

            Divider()

            switch compactTab {
            case .ready:
                ReadyToPresentSection(
                    viewModel: viewModel,
                    blockingResults: viewModel.blockingResults,
                    getBlockingWork: getBlockingWork,
                    filteredSnapshot: filteredSnapshot,
                    coordinator: coordinator,
                    filterState: filterState,
                    suggestedLessonID: suggestedLessonID
                )
            case .week:
                calendarStripView
            case .students:
                StudentsNeedingLessonsView(
                    viewModel: viewModel,
                    coordinator: coordinator,
                    filterState: filterState,
                    lessonAssignments: Array(lessonAssignmentsForChangeDetection),
                    showAboutCard: true
                )
            }
        }
    }

    private var regularLayout: some View {
        GeometryReader { proxy in
            let inboxHeight: CGFloat = proxy.size.height * (coordinator.isCalendarMinimized ? 1.0 : 0.5)
            let calendarHeight: CGFloat = proxy.size.height * 0.5

            VStack(spacing: 0) {
                inboxView
                    .frame(height: inboxHeight)

                if !coordinator.isCalendarMinimized {
                    Divider()
                    calendarStripView
                        .frame(height: calendarHeight)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
    }

    private var screenHeader: some View {
        PresentationsHeader(
            mode: $workspaceMode,
            filterState: filterState,
            coordinator: coordinator,
            cachedStudents: viewModel.cachedStudents,
            isSuggestEnabled: !viewModel.readyLessons.isEmpty,
            onSuggestNext: triggerSuggestNext,
            onFilters: { /* Filters panel: wired in a later phase. */ },
            onConsolidate: { coordinator.showConsolidatePresentations() }
        )
    }

    private func triggerSuggestNext() {
        let candidates = viewModel.filteredAndSortedReady(
            studentFilter: coordinator.selectedStudentFilter,
            debouncedSearch: filterState.debouncedSearchText,
            committedFilters: filterState.committedFilters,
            hideStudentsScheduledToday: filterState.hideStudentsScheduledToday
        )
        let all = Array(lessonAssignmentsForChangeDetection)
        guard let suggested = viewModel.suggestedNext(among: candidates, allLessonAssignments: all),
              let id = suggested.id else { return }
        suggestDismissTask?.cancel()
        adaptiveWithAnimation(.easeInOut(duration: 0.3)) {
            suggestedLessonID = id
        }
        suggestDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            adaptiveWithAnimation(.easeOut(duration: 0.5)) {
                suggestedLessonID = nil
            }
        }
    }

    private var inboxView: some View {
        PresentationsInboxView(
            viewModel: viewModel,
            blockingResults: viewModel.blockingResults,
            getBlockingWork: getBlockingWork,
            filteredSnapshot: filteredSnapshot,
            missWindow: missWindow,
            missWindowRaw: $missWindowRaw,
            coordinator: coordinator,
            filterState: filterState,
            suggestedLessonID: suggestedLessonID ?? focusedPresentationID
        )
    }

    private var calendarStripView: some View {
        WeekPlanSection(
            days: days,
            startDate: $startDate,
            isNonSchool: isNonSchool,
            legend: AnyView(presentationsLegend),
            focusedPresentationID: focusedPresentationID,
            onClear: { la in
                la.unschedule()
                do {
                    try viewContext.save()
                } catch {
                    Self.logger.warning("Failed to save schedule clear: \(error)")
                }
            },
            onSelect: { la in
                coordinator.showLessonAssignmentDetail(la)
            }
        )
    }

    private func revealFocusedPresentationIfNeeded() {
        guard let focusedPresentationID,
              let assignment = lessonAssignmentsForChangeDetection.first(where: {
                  $0.id == focusedPresentationID
              }),
              let destination = PresentationsCompactTab.focusedAssignmentDestination(
                  isPresented: assignment.isPresented,
                  scheduledFor: assignment.scheduledFor
              ) else {
            return
        }

        compactTab = destination

        switch destination {
        case .ready:
            // A prior chip selection can hide an otherwise valid deep link.
            filterState.selectedChip = .all
        case .week:
            if let scheduledFor = assignment.scheduledFor {
                startDate = calendar.startOfDay(for: scheduledFor)
            }
        case .students:
            break
        }
    }

    private var presentationsLegend: some View {
        HStack(spacing: 14) {
            legendSwatch(color: .red, label: "Absent")
            legendSwatch(color: AppColors.attention, label: "Scheduled more than once")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func legendSwatch(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Capsule()
                .stroke(color, lineWidth: 1)
                .frame(width: 18, height: 11)
            Text(label)
        }
    }

    // MARK: - Helpers

    private func updateViewModel() {
        viewModel.update(
            viewContext: viewContext,
            calendar: calendar,
            inboxOrderRaw: inboxOrderRaw,
            missWindow: missWindow,
            showTestStudents: showTestStudents,
            testStudentNamesRaw: testStudentNamesRaw
        )
    }

    private func syncInboxOrderWithCurrentBase() {
        let draftRaw = LessonAssignmentState.draft.rawValue
        let descriptor: NSFetchRequest<CDLessonAssignment> = NSFetchRequest(entityName: "LessonAssignment")
        descriptor.predicate = NSPredicate(format: "stateRaw == %@", draftRaw as CVarArg)
        let base: [CDLessonAssignment]
        do {
            base = try viewContext.fetch(descriptor)
        } catch {
            Self.logger.warning("Failed to fetch unscheduled lessons: \(error)")
            base = []
        }
        let baseIDs = base.compactMap(\.id)
        var order = InboxOrderStore.parse(inboxOrderRaw).filter { baseIDs.contains($0) }
        let missing = base
            .filter { guard let id = $0.id else { return false }; return !order.contains(id) }
            .sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
            .compactMap(\.id)
        order.append(contentsOf: missing)
        inboxOrderRaw = InboxOrderStore.serialize(order)
    }

    private func filteredSnapshot(_ la: CDLessonAssignment) -> LessonAssignmentSnapshot {
        let snap = la.snapshot()
        let allStudents = viewModel.cachedStudents
        let hiddenIDs = TestStudentsFilter.hiddenIDs(
            from: allStudents, show: showTestStudents, namesRaw: testStudentNamesRaw
        )
        let enrolledVisibleIDs = Set(allStudents.compactMap(\.id))
        let visibleIDs = snap.studentIDs.filter { enrolledVisibleIDs.contains($0) && !hiddenIDs.contains($0) }
        return LessonAssignmentSnapshot(
            id: snap.id,
            lessonID: snap.lessonID,
            studentIDs: visibleIDs,
            createdAt: snap.createdAt,
            scheduledFor: snap.scheduledFor,
            presentedAt: snap.presentedAt,
            state: snap.state,
            notes: snap.notes,
            needsPractice: snap.needsPractice,
            needsAnotherPresentation: snap.needsAnotherPresentation,
            followUpWork: snap.followUpWork,
            manuallyUnblocked: snap.manuallyUnblocked
        )
    }

}
