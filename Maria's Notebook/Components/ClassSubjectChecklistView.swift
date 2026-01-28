//
//  ClassSubjectChecklistView.swift
//  Maria's Notebook
//
//  Created by Danny De Berry on 12/22/25.
//

import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif
import Combine

struct ClassSubjectChecklistView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = ClassSubjectChecklistViewModel()

    @AppStorage("General.showTestStudents") private var showTestStudents: Bool = false
    @AppStorage("General.testStudentNames") private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"
    @AppStorage("Checklist.selectedSubject") private var persistedSubject: String = ""

    // Grid Configuration
    private let studentColumnWidth: CGFloat = 120
    private let lessonColumnWidth: CGFloat = 200
    private let rowHeight: CGFloat = 44

    // Drag selection state
    @State private var dragStart: CGPoint? = nil
    @State private var dragCurrent: CGPoint? = nil
    @State private var isDragging: Bool = false
    @State private var isInDragSelectionMode: Bool = false
    @GestureState private var isLongPressing: Bool = false

    // Track scroll offset for accurate drag selection
    @State private var scrollOffset: CGPoint = .zero

    
    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Page Header / Controls
            ViewHeader(title: "Checklist") {
                Picker("Subject", selection: $viewModel.selectedSubject) {
                    ForEach(viewModel.availableSubjects, id: \.self) { sub in
                        Text(sub).tag(sub)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 150)
            }

            Divider()

            // MARK: - Batch Actions Toolbar
            if viewModel.isSelectionMode {
                HStack(spacing: 12) {
                    Text("\(viewModel.selectedCells.count) selected")
                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        viewModel.batchAddToInbox(context: modelContext)
                    } label: {
                        Label("Add to Inbox", systemImage: "tray")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        viewModel.batchMarkPresented(context: modelContext)
                    } label: {
                        Label("Presented", systemImage: "checkmark")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        viewModel.batchMarkMastered(context: modelContext)
                    } label: {
                        Label("Mastered", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)

                    Button {
                        viewModel.batchClearStatus(context: modelContext)
                    } label: {
                        Label("Clear", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)

                    Button {
                        viewModel.clearSelection()
                    } label: {
                        Text("Done")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.05))

                Divider()
            } else {
                // Hint for selection mode when not active
                HStack {
                    Spacer()
                    #if os(iOS)
                    Text("Tip: Long press a cell or use context menu to select multiple")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    #else
                    Text("Tip: Long press or right-click to select multiple cells")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    #endif
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            // MARK: - 2D Scrollable Grid with Pinned Header
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        // Data Rows
                        ForEach(viewModel.orderedGroups, id: \.self) { group in
                            // Group Header
                            HStack(spacing: 0) {
                                StickyLeftItem(width: lessonColumnWidth, height: 30) {
                                    HStack {
                                        Text(group)
                                            .font(.system(.caption, design: .rounded).weight(.bold))
                                            .foregroundStyle(.secondary)
                                            .padding(.leading)
                                        Spacer()
                                    }
                                    .background(Color.secondary.opacity(0.05))
                                    .borderSeparated()
                                }

                                // Spacer for the rest of the group row
                                Color.secondary.opacity(0.05)
                                    .frame(height: 30)
                                    .frame(width: CGFloat(viewModel.students.count) * studentColumnWidth)
                                    .borderSeparated()
                            }

                            let lessons = viewModel.lessonsIn(group: group)
                            ForEach(lessons) { lesson in
                                HStack(spacing: 0) {
                                    // Lesson Name (Sticky Left)
                                    StickyLeftItem(width: lessonColumnWidth, height: rowHeight) {
                                        VStack(alignment: .leading) {
                                            Text(lesson.name)
                                                .font(.system(.body, design: .rounded).weight(.medium))
                                                .lineLimit(2)
                                                .minimumScaleFactor(0.9)
                                        }
                                        .padding(.horizontal, 8)
                                        .frame(width: lessonColumnWidth, height: rowHeight, alignment: .leading)
                                        .backgroundPlatform()
                                        .borderSeparated()
                                    }

                                    // Grid Cells
                                    ForEach(viewModel.students) { student in
                                        let state = viewModel.state(for: student, lesson: lesson)
                                        ClassChecklistSmartCell(
                                            state: state,
                                            isSelected: viewModel.isSelected(student: student, lesson: lesson),
                                            isSelectionMode: viewModel.isSelectionMode,
                                            isDragSelecting: isDragging,
                                            onTap: { viewModel.toggleScheduled(student: student, lesson: lesson, context: modelContext) },
                                            onSelect: { viewModel.toggleSelection(student: student, lesson: lesson) },
                                            onMarkComplete: { viewModel.markComplete(student: student, lesson: lesson, context: modelContext) },
                                            onMarkPresented: { viewModel.togglePresented(student: student, lesson: lesson, context: modelContext) },
                                            onClear: { viewModel.clearStatus(student: student, lesson: lesson, context: modelContext) },
                                            onLongPressStart: {
                                                // Enter selection mode and select this cell
                                                #if os(iOS)
                                                let generator = UIImpactFeedbackGenerator(style: .medium)
                                                generator.impactOccurred()
                                                #endif
                                                viewModel.toggleSelection(student: student, lesson: lesson)
                                            }
                                        )
                                        .frame(width: studentColumnWidth, height: rowHeight)
                                        .borderSeparated()
                                    }
                                }
                            }
                        }
                    } header: {
                        // Pinned header row - stays at top during vertical scroll
                        headerRow
                    }
                }
                .background(
                    // Track scroll offset using GeometryReader
                    GeometryReader { geo in
                        Color.clear
                            .preference(key: ScrollOffsetPreferenceKey.self, value: geo.frame(in: .named("scrollContainer")).origin)
                    }
                )
                .overlay {
                    // Visual feedback during long press
                    if isLongPressing && !isDragging {
                        Color.accentColor.opacity(0.05)
                            .allowsHitTesting(false)
                    }
                }
            }
            .coordinateSpace(name: "scrollContainer")
            .coordinateSpace(name: "gridSpace")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                scrollOffset = value
            }
            .gesture(
                // Long press to enter selection mode, then drag to select cells
                LongPressGesture(minimumDuration: 0.5)
                    .updating($isLongPressing) { currentState, gestureState, _ in
                        gestureState = currentState
                    }
                    .onEnded { _ in
                        // Haptic feedback when entering selection mode
                        #if os(iOS)
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        #endif
                        isInDragSelectionMode = true
                    }
                    .sequenced(before: DragGesture(minimumDistance: 1, coordinateSpace: .named("gridSpace")))
                    .onChanged { value in
                        switch value {
                        case .first:
                            // Still in long press phase
                            break
                        case .second(_, let dragValue):
                            // Dragging after long press
                            guard let drag = dragValue else { return }
                            if dragStart == nil {
                                dragStart = drag.startLocation
                                isDragging = true
                            }
                            dragCurrent = drag.location
                            updateDragSelection()
                        }
                    }
                    .onEnded { _ in
                        dragStart = nil
                        dragCurrent = nil
                        isDragging = false
                        isInDragSelectionMode = false
                    }
            )
        }
        .onAppear {
            // Restore persisted subject if available
            if !persistedSubject.isEmpty {
                viewModel.selectedSubject = persistedSubject
            }
            viewModel.loadData(context: modelContext)
            viewModel.applyVisibilityFilter(context: modelContext, show: showTestStudents, namesRaw: testStudentNamesRaw)
        }
        .onChange(of: viewModel.selectedSubject) { _, newValue in
            viewModel.refreshMatrix(context: modelContext)
            // Persist subject selection
            persistedSubject = newValue
        }
        .onChange(of: showTestStudents) { _, _ in
            viewModel.applyVisibilityFilter(context: modelContext, show: showTestStudents, namesRaw: testStudentNamesRaw)
        }
        .onChange(of: testStudentNamesRaw) { _, _ in
            viewModel.applyVisibilityFilter(context: modelContext, show: showTestStudents, namesRaw: testStudentNamesRaw)
        }
    }

    // MARK: - Drag Selection Helper
    private func updateDragSelection() {
        guard let start = dragStart, let current = dragCurrent else { return }

        // The drag coordinates are in the scrollContainer space, which accounts for scroll position
        // We need to adjust the cell positions by the scroll offset
        let offsetX = -scrollOffset.x
        let offsetY = -scrollOffset.y

        let dragRect = CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )

        // Compute cell positions mathematically
        // Grid layout: lessonColumnWidth for lesson names, then studentColumnWidth per student
        // Vertical: headerRow (rowHeight), then per group: groupHeader (30) + lessons (rowHeight each)

        var newSelection = Set<CellIdentifier>()
        let groupHeaderHeight: CGFloat = 30

        // Build a flat list of lessons with their Y offsets (in content space)
        var contentY: CGFloat = rowHeight // Start after header row

        for group in viewModel.orderedGroups {
            contentY += groupHeaderHeight // Group header

            let lessons = viewModel.lessonsIn(group: group)
            for lesson in lessons {
                // For each student (column), compute cell rect
                for (studentIndex, student) in viewModel.students.enumerated() {
                    let contentX = lessonColumnWidth + CGFloat(studentIndex) * studentColumnWidth

                    // Transform content coordinates to screen coordinates by adding scroll offset
                    let cellRect = CGRect(
                        x: contentX + offsetX,
                        y: contentY + offsetY,
                        width: studentColumnWidth,
                        height: rowHeight
                    )

                    if dragRect.intersects(cellRect) {
                        newSelection.insert(CellIdentifier(studentID: student.id, lessonID: lesson.id))
                    }
                }
                contentY += rowHeight
            }
        }

        viewModel.selectedCells = newSelection
    }

    // MARK: - Header Row
    private var headerRow: some View {
        HStack(spacing: 0) {
            // Top-Left Corner (Sticky horizontally)
            StickyLeftItem(width: lessonColumnWidth, height: rowHeight) {
                ZStack {
                    Color.clear.backgroundPlatform()
                    Text("Lessons \\ Students")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(width: lessonColumnWidth, height: rowHeight)
                .borderSeparated()
            }
            .zIndex(100) // Ensure corner stays above everything

            // Student Names (Scrolls Horizontally with content)
            ForEach(viewModel.students) { student in
                VStack(spacing: 2) {
                    Text(viewModel.displayName(for: student))
                    Text(AgeUtils.conciseAgeString(for: student.birthday))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(width: studentColumnWidth, height: rowHeight)
                .backgroundPlatform()
                .borderSeparated()
            }
        }
        .frame(minWidth: lessonColumnWidth + (CGFloat(viewModel.students.count) * studentColumnWidth), alignment: .leading)
    }
}

// MARK: - Scroll Offset Preference Key
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGPoint = .zero
    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) {
        value = nextValue()
    }
}

// MARK: - Sticky Layout Helper
struct StickyLeftItem<Content: View>: View {
    let width: CGFloat
    let height: CGFloat
    let content: () -> Content

    var body: some View {
        GeometryReader { geo in
            let minX = geo.frame(in: .named("gridSpace")).minX
            content()
                .offset(x: max(0, -minX))
                // Add shadow when stuck to separate from content
                .shadow(color: minX < 0 ? Color.black.opacity(0.1) : .clear, radius: 2, x: 2, y: 0)
        }
        .frame(width: width, height: height)
        .zIndex(99) // Keep above standard cells
    }
}

// MARK: - THE SMART CELL
struct ClassChecklistSmartCell: View {
    let state: StudentChecklistRowState?
    let isSelected: Bool
    let isSelectionMode: Bool
    var isDragSelecting: Bool = false

    var onTap: () -> Void
    var onSelect: () -> Void
    var onMarkComplete: () -> Void
    var onMarkPresented: () -> Void
    var onClear: () -> Void
    var onLongPressStart: (() -> Void)? = nil

    var body: some View {
        let isComplete = state?.isComplete ?? false
        let isPresented = state?.isPresented ?? false
        let isScheduled = state?.isScheduled ?? false

        // Use precomputed value from matrix builder instead of per-cell database query
        let isInboxPlan = state?.isInboxPlan ?? false

        ZStack {
            // Selection highlight background
            if isSelected {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(0.15))
            }

            Color.clear.contentShape(Rectangle()) // Hit area

            if isComplete {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.green)
                    .font(.title2)
            } else if isPresented {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.blue)
                    .font(.title3.weight(.bold))
            } else if isScheduled {
                Image(systemName: isInboxPlan ? "tray" : "calendar")
                    .foregroundStyle(Color.accentColor)
                    .font(.title3)
            } else {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 2)
                    .frame(width: 16, height: 16)
            }

            // Selection indicator
            if isSelected {
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                            .font(.caption)
                            .background(Circle().fill(Color.white).padding(-1))
                    }
                    Spacer()
                }
                .padding(4)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                .padding(2)
        )
        .onTapGesture {
            // Don't process taps while drag selecting
            guard !isDragSelecting else { return }

            if isSelectionMode {
                // In selection mode, tap toggles cell selection
                onSelect()
            } else {
                // Normal mode: tap adds/removes from inbox
                onTap()
            }
        }
        #if os(macOS)
        // On macOS, use long press to enter selection mode (right-click shows context menu)
        .onLongPressGesture(minimumDuration: 0.4, maximumDistance: 10) {
            onLongPressStart?()
        }
        #endif
        .contextMenu {
            // Selection mode option
            Button {
                onLongPressStart?()
            } label: {
                Label("Select", systemImage: "checkmark.circle")
            }
            Divider()
            Button { onTap() } label: { Label(isScheduled ? "Remove Plan" : "Add to Inbox", systemImage: "tray") }
            Button { onMarkPresented() } label: { Label("Mark Presented", systemImage: "checkmark") }
            Button { onMarkComplete() } label: { Label("Mark Mastered", systemImage: "checkmark.circle.fill") }
            Divider()
            Button(role: .destructive) { onClear() } label: { Label("Clear All Status", systemImage: "xmark.circle") }
        }
    }
}

// MARK: - Cell Identifier for Multi-Selection
struct CellIdentifier: Hashable {
    let studentID: UUID
    let lessonID: UUID
}

// MARK: - ViewModel
// Delegates to:
// - ChecklistMatrixBuilder: Matrix state computation
// - ChecklistBatchActionExecutor: Batch operations
// - ChecklistDragSelectionManager: Drag selection (used in view)
@MainActor
class ClassSubjectChecklistViewModel: ObservableObject {
    @Published var students: [Student] = []
    private var allStudents: [Student] = []
    @Published var lessons: [Lesson] = []
    @Published var orderedGroups: [String] = []
    @Published var availableSubjects: [String] = []
    @Published var selectedSubject: String = ""

    @Published var matrixStates: [UUID: [UUID: StudentChecklistRowState]] = [:]

    // MARK: - Multi-Selection State
    @Published var selectedCells: Set<CellIdentifier> = []
    var isSelectionMode: Bool { !selectedCells.isEmpty }
    private let lessonsLogic = LessonsViewModel()

    // MARK: - Name Display Helpers
    private func normalizedFirstName(_ name: String) -> String {
        name.trimmed().lowercased()
    }

    private var duplicateFirstNameKeys: Set<String> {
        var counts: [String: Int] = [:]
        for s in students {
            let key = normalizedFirstName(s.firstName)
            counts[key, default: 0] += 1
        }
        return Set(counts.filter { $0.value >= 2 }.map { $0.key })
    }

    func displayName(for student: Student) -> String {
        let firstTrimmed = student.firstName.trimmed()
        let key = normalizedFirstName(student.firstName)
        if duplicateFirstNameKeys.contains(key) {
            let lastInitial = student.lastName.trimmed().first.map { String($0) } ?? ""
            if lastInitial.isEmpty { return firstTrimmed }
            return "\(firstTrimmed) \(lastInitial)."
        } else {
            return firstTrimmed
        }
    }

    func loadData(context: ModelContext) {
        let studentFetch = FetchDescriptor<Student>(sortBy: [SortDescriptor(\.birthday)])
        let fetched = context.safeFetch(studentFetch)
        self.allStudents = fetched
        self.students = fetched

        let allLessonsFetch = FetchDescriptor<Lesson>()
        let allLessons = context.safeFetch(allLessonsFetch)
        self.availableSubjects = lessonsLogic.subjects(from: allLessons)

        if selectedSubject.isEmpty, let first = availableSubjects.first {
            selectedSubject = first
        }
        refreshMatrix(context: context)
    }

    func applyVisibilityFilter(context: ModelContext, show: Bool, namesRaw: String) {
        self.students = TestStudentsFilter.filterVisible(allStudents, show: show, namesRaw: namesRaw)
        recomputeMatrix(context: context)
    }

    func refreshMatrix(context: ModelContext) {
        guard !selectedSubject.isEmpty else { return }
        let sub = selectedSubject.trimmed()
        // Filter lessons by subject (case-insensitive to match original behavior)
        let allLessons = context.safeFetch(FetchDescriptor<Lesson>())
        self.lessons = allLessons.filter { $0.subject.localizedCaseInsensitiveCompare(sub) == .orderedSame }
        self.orderedGroups = lessonsLogic.groups(for: sub, lessons: self.lessons)
        recomputeMatrix(context: context)
    }

    func lessonsIn(group: String) -> [Lesson] {
        let groupTrimmed = group.trimmed()
        return lessons.filter {
            $0.group.trimmed().localizedCaseInsensitiveCompare(groupTrimmed) == .orderedSame
        }.sorted { $0.orderInGroup < $1.orderInGroup }
    }

    func state(for student: Student, lesson: Lesson) -> StudentChecklistRowState? {
        return matrixStates[student.id]?[lesson.id]
    }

    // MARK: - Multi-Selection Methods

    func toggleSelection(student: Student, lesson: Lesson) {
        let id = CellIdentifier(studentID: student.id, lessonID: lesson.id)
        if selectedCells.contains(id) {
            selectedCells.remove(id)
        } else {
            selectedCells.insert(id)
        }
    }

    func clearSelection() {
        selectedCells.removeAll()
    }

    func isSelected(student: Student, lesson: Lesson) -> Bool {
        selectedCells.contains(CellIdentifier(studentID: student.id, lessonID: lesson.id))
    }

    // MARK: - Batch Actions (delegated to ChecklistBatchActionExecutor)

    func batchAddToInbox(context: ModelContext) {
        ChecklistBatchActionExecutor.batchAddToInbox(
            selectedCells: selectedCells,
            students: students,
            lessons: lessons,
            matrixStates: matrixStates,
            context: context
        )
        recomputeMatrix(context: context)
        clearSelection()
    }

    func batchMarkPresented(context: ModelContext) {
        ChecklistBatchActionExecutor.batchMarkPresented(
            selectedCells: selectedCells,
            students: students,
            lessons: lessons,
            matrixStates: matrixStates,
            context: context
        )
        recomputeMatrix(context: context)
        clearSelection()
    }

    func batchMarkMastered(context: ModelContext) {
        ChecklistBatchActionExecutor.batchMarkMastered(
            selectedCells: selectedCells,
            students: students,
            lessons: lessons,
            matrixStates: matrixStates,
            context: context
        )
        recomputeMatrix(context: context)
        clearSelection()
    }

    func batchClearStatus(context: ModelContext) {
        ChecklistBatchActionExecutor.batchClearStatus(
            selectedCells: selectedCells,
            students: students,
            lessons: lessons,
            context: context
        )
        recomputeMatrix(context: context)
        clearSelection()
    }

    // MARK: - Matrix Computation (delegated to ChecklistMatrixBuilder)

    func recomputeMatrix(context: ModelContext) {
        guard !lessons.isEmpty else { matrixStates = [:]; return }
        self.matrixStates = ChecklistMatrixBuilder.buildMatrix(
            students: students,
            lessons: lessons,
            context: context
        )
    }

    // MARK: - Individual Cell Actions

    func toggleScheduled(student: Student, lesson: Lesson, context: ModelContext) {
        toggleScheduledNoRecompute(student: student, lesson: lesson, context: context)
        context.safeSave()
        recomputeMatrix(context: context)
    }

    private func toggleScheduledNoRecompute(student: Student, lesson: Lesson, context: ModelContext) {
        let lessonIDString = lesson.id.uuidString
        let studentIDString = student.id.uuidString

        let allSLs = context.safeFetch(FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.lessonID == lessonIDString }))

        if let existing = findUnscheduledLessonContaining(student: studentIDString, in: allSLs) {
            removeStudentFromLesson(student: studentIDString, lesson: existing, context: context)
        } else {
            addStudentToUnscheduledLesson(student: student, studentIDString: studentIDString, lesson: lesson, in: allSLs, context: context)
        }
    }

    private func findUnscheduledLessonContaining(student: String, in lessons: [StudentLesson]) -> StudentLesson? {
        lessons.first(where: { !$0.isGiven && $0.studentIDs.contains(student) })
    }

    private func removeStudentFromLesson(student: String, lesson: StudentLesson, context: ModelContext) {
        var ids = lesson.studentIDs
        ids.removeAll { $0 == student }
        if ids.isEmpty {
            context.delete(lesson)
        } else {
            lesson.studentIDs = ids
        }
    }

    private func addStudentToUnscheduledLesson(student: Student, studentIDString: String, lesson: Lesson, in allSLs: [StudentLesson], context: ModelContext) {
        if let group = allSLs.first(where: { !$0.isGiven && $0.scheduledFor == nil }) {
            if !group.studentIDs.contains(studentIDString) {
                group.studentIDs.append(studentIDString)
            }
        } else {
            _ = StudentLessonFactory.insertUnscheduled(
                lessonID: lesson.id,
                studentIDs: [student.id],
                into: context
            )
        }
    }

    func markComplete(student: Student, lesson: Lesson, context: ModelContext) {
        markCompleteNoRecompute(student: student, lesson: lesson, context: context)
        context.safeSave()
        recomputeMatrix(context: context)
    }

    private func markCompleteNoRecompute(student: Student, lesson: Lesson, context: ModelContext) {
        let studentIDString = student.id.uuidString
        let lessonIDString = lesson.id.uuidString

        let allSLs = context.safeFetch(FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.lessonID == lessonIDString }))
        if findGivenLessonContaining(student: studentIDString, in: allSLs) == nil {
            addStudentToGivenLesson(student: student, studentIDString: studentIDString, lesson: lesson, in: allSLs, context: context)
        }

        if let work = findOrCreateWork(student: student, lesson: lesson, context: context) {
            work.status = .complete
            work.completedAt = AppCalendar.startOfDay(Date())
        }

        upsertLessonPresentation(studentID: studentIDString, lessonID: lessonIDString, state: .mastered, context: context)
        GroupTrackService.autoEnrollInTrackIfNeeded(lesson: lesson, studentIDs: [studentIDString], modelContext: context)
        GroupTrackService.checkAndCompleteTrackIfNeeded(lesson: lesson, studentID: studentIDString, modelContext: context)
    }

    func togglePresented(student: Student, lesson: Lesson, context: ModelContext) {
        togglePresentedNoRecompute(student: student, lesson: lesson, context: context)
        context.safeSave()
        recomputeMatrix(context: context)
    }

    private func togglePresentedNoRecompute(student: Student, lesson: Lesson, context: ModelContext) {
        let studentIDString = student.id.uuidString
        let lessonIDString = lesson.id.uuidString

        let allSLs = context.safeFetch(FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.lessonID == lessonIDString }))

        if let existing = findGivenLessonContaining(student: studentIDString, in: allSLs) {
            removeStudentFromLesson(student: studentIDString, lesson: existing, context: context)
            deleteLessonPresentation(studentID: studentIDString, lessonID: lessonIDString, context: context)
        } else {
            addStudentToGivenLesson(student: student, studentIDString: studentIDString, lesson: lesson, in: allSLs, context: context)
            upsertLessonPresentation(studentID: studentIDString, lessonID: lessonIDString, state: .presented, context: context)
        }
    }

    private func findGivenLessonContaining(student: String, in lessons: [StudentLesson]) -> StudentLesson? {
        lessons.first(where: { $0.isGiven && $0.studentIDs.contains(student) })
    }

    private func addStudentToGivenLesson(student: Student, studentIDString: String, lesson: Lesson, in allSLs: [StudentLesson], context: ModelContext) {
        let today = Date()
        if let group = allSLs.first(where: { $0.isGiven && ($0.givenAt ?? Date.distantPast).isSameDay(as: today) }) {
            if !group.studentIDs.contains(studentIDString) {
                group.studentIDs.append(studentIDString)
                GroupTrackService.autoEnrollInTrackIfNeeded(lesson: lesson, studentIDs: [studentIDString], modelContext: context)
            }
        } else {
            _ = StudentLessonFactory.insertPresented(
                lessonID: lesson.id,
                studentIDs: [student.id],
                into: context
            )
            GroupTrackService.autoEnrollInTrackIfNeeded(lesson: lesson, studentIDs: [studentIDString], modelContext: context)
        }
    }

    func clearStatus(student: Student, lesson: Lesson, context: ModelContext) {
        clearStatusNoRecompute(student: student, lesson: lesson, context: context)
        context.safeSave()
        recomputeMatrix(context: context)
    }

    private func clearStatusNoRecompute(student: Student, lesson: Lesson, context: ModelContext) {
        let lid = lesson.id
        let sidString = student.id.uuidString
        let lidString = lid.uuidString

        let sls = context.safeFetch(FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.lessonID == lidString }))
        for sl in sls where sl.studentIDs.contains(sidString) {
            var newIDs = sl.studentIDs
            newIDs.removeAll { $0 == sidString }
            if newIDs.isEmpty { context.delete(sl) } else { sl.studentIDs = newIDs }
        }

        let allWorkModels = context.safeFetch(FetchDescriptor<WorkModel>())
        let workModelsToDelete = allWorkModels.filter { work in
            let hasStudent = (work.participants ?? []).contains { $0.studentID == sidString }
            guard hasStudent else { return false }
            guard let slID = work.studentLessonID,
                  let sl = sls.first(where: { $0.id == slID }),
                  UUID(uuidString: sl.lessonID) == lid else { return false }
            return true
        }
        for work in workModelsToDelete {
            context.delete(work)
        }

        deleteLessonPresentation(studentID: sidString, lessonID: lidString, context: context)
    }

    private func findOrCreateWork(student: Student, lesson: Lesson, context: ModelContext) -> WorkModel? {
        let sid = student.id
        let lid = lesson.id
        let allWorkModels = context.safeFetch(FetchDescriptor<WorkModel>())

        let existingWork = allWorkModels.first { work in
            let hasStudent = (work.participants ?? []).contains { $0.studentID == sid.uuidString }
            guard hasStudent else { return false }
            guard let slID = work.studentLessonID else { return false }
            let allSLs = context.safeFetch(FetchDescriptor<StudentLesson>())
            guard let sl = allSLs.first(where: { $0.id == slID }),
                  UUID(uuidString: sl.lessonID) == lid else { return false }
            return true
        }

        if let existing = existingWork {
            return existing
        }

        let repository = WorkRepository(context: context)
        return try? repository.createWork(
            studentID: sid,
            lessonID: lid,
            title: nil,
            kind: nil,
            presentationID: nil,
            scheduledDate: nil
        )
    }

    // MARK: - LessonPresentation Helpers

    private func upsertLessonPresentation(studentID: String, lessonID: String, state: LessonPresentationState, context: ModelContext) {
        let allLessonPresentations = context.safeFetch(FetchDescriptor<LessonPresentation>())
        let existing = allLessonPresentations.first { lp in
            lp.studentID == studentID && lp.lessonID == lessonID
        }

        if let existing = existing {
            if state == .mastered && existing.state != .mastered {
                existing.state = .mastered
                existing.masteredAt = Date()
            }
            existing.lastObservedAt = Date()
        } else {
            let lp = LessonPresentation(
                studentID: studentID,
                lessonID: lessonID,
                presentationID: nil,
                state: state,
                presentedAt: Date(),
                lastObservedAt: Date(),
                masteredAt: state == .mastered ? Date() : nil
            )
            context.insert(lp)
        }
    }

    private func deleteLessonPresentation(studentID: String, lessonID: String, context: ModelContext) {
        let allLessonPresentations = context.safeFetch(FetchDescriptor<LessonPresentation>())
        let toDelete = allLessonPresentations.filter { lp in
            lp.studentID == studentID && lp.lessonID == lessonID
        }
        for lp in toDelete {
            context.delete(lp)
        }
    }
}

// MARK: - Visual Helpers
extension View {
    func borderSeparated() -> some View {
        #if os(macOS)
        self.border(Color(nsColor: .separatorColor).opacity(0.5), width: 0.5)
        #else
        self.border(Color.gray.opacity(0.3), width: 0.5)
        #endif
    }
    
    func backgroundPlatform() -> some View {
        #if os(macOS)
        self.background(Color(nsColor: .controlBackgroundColor))
        #else
        self.background(Color(uiColor: .secondarySystemBackground))
        #endif
    }
}

