import Combine
import OSLog
import SwiftUI
import CoreData

// MARK: - Body & Layout

extension PresentationsView {

    var body: some View {
        planContent
        .task {
            if let embeddedSearchText {
                filterState.updateSearchText(embeddedSearchText)
            }
            updateViewModel()

            syncInboxOrderWithCurrentBase()
            syncRecentWindowWithMissWindow()
            revealFocusedPresentationIfNeeded()
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

    /// The Upcoming pane of the Lessons & Work workspace: what is ready to
    /// present, what is on the calendar, and who has been waiting longest.
    private var planContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: AppTheme.Spacing.compact) {
                Label("Ready to Present", systemImage: "tray.full")
                    .font(.headline)
                studentFilterChip
                Spacer()
            }
            .padding(.horizontal, AppTheme.Spacing.medium)
            .padding(.vertical, AppTheme.Spacing.small)

            Divider()

            destinationContent
        }
    }

    /// Only one destination remains: the presentations that are ready to give.
    /// Which child they are for is chosen in the rail beside this view, not by
    /// switching away from it.
    private var destinationContent: some View {
        ReadyToPresentSection(
            viewModel: viewModel,
            blockingResults: viewModel.blockingResults,
            getBlockingWork: getBlockingWork,
            filteredSnapshot: filteredSnapshot,
            coordinator: coordinator,
            filterState: filterState,
            focusedLessonID: focusedPresentationID,
            selection: selection
        )
    }

    /// Selecting a child in the rail silently narrows this list, so the filter
    /// has to be visible and clearable from the list it is narrowing.
    @ViewBuilder
    private var studentFilterChip: some View {
        if let id = coordinator.selectedStudentFilter,
           let student = viewModel.cachedStudents.first(where: { $0.id == id }) {
            Button {
                coordinator.clearStudentFilter()
            } label: {
                HStack(spacing: AppTheme.Spacing.xsmall) {
                    Text("for \(StudentFormatter.displayName(for: student))")
                        .font(AppTheme.ScaledFont.captionSemibold)
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                }
                .padding(.horizontal, AppTheme.Spacing.small)
                .padding(.vertical, AppTheme.Spacing.xxsmall)
                .background(Capsule().fill(Color.accentColor.opacity(UIConstants.OpacityConstants.accent)))
            }
            .buttonStyle(.plain)
            .help("Show lessons for every child")
            .accessibilityLabel("Showing lessons for \(StudentFormatter.displayName(for: student)). Clear filter.")
        }
    }

    private func revealFocusedPresentationIfNeeded() {
        guard let focusedPresentationID,
              let assignment = lessonAssignmentsForChangeDetection.first(where: {
                  $0.id == focusedPresentationID
              }),
              let chip = PresentationsView.chipRevealing(
                  isPresented: assignment.isPresented,
                  scheduledFor: assignment.scheduledFor
              ) else {
            return
        }
        // A prior chip or student filter can hide an otherwise valid deep link.
        filterState.selectedChip = chip
        coordinator.clearStudentFilter()
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
