import SwiftUI
import CoreData

// MARK: - Planning Section Builders

extension PresentationDetailContentView {

    // MARK: - Sections

    var lessonHeaderSection: some View {
        PresentationHeaderView(
            lessonName: currentLesson?.name ?? "Lesson",
            subject: currentLesson?.subject ?? "",
            group: currentLesson?.group ?? "",
            subjectColor: AppColors.color(forSubject: currentLesson?.subject ?? ""),
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
            subjectColor: AppColors.color(forSubject: currentLesson?.subject ?? ""),
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
        setPresentationState(isPresented: true, givenAt: calendar.startOfDay(for: Date()), needsAnother: false)
        vm.enterWorkflowMode(students: selectedStudentsList)
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
            viewContext: viewContext
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
