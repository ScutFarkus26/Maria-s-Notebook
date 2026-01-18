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

// MARK: - Preference Key for Cell Frames
fileprivate struct CellFramePreference: PreferenceKey {
    static var defaultValue: [CellIdentifier: CGRect] = [:]
    static func reduce(value: inout [CellIdentifier: CGRect], nextValue: () -> [CellIdentifier: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct ClassSubjectChecklistView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = ClassSubjectChecklistViewModel()

    @AppStorage("General.showTestStudents") private var showTestStudents: Bool = false
    @AppStorage("General.testStudentNames") private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    // Grid Configuration
    private let studentColumnWidth: CGFloat = 120
    private let lessonColumnWidth: CGFloat = 200
    private let rowHeight: CGFloat = 44

    // Drag selection state
    @State private var cellFrames: [CellIdentifier: CGRect] = [:]
    @State private var dragStart: CGPoint? = nil
    @State private var dragCurrent: CGPoint? = nil
    @State private var isDragging: Bool = false
    @GestureState private var dragGestureActive: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Page Header / Controls
            HStack {
                Text("Checklist")
                    .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                
                Spacer()
                
                Picker("Subject", selection: $viewModel.selectedSubject) {
                    ForEach(viewModel.availableSubjects, id: \.self) { sub in
                        Text(sub).tag(sub)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 150)
            }
            .padding()
            .backgroundPlatform()
            
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
                        Text("Cancel")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.05))

                Divider()
            }

            // MARK: - 2D Scrollable Grid
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    
                    Section(header: headerRow) {
                        // Data Rows
                        ForEach(viewModel.orderedGroups, id: \.self) { group in
                            // Group Header (Sticky Left)
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
                                        let cellId = CellIdentifier(studentID: student.id, lessonID: lesson.id)
                                        ClassChecklistSmartCell(
                                            state: state,
                                            isSelected: viewModel.isSelected(student: student, lesson: lesson),
                                            isSelectionMode: viewModel.isSelectionMode,
                                            isDragSelecting: isDragging,
                                            onTap: { viewModel.toggleScheduled(student: student, lesson: lesson, context: modelContext) },
                                            onSelect: { viewModel.toggleSelection(student: student, lesson: lesson) },
                                            onMarkComplete: { viewModel.markComplete(student: student, lesson: lesson, context: modelContext) },
                                            onMarkPresented: { viewModel.togglePresented(student: student, lesson: lesson, context: modelContext) },
                                            onClear: { viewModel.clearStatus(student: student, lesson: lesson, context: modelContext) }
                                        )
                                        .frame(width: studentColumnWidth, height: rowHeight)
                                        .borderSeparated()
                                        .background(
                                            GeometryReader { proxy in
                                                Color.clear
                                                    .preference(
                                                        key: CellFramePreference.self,
                                                        value: [cellId: proxy.frame(in: .named("gridSpace"))]
                                                    )
                                            }
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .coordinateSpace(name: "gridSpace")
            .onPreferenceChange(CellFramePreference.self) { prefs in
                DispatchQueue.main.async {
                    cellFrames = prefs
                }
            }
            .gesture(
                DragGesture(minimumDistance: 10, coordinateSpace: .named("gridSpace"))
                    .updating($dragGestureActive) { _, state, _ in
                        state = true
                    }
                    .onChanged { value in
                        if dragStart == nil {
                            dragStart = value.startLocation
                            isDragging = true
                        }
                        dragCurrent = value.location
                        updateDragSelection()
                    }
                    .onEnded { _ in
                        dragStart = nil
                        dragCurrent = nil
                        isDragging = false
                    }
            )
            .coordinateSpace(name: "scrollSpace")
        }
        .onAppear {
            viewModel.loadData(context: modelContext)
            viewModel.applyVisibilityFilter(context: modelContext, show: showTestStudents, namesRaw: testStudentNamesRaw)
        }
        .onChange(of: viewModel.selectedSubject) { _, _ in
            viewModel.refreshMatrix(context: modelContext)
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

        let dragRect = CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )

        var newSelection = Set<CellIdentifier>()
        for (cellId, frame) in cellFrames {
            if dragRect.intersects(frame) {
                newSelection.insert(cellId)
            }
        }
        viewModel.selectedCells = newSelection
    }

    // MARK: - Header Row (Pinned Vertically)
    private var headerRow: some View {
        HStack(spacing: 0) {
            // Top-Left Corner (Sticky Horizontally + Pinned Vertically via Section)
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
            
            // Student Names (Scrolls Horizontally)
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

// MARK: - Sticky Layout Helper
struct StickyLeftItem<Content: View>: View {
    let width: CGFloat
    let height: CGFloat
    let content: () -> Content
    
    var body: some View {
        GeometryReader { geo in
            let minX = geo.frame(in: .named("scrollSpace")).minX
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
    @Environment(\.modelContext) private var modelContext

    let state: StudentChecklistRowState?
    let isSelected: Bool
    let isSelectionMode: Bool
    var isDragSelecting: Bool = false

    var onTap: () -> Void
    var onSelect: () -> Void
    var onMarkComplete: () -> Void
    var onMarkPresented: () -> Void
    var onClear: () -> Void

    var body: some View {
        let isComplete = state?.isComplete ?? false
        let isPresented = state?.isPresented ?? false
        let isScheduled = state?.isScheduled ?? false

        let isInboxPlan: Bool = {
            guard isScheduled, let pid = state?.plannedItemID else { return false }
            let fetch = FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.id == pid })
            let sl = (try? modelContext.fetch(fetch))?.first
            return sl?.scheduledFor == nil
        }()

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
            onSelect()
        }
        .contextMenu {
            Button { onTap() } label: { Label(isScheduled ? "Remove Plan" : "Add to Inbox", systemImage: "calendar") }
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
        let fetched = (try? context.fetch(studentFetch)) ?? []
        self.allStudents = fetched
        self.students = fetched
        
        let allLessonsFetch = FetchDescriptor<Lesson>()
        let allLessons = (try? context.fetch(allLessonsFetch)) ?? []
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
        let allLessons = (try? context.fetch(FetchDescriptor<Lesson>())) ?? []
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

    // MARK: - Batch Actions

    func batchAddToInbox(context: ModelContext) {
        for cell in selectedCells {
            guard let student = students.first(where: { $0.id == cell.studentID }),
                  let lesson = lessons.first(where: { $0.id == cell.lessonID }) else { continue }
            let state = matrixStates[cell.studentID]?[cell.lessonID]
            // Only add if not already scheduled
            if state?.isScheduled != true {
                toggleScheduledNoRecompute(student: student, lesson: lesson, context: context)
            }
        }
        context.safeSave()
        recomputeMatrix(context: context)
        clearSelection()
    }

    func batchMarkPresented(context: ModelContext) {
        for cell in selectedCells {
            guard let student = students.first(where: { $0.id == cell.studentID }),
                  let lesson = lessons.first(where: { $0.id == cell.lessonID }) else { continue }
            let state = matrixStates[cell.studentID]?[cell.lessonID]
            // Only mark presented if not already presented
            if state?.isPresented != true {
                togglePresentedNoRecompute(student: student, lesson: lesson, context: context)
            }
        }
        context.safeSave()
        recomputeMatrix(context: context)
        clearSelection()
    }

    func batchMarkMastered(context: ModelContext) {
        for cell in selectedCells {
            guard let student = students.first(where: { $0.id == cell.studentID }),
                  let lesson = lessons.first(where: { $0.id == cell.lessonID }) else { continue }
            let state = matrixStates[cell.studentID]?[cell.lessonID]
            // Only mark mastered if not already complete
            if state?.isComplete != true {
                markCompleteNoRecompute(student: student, lesson: lesson, context: context)
            }
        }
        context.safeSave()
        recomputeMatrix(context: context)
        clearSelection()
    }

    func batchClearStatus(context: ModelContext) {
        for cell in selectedCells {
            guard let student = students.first(where: { $0.id == cell.studentID }),
                  let lesson = lessons.first(where: { $0.id == cell.lessonID }) else { continue }
            clearStatusNoRecompute(student: student, lesson: lesson, context: context)
        }
        context.safeSave()
        recomputeMatrix(context: context)
        clearSelection()
    }

    func recomputeMatrix(context: ModelContext) {
        let lessonIDs = Set(lessons.map { $0.id })
        guard !lessonIDs.isEmpty else { matrixStates = [:]; return }
        
        // CloudKit compatibility: Convert UUIDs to strings for comparison
        let lessonIDStrings = Set(lessonIDs.map { $0.uuidString })
        let slDescriptor = FetchDescriptor<StudentLesson>(predicate: #Predicate { lessonIDStrings.contains($0.lessonID) })
        let allSLs = (try? context.fetch(slDescriptor)) ?? []
        
        // Fetch all WorkModels and filter in memory (no predicates)
        let allWorkModels = (try? context.fetch(FetchDescriptor<WorkModel>())) ?? []

        var newMatrix: [UUID: [UUID: StudentChecklistRowState]] = [:]

        for student in students {
            var studentRow: [UUID: StudentChecklistRowState] = [:]
            let studentSLs = allSLs.filter { $0.studentIDs.contains(student.id.uuidString) }
            let studentIDString = student.id.uuidString

            // Filter WorkModels for this student
            let studentWorkModels = allWorkModels.filter { work in
                (work.participants ?? []).contains { $0.studentID == studentIDString }
            }

            for lesson in lessons {
                // CloudKit compatibility: Convert UUID to String for comparison
                let lessonIDString = lesson.id.uuidString
                let slsForLesson = studentSLs.filter { $0.lessonID == lessonIDString }

                let nonGiven = slsForLesson.filter { !$0.isGiven }
                let plannedCandidate = nonGiven.first
                let isScheduled = !nonGiven.isEmpty

                let isPresented = slsForLesson.contains { $0.isGiven }

                // Find WorkModel for this lesson
                let workModelForLesson = studentWorkModels.first { work in
                    guard let slID = work.studentLessonID,
                          let sl = studentSLs.first(where: { $0.id == slID }),
                          UUID(uuidString: sl.lessonID) == lesson.id else {
                        return false
                    }
                    return true
                }

                let isActive = workModelForLesson?.isOpen ?? false
                let isComplete = workModelForLesson?.status == .complete

                let contractID = workModelForLesson?.id
                
                let state = StudentChecklistRowState(
                    lessonID: lesson.id,
                    plannedItemID: plannedCandidate?.id,
                    presentationLogID: nil,
                    contractID: contractID,
                    isScheduled: isScheduled,
                    isPresented: isPresented,
                    isActive: isActive,
                    isComplete: isComplete,
                    lastActivityDate: nil,
                    isStale: false
                )
                studentRow[lesson.id] = state
            }
            newMatrix[student.id] = studentRow
        }
        self.matrixStates = newMatrix
    }
    
    func toggleScheduled(student: Student, lesson: Lesson, context: ModelContext) {
        toggleScheduledNoRecompute(student: student, lesson: lesson, context: context)
        context.safeSave()
        recomputeMatrix(context: context)
    }

    /// Internal version that skips save/recompute for batch operations
    private func toggleScheduledNoRecompute(student: Student, lesson: Lesson, context: ModelContext) {
        let lessonIDString = lesson.id.uuidString
        let studentIDString = student.id.uuidString

        let allSLs = context.safeFetch(FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.lessonID == lessonIDString }))

        // Check if student is already in an unscheduled lesson
        if let existing = findUnscheduledLessonContaining(student: studentIDString, in: allSLs) {
            removeStudentFromLesson(student: studentIDString, lesson: existing, context: context)
        } else {
            addStudentToUnscheduledLesson(student: student, studentIDString: studentIDString, lesson: lesson, in: allSLs, context: context)
        }
    }
    
    // MARK: - Helper Methods for toggleScheduled
    
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
            let newSL = StudentLesson(lessonID: lesson.id, studentIDs: [student.id], createdAt: Date(), scheduledFor: nil)
            context.insert(newSL)
        }
    }
    
    func markComplete(student: Student, lesson: Lesson, context: ModelContext) {
        markCompleteNoRecompute(student: student, lesson: lesson, context: context)
        context.safeSave()
        recomputeMatrix(context: context)
    }

    /// Internal version that skips save/recompute for batch operations
    private func markCompleteNoRecompute(student: Student, lesson: Lesson, context: ModelContext) {
        let studentIDString = student.id.uuidString
        let lessonIDString = lesson.id.uuidString

        // First, ensure the lesson is marked as presented (so it shows in the checklist)
        let allSLs = context.safeFetch(FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.lessonID == lessonIDString }))
        if findGivenLessonContaining(student: studentIDString, in: allSLs) == nil {
            // Not yet presented - add student to a given lesson
            addStudentToGivenLesson(student: student, studentIDString: studentIDString, lesson: lesson, in: allSLs, context: context)
        }

        // Optionally create/update WorkModel if one exists
        if let work = findOrCreateWork(student: student, lesson: lesson, context: context) {
            work.status = .complete
            work.completedAt = Date()
        }

        // Create/update LessonPresentation with mastered state
        upsertLessonPresentation(
            studentID: studentIDString,
            lessonID: lessonIDString,
            state: .mastered,
            context: context
        )

        // Auto-enroll in track if lesson belongs to a track
        GroupTrackService.autoEnrollInTrackIfNeeded(
            lesson: lesson,
            studentIDs: [studentIDString],
            modelContext: context
        )

        // Check if track is now complete and move to history if so
        GroupTrackService.checkAndCompleteTrackIfNeeded(
            lesson: lesson,
            studentID: studentIDString,
            modelContext: context
        )
    }

    func togglePresented(student: Student, lesson: Lesson, context: ModelContext) {
        togglePresentedNoRecompute(student: student, lesson: lesson, context: context)
        context.safeSave()
        recomputeMatrix(context: context)
    }

    /// Internal version that skips save/recompute for batch operations
    private func togglePresentedNoRecompute(student: Student, lesson: Lesson, context: ModelContext) {
        let studentIDString = student.id.uuidString
        let lessonIDString = lesson.id.uuidString

        let allSLs = context.safeFetch(FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.lessonID == lessonIDString }))

        // Check if student is already in a given lesson
        if let existing = findGivenLessonContaining(student: studentIDString, in: allSLs) {
            removeStudentFromLesson(student: studentIDString, lesson: existing, context: context)
            // Remove LessonPresentation when toggling off
            deleteLessonPresentation(studentID: studentIDString, lessonID: lessonIDString, context: context)
        } else {
            addStudentToGivenLesson(student: student, studentIDString: studentIDString, lesson: lesson, in: allSLs, context: context)
            // Create LessonPresentation with presented state
            upsertLessonPresentation(
                studentID: studentIDString,
                lessonID: lessonIDString,
                state: .presented,
                context: context
            )
        }
    }
    
    // MARK: - Helper Methods for togglePresented
    
    private func findGivenLessonContaining(student: String, in lessons: [StudentLesson]) -> StudentLesson? {
        lessons.first(where: { $0.isGiven && $0.studentIDs.contains(student) })
    }
    
    private func addStudentToGivenLesson(student: Student, studentIDString: String, lesson: Lesson, in allSLs: [StudentLesson], context: ModelContext) {
        let today = Date()
        if let group = allSLs.first(where: { $0.isGiven && ($0.givenAt ?? Date.distantPast).isSameDay(as: today) }) {
            if !group.studentIDs.contains(studentIDString) {
                group.studentIDs.append(studentIDString)
                // Auto-enroll student in track if lesson belongs to a track
                GroupTrackService.autoEnrollInTrackIfNeeded(
                    lesson: lesson,
                    studentIDs: [studentIDString],
                    modelContext: context
                )
            }
        } else {
            let newSL = StudentLesson(lessonID: lesson.id, studentIDs: [student.id], createdAt: Date(), givenAt: Date(), isPresented: true)
            context.insert(newSL)
            // Auto-enroll student in track if lesson belongs to a track
            GroupTrackService.autoEnrollInTrackIfNeeded(
                lesson: lesson,
                studentIDs: [studentIDString],
                modelContext: context
            )
        }
    }
    
    func clearStatus(student: Student, lesson: Lesson, context: ModelContext) {
        clearStatusNoRecompute(student: student, lesson: lesson, context: context)
        context.safeSave()
        recomputeMatrix(context: context)
    }

    /// Internal version that skips save/recompute for batch operations
    private func clearStatusNoRecompute(student: Student, lesson: Lesson, context: ModelContext) {
        let lid = lesson.id
        let sidString = student.id.uuidString
        // CloudKit compatibility: Convert UUID to String for comparison
        let lidString = lid.uuidString
        let sls = (try? context.fetch(FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.lessonID == lidString }))) ?? []
        for sl in sls where sl.studentIDs.contains(sidString) {
            var newIDs = sl.studentIDs
            newIDs.removeAll { $0 == sidString }
            if newIDs.isEmpty { context.delete(sl) } else { sl.studentIDs = newIDs }
        }
        // Delete WorkModels for this student/lesson
        let allWorkModels = (try? context.fetch(FetchDescriptor<WorkModel>())) ?? []
        let workModelsToDelete = allWorkModels.filter { work in
            // Check if student is a participant
            let hasStudent = (work.participants ?? []).contains { $0.studentID == sidString }
            guard hasStudent else { return false }
            // Check if work is for this lesson (via studentLessonID)
            guard let slID = work.studentLessonID,
                  let sl = sls.first(where: { $0.id == slID }),
                  UUID(uuidString: sl.lessonID) == lid else {
                return false
            }
            return true
        }
        for work in workModelsToDelete {
            context.delete(work)
        }
        // Delete LessonPresentation for this student/lesson
        deleteLessonPresentation(studentID: sidString, lessonID: lidString, context: context)
    }
    
    private func findOrCreateWork(student: Student, lesson: Lesson, context: ModelContext) -> WorkModel? {
        let sid = student.id
        let lid = lesson.id
        
        // Fetch all WorkModels and filter in memory
        let allWorkModels = (try? context.fetch(FetchDescriptor<WorkModel>())) ?? []
        
        // Find existing WorkModel for this student/lesson
        let existingWork = allWorkModels.first { work in
            // Check if student is a participant
            let hasStudent = (work.participants ?? []).contains { $0.studentID == sid.uuidString }
            guard hasStudent else { return false }
            // Check if work is for this lesson (via studentLessonID)
            guard let slID = work.studentLessonID else { return false }
            let allSLs = (try? context.fetch(FetchDescriptor<StudentLesson>())) ?? []
            guard let sl = allSLs.first(where: { $0.id == slID }),
                  UUID(uuidString: sl.lessonID) == lid else {
                return false
            }
            return true
        }
        
        if let existing = existingWork {
            return existing
        }
        
        // Create new WorkModel
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

    /// Creates or updates a LessonPresentation record for progress tracking.
    /// If the record exists and we're setting a "higher" state (e.g., mastered > presented), it updates.
    /// If the record exists with mastered state and we're setting presented, it leaves mastered intact.
    private func upsertLessonPresentation(
        studentID: String,
        lessonID: String,
        state: LessonPresentationState,
        context: ModelContext
    ) {
        let allLessonPresentations = (try? context.fetch(FetchDescriptor<LessonPresentation>())) ?? []
        let existing = allLessonPresentations.first { lp in
            lp.studentID == studentID && lp.lessonID == lessonID
        }

        if let existing = existing {
            // Only upgrade state (presented -> mastered), never downgrade
            if state == .mastered && existing.state != .mastered {
                existing.state = .mastered
                existing.masteredAt = Date()
            }
            existing.lastObservedAt = Date()
        } else {
            // Create new LessonPresentation
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

    /// Deletes the LessonPresentation record for a student/lesson combination.
    private func deleteLessonPresentation(
        studentID: String,
        lessonID: String,
        context: ModelContext
    ) {
        let allLessonPresentations = (try? context.fetch(FetchDescriptor<LessonPresentation>())) ?? []
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

