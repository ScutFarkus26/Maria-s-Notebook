import CoreData
import SwiftUI

@MainActor
struct PostPresentationFollowUpView: View {
    let assignment: CDLessonAssignment
    let lesson: CDLesson
    let students: [CDStudent]
    let lessons: [CDLesson]
    let lessonAssignments: [CDLessonAssignment]
    let onReturnToLesson: () -> Void
    let onClose: () -> Void

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.calendar) private var calendar
    @Environment(\.appRouter) private var appRouter
    @Environment(SaveCoordinator.self) private var saveCoordinator

    @FetchRequest private var followUpRows: FetchedResults<CDLessonPresentation>
    @FetchRequest private var linkedWork: FetchedResults<CDWorkModel>
    @State private var nextLessonViewModel: PostPresentationFormViewModel
    @State private var observationSelection: ObservationSelection?
    @State private var editorModel = PresentationFollowUpEditorModel()
    @State private var showCustomReviewDate = false
    @State private var customReviewDate = AppCalendar.startOfDay(Date())
    @State private var saveErrorMessage: String?
    @State private var hasUnsavedWorkDraft = false
    @State private var pendingExit: PendingExit?
    @State private var showDiscardWorkConfirmation = false

    init(
        assignment: CDLessonAssignment,
        lesson: CDLesson,
        students: [CDStudent],
        lessons: [CDLesson],
        lessonAssignments: [CDLessonAssignment],
        onReturnToLesson: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.assignment = assignment
        self.lesson = lesson
        self.students = students
        self.lessons = lessons
        self.lessonAssignments = lessonAssignments
        self.onReturnToLesson = onReturnToLesson
        self.onClose = onClose

        let presentationID = assignment.id?.uuidString ?? "__missing_presentation__"
        _followUpRows = FetchRequest(
            sortDescriptors: [NSSortDescriptor(key: "studentID", ascending: true)],
            predicate: NSPredicate(format: "presentationID == %@", presentationID),
            animation: .default
        )
        _linkedWork = FetchRequest(
            sortDescriptors: [NSSortDescriptor(key: "createdAt", ascending: true)],
            predicate: NSPredicate(format: "presentationID == %@", presentationID),
            animation: .default
        )
        _nextLessonViewModel = State(
            initialValue: PostPresentationFormViewModel(students: students)
        )
    }

    private var allRows: [CDLessonPresentation] { Array(followUpRows) }
    private var openRows: [CDLessonPresentation] { allRows.filter(\.hasOpenFollowUp) }
    private var allLinkedWork: [CDWorkModel] { Array(linkedWork).uniqueByID }

    private var focusedRow: CDLessonPresentation? {
        guard case .child(let objectID) = editorModel.scope else { return nil }
        return allRows.first { $0.objectID == objectID }
    }

    private var planningRows: [CDLessonPresentation] {
        editorModel.rowsInScope(from: allRows)
    }

    private var workRows: [CDLessonPresentation] {
        switch editorModel.scope {
        case .allChildren:
            return allRows
        case .child(let objectID):
            return allRows.filter { $0.objectID == objectID }
        }
    }

    private var planningStudentIDs: Set<UUID> {
        Set(planningRows.compactMap { UUID(uuidString: $0.studentID) })
    }

    /// Drives reconciliation when Core Data changes outside the action picker,
    /// such as after recording an observation or resolving a plan.
    private var followUpStateSignature: [String] {
        allRows.map { row in
            [
                row.objectID.uriRepresentation().absoluteString,
                row.followUpActionRaw ?? "",
                row.followUpReviewAt?.timeIntervalSinceReferenceDate.description ?? "",
                row.followUpSupportRaw ?? "",
                row.followUpResolvedAt?.timeIntervalSinceReferenceDate.description ?? ""
            ]
            .joined(separator: "|")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if allRows.isEmpty {
                        completedState
                    } else {
                        planningScopeSection
                        childWorkSection
                        if openRows.isEmpty {
                            completedState
                        } else if planningRows.isEmpty {
                            scopedGuideFollowUpCompleteState
                            childrenSection
                        } else {
                            actionSection
                            contextualPlanningSection
                            childrenSection
                        }
                    }
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity)
            }

            Divider()
            bottomBar
        }
        .navigationTitle("Follow This Presentation")
        .onAppear {
            synchronizeEditorFromOpenRows()
            restoreWorkDraftScopeIfNeeded()
            resolveNextLesson()
        }
        .onChange(of: planningStudentIDs) { _, _ in
            resolveNextLesson()
        }
        .onChange(of: followUpStateSignature) { _, _ in
            synchronizeEditorFromOpenRows()
        }
        .sheet(item: $observationSelection, onDismiss: synchronizeAfterChildWorkflow) { selection in
            PresentationFollowUpObservationSheet(
                row: selection.row,
                studentName: studentName(for: selection.row),
                lessonName: lesson.name
            )
        }
        .alert("Couldn’t Save Follow-Up", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("OK") { saveErrorMessage = nil }
        } message: {
            Text(saveErrorMessage ?? "The follow-up could not be saved.")
        }
        .interactiveDismissDisabled(hasUnsavedWorkDraft)
        .confirmationDialog(
            "Discard Unsaved Work Invitation?",
            isPresented: $showDiscardWorkConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard and Continue", role: .destructive) {
                discardCurrentWorkDraft()
                hasUnsavedWorkDraft = false
                if let pendingExit {
                    performExit(pendingExit)
                }
                pendingExit = nil
            }
            Button("Keep Editing", role: .cancel) {
                pendingExit = nil
            }
        } message: {
            Text("Choose Add Work before leaving if you want this invitation to appear in Children Working.")
        }
    }
}

private extension PostPresentationFollowUpView {
    var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(AppColors.success)

            VStack(alignment: .leading, spacing: 5) {
                Text("Presentation Recorded")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(lesson.name)
                    .font(.title2.weight(.semibold))
                Text(presentationContextText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !openRows.isEmpty {
                Label("Following", systemImage: "eye.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.1), in: Capsule())
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    var presentationContextText: String {
        let date = (assignment.presentedAt ?? Date()).formatted(date: .abbreviated, time: .omitted)
        let names = students.map { StudentFormatter.displayName(for: $0) }.joined(separator: ", ")
        return names.isEmpty ? date : "\(names) • \(date)"
    }

    var actionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("How should this come back to you?")
                        .font(.title3.weight(.semibold))
                    Text(actionSectionHelpText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if editorModel.hasMixedActions {
                    Label("Multiple Values", systemImage: "minus.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Picker("Follow-up", selection: actionSelectionBinding) {
                if editorModel.hasMixedActions {
                    Text("Multiple Values")
                        .tag(mixedActionSelectionValue)
                        .disabled(true)
                }

                ForEach(PresentationFollowUpAction.allCases) { action in
                    Label(action.title, systemImage: action.systemImage)
                        .tag(action.rawValue)
                }
            }
            #if os(macOS)
            .pickerStyle(.radioGroup)
            #else
            .pickerStyle(.inline)
            #endif
        }
    }

    var planningScopeSection: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Planning for")
                .font(.subheadline.weight(.semibold))

            Menu {
                Button {
                    setScope(.allChildren)
                } label: {
                    scopeMenuLabel(
                        allChildrenScopeTitle,
                        isSelected: editorModel.scope == .allChildren
                    )
                }

                Divider()

                ForEach(allRows, id: \.objectID) { row in
                    Button {
                        setScope(.child(row.objectID))
                    } label: {
                        scopeMenuLabel(
                            studentName(for: row),
                            isSelected: editorModel.scope == .child(row.objectID)
                        )
                    }
                }
            } label: {
                Text(currentScopeTitle)
            }
            .menuStyle(.button)
            .frame(maxWidth: 260, alignment: .leading)

            Spacer()

            Text("Work stays editable after guide follow-up is complete")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    var childWorkSection: some View {
        if let presentationID = assignment.id {
            PresentationFollowUpWorkSection(
                presentationID: presentationID,
                lesson: lesson,
                scopedRows: workRows,
                students: students,
                linkedWork: openLinkedWork,
                hasUnsavedDraft: $hasUnsavedWorkDraft,
                onOpenWork: {
                    requestExit(.openWork)
                }
            )
        }
    }

    var actionSelectionBinding: Binding<String> {
        Binding(
            get: { editorModel.selectedAction?.rawValue ?? mixedActionSelectionValue },
            set: { rawValue in
                guard let newAction = PresentationFollowUpAction(rawValue: rawValue) else { return }
                setAction(newAction)
            }
        )
    }

    var mixedActionSelectionValue: String { "__multiple_follow_up_actions__" }

    var allChildrenScopeTitle: String {
        allRows.count == 1 ? "All Children" : "All \(allRows.count) Children"
    }

    var currentScopeTitle: String {
        guard case .child(let objectID) = editorModel.scope,
              let row = allRows.first(where: { $0.objectID == objectID }) else {
            return allChildrenScopeTitle
        }
        return studentName(for: row)
    }

    @ViewBuilder
    func scopeMenuLabel(_ title: String, isSelected: Bool) -> some View {
        if isSelected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }

    @ViewBuilder
    var contextualPlanningSection: some View {
        switch editorModel.selectedAction {
        case .checkWork:
            checkWorkSection
        case .planSupport:
            supportSection
        case .planNextPresentation:
            nextLessonSection
        case .watchWork, .none:
            EmptyView()
        }
    }

    var checkWorkSection: some View {
        followUpInset(title: "When should you check the work?", systemImage: "calendar.badge.clock") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Button("Next Work Cycle") {
                        setAction(.checkWork, rows: planningRows, reviewAt: nil)
                    }
                    .buttonStyle(.bordered)

                    Button("Next School Day") {
                        Task { @MainActor in
                            let next = await SchoolCalendarService.shared
                                .nextSchoolDay(after: Date(), using: viewContext)
                            setAction(.checkWork, rows: planningRows, reviewAt: next)
                        }
                    }
                    .buttonStyle(.bordered)

                    Button("Choose Date") {
                        customReviewDate = editorModel.reviewAt
                            ?? calendar.startOfDay(for: Date())
                        setAction(.checkWork, rows: planningRows, reviewAt: customReviewDate)
                    }
                    .buttonStyle(.bordered)
                }

                if showCustomReviewDate {
                    DatePicker(
                        "Review on",
                        selection: $customReviewDate,
                        in: AppCalendar.startOfDay(Date())...,
                        displayedComponents: .date
                    )
                    .onChange(of: customReviewDate) { _, date in
                        setAction(.checkWork, rows: planningRows, reviewAt: date)
                    }
                }

                if checkWorkRowsWithReviewDate.isEmpty {
                    Text("Choose a date only when you want a scheduled check-in. The work remains visible in Children Working without one.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if scopedLinkedOpenWork.isEmpty {
                    Label(
                        "No work is attached yet. Add the child’s actual work above, or leave this as a presentation follow-up only.",
                        systemImage: "tray"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Button {
                        scheduleOpenWorkCheckIns()
                    } label: {
                        Label("Schedule Work Check-In", systemImage: "checklist.checked")
                    }
                    .buttonStyle(.borderedProminent)

                    if !checkWorkRowsWithoutLinkedWork.isEmpty {
                        Text(missingLinkedWorkMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("A date is optional. Next Work Cycle keeps this visible without inventing a deadline.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear(perform: synchronizeReviewDateEditor)
        .onChange(of: editorModel.reviewAt) { _, _ in
            synchronizeReviewDateEditor()
        }
    }

    var supportSection: some View {
        followUpInset(title: "What support are you planning?", systemImage: "person.crop.circle.badge.questionmark") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Support", selection: Binding(
                    get: { editorModel.selectedSupport ?? .represent },
                    set: { setAction(.planSupport, rows: planningRows, support: $0) }
                )) {
                    ForEach(PresentationFollowUpSupport.allCases) { support in
                        Text(support.title).tag(support)
                    }
                }
                .pickerStyle(.menu)

                if editorModel.selectedSupport == .confer {
                    Text("This remains in Following Presentations until you record the conference.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        addRepresentationToInbox()
                    } label: {
                        Label("Add Support Presentation to On Deck", systemImage: "tray.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    var nextLessonSection: some View {
        followUpInset(title: "Plan the related or next lesson", systemImage: "book.pages") {
            VStack(alignment: .leading, spacing: 12) {
                NextLessonSection(viewModel: nextLessonViewModel)

                Button {
                    applyNextLessonPlan()
                } label: {
                    Label("Apply Next Lesson Plan", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(nextLessonViewModel.nextLessonAction == .noChange)
            }
        }
    }

    func followUpInset<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content()
        }
        .padding(16)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
    }

    var childrenSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Each Child")
                    .font(.headline)
                Spacer()
                Text("Observe and decide individually")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(allRows, id: \.objectID) { row in
                childRow(row)
            }
        }
    }

    func childRow(_ row: CDLessonPresentation) -> some View {
        HStack(spacing: 12) {
            Image(systemName: row.hasOpenFollowUp ? "person.crop.circle" : "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(row.hasOpenFollowUp ? Color.accentColor : AppColors.success)

            VStack(alignment: .leading, spacing: 4) {
                Text(studentName(for: row))
                    .font(.subheadline.weight(.semibold))

                if row.hasOpenFollowUp {
                    HStack(spacing: 6) {
                        Text(row.followUpAction?.shortTitle ?? "Keep Watching")
                        if let reviewAt = row.followUpReviewAt {
                            Text("•")
                            Text("Review \(reviewAt.formatted(date: .abbreviated, time: .omitted))")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Text(row.followUpResolution?.title ?? "Resolved")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if row.hasOpenFollowUp {
                Menu {
                    Button("Plan for \(studentName(for: row))", systemImage: "person.crop.circle") {
                        setScope(.child(row.objectID))
                    }
                    Divider()
                    ForEach(PresentationFollowUpAction.allCases) { action in
                        Button(action.title, systemImage: action.systemImage) {
                            setScope(.child(row.objectID))
                            setAction(action)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)

                Button("Record Observation") {
                    observationSelection = ObservationSelection(row: row)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
    }

    var completedState: some View {
        ContentUnavailableView {
            Label("Follow-Up Complete", systemImage: "checkmark.circle.fill")
        } description: {
            Text("Each child’s presentation follow-up has been resolved.")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
    }

    var scopedGuideFollowUpCompleteState: some View {
        ContentUnavailableView {
            Label("Guide Follow-Up Complete", systemImage: "checkmark.circle.fill")
        } description: {
            Text("You can still add or review this child’s work above. Choose another child to plan a guide follow-up.")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    var bottomBar: some View {
        HStack {
            Button("Back to Lesson") { requestExit(.returnToLesson) }
            Spacer()
            Text(bottomStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Close") { requestExit(.close) }
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    var bottomStatusText: String {
        if hasUnsavedWorkDraft { return "Work invitation not added yet" }
        return openRows.isEmpty ? "Follow-up complete" : "Saved in Lessons & Work"
    }

    func requestExit(_ exit: PendingExit) {
        guard hasUnsavedWorkDraft else {
            performExit(exit)
            return
        }
        pendingExit = exit
        showDiscardWorkConfirmation = true
    }

    func performExit(_ exit: PendingExit) {
        switch exit {
        case .returnToLesson:
            onReturnToLesson()
        case .openWork:
            appRouter.navigateToLessonsAndWork(
                .attention,
                presentationID: assignment.id,
                workID: preferredOpenWork?.id
            )
            onClose()
        case .close:
            closeIntoWorkspace()
        }
    }

    func discardCurrentWorkDraft() {
        guard let presentationID = assignment.id else { return }
        PresentationFollowUpWorkDraftStore.clear(
            presentationID: presentationID,
            studentIDs: workRows.map(\.studentID)
        )
    }

    func restoreWorkDraftScopeIfNeeded() {
        guard let presentationID = assignment.id,
              let draft = PresentationFollowUpWorkDraftStore.mostRecent(
                presentationID: presentationID
              ) else {
            return
        }
        let draftStudents = Set(draft.studentIDs)
        let allStudents = Set(allRows.map(\.studentID))
        if draftStudents == allStudents {
            setScope(.allChildren)
        } else if draftStudents.count == 1,
                  let row = allRows.first(where: { draftStudents.contains($0.studentID) }) {
            setScope(.child(row.objectID))
        }
    }

    func closeIntoWorkspace() {
        let destination = TriageBucket.afterPresentation(
            hasOpenFollowUp: !openRows.isEmpty,
            hasOpenWork: !openLinkedWork.isEmpty
        )
        appRouter.navigateToLessonsAndWork(
            destination,
            presentationID: assignment.id,
            workID: preferredOpenWork?.id
        )
        onClose()
    }
}

private extension PostPresentationFollowUpView {
    enum PendingExit {
        case returnToLesson
        case openWork
        case close
    }

    var openLinkedWork: [CDWorkModel] {
        allLinkedWork.filter { $0.status != .complete }
    }

    var preferredOpenWork: CDWorkModel? {
        let scopedStudentIDs = Set(workRows.map(\.studentID))
        let scoped = openLinkedWork.filter { scopedStudentIDs.contains($0.studentID) }
        return (scoped.isEmpty ? openLinkedWork : scoped).max {
            ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast)
        }
    }
}

private extension PostPresentationFollowUpView {
    struct ObservationSelection: Identifiable {
        let row: CDLessonPresentation
        var id: NSManagedObjectID { row.objectID }
    }

    func studentName(for row: CDLessonPresentation) -> String {
        guard let id = UUID(uuidString: row.studentID),
              let student = students.first(where: { $0.id == id }) else {
            return "Child"
        }
        return StudentFormatter.displayName(for: student)
    }

    func resolveNextLesson() {
        guard let lessonID = lesson.id, !planningStudentIDs.isEmpty else { return }
        nextLessonViewModel.resolveNextLesson(
            lessonID: lessonID,
            studentIDs: planningStudentIDs,
            lessons: lessons,
            lessonAssignments: lessonAssignments,
            context: viewContext
        )
        nextLessonViewModel.isNextLessonSectionExpanded = true
    }

    func setScope(_ scope: PresentationFollowUpEditorModel.Scope) {
        editorModel.setScope(scope, rows: allRows)
        synchronizeReviewDateEditor()
    }

    func setAction(
        _ action: PresentationFollowUpAction,
        rows: [CDLessonPresentation]? = nil,
        reviewAt: Date? = nil,
        support: PresentationFollowUpSupport? = nil
    ) {
        let saved = editorModel.selectAction(
            action,
            rows: rows ?? allRows,
            reviewAt: reviewAt,
            support: support,
            calendar: calendar,
            persist: { persist(reason: "Updating presentation follow-up") }
        )
        if saved {
            synchronizeReviewDateEditor()
        }
    }

    func scheduleOpenWorkCheckIns() {
        guard let presentationID = assignment.id, let lessonID = lesson.id else { return }
        do {
            let result = try PresentationFollowUpWorkService(context: viewContext).scheduleCheckIns(
                for: planningRows,
                presentationID: presentationID,
                lessonID: lessonID,
                calendar: calendar,
                persist: {
                    persist(reason: "Scheduling presentation work check-ins")
                }
            )

            if result.createdCount > 0 && result.rescheduledCount > 0 {
                ToastService.shared.showSuccess(
                    "Work check-ins scheduled and updated"
                )
            } else if result.createdCount > 0 {
                let suffix = result.createdCount == 1 ? "" : "s"
                ToastService.shared.showSuccess(
                    "\(result.createdCount) work check-in\(suffix) scheduled"
                )
            } else if result.rescheduledCount > 0 {
                let suffix = result.rescheduledCount == 1 ? "" : "s"
                ToastService.shared.showSuccess(
                    "\(result.rescheduledCount) work check-in date\(suffix) updated"
                )
            } else if result.existingCount > 0 {
                ToastService.shared.showInfo("Those work check-ins are already scheduled")
            } else if !result.rowsWithoutLinkedWork.isEmpty {
                ToastService.shared.showInfo("Add the child’s work above before scheduling its check-in")
            }
        } catch {
            if saveErrorMessage == nil {
                saveErrorMessage = error.localizedDescription
            }
        }
    }

    func addRepresentationToInbox() {
        guard let lessonID = lesson.id else { return }
        let rowsToPlan = planningRows.filter {
            $0.followUpAction == .planSupport && $0.followUpSupport != .confer
        }
        let studentIDs = Set(rowsToPlan.compactMap { UUID(uuidString: $0.studentID) })
        guard !studentIDs.isEmpty else { return }

        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "lessonID == %@", lessonID.uuidString)
        let existing = viewContext.safeFetch(request).contains {
            !$0.isPresented && Set($0.studentUUIDs) == studentIDs
        }
        if !existing {
            let selected = students.filter { student in
                student.id.map(studentIDs.contains) ?? false
            }
            _ = PresentationFactory.makeDraft(
                lesson: lesson,
                students: selected,
                context: viewContext
            )
        }
        for row in rowsToPlan {
            PresentationFollowUpService.resolve(.supportOrRepresent, row: row)
        }
        if persist(reason: "Adding support presentation to On Deck") {
            synchronizeAfterChildWorkflow()
            ToastService.shared.showSuccess("Support presentation added to On Deck")
        }
    }

    func applyNextLessonPlan() {
        guard nextLessonViewModel.nextLessonAction != .noChange else { return }
        let targetRows = planningRows.filter { $0.followUpAction == .planNextPresentation }
        let targetStudentIDs = Set(targetRows.compactMap { UUID(uuidString: $0.studentID) })
        guard !targetStudentIDs.isEmpty else { return }
        nextLessonViewModel.executeNextLessonAction(
            studentIDs: targetStudentIDs,
            allStudents: students,
            allLessons: lessons,
            lessonAssignments: lessonAssignments,
            viewContext: viewContext
        )
        for row in targetRows {
            PresentationFollowUpService.resolve(.readyForNextPresentation, row: row)
        }
        if persist(reason: "Applying next presentation plan") {
            synchronizeAfterChildWorkflow()
            ToastService.shared.showSuccess("Next presentation planned")
        }
    }

    var actionSectionHelpText: String {
        if focusedRow != nil {
            return "Choose this child’s path. The other children keep their own follow-up."
        }
        if editorModel.hasMixedActions {
            return "These children have different follow-up paths. Choose an option only to apply it to all of them."
        }
        return "Choose one path for all open children, or select one child above."
    }

    var checkWorkRowsWithReviewDate: [CDLessonPresentation] {
        planningRows.filter {
            $0.followUpAction == .checkWork && $0.followUpReviewAt != nil
        }
    }

    var scopedLinkedOpenWork: [CDWorkModel] {
        guard let presentationID = assignment.id?.uuidString,
              let lessonID = lesson.id?.uuidString else { return [] }
        let studentIDs = Set(checkWorkRowsWithReviewDate.map(\.studentID))
        return allLinkedWork.filter {
            $0.presentationID == presentationID
                && $0.lessonID == lessonID
                && studentIDs.contains($0.studentID)
                && $0.status != .complete
        }
    }

    var checkWorkRowsWithoutLinkedWork: [CDLessonPresentation] {
        let studentIDsWithWork = Set(scopedLinkedOpenWork.map(\.studentID))
        return checkWorkRowsWithReviewDate.filter {
            !studentIDsWithWork.contains($0.studentID)
        }
    }

    var missingLinkedWorkMessage: String {
        let count = checkWorkRowsWithoutLinkedWork.count
        return count == 1
            ? "One child has no attached work yet; no check-in will be created for that child."
            : "\(count) children have no attached work yet; no check-ins will be created for them."
    }

    func synchronizeReviewDateEditor() {
        if let reviewAt = editorModel.reviewAt {
            customReviewDate = reviewAt
            showCustomReviewDate = true
        } else {
            showCustomReviewDate = false
        }
    }

    func synchronizeAfterChildWorkflow() {
        synchronizeEditorFromOpenRows()
        resolveNextLesson()
    }

    func synchronizeEditorFromOpenRows() {
        editorModel.synchronize(from: allRows)
        synchronizeReviewDateEditor()
    }

    @discardableResult
    func persist(reason: String) -> Bool {
        guard saveCoordinator.save(viewContext, reason: reason) else {
            saveErrorMessage = saveCoordinator.lastSaveErrorMessage ?? "The change could not be saved."
            return false
        }
        return true
    }
}
