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
            Button("Move Students…", systemImage: "arrow.right.square") {
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
            addButton: { addChildrenButton }
        )
        .sheet(isPresented: $vm.showingFindStudentsSheet) {
            findStudentsSheet
        }
    }

    var addChildrenButton: some View {
        Button {
            vm.showingStudentPickerPopover = true
        } label: {
            Label("Add or Remove Children", systemImage: "person.2.badge.gearshape")
        }
        .buttonStyle(.borderless)
        .popover(isPresented: $vm.showingStudentPickerPopover, arrowEdge: .top) {
            studentPickerPopover
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
            onOpenMove: openMoveStudentsSheet,
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
            // The roster may already hold a child who has since left; she
            // stays visible here, disabled, so she can be taken off.
            formerStudents: .shownBlocked
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

    func openMoveStudentsSheet() {
        vm.studentsToMove = []
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
