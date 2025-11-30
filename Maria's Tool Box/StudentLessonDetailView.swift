import SwiftUI
import SwiftData

struct StudentLessonDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var lessons: [Lesson]
    @Query private var studentsAll: [Student]

    let studentLesson: StudentLesson
    var onDone: (() -> Void)? = nil

    @State private var scheduledFor: Date?
    @State private var givenAt: Date?
    @State private var notes: String
    @State private var needsPractice: Bool
    @State private var needsAnotherPresentation: Bool
    @State private var followUpWork: String

    @State private var selectedStudentIDs: Set<UUID> = []
    @State private var showingAddStudentSheet = false

    @State private var showDeleteAlert = false

    init(studentLesson: StudentLesson, onDone: (() -> Void)? = nil) {
        self.studentLesson = studentLesson
        self.onDone = onDone
        _scheduledFor = State(initialValue: studentLesson.scheduledFor)
        _givenAt = State(initialValue: studentLesson.givenAt)
        _notes = State(initialValue: studentLesson.notes)
        _needsPractice = State(initialValue: studentLesson.needsPractice)
        _needsAnotherPresentation = State(initialValue: studentLesson.needsAnotherPresentation)
        _followUpWork = State(initialValue: studentLesson.followUpWork)
        _selectedStudentIDs = State(initialValue: Set(studentLesson.studentIDs))
    }

    private var lessonObject: Lesson? {
        lessons.first(where: { $0.id == studentLesson.lessonID })
    }

    private var lessonName: String {
        lessonObject?.name ?? "Lesson"
    }

    private var subject: String {
        lessonObject?.subject ?? ""
    }

    private var subjectColor: Color {
        AppColors.color(forSubject: subject)
    }

    private var selectedStudentsList: [Student] {
        studentsAll
            .filter { selectedStudentIDs.contains($0.id) }
            .sorted { $0.firstName.localizedCaseInsensitiveCompare($1.firstName) == .orderedAscending }
    }

    private func displayName(for student: Student) -> String {
        let parts = student.fullName.split(separator: " ")
        guard let first = parts.first else { return student.fullName }
        let lastInitial = parts.dropFirst().first?.first.map { String($0) } ?? ""
        return lastInitial.isEmpty ? String(first) : "\(first) \(lastInitial)."
    }

    private func dateChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.12))
            )
    }

    private var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE, MMM d, h:mm a")
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Student Lesson")
                    .font(.system(size: AppTheme.FontSize.titleSmall, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)

            Divider()

            ScrollView {
                VStack(spacing: 28) {
                    summarySection
                    scheduleSection
                    givenSection
                    flagsSection
                    followUpSection
                    notesSection
                }
                .padding(.horizontal, 32)
                .padding(.top, 28)
                .padding(.bottom, 24)
            }
        }
        .frame(minWidth: 520, minHeight: 560)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Divider()
                HStack {
                    Button(role: .destructive) {
                        showDeleteAlert = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }

                    Spacer()

                    Button("Cancel") {
                        if let onDone {
                            onDone()
                        } else {
                            dismiss()
                        }
                    }

                    Button("Save") {
                        save()
                    }
                    .bold()
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.bar)
            }
        }
        .alert("Delete Lesson?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                delete()
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showingAddStudentSheet) {
            AddStudentView()
        }
    }

    private var summarySection: some View {
        VStack(spacing: 16) {
            Text(lessonName)
                .font(.system(size: AppTheme.FontSize.titleLarge, weight: .heavy, design: .rounded))
                .multilineTextAlignment(.center)

            HStack(alignment: .center, spacing: 8) {
                if !subject.isEmpty {
                    Text(subject)
                        .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .foregroundColor(subjectColor)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(subjectColor.opacity(0.15))
                        )
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(selectedStudentsList, id: \.id) { student in
                            HStack(spacing: 6) {
                                Text(displayName(for: student))
                                    .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                                Button {
                                    selectedStudentIDs.remove(student.id)
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
                }

                Spacer(minLength: 0)

                Menu {
                    ForEach(studentsAll) { student in
                        let isSelected = selectedStudentIDs.contains(student.id)
                        Button {
                            if isSelected {
                                selectedStudentIDs.remove(student.id)
                            } else {
                                selectedStudentIDs.insert(student.id)
                            }
                        } label: {
                            Label(displayName(for: student), systemImage: isSelected ? "checkmark" : "person")
                        }
                    }
                    Divider()
                    Button {
                        showingAddStudentSheet = true
                    } label: {
                        Label("New Student…", systemImage: "plus")
                    }
                } label: {
                    Label("Add/Remove Students", systemImage: "person.2.badge.plus")
                        .labelStyle(.titleAndIcon)
                }
                .menuStyle(.borderlessButton)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text("Scheduled For")
                    .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Toggle("Scheduled", isOn: Binding(
                get: { scheduledFor != nil },
                set: { newValue in
                    if newValue {
                        scheduledFor = scheduledFor ?? Date()
                    } else {
                        scheduledFor = nil
                    }
                }
            ))

            if scheduledFor != nil {
                DatePicker("Date", selection: Binding(
                    get: { scheduledFor ?? Date() },
                    set: { scheduledFor = $0 }
                ), displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.compact)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var givenSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.clock")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text("Presented")
                    .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Toggle("Presented", isOn: Binding(
                get: { givenAt != nil },
                set: { newValue in
                    if newValue {
                        givenAt = givenAt ?? Date()
                    } else {
                        givenAt = nil
                    }
                }
            ))

            if givenAt != nil {
                DatePicker("Date", selection: Binding(
                    get: { givenAt ?? Date() },
                    set: { givenAt = $0 }
                ), displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.compact)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var flagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "flag")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text("Flags")
                    .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Toggle("Needs Practice", isOn: $needsPractice)
            Toggle("Needs Another Presentation", isOn: $needsAnotherPresentation)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var followUpSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text("Follow Up Work")
                    .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            TextField("Follow Up Work", text: $followUpWork)
                .textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "doc.plaintext")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text("Notes")
                    .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            TextEditor(text: $notes)
                .frame(minHeight: 140)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func save() {
        studentLesson.scheduledFor = scheduledFor
        studentLesson.givenAt = givenAt
        studentLesson.notes = notes
        studentLesson.needsPractice = needsPractice
        studentLesson.needsAnotherPresentation = needsAnotherPresentation
        studentLesson.followUpWork = followUpWork
        studentLesson.studentIDs = Array(selectedStudentIDs)

        do {
            try modelContext.save()
            onDone?() ?? dismiss()
        } catch {
            // Handle save error if needed
        }
    }

    private func delete() {
        modelContext.delete(studentLesson)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            // Handle delete error if needed
        }
    }
}

#Preview {
    Text("StudentLessonDetailView preview requires real model data")
}
