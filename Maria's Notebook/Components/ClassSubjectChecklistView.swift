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
    
    // Grid Configuration
    private let studentColumnWidth: CGFloat = 120
    private let lessonColumnWidth: CGFloat = 200
    private let rowHeight: CGFloat = 44
    
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
                                        ClassChecklistSmartCell(
                                            state: state,
                                            onTap: { viewModel.toggleScheduled(student: student, lesson: lesson, context: modelContext) },
                                            onMarkComplete: { viewModel.markComplete(student: student, lesson: lesson, context: modelContext) },
                                            onMarkPresented: { viewModel.togglePresented(student: student, lesson: lesson, context: modelContext) },
                                            onClear: { viewModel.clearStatus(student: student, lesson: lesson, context: modelContext) }
                                        )
                                        .frame(width: studentColumnWidth, height: rowHeight)
                                        .borderSeparated()
                                    }
                                }
                            }
                        }
                    }
                }
            }
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

// MARK: - THE SMART CELL (Unchanged)
struct ClassChecklistSmartCell: View {
    @Environment(\.modelContext) private var modelContext

    let state: StudentChecklistRowState?
    
    var onTap: () -> Void
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
        }
        .onTapGesture { onTap() }
        .contextMenu {
            Button { onTap() } label: { Label(isScheduled ? "Remove Plan" : "Add to Inbox", systemImage: "calendar") }
            Button { onMarkPresented() } label: { Label("Mark Presented", systemImage: "checkmark") }
            Button { onMarkComplete() } label: { Label("Mark Mastered", systemImage: "checkmark.circle.fill") }
            Divider()
            Button(role: .destructive) { onClear() } label: { Label("Clear All Status", systemImage: "xmark.circle") }
        }
    }
}

// MARK: - ViewModel (Unchanged)
@MainActor
class ClassSubjectChecklistViewModel: ObservableObject {
    @Published var students: [Student] = []
    private var allStudents: [Student] = []
    @Published var lessons: [Lesson] = []
    @Published var orderedGroups: [String] = []
    @Published var availableSubjects: [String] = []
    @Published var selectedSubject: String = ""
    
    @Published var matrixStates: [UUID: [UUID: StudentChecklistRowState]] = [:]
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
    
    func recomputeMatrix(context: ModelContext) {
        let lessonIDs = Set(lessons.map { $0.id })
        guard !lessonIDs.isEmpty else { matrixStates = [:]; return }
        
        // CloudKit compatibility: Convert UUIDs to strings for comparison
        let lessonIDStrings = Set(lessonIDs.map { $0.uuidString })
        let slDescriptor = FetchDescriptor<StudentLesson>(predicate: #Predicate { lessonIDStrings.contains($0.lessonID) })
        let allSLs = (try? context.fetch(slDescriptor)) ?? []
        
        // Fetch all WorkModels and filter in memory (no predicates)
        let allWorkModels = (try? context.fetch(FetchDescriptor<WorkModel>())) ?? []
        
        // Also fetch WorkContracts for legacy fallback (read-only)
        let allContracts = (try? context.fetch(FetchDescriptor<WorkContract>())) ?? []
        
        var newMatrix: [UUID: [UUID: StudentChecklistRowState]] = [:]
        
        for student in students {
            var studentRow: [UUID: StudentChecklistRowState] = [:]
            let studentSLs = allSLs.filter { $0.studentIDs.contains(student.id.uuidString) }
            let studentIDString = student.id.uuidString
            
            // Filter WorkModels for this student
            let studentWorkModels = allWorkModels.filter { work in
                (work.participants ?? []).contains { $0.studentID == studentIDString }
            }
            
            // Filter WorkContracts for this student (legacy fallback)
            let studentContracts = allContracts.filter { $0.studentID == studentIDString }
            
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
                
                // Fallback to WorkContract for legacy data
                let contractsForLesson = studentContracts.filter { $0.lessonID == lessonIDString }
                let openContract = contractsForLesson.first { $0.status == .active || $0.status == .review }
                let completeContract = contractsForLesson.first { $0.status == .complete }
                
                // Prefer WorkModel status
                let isActive = workModelForLesson?.isOpen ?? (openContract != nil)
                let isComplete = (workModelForLesson?.status == .complete) ?? (openContract == nil && completeContract != nil)
                let contractID = workModelForLesson?.id ?? workModelForLesson?.legacyContractID ?? (openContract ?? completeContract)?.id
                
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
        let studentID = student.id
        let lessonID = lesson.id
        let lessonIDString = lessonID.uuidString
        let studentIDString = studentID.uuidString
        
        let allSLs = context.safeFetch(FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.lessonID == lessonIDString }))
        
        // Check if student is already in an unscheduled lesson
        if let existing = findUnscheduledLessonContaining(student: studentIDString, in: allSLs) {
            removeStudentFromLesson(student: studentIDString, lesson: existing, context: context)
        } else {
            addStudentToUnscheduledLesson(student: student, studentIDString: studentIDString, lesson: lesson, in: allSLs, context: context)
        }
        
        context.safeSave()
        recomputeMatrix(context: context)
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
        guard let work = findOrCreateWork(student: student, lesson: lesson, context: context) else { return }
        work.status = .complete
        work.completedAt = Date()
        context.safeSave()
        recomputeMatrix(context: context)
    }
    
    func togglePresented(student: Student, lesson: Lesson, context: ModelContext) {
        let studentID = student.id
        let lessonID = lesson.id
        let studentIDString = studentID.uuidString
        let lessonIDString = lessonID.uuidString
        
        let allSLs = context.safeFetch(FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.lessonID == lessonIDString }))
        
        // Check if student is already in a given lesson
        if let existing = findGivenLessonContaining(student: studentIDString, in: allSLs) {
            removeStudentFromLesson(student: studentIDString, lesson: existing, context: context)
        } else {
            addStudentToGivenLesson(student: student, studentIDString: studentIDString, lesson: lesson, in: allSLs, context: context)
        }
        
        context.safeSave()
        recomputeMatrix(context: context)
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
            }
        } else {
            let newSL = StudentLesson(lessonID: lesson.id, studentIDs: [student.id], createdAt: Date(), givenAt: Date(), isPresented: true)
            context.insert(newSL)
        }
    }
    
    func clearStatus(student: Student, lesson: Lesson, context: ModelContext) {
        let lid = lesson.id
        let sid = student.id
        let sidString = sid.uuidString
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
        // Also delete legacy WorkContracts (read-only fallback)
        let allContracts = (try? context.fetch(FetchDescriptor<WorkContract>())) ?? []
        let contractsToDelete = allContracts.filter { $0.studentID == sidString && $0.lessonID == lidString }
        for contract in contractsToDelete {
            context.delete(contract)
        }
        context.safeSave()
        recomputeMatrix(context: context)
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

