// PresentationDetailView+Recording.swift
// The sheet's pinned footer and the moves between its two beats: Record (for
// today, an earlier day, or an earlier undated presentation), Undo, Later and
// Done.

import CoreData
import SwiftUI

extension PresentationDetailContentView {

    // MARK: - Footer

    var footer: some View {
        VStack(spacing: 0) {
            Divider()
            Group {
                if vm.isPresented {
                    presentedFooter
                } else {
                    recordFooter
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(.bar)
    }

    private var recordFooter: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                recordDayMenu
                Spacer(minLength: 8)
                cancelButton
                saveButton
                recordButton
            }
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    recordDayMenu
                    Spacer()
                    cancelButton
                    saveButton
                }
                recordButton.frame(maxWidth: .infinity)
            }
        }
    }

    private var presentedFooter: some View {
        HStack(spacing: 10) {
            cancelButton
            Spacer(minLength: 8)
            saveButton
            Button(action: continueToHowItWent) {
                Text("How It Went…").bold()
            }
            .buttonStyle(.borderedProminent)
            .disabled(currentLesson == nil || vm.selectedStudentIDs.isEmpty)
        }
    }

    /// How It Went gives work and files notes for the children the record
    /// names, so a change to the children or the lesson lands first, the way
    /// Save lands it (asking about work already given to a child taken off).
    func continueToHowItWent() {
        guard vm.hasUnsavedRosterOrLesson else {
            showHowItWent()
            return
        }
        let plans = vm.workRetractionPlans()
        howItWentAfterSave = true
        if plans.isEmpty {
            saveAndDone(retractingWork: [])
        } else {
            vm.pendingWorkRetraction = plans
        }
    }

    private var cancelButton: some View {
        Button("Cancel", action: handleCancelWithCleanup)
            .keyboardShortcut(.cancelAction)
    }

    private var saveButton: some View {
        Button("Save", action: handleSaveAndDone)
            .keyboardShortcut("s", modifiers: .command)
            .disabled(vm.selectedStudentIDs.isEmpty)
            .help("Save changes to the plan without recording it")
    }

    private var presentCount: Int {
        session.presentIDs.intersection(vm.selectedStudentIDs).count
    }

    private var recordButton: some View {
        Button(action: record) {
            Text(presentCount == 1 ? "Record Presentation · 1 child" : "Record Presentation · \(presentCount) children")
                .bold()
                .frame(minHeight: 22)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(presentCount == 0 || currentLesson == nil)
    }

    private var recordDayLabel: String {
        let day = session.presentedDay
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private var recordDayMenu: some View {
        Menu {
            Button("Today") { session.presentedDay = AppCalendar.startOfDay(Date()) }
            Button("Yesterday") {
                session.presentedDay = AppCalendar.startOfDay(
                    calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date()
                )
            }
            Button("Pick a Day…") {
                recordPickedDay = session.presentedDay
                showRecordDayPicker = true
            }
            Divider()
            Button("Earlier, Date Unknown", action: recordUndated)
        } label: {
            Label(recordDayLabel, systemImage: "calendar")
        }
        .fixedSize()
        .help("The day the lesson was given")
        .popover(isPresented: $showRecordDayPicker) {
            VStack(spacing: 12) {
                DatePicker(
                    "Presented on",
                    selection: $recordPickedDay,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                Button("Use This Day") {
                    session.presentedDay = AppCalendar.startOfDay(recordPickedDay)
                    showRecordDayPicker = false
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .frame(minWidth: 300)
        }
    }

    // MARK: - Record

    func record() {
        guard currentLesson != nil else {
            errorMessage = PresentationRecorder.RecordError.missingLesson.localizedDescription
            return
        }
        let present = session.presentIDs.intersection(vm.selectedStudentIDs)
        guard !present.isEmpty else {
            errorMessage = PresentationRecorder.RecordError.nobodyPresent.localizedDescription
            return
        }
        let day = AppCalendar.startOfDay(session.presentedDay)

        // Lesson and roster edits land first, so the record matches the sheet.
        vm.applyEditsToModel(studentsAll: studentsAll, lessons: lessons, calendar: calendar)

        do {
            let result = try PresentationRecorder.record(
                vm.lessonAssignment,
                presentIDs: present,
                on: day,
                context: viewContext,
                saveCoordinator: vm.saveCoordinator
            )
            session.undoToken = result.undoToken
            session.keptOnPlanNames = studentsAll
                .filter { $0.id.map(result.keptOnPlan.contains) ?? false }
                .map(\.shortName)
            vm.selectedStudentIDs = Set(vm.lessonAssignment.resolvedStudentIDs)
            vm.isPresented = true
            vm.givenAt = day
            vm.needsAnotherPresentation = false
            showHowItWent()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// An earlier presentation whose day nobody knows: it is marked given
    /// without a date (never today's) and the sheet closes.
    func recordUndated() {
        guard currentLesson != nil, !vm.selectedStudentIDs.isEmpty else {
            errorMessage = PresentationRecorder.RecordError.nobodyPresent.localizedDescription
            return
        }
        vm.isPresented = true
        vm.givenAt = nil
        vm.needsAnotherPresentation = false
        handleSaveAndDone()
    }

    func undoRecording() {
        guard let token = session.undoToken else { return }
        do {
            try ImmediatePresentationRecordingService.undo(
                token,
                context: viewContext,
                saveCoordinator: vm.saveCoordinator
            )
            session.undoToken = nil
            session.keptOnPlanNames = []
            vm.isPresented = vm.lessonAssignment.isPresented
            vm.givenAt = vm.lessonAssignment.presentedAt
            vm.needsAnotherPresentation = vm.lessonAssignment.needsAnotherPresentation
            vm.selectedStudentIDs = Set(vm.lessonAssignment.resolvedStudentIDs)
            session.clearNotes()
            session.showWho()
            refreshAttendance()
            dependencies.toastService.showInfo("Presentation recording undone")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - How It Went

    /// A presentation still being followed, or left with Later, opens on How It Went.
    func reopenHowItWentIfFollowing() {
        guard vm.isPresented, session.phase == .who, let id = vm.lessonAssignment.id else { return }
        let hasDraft = PresentationSessionDraftStore.load(presentationID: id) != nil
        if hasDraft || PresentationFollowUpService.hasOpenFollowUps(for: id, in: viewContext) {
            showHowItWent()
        }
    }

    func showHowItWent() {
        guard let lesson = currentLesson else { return }
        let rules = LessonProgressionRules.resolve(for: lesson, context: viewContext)
        session.loadDecisions(
            studentIDs: recordedStudentIDs,
            defaultDecision: rules.requiresPractice ? .practice : .continueObserving,
            context: viewContext
        )
        session.showHowItWent()
    }

    var recordedStudentIDs: [UUID] {
        selectedStudentsList.compactMap(\.id)
    }

    func howItWentContent(lesson: CDLesson) -> some View {
        PresentationHowItWentView(
            session: session,
            lesson: lesson,
            students: selectedStudentsList,
            presentedAt: vm.givenAt,
            nextLessonName: PlanNextLessonService.findNextLesson(after: lesson, in: lessons)?.name,
            canUndo: session.undoToken != nil,
            isSaving: isSavingSession,
            onUndo: undoRecording,
            onEditDetails: { session.showWho() },
            onLater: { saveLater(closing: true) },
            onDone: commitDone
        )
    }

    /// Later: the notes are facts, so they are filed now; the decisions wait
    /// as a draft and the presentation stays in Following.
    func saveLater(closing: Bool) {
        guard !session.isFinished, let presentationID = vm.lessonAssignment.id else {
            if closing { handleDone() }
            return
        }
        let ids = recordedStudentIDs
        if session.hasNotes {
            do {
                try PresentationOutcomePersistenceService.persistObservations(
                    groupObservation: session.groupNote,
                    studentObservations: session.childNotes,
                    studentIDs: ids,
                    presentationID: presentationID,
                    context: viewContext
                )
                guard vm.saveCoordinator.save(viewContext, reason: "Saving presentation notes") else {
                    errorMessage = vm.saveCoordinator.lastSaveErrorMessage ?? "The notes could not be saved."
                    return
                }
                session.clearNotes()
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }
        if session.pendingDecisions(for: ids).isEmpty && !session.checkInChanged {
            PresentationSessionDraftStore.clear(presentationID: presentationID)
        } else {
            PresentationSessionDraftStore.save(session.draft, presentationID: presentationID)
        }
        session.markFinished()
        if closing { handleDone() }
    }

    /// Done: notes, decisions, check-ins and next lessons in one save.
    func commitDone() {
        guard let lesson = currentLesson, !isSavingSession else { return }
        let ids = recordedStudentIDs
        guard session.hasChanges(for: ids) else {
            if let id = vm.lessonAssignment.id { PresentationSessionDraftStore.clear(presentationID: id) }
            session.markFinished()
            handleDone()
            return
        }
        isSavingSession = true
        defer { isSavingSession = false }
        do {
            try PresentationSessionCommit.apply(
                PresentationSessionCommit.Input(
                    assignment: vm.lessonAssignment,
                    lesson: lesson,
                    studentIDs: ids,
                    groupNote: session.groupNote,
                    childNotes: session.childNotes,
                    decisions: session.pendingDecisions(for: ids),
                    allDecisions: Dictionary(uniqueKeysWithValues: ids.map { ($0, session.decision(for: $0)) }),
                    checkIn: session.checkIn,
                    lessons: lessons
                ),
                context: viewContext,
                saveCoordinator: vm.saveCoordinator
            )
            if let id = vm.lessonAssignment.id { PresentationSessionDraftStore.clear(presentationID: id) }
            session.clearNotes()
            session.markFinished()
            PresentationDetailUtilities.notifyInboxRefresh()
            dependencies.toastService.showSuccess("\(lesson.name) saved")
            handleDone()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
