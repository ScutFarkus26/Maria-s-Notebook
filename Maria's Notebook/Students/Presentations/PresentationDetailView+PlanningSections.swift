import SwiftUI
import CoreData

// MARK: - Planning Section Builders

extension PresentationDetailContentView {

    // MARK: - Sections

    var lessonHeaderSection: some View {
        PresentationHeaderView(
            lessonName: currentLesson?.name ?? "Lesson",
            area: currentLesson?.area ?? "",
            sequence: currentLesson?.sequence ?? "",
            areaColor: AppColors.color(forArea: currentLesson?.area ?? ""),
            onTapTitle: lessonHasFile ? ({ openLessonFile() }) : nil
        )
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

    var studentPillsSection: some View {
        StudentPillsSection(
            students: selectedStudentsList,
            areaColor: AppColors.color(forArea: currentLesson?.area ?? ""),
            onRemove: { id in vm.selectedStudentIDs.remove(id) },
            onOpenPicker: { vm.showingStudentPickerPopover = true },
            onOpenMove: openMoveStudentsSheet,
            canMoveStudents: selectedStudentsList.count > 1 && !vm.isPresented,
            onOpenFindStudents: { vm.showingFindStudentsSheet = true },
            onOpenMoveAbsent: openMoveAbsentStudents,
            canMoveAbsentStudents: canMoveAbsentStudents
        )
        .popover(isPresented: $vm.showingStudentPickerPopover, arrowEdge: .top) {
            StudentPickerPopover(
                students: studentsAll,
                selectedIDs: $vm.selectedStudentIDs,
                onDone: { vm.showingStudentPickerPopover = false }
            )
            .padding(12)
            .frame(minWidth: 320)
        }
        .sheet(isPresented: $vm.showingFindStudentsSheet) {
            FindStudentsSheet(
                lessonID: vm.editingLessonID,
                existingStudentIDs: vm.selectedStudentIDs,
                allStudents: studentsAll,
                allLessonAssignments: lessonAssignmentsAll,
                onAdd: { newIDs in
                    vm.selectedStudentIDs.formUnion(newIDs)
                    vm.showingFindStudentsSheet = false
                },
                onCancel: { vm.showingFindStudentsSheet = false }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    func openMoveStudentsSheet() {
        vm.studentsToMove = []
        vm.showingMoveStudentsSheet = true
    }

    var inboxStatusSection: some View {
        InboxStatusSection(scheduledFor: $vm.scheduledFor)
    }

    var notesSection: some View {
        PresentationNotesSectionUnified(
            lessonAssignment: vm.lessonAssignment,
            legacyNotes: $vm.notes,
            onLegacyNotesChange: { vm.notes = $0 }
        )
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

    @ViewBuilder
    func lessonPickerOrChangeControl(horizontalPadding: CGFloat) -> some View {
        if currentLesson == nil || vm.showLessonPicker {
            VStack(alignment: .leading, spacing: 8) {
                LessonPickerSection(
                    viewModel: lessonPickerVM,
                    resolvedLesson: lessons.first(where: { $0.id == lessonPickerVM.selectedLessonID }) ?? currentLesson,
                    isFocused: $lessonPickerFocused
                )
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, 16)
        } else {
            ChangeLessonControl(showLessonPicker: $vm.showLessonPicker)
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 8)
        }
    }

    var progressButtonsRow: some View {
        ProgressStateRow(
            onJustPresented: selectJustPresented,
            onPreviouslyPresented: selectPreviouslyPresented,
            isJustPresentedActive: isJustPresentedActive,
            isPreviouslyPresentedActive: isPreviouslyPresentedActive
        )
    }

    var bottomBar: some View {
        PresentationBottomBar(
            onDelete: { vm.showDeleteAlert = true },
            onCancel: handleCancelWithCleanup,
            onSave: handleSaveAndDone,
            isSaveDisabled: vm.selectedStudentIDs.isEmpty
        )
    }

    var moveStudentsSheet: some View {
        MoveStudentsSheet(
            lessonName: currentLessonName,
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

    // MARK: - Mastery Status Row

    var proficiencyStatusRow: some View {
        ProficiencyStateRow(proficiencyState: $vm.proficiencyState)
    }

    // MARK: - Progress State Logic

    var isJustPresentedActive: Bool {
        PresentationProgressHelper.isJustPresentedActive(
            isPresented: vm.isPresented,
            givenAt: vm.givenAt,
            calendar: calendar
        )
    }

    var isPreviouslyPresentedActive: Bool {
        PresentationProgressHelper.isPreviouslyPresentedActive(
            isPresented: vm.isPresented,
            givenAt: vm.givenAt,
            calendar: calendar
        )
    }

    func selectJustPresented() {
        let presentedDay = calendar.startOfDay(for: Date())

        guard currentLesson != nil else {
            presentationRecordErrorMessage = "Choose the lesson before recording this presentation."
            return
        }
        guard !vm.selectedStudentIDs.isEmpty else {
            presentationRecordErrorMessage = "Choose at least one child before recording this presentation."
            return
        }

        // Apply lesson and roster edits before either recording or reopening the
        // optional reflection, so its fixed context always matches the assignment.
        vm.applyEditsToModel(studentsAll: studentsAll, lessons: lessons, calendar: calendar)

        // Reopening a presentation already recorded today should return to the
        // optional reflection without creating another lifecycle event.
        if vm.lessonAssignment.isPresented,
           let existingDate = vm.lessonAssignment.presentedAt,
           calendar.isDate(existingDate, inSameDayAs: presentedDay) {
            guard vm.saveCoordinator.save(
                viewContext,
                reason: "Saving edits before reopening presentation reflection"
            ) else {
                presentationRecordErrorMessage = vm.saveCoordinator.lastSaveErrorMessage
                    ?? "The lesson or roster changes could not be saved."
                return
            }
            setPresentationState(isPresented: true, givenAt: presentedDay, needsAnother: false)
            presentationUndoToken = nil
            postPresentationFlow.beginReflection()
            showPostPresentationCapture = true
            return
        }

        do {
            let undoToken = try ImmediatePresentationRecordingService.record(
                assignment: vm.lessonAssignment,
                presentedOn: presentedDay,
                context: viewContext,
                saveCoordinator: vm.saveCoordinator
            )
            presentationUndoToken = undoToken
            setPresentationState(isPresented: true, givenAt: presentedDay, needsAnother: false)
            postPresentationFlow.beginReflection()

            ToastService.shared.show(
                "Presentation recorded",
                type: .success,
                duration: 5,
                undoAction: {
                    Task { @MainActor in _ = undoJustPresented() }
                }
            )
            showPostPresentationCapture = true
        } catch {
            presentationRecordErrorMessage = error.localizedDescription
        }
    }

    func undoJustPresented() -> String? {
        guard let presentationUndoToken else { return nil }
        do {
            try ImmediatePresentationRecordingService.undo(
                presentationUndoToken,
                context: viewContext,
                saveCoordinator: vm.saveCoordinator
            )
            self.presentationUndoToken = nil
            vm.isPresented = vm.lessonAssignment.isPresented
            vm.givenAt = vm.lessonAssignment.presentedAt
            vm.needsAnotherPresentation = vm.lessonAssignment.needsAnotherPresentation
            postPresentationFlow.undoPresentation()
            showPostPresentationCapture = false
            ToastService.shared.showInfo("Presentation recording undone")
            return nil
        } catch {
            presentationRecordErrorMessage = error.localizedDescription
            return error.localizedDescription
        }
    }

    func selectPreviouslyPresented() {
        let givenAt = vm.givenAt.flatMap { calendar.isDateInToday($0) ? nil : $0 }
        setPresentationState(isPresented: true, givenAt: givenAt, needsAnother: false)
        vm.enterWorkflowMode(students: selectedStudentsList)
        vm.showAssignmentComposer = true
    }

    func setPresentationState(isPresented: Bool, givenAt: Date?, needsAnother: Bool) {
        vm.isPresented = isPresented
        vm.givenAt = givenAt
        vm.needsAnotherPresentation = needsAnother
    }

    // MARK: - Absent Logic

    var scheduledAttendanceDay: Date { AppCalendar.startOfDay(Date()) }

    var absentStudentIDs: Set<UUID> {
        PresentationAbsentHelper.computeAbsentStudentIDs(
            selectedStudentIDs: vm.selectedStudentIDs,
            scheduledDay: scheduledAttendanceDay,
            context: viewContext
        )
    }

    var canMoveAbsentStudents: Bool {
        PresentationAbsentHelper.canMoveAbsentStudents(
            studentCount: selectedStudentsList.count,
            isPresented: vm.isPresented,
            absentStudentIDs: absentStudentIDs
        )
    }

    func openMoveAbsentStudents() {
        guard !absentStudentIDs.isEmpty else { return }
        vm.studentsToMove = absentStudentIDs
        vm.showingMoveStudentsSheet = true
    }
}
