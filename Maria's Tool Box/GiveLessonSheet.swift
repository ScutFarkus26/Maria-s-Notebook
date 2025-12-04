import SwiftUI
import SwiftData
import Foundation

struct GiveLessonSheet: View {
    let initialLesson: Lesson?
    let allStudents: [Student]
    let allLessons: [Lesson]
    var onDone: (() -> Void)? = nil
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var queriedStudents: [Student]
    @Query private var queriedLessons: [Lesson]
    
    init(lesson: Lesson? = nil, preselectedStudentIDs: [UUID] = [], startGiven: Bool = false, allStudents: [Student] = [], allLessons: [Lesson] = [], onDone: (() -> Void)? = nil) {
        self.initialLesson = lesson
        self.allStudents = allStudents
        self.allLessons = allLessons
        self.onDone = onDone
        _selectedStudentIDs = State(initialValue: Set(preselectedStudentIDs))
        _mode = State(initialValue: startGiven ? .given : .plan)
        _selectedLessonID = State(initialValue: lesson?.id)
    }
    
    @State private var selectedStudentIDs: Set<UUID> = []
    @State private var scheduledFor: Date? = nil
    @State private var givenAt: Date? = nil
    @State private var notes: String = ""
    @State private var needsPractice: Bool = false
    @State private var needsAnotherPresentation: Bool = false
    @State private var followUpWork: String = ""
    @State private var isPresentedFlag: Bool = false
    @State private var selectedLessonID: UUID? = nil

    @State private var sortedLessons: [Lesson] = []
    @State private var sortedStudents: [Student] = []
    
    @State private var showingLessonSearchSheet: Bool = false
    @State private var lessonSearchText: String = ""
    
    private var lessonsSource: [Lesson] { allLessons.isEmpty ? queriedLessons : allLessons }
    private var studentsSource: [Student] { allStudents.isEmpty ? queriedStudents : allStudents }
    
    private var resolvedLesson: Lesson? {
        if let id = selectedLessonID {
            return lessonsSource.first(where: { $0.id == id })
        } else {
            return initialLesson
        }
    }
    
    private enum Mode: Hashable { case plan, given }
    @State private var mode: Mode = .plan
    
    @State private var showingAddStudentSheet: Bool = false
    @State private var showingStudentPickerPopover: Bool = false
    @State private var studentSearchText: String = ""
    
    @State private var saveAlert: (title: String, message: String)? = nil

    fileprivate enum LevelFilter: String, CaseIterable {
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
        sortedStudents.filter { selectedStudentIDs.contains($0.id) }
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
                        
                        Picker("Lesson", selection: $selectedLessonID) {
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
                                onRemove: { id in selectedStudentIDs.remove(id) }
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
                                selectedStudentIDs: $selectedStudentIDs,
                                displayName: displayName(for:),
                                showingAddStudentSheet: $showingAddStudentSheet,
                                isPresented: $showingStudentPickerPopover
                            )
                            .padding(12)
                            .frame(minWidth: 320)
                        }

                        // Helper note matching previous behavior, now conditional
                        if mode == .plan && scheduledFor == nil {
                            Text("This student lesson will be created as unscheduled and appear in Ready to Schedule.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.top, 2)
                        }
                    }

                    // Status
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Status").font(.headline)
                        Picker("Status", selection: $mode) {
                            Text("Plan").tag(Mode.plan)
                            Text("Given").tag(Mode.given)
                        }
                        .pickerStyle(.segmented)

                        if mode == .plan {
                            OptionalDatePickerRow(
                                toggleLabel: "Schedule date/time",
                                dateLabel: "Scheduled For",
                                date: $scheduledFor
                            )
                        } else {
                            OptionalDatePickerRow(
                                toggleLabel: "Include date/time",
                                dateLabel: "Given At",
                                date: $givenAt
                            )
                        }
                    }

                    // Notes
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes")
                            .font(.headline)
                        TextEditor(text: $notes)
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
                        Toggle("Needs Practice", isOn: $needsPractice)
                        Toggle("Needs Another Presentation", isOn: $needsAnotherPresentation)
                    }

                    // Follow-up Work
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Follow-up Work")
                            .font(.headline)
                        TextField("Follow-up work", text: $followUpWork)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            sortedLessons = lessonsSource.sorted { lhs, rhs in
                if lhs.subject.localizedCaseInsensitiveCompare(rhs.subject) == .orderedSame {
                    if lhs.group.localizedCaseInsensitiveCompare(rhs.group) == .orderedSame {
                        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                    }
                    return lhs.group.localizedCaseInsensitiveCompare(rhs.group) == .orderedAscending
                }
                return lhs.subject.localizedCaseInsensitiveCompare(rhs.subject) == .orderedAscending
            }
            sortedStudents = studentsSource.sorted { lhs, rhs in
                let l = (lhs.firstName.lowercased(), lhs.lastName.lowercased())
                let r = (rhs.firstName.lowercased(), rhs.lastName.lowercased())
                if l.0 == r.0 { return l.1 < r.1 }
                return l.0 < r.0
            }
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
                .disabled(selectedStudentIDs.isEmpty)
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
                selectedLessonID: $selectedLessonID,
                isPresented: $showingLessonSearchSheet
            )
            #if os(macOS)
            .frame(minWidth: 600, minHeight: 520)
            .presentationSizing(.fitted)
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
        guard let finalLesson = resolvedLesson else {
            saveAlert = (title: "Choose a Lesson", message: "Please select a lesson before saving.")
            return
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
        
        modelContext.insert(studentLesson)
        
        if needsPractice {
            let existingWorks = try? modelContext.fetch(FetchDescriptor<WorkModel>())
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
                modelContext.insert(practiceWork)
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
            modelContext.insert(followUp)
        }
        
        do {
            try modelContext.save()
            onDone?()
            dismiss()
        } catch {
            saveAlert = (title: "Save Failed", message: error.localizedDescription)
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
        VStack(spacing: 12) {
            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search students", text: $studentSearchText)
                    .textFieldStyle(.plain)
                if !studentSearchText.isEmpty {
                    Button {
                        studentSearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )

            // Level filter
            Picker("Level", selection: $studentLevelFilter) {
                Text("All").tag(GiveLessonSheet.LevelFilter.all)
                Text("Lower").tag(GiveLessonSheet.LevelFilter.lower)
                Text("Upper").tag(GiveLessonSheet.LevelFilter.upper)
            }
            .pickerStyle(.segmented)

            Divider().padding(.top, 2)

            // List of students with checkmarks
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(filteredStudents, id: \.id) { student in
                        Button {
                            if selectedStudentIDs.contains(student.id) {
                                selectedStudentIDs.remove(student.id)
                            } else {
                                selectedStudentIDs.insert(student.id)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: selectedStudentIDs.contains(student.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedStudentIDs.contains(student.id) ? Color.accentColor : Color.secondary)
                                Text(displayName(student))
                                    .foregroundStyle(.primary)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 6)
                            .padding(.horizontal, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 4)
            }
            .frame(maxHeight: 280)

            Divider()

            HStack {
                Button {
                    showingAddStudentSheet = true
                } label: {
                    Label("New Student…", systemImage: "plus")
                }
                .buttonStyle(.borderless)

                Spacer()

                Button("Done") {
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
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
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search lessons", text: $lessonSearchText)
                    .textFieldStyle(.plain)
                if !lessonSearchText.isEmpty {
                    Button {
                        lessonSearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .padding(.horizontal)
            .padding(.top)

            Divider().padding(.horizontal)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredLessons, id: \.id) { l in
                        Button {
                            selectedLessonID = l.id
                            isPresented = false
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(lessonDisplayTitle(l))
                                    .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.primary)
                                if !l.subheading.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text(l.subheading)
                                        .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading)
                    }
                    if filteredLessons.isEmpty {
                        VStack(spacing: 8) {
                            Text("No matches")
                                .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                            Text("Try a different search for lesson name, subject, or group.")
                                .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 200)
                        .padding()
                    }
                }
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Done") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                .padding(.trailing)
            }
            .padding(.bottom)
        }
    }
}

#Preview {
    GiveLessonSheet()
}

