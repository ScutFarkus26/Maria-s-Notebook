import SwiftUI
import SwiftData
import Foundation
import Combine

struct GiveLessonSheet: View {
    let initialLesson: Lesson?
    let allStudents: [Student]
    let allLessons: [Lesson]
    var onDone: (() -> Void)? = nil
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @StateObject private var viewModel = GiveLessonViewModel()

    @Query private var queriedStudents: [Student]
    @Query private var queriedLessons: [Lesson]
    
    init(lesson: Lesson? = nil, preselectedStudentIDs: [UUID] = [], startGiven: Bool = false, allStudents: [Student] = [], allLessons: [Lesson] = [], onDone: (() -> Void)? = nil) {
        self.initialLesson = lesson
        self.allStudents = allStudents
        self.allLessons = allLessons
        self.onDone = onDone
        _viewModel = StateObject(wrappedValue: GiveLessonViewModel(
            selectedStudentIDs: Set(preselectedStudentIDs),
            scheduledFor: nil,
            givenAt: nil,
            notes: "",
            needsPractice: false,
            needsAnotherPresentation: false,
            followUpWork: "",
            selectedLessonID: lesson?.id,
            mode: startGiven ? .given : .plan
        ))
    }
    

    @State private var sortedLessons: [Lesson] = []
    @State private var sortedStudents: [Student] = []
    
    @State private var showingLessonSearchSheet: Bool = false
    @State private var lessonSearchText: String = ""
    
    private var lessonsSource: [Lesson] { allLessons.isEmpty ? queriedLessons : allLessons }
    private var studentsSource: [Student] { allStudents.isEmpty ? queriedStudents : allStudents }
    
    private var resolvedLesson: Lesson? {
        if let id = viewModel.selectedLessonID {
            return lessonsSource.first(where: { $0.id == id })
        } else {
            return initialLesson
        }
    }
    
    enum Mode: Hashable { case plan, given }
    
    @State private var showingAddStudentSheet: Bool = false
    @State private var showingStudentPickerPopover: Bool = false
    @State private var studentSearchText: String = ""
    
    @State private var saveAlert: (title: String, message: String)? = nil

    enum LevelFilter: String, CaseIterable {
        case all = "All"
        case lower = "Lower"
        case upper = "Upper"
    }

    @State private var studentLevelFilter: LevelFilter = .all

    private var subjectColor: Color {
        if let s = resolvedLesson?.subject, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AppColors.color(forSubject: s)
        }
        return .accentColor
    }
    
    private var sortedLessonsForPicker: [Lesson] { sortedLessons }
    
    private var filteredLessonsForSearch: [Lesson] {
        let query = lessonSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty { return sortedLessonsForPicker }
        return sortedLessonsForPicker.filter { l in
            let name = l.name.lowercased()
            let subject = l.subject.lowercased()
            let group = l.group.lowercased()
            return name.contains(query) || subject.contains(query) || group.contains(query)
        }
    }

    private var selectedStudentsList: [Student] {
        sortedStudents.filter { viewModel.selectedStudentIDs.contains($0.id) }
    }

    private var filteredStudentsForPicker: [Student] {
        var filtered = sortedStudents

        switch studentLevelFilter {
        case .lower:
            filtered = filtered.filter { $0.level == .lower }
        case .upper:
            filtered = filtered.filter { $0.level == .upper }
        case .all:
            break
        }

        let query = studentSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            filtered = filtered.filter { s in
                let f = s.firstName.lowercased()
                let l = s.lastName.lowercased()
                let full = s.fullName.lowercased()
                return f.contains(query) || l.contains(query) || full.contains(query)
            }
        }

        return filtered
    }

    private func displayName(for student: Student) -> String {
        let parts = student.fullName.split(separator: " ")
        guard let first = parts.first else { return student.fullName }
        let lastInitial = parts.dropFirst().first?.first.map { String($0) } ?? ""
        return lastInitial.isEmpty ? String(first) : "\(first) \(lastInitial)."
    }
    
    private func lessonDisplayTitle(for lesson: Lesson) -> String {
        let subject = lesson.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let group = lesson.group.trimmingCharacters(in: .whitespacesAndNewlines)

        var suffix = ""
        if !subject.isEmpty && !group.isEmpty {
            suffix = " • \(subject) • \(group)"
        } else if !subject.isEmpty {
            suffix = " • \(subject)"
        } else if !group.isEmpty {
            suffix = " • \(group)"
        }

        return lesson.name + suffix
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Give Lesson")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(subjectColor)
                .padding(.top, 16)
                .padding(.horizontal)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Lesson selection
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Lesson")
                            .font(.headline)
                        
                        Picker("Lesson", selection: Binding(get: { viewModel.selectedLessonID }, set: { viewModel.selectedLessonID = $0 })) {
                            Text("Choose a Lesson").tag(nil as UUID?)
                            ForEach(sortedLessonsForPicker, id: \.id) { (l: Lesson) in
                                Text(lessonDisplayTitle(for: l)).tag(l.id as UUID?)
                            }
                        }
                        .pickerStyle(.menu)
                        
                        Button {
                            showingLessonSearchSheet = true
                        } label: {
                            Label("Search lessons…", systemImage: "magnifyingglass")
                        }
                        .buttonStyle(.borderless)
                    }

                    // Students chips row + picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Students")
                            .font(.headline)
                        ScrollView(.horizontal, showsIndicators: false) {
                            SelectedStudentsChipsRow(
                                students: selectedStudentsList,
                                subjectColor: subjectColor,
                                displayName: displayName(for:),
                                onRemove: { id in viewModel.selectedStudentIDs.remove(id) }
                            )
                        }
                        Button {
                            showingStudentPickerPopover = true
                        } label: {
                            Text("Add / Remove Students")
                        }
                        .popover(isPresented: $showingStudentPickerPopover, arrowEdge: .bottom) {
                            StudentPickerPopoverContent(
                                studentSearchText: $studentSearchText,
                                studentLevelFilter: $studentLevelFilter,
                                filteredStudents: filteredStudentsForPicker,
                                selectedStudentIDs: Binding(get: { viewModel.selectedStudentIDs }, set: { viewModel.selectedStudentIDs = $0 }),
                                displayName: displayName(for:),
                                showingAddStudentSheet: $showingAddStudentSheet,
                                isPresented: $showingStudentPickerPopover
                            )
                            .padding(12)
                            .frame(minWidth: 320)
                        }

                        // Helper note matching previous behavior, now conditional
                        if viewModel.mode == .plan && viewModel.scheduledFor == nil {
                            Text("This student lesson will be created as unscheduled and appear in Ready to Schedule.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.top, 2)
                        }
                    }

                    // Status
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Status").font(.headline)
                        Picker("Status", selection: Binding(get: { viewModel.mode }, set: { viewModel.mode = $0 })) {
                            Text("Plan").tag(Mode.plan)
                            Text("Given").tag(Mode.given)
                        }
                        .pickerStyle(.segmented)

                        if viewModel.mode == .plan {
                            OptionalDatePickerRow(
                                toggleLabel: "Schedule date/time",
                                dateLabel: "Scheduled For",
                                date: Binding(get: { viewModel.scheduledFor }, set: { viewModel.scheduledFor = $0 })
                            )
                        } else {
                            OptionalDatePickerRow(
                                toggleLabel: "Include date/time",
                                dateLabel: "Given At",
                                date: Binding(get: { viewModel.givenAt }, set: { viewModel.givenAt = $0 })
                            )
                        }
                    }

                    // Notes
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes")
                            .font(.headline)
                        TextEditor(text: Binding(get: { viewModel.notes }, set: { viewModel.notes = $0 }))
                            .frame(minHeight: 100)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.gray.opacity(0.4), lineWidth: 1)
                            )
                    }

                    // Flags
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Flags")
                            .font(.headline)
                        Toggle("Needs Practice", isOn: Binding(get: { viewModel.needsPractice }, set: { viewModel.needsPractice = $0 }))
                        Toggle("Needs Another Presentation", isOn: Binding(get: { viewModel.needsAnotherPresentation }, set: { viewModel.needsAnotherPresentation = $0 }))
                    }

                    // Follow-up Work
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Follow-up Work")
                            .font(.headline)
                        TextField("Follow-up work", text: Binding(get: { viewModel.followUpWork }, set: { viewModel.followUpWork = $0 }))
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            sortedLessons = viewModel.sortedLessons(from: lessonsSource)
            sortedStudents = viewModel.sortedStudents(from: studentsSource)
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                Spacer()
                Button("Save") {
                    saveStudentLesson()
                }
                .disabled(viewModel.selectedStudentIDs.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(.bar)
        }
        .sheet(isPresented: $showingAddStudentSheet) {
            AddStudentView()
        }
        .sheet(isPresented: $showingLessonSearchSheet) {
            LessonSearchSheetView(
                lessonSearchText: $lessonSearchText,
                filteredLessons: filteredLessonsForSearch,
                lessonDisplayTitle: lessonDisplayTitle(for:),
                selectedLessonID: Binding(get: { viewModel.selectedLessonID }, set: { viewModel.selectedLessonID = $0 }),
                isPresented: $showingLessonSearchSheet
            )
            #if os(macOS)
            .frame(minWidth: 600, minHeight: 520)
            #else
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            #endif
        }
        .frame(minWidth: 720, minHeight: 640)
        .alert(isPresented: Binding(get: { saveAlert != nil }, set: { if !$0 { saveAlert = nil } })) {
            Alert(title: Text(saveAlert?.title ?? "Error"), message: Text(saveAlert?.message ?? ""), dismissButton: .default(Text("OK")))
        }
    }
    
    private func saveStudentLesson() {
        do {
            try viewModel.save(context: modelContext, resolvedLesson: resolvedLesson)
            onDone?()
            dismiss()
        } catch let error as GiveLessonViewModel.SaveError {
            saveAlert = (title: error.title, message: error.localizedDescription)
        } catch {
            saveAlert = (title: "Save Failed", message: error.localizedDescription)
        }
    }
}

final class GiveLessonViewModel: ObservableObject {
    @Published var selectedStudentIDs: Set<UUID>
    @Published var scheduledFor: Date?
    @Published var givenAt: Date?
    @Published var notes: String
    @Published var needsPractice: Bool
    @Published var needsAnotherPresentation: Bool
    @Published var followUpWork: String
    @Published var selectedLessonID: UUID?
    @Published var mode: GiveLessonSheet.Mode

    init(
        selectedStudentIDs: Set<UUID> = [],
        scheduledFor: Date? = nil,
        givenAt: Date? = nil,
        notes: String = "",
        needsPractice: Bool = false,
        needsAnotherPresentation: Bool = false,
        followUpWork: String = "",
        selectedLessonID: UUID? = nil,
        mode: GiveLessonSheet.Mode = .plan
    ) {
        self.selectedStudentIDs = selectedStudentIDs
        self.scheduledFor = scheduledFor
        self.givenAt = givenAt
        self.notes = notes
        self.needsPractice = needsPractice
        self.needsAnotherPresentation = needsAnotherPresentation
        self.followUpWork = followUpWork
        self.selectedLessonID = selectedLessonID
        self.mode = mode
    }
}

extension GiveLessonViewModel {
    enum SaveError: LocalizedError {
        case missingLesson
        case persistFailed(underlying: Error)

        var title: String {
            switch self {
            case .missingLesson: return "Choose a Lesson"
            case .persistFailed: return "Save Failed"
            }
        }

        var errorDescription: String? {
            switch self {
            case .missingLesson:
                return "Please select a lesson before saving."
            case .persistFailed(let underlying):
                return underlying.localizedDescription
            }
        }
    }

    func save(context: ModelContext, resolvedLesson: Lesson?) throws {
        guard let finalLesson = resolvedLesson else {
            throw SaveError.missingLesson
        }

        let studentLesson = StudentLesson(
            lessonID: finalLesson.id,
            studentIDs: Array(selectedStudentIDs),
            scheduledFor: mode == .plan ? scheduledFor : nil,
            givenAt: mode == .given ? givenAt : nil,
            isPresented: (mode == .given),
            notes: notes,
            needsPractice: needsPractice,
            needsAnotherPresentation: needsAnotherPresentation,
            followUpWork: followUpWork
        )

        context.insert(studentLesson)

        if needsPractice {
            let existingWorks = try? context.fetch(FetchDescriptor<WorkModel>())
            let hasPractice = (existingWorks ?? []).contains { w in
                w.studentLessonID == studentLesson.id && w.workType == .practice
            }
            if !hasPractice {
                let practiceWork = WorkModel(
                    id: UUID(),
                    studentIDs: Array(selectedStudentIDs),
                    workType: .practice,
                    studentLessonID: studentLesson.id,
                    notes: "",
                    createdAt: Date()
                )
                context.insert(practiceWork)
            }
        }

        let trimmedFollowUp = followUpWork.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedFollowUp.isEmpty {
            let followUp = WorkModel(
                id: UUID(),
                title: "Follow Up: \(finalLesson.name)",
                studentIDs: Array(selectedStudentIDs),
                workType: .followUp,
                studentLessonID: studentLesson.id,
                notes: trimmedFollowUp,
                createdAt: Date()
            )
            context.insert(followUp)
        }

        do {
            try context.save()
        } catch {
            throw SaveError.persistFailed(underlying: error)
        }
    }
}

extension GiveLessonViewModel {
    func sortedLessons(from lessons: [Lesson]) -> [Lesson] {
        lessons.sorted { lhs, rhs in
            if lhs.subject.localizedCaseInsensitiveCompare(rhs.subject) == .orderedSame {
                if lhs.group.localizedCaseInsensitiveCompare(rhs.group) == .orderedSame {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.group.localizedCaseInsensitiveCompare(rhs.group) == .orderedAscending
            }
            return lhs.subject.localizedCaseInsensitiveCompare(rhs.subject) == .orderedAscending
        }
    }

    func sortedStudents(from students: [Student]) -> [Student] {
        students.sorted { lhs, rhs in
            let l = (lhs.firstName.lowercased(), lhs.lastName.lowercased())
            let r = (rhs.firstName.lowercased(), rhs.lastName.lowercased())
            if l.0 == r.0 { return l.1 < r.1 }
            return l.0 < r.0
        }
    }
}

private struct OptionalDatePickerRow: View {
    let toggleLabel: String
    let dateLabel: String
    @Binding var date: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(toggleLabel, isOn: Binding(
                get: { date != nil },
                set: { newValue in
                    date = newValue ? (date ?? Date()) : nil
                }
            ))
            if date != nil {
                DatePicker(
                    dateLabel,
                    selection: Binding(
                        get: { date ?? Date() },
                        set: { date = $0 }
                    ),
                    displayedComponents: [.date, .hourAndMinute]
                )
                #if os(macOS)
                .datePickerStyle(.field)
                #else
                .datePickerStyle(.compact)
                #endif
            }
        }
    }
}

private struct SelectedStudentsChipsRow: View {
    let students: [Student]
    let subjectColor: Color
    let displayName: (Student) -> String
    let onRemove: (UUID) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(students, id: \.id) { student in
                HStack(spacing: 4) {
                    Text(displayName(student))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(subjectColor.opacity(0.2))
                        .foregroundColor(subjectColor)
                        .clipShape(Capsule())
                    Button {
                        onRemove(student.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(subjectColor)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 2)
            }
        }
    }
}

private struct StudentPickerPopoverContent: View {
    @Binding var studentSearchText: String
    @Binding var studentLevelFilter: GiveLessonSheet.LevelFilter
    let filteredStudents: [Student]
    @Binding var selectedStudentIDs: Set<UUID>
    let displayName: (Student) -> String
    @Binding var showingAddStudentSheet: Bool
    @Binding var isPresented: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Search and level filter
            TextField("Search students", text: $studentSearchText)
                .textFieldStyle(.roundedBorder)

            Picker("Level", selection: $studentLevelFilter) {
                ForEach(GiveLessonSheet.LevelFilter.allCases, id: \.self) { level in
                    Text(level.rawValue).tag(level)
                }
            }
            .pickerStyle(.segmented)

            // Students list with selection checkmarks
            List(filteredStudents, id: \.id) { student in
                Button(action: { toggleSelection(for: student.id) }) {
                    HStack {
                        Text(displayName(student))
                            .foregroundStyle(.primary)
                        Spacer()
                        if selectedStudentIDs.contains(student.id) {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .frame(minHeight: 200, maxHeight: 360)

            HStack {
                Button {
                    showingAddStudentSheet = true
                    // Optionally close the popover when adding a student
                    isPresented = false
                } label: {
                    Label("Add Student", systemImage: "plus")
                }

                Spacer()

                Button("Done") {
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func toggleSelection(for id: UUID) {
        if selectedStudentIDs.contains(id) {
            selectedStudentIDs.remove(id)
        } else {
            selectedStudentIDs.insert(id)
        }
    }
}

private struct LessonSearchSheetView: View {
    @Binding var lessonSearchText: String
    let filteredLessons: [Lesson]
    let lessonDisplayTitle: (Lesson) -> String
    @Binding var selectedLessonID: UUID?
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Search Lessons")
                    .font(.headline)
                Spacer()
                Button("Cancel") { isPresented = false }
            }

            TextField("Search lessons", text: $lessonSearchText)
                .textFieldStyle(.roundedBorder)

            List(filteredLessons, id: \.id) { lesson in
                Button(action: {
                    selectedLessonID = lesson.id
                    isPresented = false
                }) {
                    HStack {
                        Text(lessonDisplayTitle(lesson))
                            .foregroundStyle(.primary)
                        Spacer()
                        if selectedLessonID == lesson.id {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
        .padding()
    }
}

