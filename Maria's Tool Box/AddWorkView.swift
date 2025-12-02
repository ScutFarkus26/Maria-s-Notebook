import SwiftUI
import SwiftData

struct AddWorkView: View {
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @Query private var lessons: [Lesson]
    @Query private var studentsAll: [Student]
    @Query private var studentLessons: [StudentLesson]
    
    @State private var selectedStudents: Set<UUID> = []
    @State private var workType: WorkModel.WorkType = .research
    @State private var selectedStudentLessonID: UUID? = nil
    @State private var notes: String = ""
    @State private var title: String = ""
    @State private var showingAddStudentSheet: Bool = false
    @State private var showingStudentPickerPopover: Bool = false
    @State private var studentSearchText: String = ""
    @State private var studentLevelFilter: LevelFilter = .all
    
    private var studentLessonSnapshots: [StudentLessonSnapshot] {
        studentLessons.map { $0.snapshot() }
    }
    
    var onDone: (() -> Void)?
    
    enum LevelFilter: String, CaseIterable {
        case all = "All"
        case lower = "Lower"
        case upper = "Upper"
    }
    
    private var subject: String? {
        guard let selectedID = selectedStudentLessonID else { return nil }
        if let studentLesson = studentLessons.first(where: { $0.id == selectedID }),
           let lesson = lessons.first(where: { $0.id == studentLesson.lessonID }) {
            return lesson.subject
        }
        return nil
    }
    
    private var subjectColor: Color {
        if let subject = subject, !subject.isEmpty {
            return AppColors.color(forSubject: subject)
        }
        return .accentColor
    }
    
    private var selectedStudentsList: [Student] {
        studentsAll.filter { selectedStudents.contains($0.id) }
    }
    
    private var filteredStudentsForPicker: [Student] {
        var filtered = studentsAll
        
        // Level filter
        switch studentLevelFilter {
        case .lower:
            filtered = filtered.filter { $0.level == .lower }
        case .upper:
            filtered = filtered.filter { $0.level == .upper }
        case .all:
            break
        }
        
        // Search filter
        if !studentSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let q = studentSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            filtered = filtered.filter { s in
                let f = s.firstName.lowercased()
                let l = s.lastName.lowercased()
                let full = s.fullName.lowercased()
                return f.contains(q) || l.contains(q) || full.contains(q)
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
    
    private func formattedDateOnly(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Work")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(subjectColor)
                .padding(.top, 16)
                .padding(.horizontal)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Title field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Title")
                            .font(.headline)
                        TextField("e.g. Bead Frame Practice", text: $title)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    // Students chips row
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Students")
                            .font(.headline)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(selectedStudentsList, id: \.id) { student in
                                    HStack(spacing: 4) {
                                        Text(displayName(for: student))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(subjectColor.opacity(0.2))
                                            .foregroundColor(subjectColor)
                                            .clipShape(Capsule())
                                        Button {
                                            selectedStudents.remove(student.id)
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
                        Button {
                            showingStudentPickerPopover = true
                        } label: {
                            Text("Add / Remove Students")
                        }
                        .popover(isPresented: $showingStudentPickerPopover, arrowEdge: .bottom) {
                            VStack(spacing: 12) {
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
                    }
                    
                    // Work Type segmented Picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Work Type")
                            .font(.headline)
                        Picker("Work Type", selection: $workType) {
                            ForEach(WorkModel.WorkType.allCases, id: \.self) { type in
                                Text(type.rawValue).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    // Linked Lesson Picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Linked Lesson")
                            .font(.headline)
                        Picker("Linked Lesson", selection: $selectedStudentLessonID) {
                            Text("None").tag(UUID?.none)
                            ForEach(studentLessonSnapshots, id: \.id) { snap in
                                if let lesson = lessons.first(where: { $0.id == snap.lessonID }) {
                                    let date = snap.scheduledFor ?? snap.givenAt ?? snap.createdAt
                                    Text("\(lesson.name) • \(formattedDateOnly(date))")
                                        .tag(Optional(snap.id))
                                }
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    
                    // Notes TextEditor
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
                }
                .padding(.horizontal)
                .padding(.bottom, 40)
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                Spacer()
                Button("Save") {
                    let work = WorkModel(
                        title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                        studentIDs: Array(selectedStudents),
                        workType: workType,
                        studentLessonID: selectedStudentLessonID,
                        notes: notes,
                        createdAt: Date()
                    )
                    modelContext.insert(work)
                    do {
                        try modelContext.save()
                        onDone?()
                        dismiss()
                    } catch {
                        // Handle error appropriately in real app
                    }
                }
                .disabled(selectedStudents.isEmpty || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(.bar)
        }
        .sheet(isPresented: $showingAddStudentSheet) {
            AddStudentView()
        }
        .frame(minWidth: 520, minHeight: 560)
    }
}

#Preview {
    AddWorkView()
}
