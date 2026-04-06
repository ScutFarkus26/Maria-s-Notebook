import OSLog
import SwiftUI
import CoreData

// MARK: - Body & Layout

extension PresentationsView {

    var body: some View {
        Group {
            if horizontalSizeClass == .compact {
                // iPhone Layout: Segmented Control approach
                VStack(spacing: 0) {
                    Picker("View", selection: $mobileViewSelection) {
                        ForEach(MobileViewMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding()

                    switch mobileViewSelection {
                    case .inbox:
                        PresentationsInboxView(
                            readyLessons: readyLessons,
                            blockedLessons: blockedLessons,
                            blockingResults: viewModel.blockingResults,
                            getBlockingWork: getBlockingWork,
                            filteredSnapshot: filteredSnapshot,
                            missWindow: missWindow,
                            missWindowRaw: $missWindowRaw,
                            coordinator: coordinator,
                            cachedLessons: viewModel.lessons,
                            cachedStudents: viewModel.cachedStudents,
                            daysSinceLastLessonByStudent: daysSinceLastLessonByStudent,
                            lastSubjectByStudent: viewModel.lastSubjectByStudent,
                            openWorkCountByStudent: viewModel.openWorkCountByStudent
                        )
                    case .calendar:
                        PresentationsCalendarStrip(
                            days: days,
                            startDate: $startDate,
                            isNonSchool: isNonSchool,
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
                }
            } else {
                // macOS / iPad Layout: Existing Split View
                VStack(spacing: 0) {
                    ViewHeader(title: "Presentations")
                    Divider()
                    GeometryReader { proxy in
                        let inboxHeight = proxy.size.height * (coordinator.isCalendarMinimized ? 1.0 : 0.5)
                        let calendarHeight = proxy.size.height * 0.5

                        VStack(spacing: 0) {
                            // Top: Inbox
                            PresentationsInboxView(
                                readyLessons: readyLessons,
                                blockedLessons: blockedLessons,
                                blockingResults: viewModel.blockingResults,
                                getBlockingWork: getBlockingWork,
                                filteredSnapshot: filteredSnapshot,
                                missWindow: missWindow,
                                missWindowRaw: $missWindowRaw,
                                coordinator: coordinator,
                                cachedLessons: viewModel.lessons,
                                cachedStudents: viewModel.cachedStudents,
                                daysSinceLastLessonByStudent: daysSinceLastLessonByStudent,
                                lastSubjectByStudent: viewModel.lastSubjectByStudent,
                                openWorkCountByStudent: viewModel.openWorkCountByStudent
                            )
                            .frame(height: inboxHeight)

                            if !coordinator.isCalendarMinimized {
                                Divider()
                                // Bottom: Calendar strip
                                PresentationsCalendarStrip(
                                    days: days,
                                    startDate: $startDate,
                                    isNonSchool: isNonSchool,
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
                                .frame(height: calendarHeight)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                            }
                        }
                    }
                }
            }
        }
        .task {
            // Update ViewModel immediately
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
            }

            if old.missWindowRaw != new.missWindowRaw {
                syncRecentWindowWithMissWindow()
            }

            updateViewModel()
        }
        .sheet(item: $coordinator.activeSheet) { sheet in
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

            case .postPresentation, .unifiedWorkflow, .lessonAssignmentHistory:
                Text("Sheet not yet implemented")
            }
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

    // MARK: - Helper Functions

    static func unresolvedWorkCount(forPresentationID pid: String, studentIDs: [String], allWork: [CDWorkModel]) -> Int {
        return allWork.filter { w in
            w.presentationID == pid &&
            studentIDs.contains(w.studentID) &&
            w.statusRaw != "complete"
        }.count
    }
}
