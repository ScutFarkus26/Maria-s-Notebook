import SwiftUI
import SwiftData

private extension WorkModel.WorkType {
    var title: String { self.rawValue }
    var color: Color {
        switch self {
        case .research: return .teal
        case .followUp: return .orange
        case .practice: return .purple
        }
    }
}

struct WorkDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var lessons: [Lesson]
    @Query private var studentsAll: [Student]
    @Query private var studentLessons: [StudentLesson]
    
    let work: WorkModel
    var onDone: (() -> Void)? = nil
    
    @State private var selectedStudents: Set<UUID>
    @State private var workType: WorkModel.WorkType
    @State private var selectedStudentLessonID: UUID?
    @State private var notes: String
    @State private var showDeleteAlert = false

    @State private var showingAddStudentSheet = false
    @State private var showingStudentPickerPopover = false
    @State private var studentSearchText: String = ""

    private enum LevelFilter: String, CaseIterable {
        case all = "All"
        case lower = "Lower"
        case upper = "Upper"
    }

    @State private var studentLevelFilter: LevelFilter = .all
    
    init(work: WorkModel, onDone: (() -> Void)? = nil) {
        self.work = work
        self.onDone = onDone
        _selectedStudents = State(initialValue: Set(work.studentIDs))
        _workType = State(initialValue: work.workType)
        _selectedStudentLessonID = State(initialValue: work.studentLessonID)
        _notes = State(initialValue: work.notes)
    }
    
    private var lessonsByID: [UUID: Lesson] {
        Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) })
    }
    private var studentsByID: [UUID: Student] {
        Dictionary(uniqueKeysWithValues: studentsAll.map { ($0.id, $0) })
    }
    private var studentLessonsByID: [UUID: StudentLesson] {
        Dictionary(uniqueKeysWithValues: studentLessons.map { ($0.id, $0) })
    }
    
    private var chipBackgroundColor: Color {
        #if os(macOS)
        return Color(NSColor.windowBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }

    private var separatorStrokeColor: Color {
        #if os(macOS)
        return Color.primary.opacity(0.12)
        #else
        return Color(uiColor: .separator)
        #endif
    }
    
    private func displayName(for student: Student) -> String {
        let f = student.firstName
        let l = student.lastName
        if !f.isEmpty && !l.isEmpty {
            return "\(f) \(l.prefix(1))."
        }
        return f + (l.isEmpty ? "" : " \(l)")
    }
    
    private var createdAtDateFormatter: DateFormatter {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }
    
    private var createdDateOnlyFormatter: DateFormatter {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df
    }

    private var subject: String {
        if let slID = selectedStudentLessonID, let sl = studentLessonsByID[slID], let lesson = lessonsByID[sl.lessonID] {
            return lesson.subject
        }
        return ""
    }

    private var subjectColor: Color {
        subject.isEmpty ? .accentColor : AppColors.color(forSubject: subject)
    }

    private var selectedStudentsList: [Student] {
        studentsAll
            .filter { selectedStudents.contains($0.id) }
            .sorted { $0.firstName.localizedCaseInsensitiveCompare($1.firstName) == .orderedAscending }
    }

    private var filteredStudentsForPicker: [Student] {
        let query = studentSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let searched: [Student]
        if query.isEmpty {
            searched = studentsAll
        } else {
            searched = studentsAll.filter { s in
                let f = s.firstName.lowercased()
                let l = s.lastName.lowercased()
                let full = s.fullName.lowercased()
                return f.contains(query) || l.contains(query) || full.contains(query)
            }
        }
        let leveled: [Student] = searched.filter { s in
            switch studentLevelFilter {
            case .all: return true
            case .lower: return s.level == .lower
            case .upper: return s.level == .upper
            }
        }
        return leveled.sorted {
            let lhs = ($0.firstName, $0.lastName)
            let rhs = ($1.firstName, $1.lastName)
            if lhs.0.caseInsensitiveCompare(rhs.0) == .orderedSame {
                return lhs.1.caseInsensitiveCompare(rhs.1) == .orderedAscending
            }
            return lhs.0.caseInsensitiveCompare(rhs.0) == .orderedAscending
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("Work Details")
                    .font(.system(size: AppTheme.FontSize.titleSmall, weight: .semibold))
                Divider()
            }
            .padding(.top)
            
            ScrollView {
                VStack(spacing: 28) {
                    summarySection
                    workTypeSection
                    linkedLessonSection
                    notesSection
                }
                .padding(.vertical)
                .padding(.horizontal)
            }
        }
        .safeAreaInset(edge: .bottom) {
            bottomBar
                .background(.ultraThinMaterial)
                .padding(.top, 6)
                .padding(.horizontal)
                .padding(.bottom, 10)
        }
        .alert("Delete Work?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                deleteWork()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This action cannot be undone.")
        }
        .sheet(isPresented: $showingAddStudentSheet) {
            AddStudentView()
        }
    }
    
    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Created:")
                    .font(.system(size: AppTheme.FontSize.caption))
                    .foregroundColor(.secondary)
                Text(createdAtDateFormatter.string(from: work.createdAt))
                    .font(.system(size: AppTheme.FontSize.caption))
                    .foregroundColor(.primary)
                workTypeBadge
                Spacer()
            }

            HStack(alignment: .center, spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(selectedStudentsList, id: \.id) { student in
                            HStack(spacing: 6) {
                                Text(displayName(for: student))
                                    .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                                Button {
                                    selectedStudents.remove(student.id)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(subjectColor)
                                .accessibilityLabel("Remove \(displayName(for: student))")
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .foregroundColor(subjectColor)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(subjectColor.opacity(0.15))
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }

                Spacer(minLength: 0)

                Button {
                    showingStudentPickerPopover = true
                } label: {
                    Label("Add/Remove Students", systemImage: "person.2.badge.plus")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderless)
                .popover(isPresented: $showingStudentPickerPopover, arrowEdge: .top) {
                    studentPickerPopover
                }
            }
        }
    }
    
    private var workTypeBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(workType.color)
                .frame(width: 10, height: 10)
            Text(workType.title)
                .font(.system(size: AppTheme.FontSize.caption))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(chipBackgroundColor)
        )
    }
    
    private var workTypeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Work Type")
                .font(.system(size: AppTheme.FontSize.caption))
                .foregroundColor(.secondary)
            
            Picker("Work Type", selection: $workType) {
                ForEach(WorkModel.WorkType.allCases, id: \.self) { type in
                    Text(type.title).tag(type)
                }
            }
            .pickerStyle(.segmented)
        }
    }
    
    private var linkedLessonSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Linked Lesson")
                .font(.system(size: AppTheme.FontSize.caption))
                .foregroundColor(.secondary)
            
            Picker("Linked Lesson", selection: $selectedStudentLessonID) {
                Text("None").tag(nil as UUID?)
                ForEach(studentLessons) { sl in
                    let lessonName = lessonsByID[sl.lessonID]?.name ?? ""
                    let date = sl.scheduledFor ?? sl.givenAt ?? sl.createdAt
                    Text("\(lessonName) • \(createdDateOnlyFormatter.string(from: date))")
                        .tag(Optional(sl.id))
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var studentPickerPopover: some View {
        VStack(spacing: 10) {
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

            Picker("Level", selection: $studentLevelFilter) {
                Text("All").tag(LevelFilter.all)
                Text("Lower").tag(LevelFilter.lower)
                Text("Upper").tag(LevelFilter.upper)
            }
            .pickerStyle(.segmented)

            Divider().padding(.top, 2)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(filteredStudentsForPicker, id: \.id) { student in
                        Button {
                            if selectedStudents.contains(student.id) {
                                selectedStudents.remove(student.id)
                            } else {
                                selectedStudents.insert(student.id)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: selectedStudents.contains(student.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedStudents.contains(student.id) ? Color.accentColor : Color.secondary)
                                Text(displayName(for: student))
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
                    showingStudentPickerPopover = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(minWidth: 320)
    }
    
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.system(size: AppTheme.FontSize.caption))
                .foregroundColor(.secondary)
            
            TextEditor(text: $notes)
                .frame(minHeight: 100)
                .padding(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(separatorStrokeColor, lineWidth: 1)
                )
        }
    }
    
    private var bottomBar: some View {
        HStack {
            Button(role: .destructive) {
                showDeleteAlert = true
            } label: {
                Text("Delete")
                    .font(.system(size: AppTheme.FontSize.caption))
            }
            
            Spacer()
            
            Button("Cancel") {
                if let onDone = onDone {
                    onDone()
                } else {
                    dismiss()
                }
            }
            .font(.system(size: AppTheme.FontSize.caption))
            
            Button("Save") {
                saveWork()
            }
            .buttonStyle(.borderedProminent)
            .font(.system(size: AppTheme.FontSize.caption))
            .keyboardShortcut(.defaultAction)
        }
    }
    
    private func saveWork() {
        work.studentIDs = Array(selectedStudents)
        work.workType = workType
        work.studentLessonID = selectedStudentLessonID
        work.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try modelContext.save()
            if let onDone = onDone {
                onDone()
            } else {
                dismiss()
            }
        } catch {
            // Handle save error if needed
        }
    }
    
    private func deleteWork() {
        modelContext.delete(work)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            // Handle save error if needed
        }
    }
}

#Preview {
    // Requires real model data for meaningful preview.
    Text("WorkDetailView requires real model data for preview")
}
