import SwiftUI
import SwiftData

struct GiveLessonSheet: View {
    let lesson: Lesson
    var onDone: (() -> Void)? = nil
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var students: [Student]
    
    @State private var selectedStudentIDs: Set<UUID> = []
    @State private var scheduledFor: Date? = nil
    @State private var givenAt: Date? = nil
    @State private var notes: String = ""
    @State private var needsPractice: Bool = false
    @State private var needsAnotherPresentation: Bool = false
    @State private var followUpWork: String = ""
    
    private enum Mode { case plan, given }
    @State private var mode: Mode = .plan
    
    @State private var showingAddStudentSheet: Bool = false
    @State private var showingStudentPickerPopover: Bool = false
    @State private var studentSearchText: String = ""
    
    @State private var saveAlert: (title: String, message: String)? = nil

    private enum LevelFilter: String, CaseIterable {
        case all = "All"
        case lower = "Lower"
        case upper = "Upper"
    }

    @State private var studentLevelFilter: LevelFilter = .all

    private var subjectColor: Color {
        AppColors.color(forSubject: lesson.subject)
    }

    private var selectedStudentsList: [Student] {
        students.filter { selectedStudentIDs.contains($0.id) }
            .sorted { $0.firstName.localizedCaseInsensitiveCompare($1.firstName) == .orderedAscending }
    }

    private var filteredStudentsForPicker: [Student] {
        // Start with all students
        var filtered = students

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
        let query = studentSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            filtered = filtered.filter { s in
                let f = s.firstName.lowercased()
                let l = s.lastName.lowercased()
                let full = s.fullName.lowercased()
                return f.contains(query) || l.contains(query) || full.contains(query)
            }
        }

        // Sort by first then last name for stable ordering
        return filtered.sorted {
            let lhs = ($0.firstName, $0.lastName)
            let rhs = ($1.firstName, $1.lastName)
            if lhs.0.caseInsensitiveCompare(rhs.0) == .orderedSame {
                return lhs.1.caseInsensitiveCompare(rhs.1) == .orderedAscending
            }
            return lhs.0.caseInsensitiveCompare(rhs.0) == .orderedAscending
        }
    }

    private func displayName(for student: Student) -> String {
        let parts = student.fullName.split(separator: " ")
        guard let first = parts.first else { return student.fullName }
        let lastInitial = parts.dropFirst().first?.first.map { String($0) } ?? ""
        return lastInitial.isEmpty ? String(first) : "\(first) \(lastInitial)."
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Give Lesson")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(subjectColor)
                .padding(.top, 16)
                .padding(.horizontal)

            // Lesson name subtitle for context
            if !lesson.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(lesson.name)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Students chips row + picker
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
                                            selectedStudentIDs.remove(student.id)
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
                                    Text("All").tag(LevelFilter.all)
                                    Text("Lower").tag(LevelFilter.lower)
                                    Text("Upper").tag(LevelFilter.upper)
                                }
                                .pickerStyle(.segmented)

                                Divider().padding(.top, 2)

                                // List of students with checkmarks
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 4) {
                                        ForEach(filteredStudentsForPicker, id: \.id) { student in
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

                        // Helper note matching previous behavior
                        Text("This student lesson will be created as unscheduled and appear in Ready to Schedule.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
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
                            DatePicker("Scheduled For", selection: Binding(get: { scheduledFor ?? Date() }, set: { scheduledFor = $0 }), displayedComponents: [.date, .hourAndMinute])
                                .datePickerStyle(.compact)
                        } else {
                            DatePicker("Given At", selection: Binding(get: { givenAt ?? Date() }, set: { givenAt = $0 }), displayedComponents: [.date, .hourAndMinute])
                                .datePickerStyle(.compact)
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
        .frame(minWidth: 520, minHeight: 560)
        .alert(isPresented: Binding(get: { saveAlert != nil }, set: { if !$0 { saveAlert = nil } })) {
            Alert(title: Text(saveAlert?.title ?? "Error"), message: Text(saveAlert?.message ?? ""), dismissButton: .default(Text("OK")))
        }
    }
    
    private func saveStudentLesson() {
        let studentLesson = StudentLesson(
            lessonID: lesson.id,
            studentIDs: Array(selectedStudentIDs),
            scheduledFor: mode == .plan ? (scheduledFor ?? nil) : nil,
            givenAt: mode == .given ? (givenAt ?? Date()) : nil,
            notes: notes,
            needsPractice: needsPractice,
            needsAnotherPresentation: needsAnotherPresentation,
            followUpWork: followUpWork
        )
        
        modelContext.insert(studentLesson)
        
        // Auto-create a WorkModel for Needs Practice when flagged
        if needsPractice {
            // Avoid duplicates: ensure no existing practice work for this StudentLesson
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
        
        do {
            try modelContext.save()
            onDone?()
            dismiss()
        } catch {
            saveAlert = (title: "Save Failed", message: error.localizedDescription)
        }
    }
}

#Preview {
    Text("GiveLessonSheet preview requires app data and context to display properly.")
}
