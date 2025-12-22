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
    private let studentColumnWidth: CGFloat = 140
    private let lessonColumnWidth: CGFloat = 200
    private let rowHeight: CGFloat = 50 // Fixed height to ensure alignment
    
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
            
            // MARK: - Main Content
            // We use a Vertical ScrollView for the whole page.
            // Inside, we split: Left (Lesson Names) and Right (Student Grid).
            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 0) {
                    
                    // 1. LEFT COLUMN (Sticky Horizontally)
                    VStack(alignment: .leading, spacing: 0) {
                        // Empty Top-Left Corner (matches Student Header height)
                        Color.clear
                            .frame(width: lessonColumnWidth, height: rowHeight)
                            #if os(macOS)
                            .border(Color(nsColor: .separatorColor).opacity(0.5), width: 0.5)
                            #else
                            .border(Color.gray.opacity(0.5), width: 0.5)
                            #endif

                        // Rows of Lesson Names
                        ForEach(viewModel.orderedGroups, id: \.self) { group in
                            // Group Header
                            groupHeaderView(group)
                                .frame(width: lessonColumnWidth)
                            
                            // Lessons
                            let lessons = viewModel.lessonsIn(group: group)
                            ForEach(lessons) { lesson in
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
                                .frame(width: lessonColumnWidth, height: rowHeight, alignment: .leading)
                                #if os(macOS)
                                .border(Color(nsColor: .separatorColor).opacity(0.5), width: 0.5)
                                #else
                                .border(Color.gray.opacity(0.5), width: 0.5)
                                #endif
                            }
                        }
                    }
                    #if os(macOS)
                    .background(Color(nsColor: .controlBackgroundColor)) // Distinct background for sticky column
                    #else
                    .background(Color(uiColor: .secondarySystemBackground))
                    #endif
                    .zIndex(1) // Keep above if there's any overlap
                    
                    // 2. RIGHT PANE (Scrolls Horizontally)
                    ScrollView(.horizontal) {
                        VStack(alignment: .leading, spacing: 0) {
                            
                            // Student Header Row
                            HStack(spacing: 0) {
                                ForEach(viewModel.students) { student in
                                    VStack(spacing: 2) {
                                        Text(student.firstName)
                                            .font(.headline)
                                        // FIXED: Used conciseAgeString instead of missing ageString
                                        Text(AgeUtils.conciseAgeString(for: student.birthday))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(width: studentColumnWidth, height: rowHeight, alignment: .center)
                                    #if os(macOS)
                                    .border(Color(nsColor: .separatorColor).opacity(0.5), width: 0.5)
                                    #else
                                    .border(Color.gray.opacity(0.5), width: 0.5)
                                    #endif
                                }
                            }
                            #if os(macOS)
                            .background(Color(nsColor: .controlBackgroundColor))
                            #else
                            .background(Color(uiColor: .secondarySystemBackground))
                            #endif
                            
                            // Data Rows
                            ForEach(viewModel.orderedGroups, id: \.self) { group in
                                // Group Header Spacer (extends right)
                                #if os(macOS)
                                Color(nsColor: .underPageBackgroundColor)
                                    .frame(height: 35) // Match groupHeaderView height
                                    .border(Color(nsColor: .separatorColor).opacity(0.5), width: 0.5)
                                #else
                                Color(uiColor: .tertiarySystemBackground)
                                    .frame(height: 35)
                                    .border(Color.gray.opacity(0.5), width: 0.5)
                                #endif
                                
                                let lessons = viewModel.lessonsIn(group: group)
                                ForEach(lessons) { lesson in
                                    HStack(spacing: 0) {
                                        ForEach(viewModel.students) { student in
                                            let state = viewModel.state(for: student, lesson: lesson)
                                            
                                            ClassChecklistCell(
                                                state: state,
                                                onTapScheduled: { viewModel.toggleScheduled(student: student, lesson: lesson, context: modelContext) },
                                                onTapPresented: { viewModel.togglePresented(student: student, lesson: lesson, context: modelContext) },
                                                onTapActive: { viewModel.toggleActive(student: student, lesson: lesson, context: modelContext) },
                                                onTapComplete: { viewModel.toggleComplete(student: student, lesson: lesson, context: modelContext) }
                                            )
                                            .frame(width: studentColumnWidth, height: rowHeight)
                                            #if os(macOS)
                                            .border(Color(nsColor: .separatorColor).opacity(0.2), width: 0.5)
                                            #else
                                            .border(Color.gray.opacity(0.2), width: 0.5)
                                            #endif
                                        }
                                    }
                                }
                            }
                        }
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
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.leading)
            Spacer()
        }
        .frame(height: 35)
        #if os(macOS)
        .background(Color(nsColor: .underPageBackgroundColor))
        .border(Color(nsColor: .separatorColor).opacity(0.5), width: 0.5)
        #else
        .background(Color(uiColor: .tertiarySystemBackground))
        .border(Color.gray.opacity(0.5), width: 0.5)
        #endif
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
                    .foregroundStyle(isScheduled ? Color.green : Color.secondary.opacity(0.2))
            }
            .buttonStyle(.plain)
            
            // Present
            Button(action: onTapPresented) {
                ZStack {
                    if !isPresented && isScheduled {
                        Circle().stroke(Color.green, lineWidth: 1)
                    }
                    Image(systemName: "checkmark")
                        .foregroundStyle(isPresented ? Color.green : Color.secondary.opacity(0.2))
                }
            }
            .buttonStyle(.plain)
            
            // Work
            Button(action: onTapActive) {
                Image(systemName: "hammer")
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary.opacity(0.2))
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
                    .foregroundStyle(isComplete ? Color.green : Color.secondary.opacity(0.2))
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
    @Published var availableSubjects: [String] = []
    @Published var selectedSubject: String = "" // Initialize empty
    
    // Cache: [StudentID: [LessonID: State]]
    @Published var matrixStates: [UUID: [UUID: StudentChecklistRowState]] = [:]
    
    // Re-use logic from your existing logic helper
    private let lessonsLogic = LessonsViewModel()
    
    // MARK: - Data Loading
    func loadData(context: ModelContext) {
        // 1. Fetch Students (Sorted by Birthday)
        // Sort ascending (Oldest first) or descending (Youngest first).
        // Defaulting to Ascending (Oldest -> Youngest)
        let studentFetch = FetchDescriptor<Student>(sortBy: [SortDescriptor(\.birthday)])
        self.students = (try? context.fetch(studentFetch)) ?? []
        
        // 2. Fetch All Lessons to determine Subjects
        let allLessonsFetch = FetchDescriptor<Lesson>()
        let allLessons = (try? context.fetch(allLessonsFetch)) ?? []
        
        // 3. Compute Subjects
        self.availableSubjects = lessonsLogic.subjects(from: allLessons)
        
        // Set default subject if needed
        if selectedSubject.isEmpty, let first = availableSubjects.first {
            selectedSubject = first
        }
        
        // 4. Load Matrix
        refreshMatrix(context: context)
    }
    
    func refreshMatrix(context: ModelContext) {
        guard !selectedSubject.isEmpty else { return }
        
        // Fetch Lessons for CURRENT subject
        let sub = selectedSubject.trimmingCharacters(in: .whitespacesAndNewlines)
        let allLessons = (try? context.fetch(FetchDescriptor<Lesson>())) ?? [] // Fetch all to filter safely case-insensitive
        
        self.lessons = allLessons.filter {
            $0.subject.localizedCaseInsensitiveCompare(sub) == .orderedSame
        }
        
        // Extract Groups using Logic
        self.orderedGroups = lessonsLogic.groups(for: sub, lessons: self.lessons)
        
        recomputeMatrix(context: context)
    }
    
    func lessonsIn(group: String) -> [Lesson] {
        let groupTrimmed = group.trimmingCharacters(in: .whitespacesAndNewlines)
        // Filter from our already filtered `self.lessons`
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
    func recomputeMatrix(context: ModelContext) {
        let lessonIDs = Set(lessons.map { $0.id })
        guard !lessonIDs.isEmpty else {
             matrixStates = [:]
             return
        }
        
        // Fetch ALL StudentLessons for these lessons
        let slDescriptor = FetchDescriptor<StudentLesson>(
            predicate: #Predicate { lessonIDs.contains($0.lessonID) }
        )
        let allSLs = (try? context.fetch(slDescriptor)) ?? []
        
        // Fetch ALL WorkContracts for these lessons
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
                
                let isStale = false
                
                let state = StudentChecklistRowState(
                    lessonID: lesson.id,
                    plannedItemID: nil,
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
            if let sl = findMutableSL(for: student, lesson: lesson, context: context) {
                sl.scheduledFor = nil
                sl.scheduledForDay = Date.distantPast
            }
        } else {
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
             if let sl = findMutableSL(for: student, lesson: lesson, context: context) {
                 sl.isPresented = false
                 sl.givenAt = nil
             }
        } else {
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
            print("Already active")
        } else {
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
        let studentIDString = student.id.uuidString
        let lessonIDString = lesson.id.uuidString
        let descriptor = FetchDescriptor<WorkContract>(predicate: #Predicate { contract in
            contract.studentID == studentIDString && contract.lessonID == lessonIDString
        })
        let allContracts = (try? context.fetch(descriptor)) ?? []
        
        if let existing = allContracts.first {
            if existing.status == .complete {
                existing.status = .active
                existing.completedAt = nil
            } else {
                existing.status = .complete
                existing.completedAt = Date()
            }
        } else {
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
        let newSL = StudentLesson(
            lessonID: lesson.id,
            studentIDs: [student.id],
            createdAt: Date()
        )
        newSL.lesson = lesson
        newSL.students = [student]
        context.insert(newSL)
        return newSL
    }
}
