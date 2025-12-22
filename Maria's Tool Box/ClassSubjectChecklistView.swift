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
    
    // Selectable Subject
    @State private var selectedSubject: String = "Math" // Default or injected
    
    // Grid Configuration
    private let studentColumnWidth: CGFloat = 140
    private let lessonColumnWidth: CGFloat = 200
    
    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header / Controls
            HStack {
                Text("Class Checklist")
                    .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                
                Spacer()
                
                Picker("Subject", selection: $selectedSubject) {
                    // Ideally, dynamically fetch subjects from your Lesson list
                    Text("Math").tag("Math")
                    Text("Language").tag("Language")
                    Text("Science").tag("Science")
                    Text("Cultural").tag("Cultural")
                }
                .pickerStyle(.menu)
                .frame(width: 150)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            // MARK: - Main Grid
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Sticky Header Row (Students)
                    HStack(spacing: 0) {
                        // Empty Corner for Lesson Names
                        Color.clear
                            .frame(width: lessonColumnWidth, height: 50)
                        
                        // Student Names
                        ForEach(viewModel.students) { student in
                            Text(student.firstName)
                                .font(.headline)
                                .frame(width: studentColumnWidth, alignment: .center)
                            Divider()
                        }
                    }
                    .background(Color(nsColor: .controlBackgroundColor))
                    .sticky() // Requires custom sticky modifier or pinnedViews in generic ScrollView (native pinnedViews only work for Section headers in vertical scroll)
                    
                    // Grouped Lessons
                    ForEach(viewModel.orderedGroups, id: \.self) { group in
                        // Group Header
                        HStack {
                            Text(group)
                                .font(.system(.title3, design: .rounded).weight(.bold))
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 8)
                                .padding(.leading)
                            Spacer()
                        }
                        .background(Color(nsColor: .underPageBackgroundColor))
                        
                        // Lessons in Group
                        let lessons = viewModel.lessonsIn(group: group)
                        ForEach(lessons) { lesson in
                            HStack(spacing: 0) {
                                // Lesson Name Column
                                VStack(alignment: .leading) {
                                    Text(lesson.name)
                                        .font(.system(.body, design: .rounded).weight(.medium))
                                        .lineLimit(2)
                                        .minimumScaleFactor(0.9)
                                    if !lesson.subheading.isEmpty {
                                        Text(lesson.subheading)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .frame(width: lessonColumnWidth, alignment: .leading)
                                .frame(height: 50) // Fixed height for alignment
                                
                                Divider()
                                
                                // Student Columns (Checklist Cells)
                                ForEach(viewModel.students) { student in
                                    let state = viewModel.state(for: student, lesson: lesson)
                                    
                                    ClassChecklistCell(
                                        state: state,
                                        onTapScheduled: { viewModel.toggleScheduled(student: student, lesson: lesson, context: modelContext) },
                                        onTapPresented: { viewModel.togglePresented(student: student, lesson: lesson, context: modelContext) },
                                        onTapActive: { viewModel.toggleActive(student: student, lesson: lesson, context: modelContext) },
                                        onTapComplete: { viewModel.toggleComplete(student: student, lesson: lesson, context: modelContext) }
                                    )
                                    .frame(width: studentColumnWidth)
                                    .frame(height: 50)
                                    
                                    Divider()
                                }
                            }
                            Divider() // Row separator
                        }
                    }
                }
            }
        }
        .onAppear {
            viewModel.loadData(subject: selectedSubject, context: modelContext)
        }
        .onChange(of: selectedSubject) { _, newSubject in
            viewModel.loadData(subject: newSubject, context: modelContext)
        }
    }
}

// MARK: - Cell View
struct ClassChecklistCell: View {
    let state: StudentChecklistRowState?
    var onTapScheduled: () -> Void
    var onTapPresented: () -> Void
    var onTapActive: () -> Void
    var onTapComplete: () -> Void
    
    var body: some View {
        let isScheduled = state?.isScheduled ?? false
        let isPresented = state?.isPresented ?? false
        let isActive = state?.isActive ?? false
        let isComplete = state?.isComplete ?? false
        let isStale = (state?.isStale ?? false) && !isComplete
        
        HStack(spacing: 8) {
            // Plan
            Button(action: onTapScheduled) {
                Image(systemName: "calendar.badge.plus")
                    .foregroundStyle(isScheduled ? Color.green : Color.secondary.opacity(0.3))
            }
            .buttonStyle(.plain)
            
            // Present
            Button(action: onTapPresented) {
                ZStack {
                    if !isPresented && isScheduled {
                        Circle().stroke(Color.green, lineWidth: 1)
                    }
                    Image(systemName: "checkmark")
                        .foregroundStyle(isPresented ? Color.green : Color.secondary.opacity(0.3))
                }
            }
            .buttonStyle(.plain)
            
            // Work
            Button(action: onTapActive) {
                Image(systemName: "hammer")
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary.opacity(0.3))
                    .overlay {
                        if isActive && isStale {
                            Circle().fill(Color.orange).frame(width: 5, height: 5).offset(x: 6, y: -6)
                        }
                    }
            }
            .buttonStyle(.plain)
            
            // Complete
            Button(action: onTapComplete) {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(isComplete ? Color.green : Color.secondary.opacity(0.3))
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 18))
    }
}

// MARK: - ViewModel
@MainActor
class ClassSubjectChecklistViewModel: ObservableObject {
    @Published var students: [Student] = []
    @Published var lessons: [Lesson] = []
    @Published var orderedGroups: [String] = []
    
    // Cache: [StudentID: [LessonID: State]]
    @Published var matrixStates: [UUID: [UUID: StudentChecklistRowState]] = [:]
    
    private var subject: String = ""
    
    // MARK: - Data Loading
    func loadData(subject: String, context: ModelContext) {
        self.subject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1. Fetch Students
        // (You might want to filter this by classroom/level if needed)
        let studentFetch = FetchDescriptor<Student>(sortBy: [SortDescriptor(\.firstName)])
        self.students = (try? context.fetch(studentFetch)) ?? []
        
        // 2. Fetch Lessons for Subject
        let lessonFetch = FetchDescriptor<Lesson>(
            predicate: #Predicate { $0.subject == subject } // Note: String comparison in SwiftData predicates is case-sensitive usually
        )
        let allLessons = (try? context.fetch(lessonFetch)) ?? []
        
        // Filter case-insensitive manually if SwiftData predicate is strict, 
        // effectively doing what lessonsIn(group:) does
        self.lessons = allLessons.filter {
            $0.subject.localizedCaseInsensitiveCompare(self.subject) == .orderedSame
        }
        
        // 3. Extract Groups
        let groups = Set(self.lessons.map { $0.group.trimmingCharacters(in: .whitespacesAndNewlines) })
        self.orderedGroups = groups.sorted()
        
        // 4. Batch Fetch Progress
        recomputeMatrix(context: context)
    }
    
    func lessonsIn(group: String) -> [Lesson] {
        let groupTrimmed = group.trimmingCharacters(in: .whitespacesAndNewlines)
        return lessons.filter {
            $0.group.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare(groupTrimmed) == .orderedSame
        }.sorted { lhs, rhs in
            if lhs.orderInGroup == rhs.orderInGroup {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.orderInGroup < rhs.orderInGroup
        }
    }
    
    func state(for student: Student, lesson: Lesson) -> StudentChecklistRowState? {
        return matrixStates[student.id]?[lesson.id]
    }
    
    // MARK: - Logic / Recompute
    // This logic mirrors StudentChecklistViewModel but optimized for batch fetching
    func recomputeMatrix(context: ModelContext) {
        let lessonIDs = Set(lessons.map { $0.id })
        
        // Fetch ALL StudentLessons for these lessons
        let slDescriptor = FetchDescriptor<StudentLesson>(
            predicate: #Predicate { lessonIDs.contains($0.lessonID) }
        )
        let allSLs = (try? context.fetch(slDescriptor)) ?? []
        
        // Fetch ALL WorkContracts for these lessons
        // Note: WorkContract stores lessonID as String
        let allContracts = (try? context.fetch(FetchDescriptor<WorkContract>())) ?? []
        let relevantContracts = allContracts.filter {
            guard let lid = UUID(uuidString: $0.lessonID) else { return false }
            return lessonIDs.contains(lid)
        }
        
        var newMatrix: [UUID: [UUID: StudentChecklistRowState]] = [:]
        
        for student in students {
            var studentRow: [UUID: StudentChecklistRowState] = [:]
            
            // Filter data for this student
            let studentSLs = allSLs.filter { $0.studentIDs.contains(student.id) }
            let studentContracts = relevantContracts.filter { $0.studentID == student.id.uuidString }
            
            for lesson in lessons {
                // Determine State
                let slsForLesson = studentSLs.filter { $0.lessonID == lesson.id }
                let contractsForLesson = studentContracts.filter { $0.lessonID == lesson.id.uuidString }
                
                // Presented?
                let isPresented = slsForLesson.contains { $0.isGiven }
                
                // Scheduled? (Not given, but has date)
                let isScheduled = slsForLesson.contains { !$0.isGiven && $0.scheduledFor != nil }
                
                // Active / Complete from Contracts
                // Prioritize 'open' contracts
                let openContract = contractsForLesson.first { $0.status == .active || $0.status == .review }
                let completeContract = contractsForLesson.first { $0.status == .complete }
                
                let isActive = (openContract != nil)
                let isComplete = (openContract == nil && completeContract != nil)
                
                // Stale check (Simplified)
                let isStale = false // Implement your date math if needed
                
                let state = StudentChecklistRowState(
                    lessonID: lesson.id,
                    plannedItemID: nil, // Not needed for grid view usually
                    presentationLogID: nil,
                    contractID: (openContract ?? completeContract)?.id,
                    isScheduled: isScheduled,
                    isPresented: isPresented,
                    isActive: isActive,
                    isComplete: isComplete,
                    lastActivityDate: nil,
                    isStale: isStale
                )
                studentRow[lesson.id] = state
            }
            newMatrix[student.id] = studentRow
        }
        
        self.matrixStates = newMatrix
    }
    
    // MARK: - User Actions
    
    func toggleScheduled(student: Student, lesson: Lesson, context: ModelContext) {
        let currentState = state(for: student, lesson: lesson)
        let wasScheduled = currentState?.isScheduled ?? false
        
        if wasScheduled {
            // Unschedule: Find the SL and remove date
            // Note: This logic assumes individual SLs or handles groups carefully
            if let sl = findMutableSL(for: student, lesson: lesson, context: context) {
                sl.scheduledFor = nil
                sl.scheduledForDay = Date.distantPast
            }
        } else {
            // Schedule for Today
            let sl = findOrCreateSL(for: student, lesson: lesson, context: context)
            sl.scheduledFor = Date()
            sl.scheduledForDay = AppCalendar.startOfDay(Date())
        }
        
        try? context.save()
        recomputeMatrix(context: context)
    }
    
    func togglePresented(student: Student, lesson: Lesson, context: ModelContext) {
        let currentState = state(for: student, lesson: lesson)
        let wasPresented = currentState?.isPresented ?? false
        
        if wasPresented {
            // Un-present
             if let sl = findMutableSL(for: student, lesson: lesson, context: context) {
                 sl.isPresented = false
                 sl.givenAt = nil
             }
        } else {
            // Mark Presented
            let sl = findOrCreateSL(for: student, lesson: lesson, context: context)
            sl.isPresented = true
            sl.givenAt = Date()
        }
        
        try? context.save()
        recomputeMatrix(context: context)
    }
    
    func toggleActive(student: Student, lesson: Lesson, context: ModelContext) {
        let currentState = state(for: student, lesson: lesson)
        if currentState?.isActive == true {
            // Maybe do nothing, or navigate to work?
            // For now, let's treat it as a toggle: If active, nothing.
            print("Already active")
        } else {
            // Create Active Work Contract
            let contract = WorkContract(
                studentID: student.id.uuidString,
                lessonID: lesson.id.uuidString,
                status: .active
            )
            context.insert(contract)
        }
        try? context.save()
        recomputeMatrix(context: context)
    }
    
    func toggleComplete(student: Student, lesson: Lesson, context: ModelContext) {
        // Toggle between Complete and Active
        // Find existing contract
        let studentIDString = student.id.uuidString
        let lessonIDString = lesson.id.uuidString
        let descriptor = FetchDescriptor<WorkContract>(predicate: #Predicate { contract in
            contract.studentID == studentIDString && contract.lessonID == lessonIDString
        })
        let allContracts = (try? context.fetch(descriptor)) ?? []
        
        if let existing = allContracts.first {
            if existing.status == .complete {
                existing.status = .active // Reopen
                existing.completedAt = nil
            } else {
                existing.status = .complete
                existing.completedAt = Date()
            }
        } else {
            // Create as complete immediately?
            let contract = WorkContract(
                studentID: student.id.uuidString,
                lessonID: lesson.id.uuidString,
                status: .complete,
                completedAt: Date()
            )
            context.insert(contract)
        }
        try? context.save()
        recomputeMatrix(context: context)
    }
    
    // MARK: - Helpers
    private func findMutableSL(for student: Student, lesson: Lesson, context: ModelContext) -> StudentLesson? {
        // Find an SL that belongs to this student and lesson
        let lessonID = lesson.id
        let fetch = FetchDescriptor<StudentLesson>(predicate: #Predicate { sl in
            sl.lessonID == lessonID
        })
        let candidates = (try? context.fetch(fetch)) ?? []
        return candidates.first { $0.studentIDs.contains(student.id) }
    }
    
    private func findOrCreateSL(for student: Student, lesson: Lesson, context: ModelContext) -> StudentLesson {
        if let existing = findMutableSL(for: student, lesson: lesson, context: context) {
            return existing
        }
        // Create new
        let newSL = StudentLesson(
            lessonID: lesson.id,
            studentIDs: [student.id],
            createdAt: Date()
        )
        // Link objects transiently if needed by your model logic
        newSL.lesson = lesson
        newSL.students = [student]
        context.insert(newSL)
        return newSL
    }
}

// Helper for generic view sticky header (Optional)
extension View {
    func sticky() -> some View {
        self.frame(maxWidth: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipped()
            // Note: True sticky headers in LazyVStack require Section(header:...)
            // If you want the student names to stick, you should wrap the inner content in a Section per row or put this Header in the main ScrollView's pinnedViews if possible.
            // For a grid like this, often just putting the header *outside* the scroll view (if horizontal scroll is synced) is easiest, 
            // but since we want 2D scrolling, a simple approach is keeping it at top.
    }
}
