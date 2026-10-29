import SwiftUI
import CoreData

// MARK: - Planning Section Builders

extension PresentationDetailContentView {

    // MARK: - Header

    var headerBand: some View {
        PresentationHeaderBand(
            lessonName: currentLesson?.name ?? "Choose a Lesson",
            area: currentLesson?.area ?? "",
            sequence: currentLesson?.sequence ?? "",
            areaColor: AppColors.color(forArea: currentLesson?.area ?? ""),
            statusLine: statusLine,
            onTapTitle: lessonHasFile ? ({ openLessonFile() }) : nil
        ) {
            headerMenuItems
        }
    }

    /// When it is planned, or when it was given.
    var statusLine: String {
        if vm.isPresented {
            guard let givenAt = vm.givenAt else { return "Given earlier, date not recorded" }
            if calendar.isDateInToday(givenAt) { return "Given today" }
            return "Given " + givenAt.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        }
        guard let scheduled = vm.scheduledFor else {
            return "On Deck, not yet scheduled"
        }
        let half = calendar.component(.hour, from: scheduled) < 12 ? "morning" : "afternoon"
        if calendar.isDateInToday(scheduled) { return "Planned for today, \(half)" }
        if calendar.isDateInTomorrow(scheduled) { return "Planned for tomorrow, \(half)" }
        return "Planned for " + scheduled.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()) + ", \(half)"
    }

    @ViewBuilder
    var headerMenuItems: some View {
        Button("Change Lesson…", systemImage: "book") {
            vm.showLessonPicker = true
            lessonPickerFocused = true
        }
        if !vm.isPresented {
            Button("Reschedule…", systemImage: "calendar") {
                showRescheduleSheet = true
            }
        }
        Button("Find Students…", systemImage: "person.badge.plus") {
            vm.showingFindStudentsSheet = true
        }
        if selectedStudentsList.count > 1 && !vm.isPresented {
            Button("Split Off to a Different Group…", systemImage: "person.2.slash") {
                openMoveStudentsSheet()
            }
        }
        if lessonHasFile {
            Button("Open Lesson File", systemImage: "doc.richtext") {
                openLessonFile()
            }
        }
        Divider()
        Button("Delete Presentation…", systemImage: "trash", role: .destructive) {
            vm.showDeleteAlert = true
        }
    }

    var lessonHasFile: Bool {
        guard let lesson = currentLesson else { return false }
        if let rel = lesson.pagesFileRelativePath, !rel.isEmpty { return true }
        return lesson.pagesFileBookmark != nil
    }

    func openLessonFile() {
        if let url = resolveLessonPagesURL() {
            openInPages(url)
        }
    }

    // MARK: - Lesson picker

    @ViewBuilder
    var lessonPickerIfNeeded: some View {
        if currentLesson == nil || vm.showLessonPicker {
            LessonPickerSection(
                viewModel: lessonPickerVM,
                resolvedLesson: lessons.first(where: { $0.id == lessonPickerVM.selectedLessonID }) ?? currentLesson,
                isFocused: $lessonPickerFocused
            )
        }
    }

    // MARK: - Sequence

    /// The sequence recap folded to one line; it opens to the full grid.
    @ViewBuilder
    var sequenceLine: some View {
        if let recap = vm.groupRecap, !recap.lessonsInSequence.isEmpty {
            DisclosureGroup {
                groupRecapSection
                    .padding(.top, 8)
            } label: {
                Label(recap.sequenceName, systemImage: "list.bullet.indent")
                    .font(AppTheme.ScaledFont.calloutSemibold)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(
                Color.primary.opacity(UIConstants.OpacityConstants.whisper),
                in: RoundedRectangle(cornerRadius: UIConstants.CornerRadius.large, style: .continuous)
            )
        }
    }

    @ViewBuilder
    var groupRecapSection: some View {
        if let recap = vm.groupRecap, !recap.lessonsInSequence.isEmpty {
            SequenceRecapSection(
                recap: recap,
                onUpdateState: { lessonID, studentID, newState in
                    vm.updateSiblingLessonProficiencyState(
                        lessonID: lessonID.uuidString,
                        studentID: studentID.uuidString,
                        state: newState,
                        lessons: lessons,
                        currentLesson: currentLesson,
                        students: selectedStudentsList
                    )
                },
                onOpenWork: { workID in
                    vm.recapWorkSheetID = workID
                },
                onCycleWorkStatus: { workID, newStatus in
                    vm.cycleRecapWorkStatus(
                        workID: workID,
                        to: newStatus,
                        currentLesson: currentLesson,
                        students: selectedStudentsList
                    )
                },
                onAddWork: { lessonID, studentID, presentationID in
                    vm.addRecapWork(
                        lessonID: lessonID,
                        studentID: studentID,
                        presentationID: presentationID,
                        currentLesson: currentLesson,
                        students: selectedStudentsList
                    )
                }
            )
        }
    }

    // MARK: - Before you start

    /// The children's open work from earlier in the sequence, above "Who was
    /// there?". Shown only when it has a row to list: `showFirst` can hold a
    /// child the plan no longer lists.
    @ViewBuilder
    var beforeYouStartSection: some View {
        if !PresentationBeforeYouStartSection.rows(students: selectedStudentsList, showFirst: showFirst).isEmpty {
            PresentationBeforeYouStartSection(
                students: selectedStudentsList,
                showFirst: showFirst,
                onLog: logEarlierWork,
                onOpenWork: { vm.recapWorkSheetID = $0 }
            )
        }
    }

    /// The saves that can change "Before you start": work rows and the
    /// participant rows that say whose part is done.
    nonisolated static let showFirstEntityNames: Set<String> = ["WorkModel", "WorkParticipantEntity"]

    func refreshWorkToShowFirst() {
        guard !vm.isPresented else {
            if !showFirst.isEmpty { showFirst = [:] }
            return
        }
        showFirst = WorkToShowFirst.find(
            lessonID: vm.editingLessonID.uuidString,
            studentIDs: vm.selectedStudentIDs,
            sequences: WorkToShowFirst.Sequences(lessons: lessons),
            in: viewContext
        )
    }

    /// Closes one row of earlier work the way every other log does, and
    /// offers Undo. A row logged elsewhere since the list was read is only
    /// taken off the list; a shared row is never logged from here.
    func logEarlierWork(_ item: WorkToShowFirst.Item, as status: WorkStatus) {
        let saveCoordinator = dependencies.saveCoordinator
        do {
            let receipt = try WorkToShowFirst.log(
                item, as: status, context: viewContext, saveCoordinator: saveCoordinator
            )
            refreshWorkToShowFirst()
            vm.recomputeSequenceRecap(currentLesson: currentLesson, students: selectedStudentsList)
            dependencies.toastService.show("Logged as \(status.displayName)", type: .success, duration: 5) {
                do {
                    try WorkLogService.undo(receipt.token, context: viewContext, saveCoordinator: saveCoordinator)
                } catch {
                    let message = PresentationFailureMessage.message(
                        for: error, fallback: "Couldn't undo that. Try again."
                    )
                    dependencies.toastService.show(message, type: .error, duration: 4)
                }
                refreshWorkToShowFirst()
                vm.recomputeSequenceRecap(currentLesson: currentLesson, students: selectedStudentsList)
            }
        } catch WorkToShowFirst.LogRefusal.noLongerOpen {
            refreshWorkToShowFirst()
        } catch WorkToShowFirst.LogRefusal.sharedWithOthers {
            refreshWorkToShowFirst()
            dependencies.toastService.show(
                "Other children share this work. Open it to log it.", type: .info, duration: 4
            )
        } catch {
            let message = PresentationFailureMessage.message(for: error, fallback: "Couldn't log that work. Try again.")
            dependencies.toastService.show(message, type: .error, duration: 4)
        }
    }

    // MARK: - Children

    var whoWasThereSection: some View {
        PresentationWhoWasThereSection(
            students: selectedStudentsList,
            presentIDs: session.presentIDs,
            attendance: attendance,
            masteredOn: masteredOn,
            isToday: calendar.isDateInToday(session.presentedDay),
            onToggle: { session.togglePresent($0) },
            onRemove: { vm.selectedStudentIDs.remove($0) },
            onSplit: { openMoveStudentsSheet(preselecting: $0) },
            addButton: { addChildrenButton }
        )
        .sheet(isPresented: $vm.showingFindStudentsSheet) {
            findStudentsSheet
        }
    }

    var addChildrenButton: some View {
        // Side by side where they fit; stacked on a phone, where together
        // they are wider than the screen.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 20) { childrenButtons }
            VStack(alignment: .leading, spacing: 10) { childrenButtons }
        }
        .popover(isPresented: $vm.showingStudentPickerPopover, arrowEdge: .top) {
            studentPickerPopover
        }
    }

    @ViewBuilder
    private var childrenButtons: some View {
        Button {
            vm.showingStudentPickerPopover = true
        } label: {
            Label("Add or Remove Children", systemImage: "person.2.badge.gearshape")
        }
        .buttonStyle(.borderless)

        if selectedStudentsList.count > 1 {
            Button {
                openMoveStudentsSheet()
            } label: {
                Label("Split Off to a Different Group", systemImage: "person.2.slash")
            }
            .buttonStyle(.borderless)
        }
    }

    var studentPillsSection: some View {
        let lesson: CDLesson? = currentLesson
        let areaColor: Color = AppColors.color(forArea: lesson?.area ?? "")
        return StudentPillsSection(
            students: selectedStudentsList,
            lessonOnRecord: lesson,
            areaColor: areaColor,
            onRemove: { id in vm.selectedStudentIDs.remove(id) },
            onOpenPicker: { vm.showingStudentPickerPopover = true },
            onOpenMove: { openMoveStudentsSheet() },
            canMoveStudents: false,
            onOpenFindStudents: { vm.showingFindStudentsSheet = true },
            onOpenMoveAbsent: {},
            canMoveAbsentStudents: false
        )
        .popover(isPresented: $vm.showingStudentPickerPopover, arrowEdge: .top) {
            studentPickerPopover
        }
        .sheet(isPresented: $vm.showingFindStudentsSheet) {
            findStudentsSheet
        }
    }

    var studentPickerPopover: some View {
        StudentPickerPopover(
            students: studentsAll,
            selectedIDs: $vm.selectedStudentIDs,
            onDone: { vm.showingStudentPickerPopover = false },
            lessonOnRecord: currentLesson,
            // Only the class as it is now. A child already on this
            // presentation who has since left stays under Selected, disabled,
            // so she can be taken off; any other leaver is not listed.
            formerStudents: .shownIfSelected,
            // Selected, then Ready for this lesson, then everyone else, A–Z;
            // no Age sort here.
            arrangement: .selectedThenReady
        )
        .padding(12)
        .frame(minWidth: 320)
    }

    var findStudentsSheet: some View {
        LiveLessonAssignments { allLessonAssignments in
            FindStudentsSheet(
                lessonID: vm.editingLessonID,
                existingStudentIDs: vm.selectedStudentIDs,
                allStudents: studentsAll,
                allLessonAssignments: allLessonAssignments,
                onAdd: { newIDs in
                    vm.selectedStudentIDs.formUnion(newIDs)
                    vm.showingFindStudentsSheet = false
                },
                onCancel: { vm.showingFindStudentsSheet = false }
            )
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    func openMoveStudentsSheet(preselecting id: UUID? = nil) {
        vm.studentsToMove = id.map { [$0] } ?? []
        vm.showingMoveStudentsSheet = true
    }

    var notesSection: some View {
        PresentationNotesSectionUnified(
            lessonAssignment: vm.lessonAssignment,
            legacyNotes: $vm.notes,
            onLegacyNotesChange: { vm.notes = $0 }
        )
    }

    // MARK: - Sheets

    var moveStudentsSheet: some View {
        MoveStudentsSheet(
            lessonName: vm.splitLesson(from: lessons)?.name ?? currentLessonName,
            students: selectedStudentsList,
            studentsToMove: $vm.studentsToMove,
            selectedStudentIDs: vm.selectedStudentIDs,
            onMove: handleMoveStudents,
            onCancel: cancelMoveStudents
        )
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 520)
        .presentationSizingFitted()
        #endif
    }

    var rescheduleSheet: some View {
        NavigationStack {
            Form {
                InboxStatusSection(scheduledFor: $vm.scheduledFor)
            }
            .formStyle(.grouped)
            .navigationTitle("Reschedule")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showRescheduleSheet = false }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 320)
        #else
        .presentationDetents([.medium])
        #endif
    }

    func handleMoveStudents() {
        vm.moveStudentsToInbox(
            studentsAll: studentsAll,
            lessonAssignmentsAll: lessonAssignmentsAll,
            lessons: lessons
        )
        vm.showingMoveStudentsSheet = false
    }

    func cancelMoveStudents() {
        vm.studentsToMove = []
        vm.showingMoveStudentsSheet = false
    }
}
