//
//  ClassSubjectChecklistView.swift
//  Maria's Toolbox
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
    
    // Grid Configuration
    private let studentColumnWidth: CGFloat = 120
    private let lessonColumnWidth: CGFloat = 200
    private let rowHeight: CGFloat = 44
    
    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header / Controls
            HStack {
                Text("Class Checklist")
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
            #if os(macOS)
            .background(Color(nsColor: .windowBackgroundColor))
            #else
            .background(Color(uiColor: .systemBackground))
            #endif
            
            Divider()
            
            ZStack(alignment: .topLeading) {
                // Main vertical scrolling content (left column + right grid)
                ScrollView(.vertical) {
                    HStack(alignment: .top, spacing: 0) {
                        
                        // 1. LEFT COLUMN (Sticky Horizontally) - Lesson Names
                        VStack(alignment: .leading, spacing: 0) {
                            // Header row (non-sticky) placeholder for left corner
                            Color.clear
                                .frame(width: lessonColumnWidth, height: rowHeight)
                                .borderSeparated()
                            
                            let groups = viewModel.orderedGroups
                            ForEach(groups, id: \.self) { group in
                                groupHeaderView(group)
                                    .frame(width: lessonColumnWidth)
                                
                                let lessons = viewModel.lessonsIn(group: group)
                                ForEach(lessons) { lesson in
                                    VStack(alignment: .leading) {
                                        Text(lesson.name)
                                            .font(.system(.body, design: .rounded).weight(.medium))
                                            .lineLimit(2)
                                            .minimumScaleFactor(0.9)
                                    }
                                    .padding(.horizontal, 8)
                                    .frame(width: lessonColumnWidth, height: rowHeight, alignment: .leading)
                                    .borderSeparated()
                                }
                            }
                        }
                        .backgroundPlatform()
                        .zIndex(1)
                        
                        // 2. RIGHT PANE (Scrolls Horizontally) - The Grid
                        // Equatable subview prevents bounce-back on state change
                        ClassChecklistGrid(
                            viewModel: viewModel,
                            studentColumnWidth: studentColumnWidth,
                            rowHeight: rowHeight
                        )
                        .equatable()
                    }
                }
            }
            
        }
        .onAppear {
            viewModel.loadData(context: modelContext)
        }
        .onChange(of: viewModel.selectedSubject) { _, _ in
            viewModel.refreshMatrix(context: modelContext)
        }
    }
    
    private func groupHeaderView(_ group: String) -> some View {
        HStack {
            Text(group)
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.leading)
            Spacer()
        }
        .frame(height: 30)
        .background(Color.secondary.opacity(0.05))
        .borderSeparated()
    }
}

// MARK: - Equatable Grid Subview
struct ClassChecklistGrid: View, Equatable {
    @ObservedObject var viewModel: ClassSubjectChecklistViewModel
    let studentColumnWidth: CGFloat
    let rowHeight: CGFloat
    
    @Environment(\.modelContext) private var modelContext
    
    static func == (lhs: ClassChecklistGrid, rhs: ClassChecklistGrid) -> Bool {
        return lhs.viewModel === rhs.viewModel &&
               lhs.studentColumnWidth == rhs.studentColumnWidth &&
               lhs.rowHeight == rhs.rowHeight
    }
    
    var body: some View {
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 0) {
                
                // Header row (non-sticky)
                HStack(spacing: 0) {
                    ForEach(viewModel.students) { student in
                        VStack(spacing: 2) {
                            Text(student.firstName)
                                .font(.headline)
                            Text(AgeUtils.conciseAgeString(for: student.birthday))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: studentColumnWidth, height: rowHeight, alignment: .center)
                        .borderSeparated()
                    }
                }
                
                // Data Rows
                ForEach(viewModel.orderedGroups, id: \.self) { group in
                    // Group Header Spacer
                    Color.clear
                        .frame(height: 30)
                        .borderSeparated()
                        .background(Color.secondary.opacity(0.05))
                    
                    let lessons = viewModel.lessonsIn(group: group)
                    ForEach(lessons) { lesson in
                        HStack(spacing: 0) {
                            ForEach(viewModel.students) { student in
                                let state = viewModel.state(for: student, lesson: lesson)
                                
                                ClassChecklistSmartCell(
                                    state: state,
                                    onTap: {
                                        viewModel.toggleScheduled(student: student, lesson: lesson, context: modelContext)
                                    },
                                    onMarkComplete: {
                                        viewModel.markComplete(student: student, lesson: lesson, context: modelContext)
                                    },
                                    onMarkPresented: {
                                        viewModel.togglePresented(student: student, lesson: lesson, context: modelContext)
                                    },
                                    onClear: {
                                        viewModel.clearStatus(student: student, lesson: lesson, context: modelContext)
                                    }
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
}

// MARK: - THE SMART CELL
struct ClassChecklistSmartCell: View {
    let state: StudentChecklistRowState?
    
    // Actions
    var onTap: () -> Void
    var onMarkComplete: () -> Void
    var onMarkPresented: () -> Void
    var onClear: () -> Void
    
    var body: some View {
        // Determine Status
        let isComplete = state?.isComplete ?? false
        let isPresented = state?.isPresented ?? false
        let isScheduled = state?.isScheduled ?? false
        
        // Single Icon Logic
        ZStack {
            // Hit area for tap
            Color.clear.contentShape(Rectangle())
            
            if isComplete {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.green)
                    .font(.title2)
            } else if isPresented {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.blue)
                    .font(.title3.weight(.bold))
            } else if isScheduled {
                Image(systemName: "calendar")
                    .foregroundStyle(Color.accentColor)
                    .font(.title3)
            } else {
                // Empty State
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 2)
                    .frame(width: 16, height: 16)
            }
        }
        .onTapGesture {
            onTap() // Primary: Toggle Plan
        }
        .contextMenu {
            Button { onTap() } label: {
                Label(isScheduled ? "Unschedule" : "Plan for Today", systemImage: "calendar")
            }
            
            Button { onMarkPresented() } label: {
                Label("Mark Presented", systemImage: "checkmark")
            }
            
            Button { onMarkComplete() } label: {
                Label("Mark Mastered", systemImage: "checkmark.circle.fill")
            }
            
            Divider()
            
            Button(role: .destructive) { onClear() } label: {
                Label("Clear All Status", systemImage: "xmark.circle")
            }
        }
    }
}


// MARK: - ViewModel
@MainActor
class ClassSubjectChecklistViewModel: ObservableObject {
    @Published var students: [Student] = []
    @Published var lessons: [Lesson] = []
    @Published var orderedGroups: [String] = []
    @Published var availableSubjects: [String] = []
    @Published var selectedSubject: String = ""
    
    @Published var matrixStates: [UUID: [UUID: StudentChecklistRowState]] = [:]
    private let lessonsLogic = LessonsViewModel()
    
    func loadData(context: ModelContext) {
        let studentFetch = FetchDescriptor<Student>(sortBy: [SortDescriptor(\.birthday)])
        self.students = (try? context.fetch(studentFetch)) ?? []
        
        let allLessonsFetch = FetchDescriptor<Lesson>()
        let allLessons = (try? context.fetch(allLessonsFetch)) ?? []
        self.availableSubjects = lessonsLogic.subjects(from: allLessons)
        
        if selectedSubject.isEmpty, let first = availableSubjects.first {
            selectedSubject = first
        }
        refreshMatrix(context: context)
    }
    
    func refreshMatrix(context: ModelContext) {
        guard !selectedSubject.isEmpty else { return }
        let sub = selectedSubject.trimmingCharacters(in: .whitespacesAndNewlines)
        let allLessons = (try? context.fetch(FetchDescriptor<Lesson>())) ?? []
        self.lessons = allLessons.filter { $0.subject.localizedCaseInsensitiveCompare(sub) == .orderedSame }
        self.orderedGroups = lessonsLogic.groups(for: sub, lessons: self.lessons)
        recomputeMatrix(context: context)
    }
    
    func lessonsIn(group: String) -> [Lesson] {
        let groupTrimmed = group.trimmingCharacters(in: .whitespacesAndNewlines)
        return lessons.filter {
            $0.group.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare(groupTrimmed) == .orderedSame
        }.sorted { $0.orderInGroup < $1.orderInGroup }
    }
    
    func state(for student: Student, lesson: Lesson) -> StudentChecklistRowState? {
        return matrixStates[student.id]?[lesson.id]
    }
    
    func recomputeMatrix(context: ModelContext) {
        let lessonIDs = Set(lessons.map { $0.id })
        guard !lessonIDs.isEmpty else { matrixStates = [:]; return }
        
        let slDescriptor = FetchDescriptor<StudentLesson>(predicate: #Predicate { lessonIDs.contains($0.lessonID) })
        let allSLs = (try? context.fetch(slDescriptor)) ?? []
        
        let allContracts = (try? context.fetch(FetchDescriptor<WorkContract>())) ?? []
        let relevantContracts = allContracts.filter {
            guard let lid = UUID(uuidString: $0.lessonID) else { return false }
            return lessonIDs.contains(lid)
        }
        
        var newMatrix: [UUID: [UUID: StudentChecklistRowState]] = [:]
        
        for student in students {
            var studentRow: [UUID: StudentChecklistRowState] = [:]
            let studentSLs = allSLs.filter { $0.studentIDs.contains(student.id) }
            let studentContracts = relevantContracts.filter { $0.studentID == student.id.uuidString }
            
            for lesson in lessons {
                let slsForLesson = studentSLs.filter { $0.lessonID == lesson.id }
                let contractsForLesson = studentContracts.filter { $0.lessonID == lesson.id.uuidString }
                
                let isPresented = slsForLesson.contains { $0.isGiven }
                let isScheduled = slsForLesson.contains { !$0.isGiven && $0.scheduledFor != nil }
                
                let openContract = contractsForLesson.first { $0.status == .active || $0.status == .review }
                let completeContract = contractsForLesson.first { $0.status == .complete }
                let isActive = (openContract != nil)
                let isComplete = (openContract == nil && completeContract != nil)
                
                let state = StudentChecklistRowState(
                    lessonID: lesson.id, plannedItemID: nil, presentationLogID: nil, contractID: (openContract ?? completeContract)?.id,
                    isScheduled: isScheduled, isPresented: isPresented, isActive: isActive, isComplete: isComplete, lastActivityDate: nil, isStale: false
                )
                studentRow[lesson.id] = state
            }
            newMatrix[student.id] = studentRow
        }
        self.matrixStates = newMatrix
    }
    
    // MARK: - SMART ACTIONS
    
    // PRIMARY ACTION: Toggle Plan with Grouping
    func toggleScheduled(student: Student, lesson: Lesson, context: ModelContext) {
        // 1. Check if this specific student is already scheduled
        let studentID = student.id
        let lessonID = lesson.id
        
        // Fetch ALL SLs for this lesson (to find group candidates)
        let fetch = FetchDescriptor<StudentLesson>(predicate: #Predicate { sl in
            sl.lessonID == lessonID
        })
        let allSLsForLesson = (try? context.fetch(fetch)) ?? []
        
        // Find if *this specific student* is scheduled
        let existingForStudent = allSLsForLesson.first { sl in
            !sl.isGiven && sl.scheduledFor != nil && sl.studentIDs.contains(studentID)
        }
        
        if let existing = existingForStudent {
            // UNSCHEDULE: Remove student from this group
            var ids = existing.studentIDs
            ids.removeAll { $0 == studentID }
            
            if ids.isEmpty {
                // If they were the only one, delete the whole SL
                context.delete(existing)
            } else {
                // Otherwise just update the list
                existing.studentIDs = ids
            }
        } else {
            // SCHEDULE: Try to join an existing group for TODAY
            let todayStart = AppCalendar.startOfDay(Date())
            
            // Look for an SL that is:
            // 1. Not given
            // 2. Scheduled for TODAY
            // 3. For this lesson
            let candidateGroup = allSLsForLesson.first { sl in
                !sl.isGiven && sl.scheduledForDay == todayStart
            }
            
            if let group = candidateGroup {
                // Add student to this existing group
                if !group.studentIDs.contains(studentID) {
                    group.studentIDs.append(studentID)
                }
            } else {
                // Create NEW SL
                let newSL = StudentLesson(
                    lessonID: lesson.id,
                    studentIDs: [student.id],
                    createdAt: Date(),
                    scheduledFor: Date() // Sets scheduledForDay automatically
                )
                newSL.lesson = lesson
                context.insert(newSL)
            }
        }
        
        try? context.save()
        recomputeMatrix(context: context)
    }
    
    func markComplete(student: Student, lesson: Lesson, context: ModelContext) {
        // Work Contracts are per-student, so no grouping logic needed here
        let contract = findOrCreateContract(student: student, lesson: lesson, context: context)
        contract.status = .complete
        contract.completedAt = Date()
        try? context.save()
        recomputeMatrix(context: context)
    }
    
    func togglePresented(student: Student, lesson: Lesson, context: ModelContext) {
        // Similar "Group Merge" logic for Presentations
        let studentID = student.id
        let lessonID = lesson.id
        
        let fetch = FetchDescriptor<StudentLesson>(predicate: #Predicate { sl in
            sl.lessonID == lessonID
        })
        let allSLsForLesson = (try? context.fetch(fetch)) ?? []
        
        // Is this student already presented?
        let existingPresented = allSLsForLesson.first { sl in
            sl.isGiven && sl.studentIDs.contains(studentID)
        }
        
        if let existing = existingPresented {
            // UN-PRESENT
            var ids = existing.studentIDs
            ids.removeAll { $0 == studentID }
            
            if ids.isEmpty {
                context.delete(existing)
            } else {
                existing.studentIDs = ids
            }
        } else {
            // MARK PRESENTED: Try to join an existing "Presented Today" group
            let todayStart = AppCalendar.startOfDay(Date())
            
            let candidateGroup = allSLsForLesson.first { sl in
                sl.isGiven && AppCalendar.startOfDay(sl.givenAt ?? Date.distantPast) == todayStart
            }
            
            if let group = candidateGroup {
                if !group.studentIDs.contains(studentID) {
                    group.studentIDs.append(studentID)
                }
            } else {
                let newSL = StudentLesson(
                    lessonID: lesson.id,
                    studentIDs: [student.id],
                    createdAt: Date(),
                    givenAt: Date(),
                    isPresented: true
                )
                newSL.lesson = lesson
                context.insert(newSL)
            }
        }
        
        try? context.save()
        recomputeMatrix(context: context)
    }
    
    func clearStatus(student: Student, lesson: Lesson, context: ModelContext) {
        // 1. Remove from any StudentLesson (Scheduled or Presented)
        let lid = lesson.id
        let sid = student.id
        let sls = (try? context.fetch(FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.lessonID == lid }))) ?? []
        
        for sl in sls {
            if sl.studentIDs.contains(sid) {
                var newIDs = sl.studentIDs
                newIDs.removeAll { $0 == sid }
                if newIDs.isEmpty {
                    context.delete(sl)
                } else {
                    sl.studentIDs = newIDs
                }
            }
        }
        
        // 2. Remove Contract
        let contracts = fetchContracts(student: student, lesson: lesson, context: context)
        for contract in contracts {
            context.delete(contract)
        }
        
        try? context.save()
        recomputeMatrix(context: context)
    }
    
    // Helpers
    private func fetchContracts(student: Student, lesson: Lesson, context: ModelContext) -> [WorkContract] {
        let sid = student.id.uuidString; let lid = lesson.id.uuidString
        let fetch = FetchDescriptor<WorkContract>(predicate: #Predicate { $0.studentID == sid && $0.lessonID == lid })
        return (try? context.fetch(fetch)) ?? []
    }
    
    private func findOrCreateContract(student: Student, lesson: Lesson, context: ModelContext) -> WorkContract {
        if let existing = fetchContracts(student: student, lesson: lesson, context: context).first { return existing }
        let c = WorkContract(studentID: student.id.uuidString, lessonID: lesson.id.uuidString)
        context.insert(c)
        return c
    }
}

// Visual Helpers
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
