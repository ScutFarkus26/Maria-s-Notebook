import SwiftUI
import SwiftData

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct StudentLessonDetailView: View {
    @Environment(\.modelContext) private var modelContext
    
    // Live Queries
    @Query private var lessons: [Lesson]
    @Query private var studentsAll: [Student]
    @Query private var studentLessonsAll: [StudentLesson]
    
    let studentLesson: StudentLesson
    let autoFocusLessonPicker: Bool
    var onDone: (() -> Void)? = nil
    
    // ViewModel is optional and initialized in onAppear
    @State private var vm: StudentLessonDetailViewModel?
    
    // Child ViewModel (LessonPicker)
    // We initialize it with a dummy state; it will be configured in onAppear
    @StateObject private var lessonPickerVM = LessonPickerViewModel(selectedStudentIDs: [], selectedLessonID: UUID())

    init(studentLesson: StudentLesson, onDone: (() -> Void)? = nil, autoFocusLessonPicker: Bool = false) {
        self.studentLesson = studentLesson
        self.onDone = onDone
        self.autoFocusLessonPicker = autoFocusLessonPicker
    }

    var body: some View {
        Group {
            if let vm = vm {
                // Pass non-optional VM to the content view to enable Bindings
                StudentLessonDetailContentView(
                    vm: vm,
                    lessonPickerVM: lessonPickerVM,
                    lessons: lessons,
                    studentsAll: studentsAll,
                    studentLessonsAll: studentLessonsAll,
                    onDone: onDone
                )
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if vm == nil {
                // Initialize Main VM
                let newVM = StudentLessonDetailViewModel(
                    studentLesson: studentLesson,
                    modelContext: modelContext,
                    autoFocusLessonPicker: autoFocusLessonPicker
                )
                self.vm = newVM
                
                // Configure Picker VM
                lessonPickerVM.configure(lessons: lessons, students: studentsAll)
                lessonPickerVM.selectLesson(newVM.editingLessonID)
            }
        }
        .onChange(of: lessons.map { $0.id }) { _, _ in
            lessonPickerVM.configure(lessons: lessons, students: studentsAll)
        }
        .onChange(of: lessonPickerVM.selectedLessonID) { _, newValue in
            // Sync Picker -> Main VM
            if let newID = newValue, let vm = vm {
                vm.editingLessonID = newID
                vm.showLessonPicker = false
            }
        }
        .onChange(of: vm?.needsAnotherPresentation) { _, newValue in
            // Sync Main VM -> Logic
            if let val = newValue, let vm = vm {
                vm.handleNeedsAnotherChange(
                    newValue: val,
                    studentsAll: studentsAll,
                    studentLessonsAll: studentLessonsAll,
                    lessons: lessons
                )
            }
        }
    }
}

// MARK: - Content Subview
/// Extracts the content so `vm` can be treated as non-optional for Bindings
struct StudentLessonDetailContentView: View {
    @Bindable var vm: StudentLessonDetailViewModel
    @ObservedObject var lessonPickerVM: LessonPickerViewModel
    
    let lessons: [Lesson]
    let studentsAll: [Student]
    let studentLessonsAll: [StudentLesson]
    let onDone: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @State private var lessonPickerFocused: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    // 1. Lesson Title & Tags Header
                    lessonHeaderSection
                        .padding(.horizontal, 32)
                        .padding(.top, 32)
                    
                    // 2. Conditional Lesson Picker
                    if vm.lessonObject(from: lessons) == nil || vm.showLessonPicker {
                        lessonPickerSection
                            .padding(.horizontal, 32)
                            .padding(.top, 16)
                    } else {
                        ChangeLessonControl(showLessonPicker: $vm.showLessonPicker)
                            .padding(.horizontal, 32)
                            .padding(.top, 8)
                    }
                    
                    // 3. Student Pills Block
                    studentPillsSection
                        .padding(.horizontal, 32)
                        .padding(.top, 20)
                    
                    Divider()
                        .padding(.horizontal, 32)
                        .padding(.vertical, 20)
                    
                    // 4. Inbox/Scheduling Status Row
                    inboxStatusSection
                        .padding(.horizontal, 32)
                    
                    Divider()
                        .padding(.horizontal, 32)
                        .padding(.vertical, 20)
                    
                    // 5. Notes Section
                    notesSection
                        .padding(.horizontal, 32)
                        .padding(.top, 24)
                        .padding(.bottom, 32)
                    
                    // 6. Progress buttons row
                    progressButtonsRow
                        .padding(.horizontal, 32)
                        .padding(.top, 16)
                }
            }
        }
        .frame(minWidth: 720, minHeight: 640)
        .safeAreaInset(edge: .bottom) { bottomBar }
        .alert("Delete Presentation?", isPresented: $vm.showDeleteAlert) {
            Button("Delete", role: .destructive) {
                vm.delete { handleDone() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $vm.showingAddStudentSheet) {
            AddStudentView()
        }
        .overlay(alignment: .top) {
            if vm.showMovedBanner {
                MovedStudentsBanner(studentNames: vm.movedStudentNames)
            }
        }
        .sheet(isPresented: $vm.showingMoveStudentsSheet) {
            moveStudentsSheet
        }
        .sheet(isPresented: $vm.showAssignmentComposer) {
            assignmentComposerSheet
        }
        .onChange(of: vm.showingStudentPickerPopover) { _, isShowing in
            if !isShowing && lessonPickerFocused {
                lessonPickerFocused = false
            }
        }
        .onAppear {
            if vm.showLessonPicker { lessonPickerFocused = true }
        }
        .onDisappear {
            vm.flushNotesAutosaveIfNeeded()
        }
    }
    
    // MARK: - Sections
    
    private var lessonHeaderSection: some View {
        let lesson = vm.lessonObject(from: lessons)
        let hasFile: Bool = {
            guard let l = lesson else { return false }
            if let rel = l.pagesFileRelativePath, !rel.isEmpty { return true }
            return l.pagesFileBookmark != nil
        }()
        
        return StudentLessonHeaderView(
            lessonName: lesson?.name ?? "Lesson",
            subject: lesson?.subject ?? "",
            group: lesson?.group ?? "",
            subjectColor: AppColors.color(forSubject: lesson?.subject ?? ""),
            onTapTitle: hasFile ? { if let url = resolveLessonPagesURL() { openInPages(url) } } : nil
        )
    }
    
    private var studentPillsSection: some View {
        StudentPillsSection(
            students: selectedStudentsList,
            subjectColor: AppColors.color(forSubject: vm.lessonObject(from: lessons)?.subject ?? ""),
            onRemove: { id in vm.selectedStudentIDs.remove(id) },
            onOpenPicker: { vm.showingStudentPickerPopover = true },
            onOpenMove: {
                vm.studentsToMove = []
                vm.showingMoveStudentsSheet = true
            },
            canMoveStudents: selectedStudentsList.count > 1 && !vm.isPresented,
            onOpenMoveAbsent: { openMoveAbsentStudents() },
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
    }
    
    private var inboxStatusSection: some View {
        InboxStatusSection(scheduledFor: $vm.scheduledFor)
    }
    
    private var notesSection: some View {
        StudentLessonNotesSectionUnified(
            studentLesson: vm.studentLesson,
            legacyNotes: $vm.notes,
            onLegacyNotesChange: { newNotes in
                vm.notes = newNotes
            }
        )
    }
    
    private var lessonPickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            LessonPickerSection(
                viewModel: lessonPickerVM,
                resolvedLesson: lessons.first(where: { $0.id == lessonPickerVM.selectedLessonID }) ?? vm.lessonObject(from: lessons),
                isFocused: $lessonPickerFocused
            )
        }
    }
    
    private var progressButtonsRow: some View {
        HStack(spacing: 12) {
            Button { selectJustPresented() } label: {
                StatePill(
                    title: "Just Presented",
                    systemImage: "checkmark.circle.fill",
                    tint: .green,
                    active: isJustPresentedActive
                )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)

            Button { selectPreviouslyPresented() } label: {
                StatePill(
                    title: "Previously Presented",
                    systemImage: "clock.badge.checkmark",
                    tint: .green,
                    active: isPreviouslyPresentedActive
                )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)

            Button { selectNeedsAnother() } label: {
                StatePill(
                    title: "Needs Another Presentation",
                    systemImage: "arrow.clockwise.circle.fill",
                    tint: .orange,
                    active: isNeedsAnotherActive
                )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            
            Spacer()

            Button {
                vm.scheduleNextLessonToInbox(
                    studentsAll: studentsAll,
                    studentLessonsAll: studentLessonsAll,
                    lessons: lessons
                )
            } label: {
                Label("Schedule Next Presentation", systemImage: "calendar.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.nextLessonInGroup(from: lessons) == nil || vm.selectedStudentIDs.isEmpty)
        }
    }
    
    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Button(role: .destructive) {
                    vm.showDeleteAlert = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }

                Spacer()

                Button("Cancel") {
                    // Cleanup empty drafts if cancelling
                    if vm.studentLesson.studentIDs.isEmpty {
                        modelContext.delete(vm.studentLesson)
                        try? modelContext.save()
                    }
                    handleDone()
                }

                Button("Save") {
                    vm.save(
                        studentsAll: studentsAll,
                        lessons: lessons,
                        studentLessonsAll: studentLessonsAll,
                        calendar: calendar
                    ) {
                        handleDone()
                    }
                }
                .bold()
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(vm.selectedStudentIDs.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)
        }
    }
    
    private var moveStudentsSheet: some View {
        MoveStudentsSheet(
            lessonName: vm.lessonObject(from: lessons)?.name ?? "Lesson",
            students: selectedStudentsList,
            studentsToMove: $vm.studentsToMove,
            selectedStudentIDs: vm.selectedStudentIDs,
            onMove: {
                vm.moveStudentsToInbox(
                    studentsAll: studentsAll,
                    studentLessonsAll: studentLessonsAll,
                    lessons: lessons
                )
                vm.showingMoveStudentsSheet = false
            },
            onCancel: {
                vm.studentsToMove = []
                vm.showingMoveStudentsSheet = false
            }
        )
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 520)
        .presentationSizingFitted()
        #endif
    }
    
    private var assignmentComposerSheet: some View {
        let selected = studentsAll.filter { vm.selectedStudentIDs.contains($0.id) }
        let lessonTitle = vm.lessonObject(from: lessons)?.name ?? "Lesson"
        
        return PostPresentationAssignmentsSheet(
            students: selected,
            lessonName: lessonTitle,
            onCreate: { assignments in
                createFollowUpAssignments(assignments)
                vm.showAssignmentComposer = false
                vm.save(
                    studentsAll: studentsAll,
                    lessons: lessons,
                    studentLessonsAll: studentLessonsAll,
                    calendar: calendar
                ) {
                    handleDone()
                }
            },
            onCancel: {
                vm.showAssignmentComposer = false
            }
        )
    }

    // MARK: - Helpers & Logic
    
    private func handleDone() {
        if let onDone {
            onDone()
        } else {
            dismiss()
        }
    }

    private var selectedStudentsList: [Student] {
        studentsAll
            .filter { vm.selectedStudentIDs.contains($0.id) }
            .sorted { $0.firstName.localizedCaseInsensitiveCompare($1.firstName) == .orderedAscending }
    }
    
    private func resolveLessonPagesURL() -> URL? {
        guard let lesson = vm.lessonObject(from: lessons) else { return nil }
        if let rel = lesson.pagesFileRelativePath, !rel.isEmpty, let url = try? LessonFileStorage.resolve(relativePath: rel) {
            return url
        }
        guard let bookmark = lesson.pagesFileBookmark else { return nil }
        var stale = false
        do {
#if os(macOS)
            let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
#else
            let url = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
#endif
            _ = url.startAccessingSecurityScopedResource()
            return url
        } catch {
            return nil
        }
    }
    
    private func openInPages(_ url: URL) {
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
#if os(iOS)
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
#elseif os(macOS)
        if let pagesAppURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iWork.Pages") {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.open([url], withApplicationAt: pagesAppURL, configuration: config, completionHandler: nil)
        } else {
            NSWorkspace.shared.open(url)
        }
#endif
    }
    
    // MARK: - Progress State Logic
    
    private var isJustPresentedActive: Bool {
        if !vm.isPresented { return false }
        guard let date = vm.givenAt else { return false }
        return calendar.isDateInToday(date)
    }
    private var isPreviouslyPresentedActive: Bool {
        vm.isPresented && !isJustPresentedActive
    }
    private var isNeedsAnotherActive: Bool {
        vm.needsAnotherPresentation && !vm.isPresented
    }
    private func selectJustPresented() {
        vm.isPresented = true
        vm.givenAt = calendar.startOfDay(for: Date())
        vm.needsAnotherPresentation = false
        vm.showAssignmentComposer = true
    }
    private func selectPreviouslyPresented() {
        vm.isPresented = true
        vm.needsAnotherPresentation = false
        if let date = vm.givenAt, calendar.isDateInToday(date) {
            vm.givenAt = nil
        }
    }
    private func selectNeedsAnother() {
        vm.isPresented = false
        vm.givenAt = nil
        vm.needsAnotherPresentation = true
    }
    
    // MARK: - Assignments Logic
    
    private func createFollowUpAssignments(_ assignments: [PostPresentationAssignmentsSheet.AssignmentEntry]) {
        let lessonID = (vm.lessonObject(from: lessons)?.id ?? vm.editingLessonID)
        let lidString = lessonID.uuidString
        let activeRaw = WorkStatus.active.rawValue
        let reviewRaw = WorkStatus.review.rawValue
        let followRaw = WorkKind.followUpAssignment.rawValue

        for entry in assignments {
            let sid = entry.studentID.uuidString
            // Explicit Predicate variables to avoid "Any" errors
            let predicate = #Predicate<WorkContract> {
                $0.studentID == sid && $0.lessonID == lidString
            }
            let fetchExisting = FetchDescriptor<WorkContract>(predicate: predicate)
            let existingContracts = (try? modelContext.fetch(fetchExisting)) ?? []
            
            let existing = existingContracts.first(where: {
                ($0.statusRaw == activeRaw || $0.statusRaw == reviewRaw) && (($0.kindRaw ?? "") == followRaw)
            })

            let contract: WorkContract
            if let e = existing {
                contract = e
            } else {
                let c = WorkContract(studentID: sid, lessonID: lidString, status: .active)
                c.kind = WorkKind.followUpAssignment // Explicit Type
                modelContext.insert(c)
                contract = c
            }

            let trimmed = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                contract.scheduledNote = trimmed
            }

            if let sched = entry.schedule {
                let normalized = AppCalendar.startOfDay(sched.date)
                let checkInKind = PostPresentationAssignmentsSheet.ScheduleKind.checkIn
                let reason: WorkPlanItem.Reason = (sched.kind == checkInKind) ? .progressCheck : .dueDate
                
                let workID = contract.id
                // CloudKit compatibility: Convert UUID to String for comparison
                let workIDString = workID.uuidString
                let planPredicate = #Predicate<WorkPlanItem> { $0.workID == workIDString }
                let planFetch = FetchDescriptor<WorkPlanItem>(predicate: planPredicate)
                
                let existingPlans = (try? modelContext.fetch(planFetch)) ?? []
                if !existingPlans.contains(where: { $0.scheduledDate == normalized }) {
                    let item = WorkPlanItem(workID: contract.id, scheduledDate: normalized, reason: reason)
                    modelContext.insert(item)
                }
            }
        }
    }
    
    // MARK: - Absent Logic
    private var scheduledAttendanceDay: Date { AppCalendar.startOfDay(Date()) }

    private var absentStudentIDs: Set<UUID> {
        let statuses = modelContext.attendanceStatuses(for: Array(vm.selectedStudentIDs), on: scheduledAttendanceDay)
        return Set(statuses.compactMap { (key: UUID, value: AttendanceStatus) in
            value == .absent ? key : nil
        })
    }

    private var canMoveAbsentStudents: Bool {
        return selectedStudentsList.count > 1 && !vm.isPresented && !absentStudentIDs.isEmpty
    }

    private func openMoveAbsentStudents() {
        let ids = absentStudentIDs
        guard !ids.isEmpty else { return }
        vm.studentsToMove = ids
        vm.showingMoveStudentsSheet = true
    }

    // MARK: - UI Components
    private struct StatePill: View {
        let title: String
        let systemImage: String
        let tint: Color
        var active: Bool = false
        var body: some View {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .foregroundStyle(tint)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(active ? 0.20 : 0.10))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(tint.opacity(0.35), lineWidth: 1)
            )
        }
    }
}
